import SwiftUI

struct CircuitBreakerSheet: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let account: Account

    @State private var enabled: Bool
    @State private var thresholdText: String
    @State private var windowMinutesText: String

    init(account: Account) {
        self.account = account
        self._enabled = State(initialValue: account.circuitBreaker.enabled)
        self._thresholdText = State(initialValue: String(account.circuitBreaker.failureThreshold))
        self._windowMinutesText = State(initialValue: String(Int(account.circuitBreaker.windowSeconds / 60)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Circuit Breaker")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(account.label)
                    .foregroundStyle(.secondary)
            }

            Text("Warn when failures exceed the threshold within a rolling time window. Routing always continues — this never auto-excludes the account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                Toggle("Enabled", isOn: $enabled)
                LabeledContent("Failure threshold") {
                    TextField("5", text: $thresholdText)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .disabled(!enabled)
                }
                LabeledContent("Window (minutes)") {
                    TextField("5", text: $windowMinutesText)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .disabled(!enabled)
                }
                LabeledContent("Recent failures") {
                    HStack {
                        Text("\(account.recentFailures.count)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            store.clearFailures(accountID: account.id)
                        }
                        .buttonStyle(.borderless)
                        .disabled(account.recentFailures.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func save() {
        let threshold = max(1, Int(thresholdText) ?? 5)
        let minutes = max(1, Int(windowMinutesText) ?? 5)
        store.setCircuitBreaker(
            accountID: account.id,
            config: CircuitBreakerConfig(
                enabled: enabled,
                failureThreshold: threshold,
                windowSeconds: TimeInterval(minutes * 60)
            )
        )
    }
}
