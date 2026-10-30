import SwiftUI
import CoderSwitchCore

struct StatusPopoverActions {
    var openSettings: () -> Void
    var addAccount: () -> Void
    var signIn: (Account) -> Void
}

/// Menu bar popover: usage cards and the switch and proxy panel in equal-weight sections.
struct StatusPopover: View {
    let actions: StatusPopoverActions

    @Environment(AccountStore.self) private var store
    @Environment(QuotaPoller.self) private var poller

    private var usageAccounts: [Account] {
        store.accountsByProvider.flatMap(\.1).filter(\.isEnabled)
    }

    var body: some View {
        PopoverScaffold {
            PopoverHeader(
                lastUpdated: poller.lastRunAt,
                isRefreshing: poller.isPolling,
                onRefresh: { Task { await poller.pollOnce() } }
            )
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                UsageSection(
                    accounts: usageAccounts,
                    hasAnyAccounts: !store.accounts.isEmpty,
                    isPolling: poller.isPolling,
                    onSignIn: actions.signIn,
                    onOpenSettings: actions.openSettings,
                    onAddAccount: actions.addAccount
                )
                SwitchProxySection()
            }
            .padding(14)
        } footer: {
            PopoverFooter(
                onAddAccount: actions.addAccount,
                onOpenSettings: actions.openSettings,
                onQuit: {
                    AppTerminationController.shared.allowTermination()
                    NSApplication.shared.terminate(nil)
                }
            )
        }
    }
}
