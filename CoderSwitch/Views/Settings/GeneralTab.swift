import SwiftUI
import ServiceManagement
import CoderSwitchCore

struct GeneralTab: View {
    @Environment(AccountStore.self) private var store
    @Environment(QuotaPoller.self) private var poller

    @AppStorage(UsagePreferences.followedAccountKey) private var followedAccount = UsagePreferences.automaticFollow
    @AppStorage(UsagePreferences.showsPercentageKey) private var showsPercentage = false
    @AppStorage(UsagePreferences.refreshMinutesKey) private var refreshMinutes = UsagePreferences.defaultRefreshMinutes

    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Favourite account", selection: followedSelection) {
                    Text("Automatic (highest usage)").tag(UsagePreferences.automaticFollow)
                    ForEach(store.accounts) { account in
                        Text("\(account.provider.displayName) · \(account.label)").tag(account.id.uuidString)
                    }
                }
                Toggle("Show percentage next to the meter", isOn: $showsPercentage)
                LabeledContent("Preview") {
                    MenuBarMeterPreview(state: previewState)
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("The menu bar shows the favourite account's logo. The top bar is session usage and the bottom bar is weekly usage. A bar turns orange above 50% and red above 80%. Automatic follows the enabled account closest to its limit.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Refresh") {
                Picker("Check usage every", selection: $refreshMinutes) {
                    ForEach(UsagePreferences.refreshMinuteOptions, id: \.self) { minutes in
                        Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                    }
                }
                .onChange(of: refreshMinutes) {
                    poller.interval = UsagePreferences.refreshInterval()
                    // Restart so a long wait from the old interval does not linger.
                    poller.stop()
                    poller.start()
                }
            }

            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    /// An account that was deleted falls back to Automatic instead of showing an empty picker.
    private var followedSelection: Binding<String> {
        Binding(
            get: {
                store.accounts.contains { $0.id.uuidString == followedAccount }
                    ? followedAccount : UsagePreferences.automaticFollow
            },
            set: { followedAccount = $0 }
        )
    }

    private var previewState: MenuBarMeterState {
        MenuBarMeterState.make(accounts: store.accounts, selection: followedAccount, showsPercentage: showsPercentage)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { setLaunchAtLogin($0) }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not change launch at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}

/// Shows the menu bar meter the way it looks in the bar.
struct MenuBarMeterPreview: View {
    let state: MenuBarMeterState

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarMeterRenderer.image(for: state))
            if let text = state.percentText {
                Text(text)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .help(state.tooltip)
    }
}
