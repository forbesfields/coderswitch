import SwiftUI
import CoderSwitchCore

/// One account's usage: headline bars, a short list of other limits, and an error state with an action.
struct AccountUsageCard: View {
    let account: Account
    var isChecking = false
    var now = Date()
    var startsExpanded = false
    let onSignIn: () -> Void
    let onOpenSettings: () -> Void

    @State private var showsOthers = false

    private var summary: AccountUsageSummary { account.usageSummary }
    private var hasData: Bool { !summary.headlines.isEmpty || !summary.others.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = account.lastCheckError {
                ErrorBanner(
                    message: error,
                    actionTitle: account.usesWebSession ? "Sign in" : "Open Settings",
                    action: account.usesWebSession ? onSignIn : onOpenSettings
                )
            }
            if hasData {
                limits.opacity(account.lastCheckError == nil ? 1 : 0.5)
            } else if account.lastCheckError == nil {
                placeholder
            }
            tokenLine
        }
        .padding(12)
        .cardStyle()
        .onAppear { showsOthers = startsExpanded }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(account.provider.displayName), \(account.label)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderGlyph(provider: account.provider, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.provider.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(account.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isChecking {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var limits: some View {
        ForEach(summary.headlines) { headline in
            UsageMeterRow(title: headline.title, limit: headline.limit, now: now)
        }
        if !summary.others.isEmpty {
            if summary.others.count <= 2 {
                otherRows
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showsOthers.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showsOthers ? 90 : 0))
                        Text(showsOthers ? "Hide other limits" : "\(summary.others.count) other limits")
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showsOthers { otherRows }
            }
        }
    }

    private var otherRows: some View {
        VStack(spacing: 6) {
            ForEach(summary.others) { CompactLimitRow(limit: $0) }
        }
    }

    @ViewBuilder
    private var tokenLine: some View {
        let allTime = account.tokenUsageTotal(period: .allTime)
        if !allTime.isEmpty {
            let today = account.tokenUsageTotal(period: .today)
            Text("Tokens today \(UsageFormat.tokens(today.processedTokens)) · all time \(UsageFormat.tokens(allTime.processedTokens))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        if isChecking || account.lastCheckedAt == nil && account.provider.supportsUsagePolling {
            Label(isChecking ? "Checking usage…" : "Waiting for the first check", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !account.provider.supportsUsagePolling {
            Label("Proxy only. This provider reports no usage.", systemImage: "minus.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("No usage limits reported", systemImage: "tray")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
