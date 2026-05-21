import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image("AppIcon")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("CoderSwitch")
                .font(.largeTitle.bold())

            VStack(spacing: 4) {
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("macOS 14.0+")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("A local proxy for managing AI subscriptions and API keys across multiple providers.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Divider()

            VStack(spacing: 4) {
                Text("Features")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    FeatureRow(icon: "key.fill", text: "Encrypted local credential storage")
                    FeatureRow(icon: "network", text: "Local proxy for Claude Code & Codex")
                    FeatureRow(icon: "chart.bar.fill", text: "Usage tracking and quota monitoring")
                    FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Multi-account provider support")
                }
            }

            Spacer()

            Text("© 2026 f9Labs. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 420, height: 480)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    AboutView()
}
