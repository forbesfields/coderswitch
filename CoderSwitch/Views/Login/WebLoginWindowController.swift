import AppKit
import SwiftUI
import CoderSwitchCore

/// In-app browser window where the user signs in to a usage site. One per account.
@MainActor
final class WebLoginWindowController: NSWindowController, NSWindowDelegate {
    private let model: WebLoginModel
    private let onClose: () -> Void

    init(account: Account, onClose: @escaping () -> Void) {
        model = WebLoginModel(account: account)
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to \(account.provider == .customWeb ? account.label : account.provider.displayName)"
        window.contentMinSize = NSSize(width: 420, height: 520)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)

        window.delegate = self
        window.contentView = NSHostingView(
            rootView: WebLoginView(model: model, onDone: { [weak window] in window?.close() })
        )
        window.center()
        model.load()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        onClose()
    }
}
