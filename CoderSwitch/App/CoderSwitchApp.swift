import SwiftUI
import CoderSwitchCore
import AppKit

@main
enum CoderSwitchMain {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let context: AppContext
    private let oauthStore: OAuthStore
    private var keepAliveActivity: NSObjectProtocol?

    override init() {
        let oauthStore = OAuthStore.shared
        self.oauthStore = oauthStore
        context = AppContext(oauthStore: oauthStore)
        super.init()
        AppShell.shared.configure(context: context, oauthStore: oauthStore)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("CoderSwitch menu bar utility")
        ProcessInfo.processInfo.disableSuddenTermination()
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "CoderSwitch menu bar utility"
        )
        NativeStatusItemController.shared.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keepAliveActivity {
            ProcessInfo.processInfo.endActivity(keepAliveActivity)
            self.keepAliveActivity = nil
        }
        ProcessInfo.processInfo.enableAutomaticTermination("CoderSwitch menu bar utility")
        ProcessInfo.processInfo.enableSuddenTermination()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppTerminationController.shared.shouldAllowTermination {
            return .terminateNow
        }
        #if DEBUG
        return .terminateNow
        #else
        return .terminateCancel
        #endif
    }
}

@MainActor
final class AppShell: NSObject {
    static let shared = AppShell()

    private var context: AppContext?
    private var oauthStore: OAuthStore?
    private var settingsWindow: NSWindow?
    private var addAccountWindow: NSWindow?
    private var loginWindows: [UUID: WebLoginWindowController] = [:]
    private var windowCloseObserver: NSObjectProtocol?

    private override init() {}

