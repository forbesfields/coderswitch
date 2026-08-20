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
        MenuBarPlaceholderController.shared.install()
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

// MARK: - Codex placeholder (remove after user confirms real menu bar icon works)

@MainActor
final class MenuBarPlaceholderController: NSObject {
    static let shared = MenuBarPlaceholderController()

    private var windows: [NSWindow] = []
    private weak var context: AppContext?
    private weak var oauthStore: OAuthStore?
    private var popover: NSPopover?
    private weak var highlightedButton: NSButton?

    private override init() {
        super.init()
    }

    func configure(context: AppContext, oauthStore: OAuthStore) {
        self.context = context
        self.oauthStore = oauthStore
    }

    func install() {
        guard context != nil, oauthStore != nil else { return }
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let size = NSSize(width: 46, height: 22)
            let frame = NSRect(
                x: max(screen.frame.minX + 24, screen.frame.maxX - 760),
                y: screen.frame.maxY - size.height - 2,
                width: size.width,
                height: size.height
            )

            let button = NSButton(frame: NSRect(origin: .zero, size: size))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.masksToBounds = true
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            button.attributedTitle = NSAttributedString(
                string: "CS",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: NSColor.systemBlue
                ]
            )
            button.toolTip = "CoderSwitch (placeholder)"
            button.setAccessibilityTitle("CoderSwitch")
            button.setAccessibilityIdentifier("CoderSwitch.PlaceholderStatusItem")
            button.target = self
            button.action = #selector(togglePopover(_:))

            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentView = button
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            panel.orderFrontRegardless()
            return panel
        }
    }

    @objc private func togglePopover(_ sender: NSButton) {
        guard let context, let oauthStore else { return }

        if let popover, popover.isShown {
            closePopover()
            return
        }

        let popover = StatusPopoverPresenter.makePopover(
            context: context,
            oauthStore: oauthStore,
            delegate: self,
            openSettings: { [weak self] in
                self?.closePopover()
                AppShell.shared.showSettingsWindow()
            }
        )
        self.popover = popover
        highlightedButton = sender
        sender.isHighlighted = true
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.close()
        popover = nil
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
    }
}

extension MenuBarPlaceholderController: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        popover = nil
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
    }
}

@MainActor
final class AppShell: NSObject {
    static let shared = AppShell()

    private var context: AppContext?
    private var oauthStore: OAuthStore?
    private var settingsWindow: NSWindow?

    private override init() {}

    func configure(context: AppContext, oauthStore: OAuthStore) {
        self.context = context
        self.oauthStore = oauthStore
        NativeStatusItemController.shared.configure(context: context, oauthStore: oauthStore)
        MenuBarPlaceholderController.shared.configure(context: context, oauthStore: oauthStore)
    }

    func showSettingsWindow() {
        guard let context, let oauthStore else { return }

        if let settingsWindow {
            NSApp.setActivationPolicy(.regular)
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(
            rootView: SettingsWindow()
                .environment(context.accountStore)
                .environment(context.proxySettings)
                .environment(context.proxyManager)
                .environment(context.quotaPoller)
                .environment(context.requestLogStore)
                .environment(oauthStore)
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "CoderSwitch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private override init() {
        super.init()
    }

    func configure(context: AppContext, oauthStore: OAuthStore) {
        self.context = context
        self.oauthStore = oauthStore
    }

    func install() {
        guard context != nil, oauthStore != nil else { return }

        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: 32)
        statusItem = item
        item.isVisible = true
        item.length = 32

        guard let button = item.button else { return }
        button.image = nil
        button.title = "CS"
        button.toolTip = "CoderSwitch"
        button.setAccessibilityTitle("CoderSwitch")
        button.setAccessibilityIdentifier("CoderSwitch.NativeStatusItem")
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
            openSettings: { [weak self] in
                self?.closePopover()
                AppShell.shared.showSettingsWindow()
            }
        )
        self.popover = popover
        highlightedButton = sender
        sender.isHighlighted = true
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.close()
        popover = nil
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
    }
}

extension NativeStatusItemController: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        popover = nil
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
    }
}

@MainActor
private enum StatusPopoverPresenter {
    static let contentSize = NSSize(width: 340, height: 720)

    static func makePopover(
        context: AppContext,
        oauthStore: OAuthStore,
        delegate: NSPopoverDelegate,
        openSettings: @escaping () -> Void
    ) -> NSPopover {
        let content = ScrollView {
            StatusPopover(openSettings: openSettings)
                .environment(context.accountStore)
                .environment(context.proxySettings)
                .environment(context.proxyManager)
                .environment(context.quotaPoller)
                .environment(context.requestLogStore)
                .environment(oauthStore)
        }
        .frame(width: contentSize.width, height: contentSize.height)

        let hosting = NSHostingController(rootView: content)
        hosting.preferredContentSize = contentSize
        hosting.view.frame = NSRect(origin: .zero, size: contentSize)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = contentSize
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
