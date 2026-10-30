import SwiftUI
import CoderSwitchCore

/// Credential sources that need no secret typed here: Claude Code login, a provider CLI login,
/// or a web sign-in. The user only picks a label.
struct SourceAccountForm: View {
    let provider: Provider
    let source: AccountCredentialSource
    let submit: (Account, String?) throws -> Void

    @State private var label: String
    @State private var errorMessage: String?

    init(provider: Provider, source: AccountCredentialSource, submit: @escaping (Account, String?) throws -> Void) {
        self.provider = provider
        self.source = source
        self.submit = submit
        _label = State(initialValue: provider.displayName)
    }

    private var signsInAfterAdding: Bool { source == .webSession }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Label", text: $label, prompt: Text("e.g. Work \(provider.displayName)"))
                } footer: {
                    Text("Use a label that tells your accounts apart.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Section {
                    Label(source.explanation(for: provider), systemImage: source.symbolName)
                        .font(.callout)
                    if signsInAfterAdding {
                        Label(
                            "A sign-in window opens next. Cookies stay separate for each account.",
                            systemImage: "lock.shield"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            FlowActionBar(
                primaryTitle: signsInAfterAdding ? "Add and sign in" : "Add account",
                canSubmit: !label.trimmingCharacters(in: .whitespaces).isEmpty,
                errorMessage: errorMessage,
                action: save
            )
        }
    }

    private func save() {
        let account = Account(
            label: label.trimmingCharacters(in: .whitespaces),
            provider: provider,
            credentialSource: source
        )
        do {
            try submit(account, nil)
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}

extension AccountCredentialSource {
    var symbolName: String {
        switch self {
        case .apiKey: "key"
        case .oauth: "person.badge.key"
        case .claudeCodeKeychain: "terminal"
        case .webSession: "globe"
        case .localCLI: "terminal"
        }
    }

    /// One line shown when the user picks a credential source.
    func explanation(for provider: Provider) -> String {
        switch self {
        case .apiKey: "Paste an API key. CoderSwitch stores it encrypted on this Mac."
        case .oauth: "Sign in with your browser. CoderSwitch keeps the tokens."
        case .claudeCodeKeychain: "Reads your current Claude Code login. Read-only."
        case .webSession: "Sign in to \(provider.displayName) in a CoderSwitch window with its own cookies."
        case .localCLI: "Uses the login the \(provider.displayName) CLI already saved on this Mac. Read-only."
        }
    }
}