    func configure(context: AppContext, oauthStore: OAuthStore) {
        self.context = context
        self.oauthStore = oauthStore
        NativeStatusItemController.shared.configure(context: context, oauthStore: oauthStore)
        // The task runs after the close finishes, so the closing window no longer counts as visible.
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.returnToMenuBarIfNoWindows() }
        }
    }

    func showSettingsWindow() {
        guard let context, let oauthStore else { return }

        if let settingsWindow {
            bringToFront(settingsWindow)
            return
        }

        let controller = NSHostingController(rootView: SettingsWindow().appEnvironment(context, oauthStore: oauthStore))
        let window = NSWindow(contentViewController: controller)
        window.title = "CoderSwitch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 720, height: 520)
        window.setContentSize(NSSize(width: 800, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("CoderSwitchSettings")
        settingsWindow = window
        bringToFront(window)
    }

    func showAddAccountWindow() {
        guard let context, let oauthStore else { return }

        if let addAccountWindow {
            bringToFront(addAccountWindow)
            return
        }

        let window = NSWindow()
        let root = AddAccountFlow(onFinish: { [weak window] in window?.close() })
            .appEnvironment(context, oauthStore: oauthStore)
        window.contentViewController = NSHostingController(rootView: root)
        window.title = "Add Account"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        addAccountWindow = window
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.addAccountWindow = nil }
        }
        bringToFront(window)
    }

    /// One login window per account; asking again focuses the existing one.
    func showLoginWindow(for account: Account) {
        guard let context else { return }

        if let existing = loginWindows[account.id] {
            existing.showWindow(nil)
            bringToFront(existing.window)
            return
        }

        let controller = WebLoginWindowController(account: account) { [weak self] in
            self?.loginWindows[account.id] = nil
            Task { await context.quotaPoller.pollOnce() }
        }
        loginWindows[account.id] = controller
        controller.showWindow(nil)
        bringToFront(controller.window)
    }

    private func bringToFront(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A regular app cannot show its popover over another app's full-screen Space, so macOS
    /// shows it on the desktop instead. Go back to a menu bar only app when the last window closes.
    private func returnToMenuBarIfNoWindows() {
        let hasOpenWindow = settingsWindow?.isVisible == true
            || addAccountWindow?.isVisible == true
            || loginWindows.values.contains { $0.window?.isVisible == true }
        guard !hasOpenWindow, NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class NativeStatusItemController: NSObject {
    static let shared = NativeStatusItemController()

    private var statusItem: NSStatusItem?
    private weak var context: AppContext?
    private weak var oauthStore: OAuthStore?
    private var popover: NSPopover?
    private weak var highlightedButton: NSButton?
    private var lastMeterState: MenuBarMeterState?
    private var defaultsObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var outsideClickMonitor: Any?

    private override init() {
        super.init()
    }

    func configure(context: AppContext, oauthStore: OAuthStore) {
        self.context = context
        self.oauthStore = oauthStore
    }

    func install() {
        guard context != nil, oauthStore != nil else { return }

        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.isVisible = true
        item.length = NSStatusItem.variableLength

        guard let button = item.button else { return }
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.setAccessibilityTitle("CoderSwitch")
        button.setAccessibilityIdentifier("CoderSwitch.NativeStatusItem")
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // The meter is not a template image, so it picks white or black itself.
        // Redraw when the menu bar switches between light and dark.
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.lastMeterState = nil
                self.apply(self.currentMeterState())
            }
        }
        startObservingMeter()
    }

    /// Redraws the meter whenever the account store changes. The tracking closure fires once,
    /// so each change re-arms it. Preference changes arrive through UserDefaults instead.
    private func observeMeter() {
        let state = withObservationTracking {
            currentMeterState()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeMeter() }
        }
        apply(state)
    }

    private func startObservingMeter() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.currentMeterState())
            }
        }
        observeMeter()
    }

    private func currentMeterState() -> MenuBarMeterState {
        let defaults = UserDefaults.standard
        return MenuBarMeterState.make(
            accounts: context?.accountStore.accounts ?? [],
            selection: defaults.string(forKey: UsagePreferences.followedAccountKey) ?? UsagePreferences.automaticFollow,
            showsPercentage: defaults.bool(forKey: UsagePreferences.showsPercentageKey)
        )
    }

    private func apply(_ state: MenuBarMeterState) {
        guard state != lastMeterState, let button = statusItem?.button else { return }
        lastMeterState = state
        button.image = MenuBarMeterRenderer.image(for: state)
        if let text = state.percentText {
            button.title = text
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = state.tooltip
        button.setAccessibilityValue(state.tooltip)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let context, let oauthStore else { return }

        if let popover, popover.isShown {
            closePopover()
            return
        }

        let popover = StatusPopoverPresenter.makePopover(
            context: context,
            oauthStore: oauthStore,
            delegate: self,
            actions: StatusPopoverActions(
                openSettings: { [weak self] in
                    self?.closePopover()
                    AppShell.shared.showSettingsWindow()
                },
                addAccount: { [weak self] in
                    self?.closePopover()
                    AppShell.shared.showAddAccountWindow()
                },
                signIn: { [weak self] account in
                    self?.closePopover()
                    AppShell.shared.showLoginWindow(for: account)
                }
            )
        )
        self.popover = popover
        highlightedButton = sender
        sender.isHighlighted = true
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        // Show on the current Space, also over another app's full-screen window.
        popover.contentViewController?.view.window?.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        startOutsideClickMonitor()
    }

    /// The app is not active while the popover is open, so `.transient` does not see clicks
    /// in other apps. A global monitor gets only those clicks; clicks on the status item stay local.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func closePopover() {
        popover?.close()
        popoverDidDismiss()
    }

    private func popoverDidDismiss() {
        popover = nil
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}

extension NativeStatusItemController: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        popoverDidDismiss()
    }
}

@MainActor
private enum StatusPopoverPresenter {
    static func makePopover(
        context: AppContext,
        oauthStore: OAuthStore,
        delegate: NSPopoverDelegate,
        actions: StatusPopoverActions
    ) -> NSPopover {
        let hosting = NSHostingController(
            rootView: StatusPopover(actions: actions).appEnvironment(context, oauthStore: oauthStore)
        )
        // The popover follows the SwiftUI content height, which StatusPopover caps with a scroll view.
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.layoutSubtreeIfNeeded()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
        popover.delegate = delegate
        return popover
    }
}

@MainActor
final class AppTerminationController {
    static let shared = AppTerminationController()
    private(set) var shouldAllowTermination = false

    private init() {}

    func allowTermination() {
        shouldAllowTermination = true
    }
}
