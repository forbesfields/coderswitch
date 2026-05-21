import SwiftUI

struct ProxyTab: View {
    @Environment(ProxySettings.self) private var settings
    @Environment(ProxyManager.self) private var proxy
    @Environment(RequestLogStore.self) private var requestLogStore
    @State private var portText = ""
    @State private var showKey = false
    @State private var hideKeyTask: Task<Void, Never>?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Setup Checklist") {
                SetupCheckRow(title: "Codex auth", path: "~/.codex/auth.json", isPresent: fileExists(".codex/auth.json"))
                SetupCheckRow(title: "Codex config", path: "~/.codex/config.toml", isPresent: fileExists(".codex/config.toml"))
                SetupCheckRow(title: "Claude config", path: "~/.claude/config.json", isPresent: fileExists(".claude/config.json"))
                SetupCheckRow(title: "Gemini env", path: "~/.gemini/.env", isPresent: fileExists(".gemini/.env"))
                SetupCheckRow(title: "CLIProxyAPI auth", path: "~/.cli-proxy-api", isPresent: fileExists(".cli-proxy-api"))
            }

            Section("Server") {
                LabeledContent("Status") {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if proxy.status.isRunning {
                            Button("Stop") { proxy.stop() }
                            Button("Restart") { proxy.restart() }
                        } else {
                            Button("Start") { proxy.start() }
                        }
                    }
                }
                HStack {
                    TextField("Port", text: $portText)
                        .frame(width: 100)
                        .onAppear { portText = String(settings.port) }
                    Button("Apply") {
                        if let p = Int(portText), p > 0, p < 65536 {
                            settings.port = p
                            if proxy.status.isRunning { proxy.restart() }
                        }
                    }
                    Spacer()
                }
                LabeledContent("Base URL") {
                    HStack {
                        Text(settings.baseURL)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.baseURL, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Toggle("Start proxy when app launches", isOn: $settings.autoStart)
            }

            Section("Admin Key") {
                LabeledContent("Key") {
                    HStack {
                        if showKey {
                            Text(settings.adminKey)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            Text(String(repeating: "•", count: min(settings.adminKey.count, 24)))
                                .font(.system(.caption, design: .monospaced))
                        }
                        Spacer()
                        Button(showKey ? "Hide" : "Show") {
                            toggleKey()
                        }
                        .buttonStyle(.borderless)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(settings.adminKey, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy admin key")
                    }
                }
                Button("Regenerate Key") {
                    settings.regenerateKey()
                }
                Text("Key auto-hides after 10 seconds. Send as `Authorization: Bearer <key>` for OpenAI-compatible requests, or `x-api-key: <key>` for Anthropic-compatible requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Usage") {
                Text("Point Claude Code at this proxy:")
                    .font(.caption)
                Text("ANTHROPIC_BASE_URL=\(settings.baseURL)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("Point Codex / OpenAI clients at this proxy:")
                    .font(.caption)
                Text("OPENAI_BASE_URL=\(settings.baseURL)/v1")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section {
                if requestLogStore.logs.isEmpty {
                    Text("No requests recorded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(requestLogStore.logs.prefix(12)) { log in
                        RequestLogRow(log: log)
                    }
                }
            } header: {
                HStack {
                    Text("Recent Requests")
                    Spacer()
                    Button("Clear") {
                        requestLogStore.clear()
                    }
                    .disabled(requestLogStore.logs.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func toggleKey() {
        showKey.toggle()
        hideKeyTask?.cancel()
        if showKey {
            hideKeyTask = Task {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled {
                    showKey = false
                }
            }
        }
    }

    private var statusColor: Color {
        switch proxy.status {
        case .running: .green
        case .starting, .stopping: .yellow
        case .stopped: .secondary
        case .failed: .red
        }
    }

    private var statusText: String {
        switch proxy.status {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running(let port): "Running on :\(port)"
        case .stopping: "Stopping…"
        case .failed(let m): "Failed: \(m)"
        }
    }

    private func fileExists(_ relativePath: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }
}

private struct SetupCheckRow: View {
    let title: String
    let path: String
    let isPresent: Bool

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                Image(systemName: isPresent ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isPresent ? .green : .secondary)
            }
        }
    }
}

private struct RequestLogRow: View {
    let log: ProxyRequestLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(log.method)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(log.path)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(log.statusSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(statusColor)
                Text("\(log.latencyMS) ms")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(log.routeSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !log.usage.isEmpty {
                    Text("\(formatLogTokens(log.usage.totalTokens)) tokens")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if let error = log.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        guard let status = log.statusCode else { return .secondary }
        switch status {
        case 200..<300: return .green
        case 400..<500: return .orange
        case 500...: return .red
        default: return .secondary
        }
    }
}

private func formatLogTokens(_ value: Int) -> String {
    switch value {
    case 1_000_000...:
        String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...:
        String(format: "%.1fK", Double(value) / 1_000)
    default:
        "\(value)"
    }
}
