import SwiftUI
import CoderSwitchCore

struct SettingsWindow: View {
    @State private var selectedTab: Tab = .general

    enum Tab: Hashable { case general, accounts, signIns, proxy, usage, backup }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(Tab.accounts)
            OAuthAccountsTab()
                .tabItem { Label("Sign-ins", systemImage: "person.badge.key.fill") }
                .tag(Tab.signIns)
            ProxyTab()
                .tabItem { Label("Proxy", systemImage: "network") }
                .tag(Tab.proxy)
            UsageTab()
                .tabItem { Label("Usage", systemImage: "chart.bar.xaxis") }
                .tag(Tab.usage)
            ConfigBackupTab()
                .tabItem { Label("Backup", systemImage: "externaldrive") }
                .tag(Tab.backup)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
