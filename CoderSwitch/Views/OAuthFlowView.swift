import SwiftUI

struct OAuthFlowView: View {
    let provider: OAuthProvider
    @Binding var isAuthenticating: Bool
    @Binding var authError: String?
    let onComplete: () -> Void

    @Environment(OAuthStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: provider.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Connect \(provider.displayName)")
                .font(.title2)
                .fontWeight(.semibold)

            Text(isAuthenticating
                 ? "Approve the request in your browser. If you closed the tab without signing in, click Cancel and try again."
                 : "Click 'Start Authentication' to begin the OAuth flow. After approval, CoderSwitch will write a CLIProxyAPI auth file.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.red.opacity(0.1))
                    .cornerRadius(8)
            }

            if isAuthenticating {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for authorization…")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if isAuthenticating {
                    Button("Reopen browser") {
                        reopenBrowser()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Start Authentication") {
                        startAuth()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 420, height: 340)
        .onDisappear {
            if isAuthenticating {
                store.cancelOAuthFlow()
                isAuthenticating = false
            }
        }
    }

    private func startAuth() {
        isAuthenticating = true
        authError = nil

        Task {
            do {
                try await store.initiateOAuthFlow(provider: provider) { result in
                    DispatchQueue.main.async {
                        isAuthenticating = false
                        switch result {
                        case .success:
                            onComplete()
                        case .failure(let error):
                            if case OAuthError.cancelled = error {
                                authError = nil
                            } else {
                                authError = error.localizedDescription
                            }
                        }
                    }
                }
            } catch {
                authError = error.localizedDescription
                isAuthenticating = false
            }
        }
    }

    private func cancel() {
        store.cancelOAuthFlow()
        isAuthenticating = false
        authError = nil
    }

    private func reopenBrowser() {
        Task {
            if let url = try? await store.currentAuthURL(for: provider) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
