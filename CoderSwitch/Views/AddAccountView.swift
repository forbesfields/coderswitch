import SwiftUI

struct AddAccountView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var provider: Provider = .openRouter
    @State private var label: String = ""
    @State private var apiKey: String = ""
    @State private var customEndpoint: String = ""
    @State private var errorMessage: String?
    private let providers = Provider.allCases.filter(\.canAddWithAPIKey)

    private var canSave: Bool {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if provider.requiresCustomEndpoint {
            return !customEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
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

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420, height: 320)
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
            customEndpoint: customEndpoint.trimmingCharacters(in: .whitespaces)
        )
        do {
            try store.add(account, apiKey: apiKey.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
