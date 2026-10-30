import SwiftUI
import CoderSwitchCore

/// Pure URL checks for the custom web form.
enum WebURLValidation {
    /// True for an https URL with a host and no embedded credentials.
    static func isValidHTTPS(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return false }
        return true
    }
}

/// Describes one metric row while the user is still typing.
private struct MetricDraft: Identifiable {
    let id = UUID()
    var name = ""
    var usedPath = ""
    var limitPath = ""
    var resetPath = ""
    var window: UsageWindow?

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !usedPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var metric: WebUsageMetric {
        WebUsageMetric(
            name: name.trimmingCharacters(in: .whitespaces),
            usedPath: usedPath.trimmingCharacters(in: .whitespaces),
            limitPath: limitPath.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            resetPath: resetPath.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            window: window
        )
    }
}

/// Add-account form for any site that shows usage as JSON after sign-in.
struct CustomWebAccountForm: View {
    let submit: (Account, String?) throws -> Void

    @State private var name = ""
    @State private var loginURL = ""
    @State private var usageURL = ""
    @State private var metrics = [MetricDraft()]
    @State private var errorMessage: String?

    private var loginURLIsValid: Bool { WebURLValidation.isValidHTTPS(loginURL) }
    private var usageURLIsValid: Bool { WebURLValidation.isValidHTTPS(usageURL) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && loginURLIsValid && usageURLIsValid
            && !metrics.isEmpty && metrics.allSatisfy(\.isComplete)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Site") {
                    TextField("Name", text: $name, prompt: Text("e.g. Acme AI"))
                    TextField("Login page", text: $loginURL, prompt: Text("https://example.com/login"))
                    urlHint(for: loginURL, isValid: loginURLIsValid)
                    TextField("Usage JSON URL", text: $usageURL, prompt: Text("https://example.com/api/usage"))
                    urlHint(for: usageURL, isValid: usageURLIsValid)
                }

                ForEach($metrics) { $metric in
                    Section {
                        TextField("Name", text: $metric.name, prompt: Text("e.g. Session"))
                        TextField("Used path", text: $metric.usedPath, prompt: Text("data.usage.used"))
                        TextField("Limit path", text: $metric.limitPath, prompt: Text("Optional. Blank = used is a percent"))
                        TextField("Reset path", text: $metric.resetPath, prompt: Text("Optional, e.g. data.usage.resetsAt"))
                        Picker("Window", selection: $metric.window) {
                            Text("None").tag(UsageWindow?.none)
                            ForEach(UsageWindow.allCases, id: \.self) { window in
                                Text(window.title).tag(UsageWindow?.some(window))
                            }
                        }
                    } header: {
                        HStack {
                            Text("Metric \((metrics.firstIndex { $0.id == metric.id } ?? 0) + 1)")
                            Spacer()
                            if metrics.count > 1 {
                                Button {
                                    metrics.removeAll { $0.id == metric.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this metric")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        metrics.append(MetricDraft())
                    } label: {
                        Label("Add metric", systemImage: "plus")
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paths use dots and array positions, like data.plans[0].used. Leave Limit blank when the page already reports a 0–100 percent. Window tells the menu bar which value is session or weekly usage.")
                        Text("Example: {\"data\":{\"used\":42,\"limit\":100,\"resetsAt\":\"2026-11-01T00:00:00Z\"}} uses data.used, data.limit, and data.resetsAt.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            FlowActionBar(
                primaryTitle: "Add and sign in",
                canSubmit: canSave,
                errorMessage: errorMessage,
                action: save
            )
        }
    }

    @ViewBuilder
    private func urlHint(for text: String, isValid: Bool) -> some View {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty && !isValid {
            Text("Use a full https:// address.")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func save() {
        let account = Account(
            label: name.trimmingCharacters(in: .whitespaces),
            provider: .customWeb,
            credentialSource: .webSession,
            webUsage: WebUsageConfig(
                loginURL: loginURL.trimmingCharacters(in: .whitespacesAndNewlines),
                usageURL: usageURL.trimmingCharacters(in: .whitespacesAndNewlines),
                metrics: metrics.map(\.metric)
            )
        )
        do {
            try submit(account, nil)
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
