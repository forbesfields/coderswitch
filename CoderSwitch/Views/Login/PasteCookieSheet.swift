import SwiftUI
import CoderSwitchCore

/// Fallback for sites whose sign-in refuses embedded browsers (Google): sign in with a normal
/// browser, copy the site's cookie, and paste it into this account's own cookie jar.
struct PasteCookieSheet: View {
    let host: String
    let importCookies: (String) async throws -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a cookie from your browser")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                step(1, "In your normal browser, sign in to \(host).")
                step(2, "Open Developer Tools (⌥⌘I), select Network, and reload the page.")
                step(3, "Select a request to \(host). Under Request Headers, copy the whole Cookie value.")
                step(4, "Paste it below. A JSON export from a cookie extension also works.")
            }
            .font(.callout)

            TextEditor(text: $text)
                .font(.system(.caption, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("name=value; other=value")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Label(
                    "The cookie is a sign-in secret. It is kept only in this account's private cookie jar. To sign this account out later, delete the account.",
                    systemImage: "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    submit()
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Import")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() {
        isImporting = true
        errorMessage = nil
        Task {
            defer { isImporting = false }
            do {
                _ = try await importCookies(text)
                text = ""
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
