import SwiftUI
import CoderSwitchCore

/// Thin rounded progress bar tinted by severity.
struct UsageBar: View {
    let fraction: Double
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: fillWidth(in: proxy.size.width))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(UsageFormat.percent(fraction)) used")
    }

    private func fillWidth(in total: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(height, total * min(1, fraction))
    }
}

/// One limit with a title, reset hint, percentage, and bar.
struct UsageMeterRow: View {
    let title: String
    let limit: UsageLimit
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                if let resetAt = limit.resetAt {
                    Text(UsageFormat.resetsIn(resetAt, now: now))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                if let fraction = limit.fraction {
                    Text(UsageFormat.percent(fraction))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(limit.usageTintColor)
                } else if let detail = limit.remainingDescription {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = limit.fraction {
                UsageBar(fraction: fraction, tint: limit.usageTintColor)
            }
        }
        .help(limit.remainingDescription ?? limit.name)
    }
}

/// Dense one-line limit for secondary lists (monthly, credits, per-model).
struct CompactLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        HStack(spacing: 8) {
            Text(limit.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let fraction = limit.fraction {
                UsageBar(fraction: fraction, tint: limit.usageTintColor, height: 4)
                    .frame(width: 56)
                Text(UsageFormat.percent(fraction))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(limit.usageTintColor)
                    .frame(width: 34, alignment: .trailing)
            } else if let detail = limit.remainingDescription {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .help(limit.remainingDescription ?? limit.name)
    }
}

extension UsageLimit {
    var usageTintColor: Color {
        guard let fraction else { return .secondary }
        switch fraction {
        case ...0.4: return .green
        case ...0.6: return .yellow
        case ...0.8: return .orange
        default: return .red
        }
    }
}
