import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConfigBackupTab: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(OAuthStore.self) private var oauthStore
    @Environment(ProxySettings.self) private var proxySettings
    @Environment(ProxyManager.self) private var proxyManager
    @Environment(RequestLogStore.self) private var requestLogStore
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Backup") {
                LabeledContent("Included") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(accountStore.accounts.count) API-key accounts")
                        Text("\(oauthStore.accounts.count) OAuth accounts")
                        Text("Proxy settings and account usage metadata")
                    }
                    .foregroundStyle(.secondary)
                }
                Button {
                    exportConfig()
                } label: {
                    Label("Export Config", systemImage: "square.and.arrow.up")
                }
                Text("The backup file contains decrypted API keys, OAuth tokens, and the proxy admin key. Keep it private and delete it when you no longer need it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Restore") {
                Button(role: .destructive) {
                    importConfig()
                } label: {
                    Label("Import Config", systemImage: "square.and.arrow.down")
                }
                Text("Import replaces the local CoderSwitch accounts, OAuth accounts, and proxy settings with the contents of the selected backup file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Delete User Data") {
                Button(role: .destructive) {
                    deleteAllUserData()
                } label: {
                    Label("Delete All User Data", systemImage: "trash")
                }
                Text("Deletes local accounts, API keys, OAuth tokens, proxy settings, and request logs. Export a backup first if you want to restore this data later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func exportConfig() {
        errorMessage = nil
        statusMessage = nil

        let panel = NSSavePanel()
        panel.title = "Export CoderSwitch Config"
        panel.nameFieldStringValue = "CoderSwitch Config \(Self.filenameDate()).coderswitchconfig"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.coderSwitchConfig]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let archive = ConfigBackupStore.exportArchive(
                accountStore: accountStore,
                oauthStore: oauthStore,
                proxySettings: proxySettings
            )
            try ConfigBackupStore.write(archive: archive, to: url)
            statusMessage = "Exported config to \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importConfig() {
        errorMessage = nil
        statusMessage = nil

        let panel = NSOpenPanel()
        panel.title = "Import CoderSwitch Config"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.coderSwitchConfig, .json]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmImport() else { return }

        do {
            let archive = try ConfigBackupStore.read(from: url)
            let wasRunning = proxyManager.status.isRunning
            try ConfigBackupStore.importArchive(
                archive,
                accountStore: accountStore,
                oauthStore: oauthStore,
                proxySettings: proxySettings
            )
            if wasRunning {
                proxyManager.restart()
            }
            statusMessage = "Imported config from \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmImport() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace local CoderSwitch config?"
        alert.informativeText = "This will replace local accounts, OAuth accounts, and proxy settings with the selected backup file."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func deleteAllUserData() {
        errorMessage = nil
        statusMessage = nil

        guard confirmDeleteAllUserData() else { return }

        do {
            proxyManager.stop()
            try ConfigBackupStore.deleteAllUserData(
                accountStore: accountStore,
                oauthStore: oauthStore,
                proxySettings: proxySettings,
                requestLogStore: requestLogStore
            )
            statusMessage = "Deleted local user data."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmDeleteAllUserData() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete all local CoderSwitch user data?"
        alert.informativeText = "This deletes local accounts, API keys, OAuth tokens, proxy settings, and request logs. You can only restore them if you exported a backup first."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func filenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: Date())
    }
}

private extension UTType {
    static let coderSwitchConfig = UTType(filenameExtension: "coderswitchconfig") ?? .json
}
