import SwiftUI
import CoderSwitchCore

extension Provider {
    var tintColor: Color {
        switch self {
        case .codex: .blue
        case .openRouter: .purple
        case .refuseless: .red
        case .opencodeGo: .teal
        case .miniMax, .glmCodingPlan: .pink
        case .anthropic, .anthropicCompatible, .kimiCodingPlan, .qwenCodingPlan: .orange
        case .openAI, .openAICompatible: .green
        case .googleAntigravity: .indigo
        case .claude: .orange
        case .commandCode: .mint
        case .customWeb: .gray
        }
    }

    var symbolName: String {
        switch self {
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .openAI: "sparkle"
        case .anthropic, .anthropicCompatible: "a.circle"
        case .openRouter: "arrow.triangle.branch"
        case .refuseless: "infinity"
        case .opencodeGo: "curlybraces"
        case .miniMax: "waveform"
        case .glmCodingPlan: "z.square"
        case .kimiCodingPlan: "moon.stars"
        case .qwenCodingPlan: "q.circle"
        case .openAICompatible: "puzzlepiece.extension"
        case .googleAntigravity: "sparkles"
        case .claude: "asterisk"
        case .commandCode: "terminal"
        case .customWeb: "globe"
        }
    }
}

/// Rounded tile with the provider's symbol, used on cards and in the add-account list.
struct ProviderGlyph: View {
    let provider: Provider
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: provider.symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(provider.tintColor)
            .frame(width: size, height: size)
            .background(provider.tintColor.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
