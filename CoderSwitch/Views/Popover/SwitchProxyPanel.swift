import SwiftUI
import CoderSwitchCore

/// One account the user can switch a CLI to.
struct SwitchTarget: Identifiable, Equatable {
    let id: UUID
    let title: String
    var subtitle: String?
}

struct SwitchGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let targets: [SwitchTarget]
}

struct SwitchMessage: Equatable {
    let text: String
    let isError: Bool
}

/// Switch and proxy half of the popover. Pure view: the container wires real actions.
struct SwitchProxyPanel: View {
    let proxyStatus: ProxyManager.Status
    let baseURL: String
    let claudeTargets: [SwitchTarget]
    let oauthGroups: [SwitchGroup]
    var busyTargetID: UUID?
    var message: SwitchMessage?
    let onStartProxy: () -> Void
    let onStopProxy: () -> Void
    let onCopyURL: () -> Void
    let onOpenClaude: (UUID) -> Void
    let onRestoreOfficialClaude: () -> Void
    let onSwitchOAuth: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Switch & Proxy", systemImage: "arrow.left.arrow.right")
            ProxyStatusCard(
                status: proxyStatus,
                baseURL: baseURL,
                onStart: onStartProxy,
                onStop: onStopProxy,
                onCopy: onCopyURL
            )
            claudeCard
            ForEach(oauthGroups) { group in
                groupCard(title: group.title, symbolName: group.symbolName) {
                    ForEach(group.targets) { target in
                        Button { onSwitchOAuth(target.id) } label: {
                            TargetRow(
                                title: target.title,
                                subtitle: target.subtitle,
                                trailingSymbol: "arrow.left.arrow.right",
                                isBusy: busyTargetID == target.id
                            )
                        }
                        .buttonStyle(HoverRowButtonStyle())
                        .disabled(busyTargetID != nil)
                    }
                }
            }
            if let message {
                Label(message.text, systemImage: message.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(message.isError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var claudeCard: some View {
        groupCard(title: "Claude Code", symbolName: "terminal") {
            ForEach(claudeTargets) { target in
                Button { onOpenClaude(target.id) } label: {
                    TargetRow(title: target.title, subtitle: target.subtitle, trailingSymbol: "arrow.up.forward.app")
                }
                .buttonStyle(HoverRowButtonStyle())
                .help("Choose a folder and open Claude Code with this account")
            }
            Button(action: onRestoreOfficialClaude) {
                TargetRow(title: "Official Claude", subtitle: "Restore your own login", trailingSymbol: "arrow.uturn.backward")
            }
            .buttonStyle(HoverRowButtonStyle())
            if claudeTargets.isEmpty {
                Text("Add an Anthropic-compatible API key account to open Claude Code through the proxy.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }
        }
    }

    private func groupCard<Rows: View>(
        title: String,
        symbolName: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)
            rows()
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct TargetRow: View {
    let title: String
    var subtitle: String?
    let trailingSymbol: String
    var isBusy = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: trailingSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProxyStatusCard: View {
    let status: ProxyManager.Status
    let baseURL: String
    let onStart: () -> Void
    let onStop: () -> Void
    let onCopy: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(pillText)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
                Spacer()
                if status.isRunning {
                    Button(action: copy) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .frame(width: 14)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy proxy URL")
                    .accessibilityLabel("Copy proxy URL")
                    Button("Stop", action: onStop)
                        .controlSize(.small)
                } else {
                    Button("Start", action: onStart)
                        .controlSize(.small)
                        .disabled(isTransitioning)
                }
            }
            if status.isRunning {
                Text(baseURL)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if case .failed(let reason) = status {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func copy() {
        onCopy()
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    private var isTransitioning: Bool {
        status == .starting || status == .stopping
    }

    private var tint: Color {
        switch status {
        case .running: .green
        case .starting, .stopping: .yellow
        case .stopped: .secondary
        case .failed: .red
        }
    }

    private var pillText: String {
        switch status {
        case .stopped: "Proxy stopped"
        case .starting: "Starting…"
        case .running(let port): "Proxy running · :\(port)"
        case .stopping: "Stopping…"
        case .failed: "Proxy failed"
        }
    }
}
