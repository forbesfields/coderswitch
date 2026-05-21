import SwiftUI

struct SettingsWindow: View {
    @State private var selectedTab: Tab = .accounts

    enum Tab: Hashable { case accounts, proxy, usage, oauth, backup }

    var body: some View {
        TabView(selection: $selectedTab) {
            AccountsTab()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(Tab.accounts)
            OAuthAccountsTab()
                .tabItem { Label("OAuth", systemImage: "person.badge.key.fill") }
                .tag(Tab.oauth)
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
