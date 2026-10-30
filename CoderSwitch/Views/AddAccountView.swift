import SwiftUI
import CoderSwitchCore

struct AddAccountView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var provider: Provider = .openRouter
    @State private var label: String = ""
    @State private var apiKey: String = ""
    @State private var customEndpoint: String = ""
    @State private var hasAccessGainedAt = false
    @State private var accessGainedAt = Date()
    @State private var hasAccessDuration = false
    @State private var accessDurationValue = "1"
    @State private var accessDurationUnit: AccountAccessDurationUnit = .month
    @State private var errorMessage: String?
    private let providers = Provider.allCases.filter(\.canAddWithAPIKey)

    private var canSave: Bool {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if hasAccessDuration && parsedAccessDuration == nil { return false }
        if provider.requiresCustomEndpoint {
            return !customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private var parsedAccessDuration: AccountAccessDuration? {
        guard hasAccessDuration else { return nil }
        guard let value = Int(accessDurationValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0 else { return nil }
        return AccountAccessDuration(value: value, unit: accessDurationUnit)
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(providers) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                TextField("Label", text: $label, prompt: Text("e.g. Personal OpenRouter"))
                SecureField("API Key", text: $apiKey)
                TextField(
                    "Custom Endpoint",
                    text: $customEndpoint,
                    prompt: Text(
                        provider.requiresCustomEndpoint
                            ? "https://api.example.com/v1"
                            : "Optional override"
                    )
                )
            }

            Section("Access") {
                Toggle("Track access date", isOn: $hasAccessGainedAt)
                if hasAccessGainedAt {
                    DatePicker(
                        "Gained access",
                        selection: $accessGainedAt,
                        displayedComponents: .date
                    )
                }
                Toggle("Track account period", isOn: $hasAccessDuration)
                if hasAccessDuration {
                    HStack {
                        TextField("Period", text: $accessDurationValue)
                            .frame(width: 72)
                        Picker("Unit", selection: $accessDurationUnit) {
                            ForEach(AccountAccessDurationUnit.allCases) { unit in
                                Text(unit.displayName(for: durationValueForLabel)).tag(unit)
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420, height: 460)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .navigationTitle("Add Account")
    }

    private func save() {
        let account = Account(
            label: label.trimmingCharacters(in: .whitespaces),
            provider: provider,
            customEndpoint: customEndpoint.trimmingCharacters(in: .whitespaces),
            defaultModel: provider.defaultModel,
            availableModels: provider.bundledModels.nonEmpty,
            accessGainedAt: hasAccessGainedAt ? accessGainedAt : nil,
            accessDuration: parsedAccessDuration
        )
        do {
            try store.add(account, apiKey: apiKey.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private var durationValueForLabel: Int {
        Int(accessDurationValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 2
    }
}

private extension Array {
    var nonEmpty: [Element]? { isEmpty ? nil : self }
}
