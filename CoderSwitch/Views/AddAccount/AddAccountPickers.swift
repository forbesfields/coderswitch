import SwiftUI
import CoderSwitchCore

/// Step 1 of the add-account flow: providers grouped by how they are paid for and signed in to.
struct ProviderPickerList: View {
    let onPick: (Provider) -> Void

    private struct Group: Identifiable {
        let title: String
        let providers: [Provider]
        var id: String { title }
    }

    private let groups = [
        Group(title: "Subscriptions", providers: [.claude, .codex, .commandCode, .opencodeGo, .googleAntigravity]),
        Group(title: "API keys", providers: [.openRouter, .refuseless, .miniMax, .glmCodingPlan, .kimiCodingPlan, .qwenCodingPlan, .openAI, .anthropic]),
        Group(title: "Custom", providers: [.customWeb, .openAICompatible, .anthropicCompatible]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: group.title)
                            .padding(.horizontal, 8)
                        ForEach(group.providers) { provider in
                            Button { onPick(provider) } label: {
                                HStack(spacing: 10) {
                                    ProviderGlyph(provider: provider, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(provider.displayName).font(.callout)
                                        if let detail = provider.addDetail {
                                            Text(detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(HoverRowButtonStyle())
                        }
                    }
                }
            }
            .padding(14)
        }
    }
}

private extension Provider {
    var addDetail: String? {
        switch self {
        case .claude: "Track Claude Pro or Max session and weekly usage"
        case .codex: "Track usage and switch the Codex CLI account"
        case .commandCode: "Track Command Code usage"
        case .refuseless: "Abliterated open models, dollar balance"
        case .opencodeGo: "API key for routing, web sign-in for usage"
        case .googleAntigravity: "Track Google model quotas"
        case .customWeb: "Any site that shows usage as JSON after sign-in"
        case .openAICompatible, .anthropicCompatible: "Your own endpoint and API key"
        default: nil
        }
    }
}

/// Step 2: the credential sources a provider supports, each with a one-line explanation.
struct SourcePickerList: View {
    let provider: Provider
    let onPick: (AccountCredentialSource) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(provider.supportedCredentialSources) { source in
                    Button { onPick(source) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: source.symbolName)
                                .font(.system(size: 15))
                                .frame(width: 28, height: 28)
                                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName).font(.callout.weight(.medium))
                                Text(source.explanation(for: provider))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(HoverRowButtonStyle())
                }
            }
            .padding(14)
        }
    }
}
