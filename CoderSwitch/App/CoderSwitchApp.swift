import SwiftUI
import AppKit

@main
struct CoderSwitchApp: App {
    @State private var context = AppContext()
    private let oauthStore = OAuthStore.shared

    var body: some Scene {
        MenuBarExtra("CoderSwitch", image: "CoderSwitchMenuBarIcon") {
            StatusPopover()
                .environment(context.accountStore)
                .environment(context.proxySettings)
                .environment(context.proxyManager)
                .environment(context.quotaPoller)
                .environment(context.requestLogStore)
                .environment(oauthStore)
            Divider()
            Button("About CoderSwitch") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationIcon: NSImage(named: "CoderSwitchAppIcon") ?? NSApplication.shared.applicationIconImage
                ])
            }
        }
        .menuBarExtraStyle(.window)

        Window("CoderSwitch Settings", id: "settings") {
            SettingsWindow()
                .environment(context.accountStore)
                .environment(context.proxySettings)
                .environment(context.proxyManager)
                .environment(context.quotaPoller)
                .environment(context.requestLogStore)
                .environment(oauthStore)
        }
        .windowResizability(.contentSize)

        Settings {
            Text("CoderSwitch")
        }
    }
}
