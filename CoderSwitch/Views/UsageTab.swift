import SwiftUI
import Charts

struct UsageTab: View {
    @Environment(AccountStore.self) private var store
    @State private var period: TokenUsagePeriod = .week
    @State private var expandedAccountIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(TokenUsagePeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                TotalsCard(totals: store.tokenUsageTotal(period: period), period: period)

                DailyChartCard(series: store.tokenUsageDailySeries(period: period))

                ByAccountCard(
                    rows: store.tokenUsageByAccount(period: period),
                    period: period,
                    expandedIDs: $expandedAccountIDs
                )

                ByProviderCard(rows: store.tokenUsageTotalsByProvider(period: period))
            }
            .padding()
        }
    }
}

private struct TotalsCard: View {
    let totals: TokenUsageDelta
    let period: TokenUsagePeriod

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(period.displayName)
                        .font(.headline)
                    Spacer()
                    Text(formatTokens(totals.totalTokens))
                        .font(.system(.title2, design: .monospaced))
                }
                HStack(spacing: 16) {
                    StatBlock(label: "Requests", value: "\(totals.requests)")
                    StatBlock(label: "Input", value: formatTokens(totals.inputTokens))
                    StatBlock(label: "Output", value: formatTokens(totals.outputTokens))
                    if totals.cacheReadTokens > 0 {
                        StatBlock(label: "Cache R", value: formatTokens(totals.cacheReadTokens))
                    }
                    if totals.cacheWriteTokens > 0 {
                        StatBlock(label: "Cache W", value: formatTokens(totals.cacheWriteTokens))
                    }
                }
            }
        }
    }
}

private struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct DailyChartCard: View {
    let series: [(day: String, totals: TokenUsageDelta)]

    var body: some View {
        GroupBox("Daily totals") {
            if series.isEmpty {
                Text("No data for this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                Chart {
                    ForEach(series, id: \.day) { entry in
                        BarMark(
                            x: .value("Day", entry.day),
                            y: .value("Input", entry.totals.inputTokens)
                        )
                        .foregroundStyle(by: .value("Kind", "Input"))
                        BarMark(
                            x: .value("Day", entry.day),
                            y: .value("Output", entry.totals.outputTokens)
                        )
                        .foregroundStyle(by: .value("Kind", "Output"))
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 180)
            }
        }
    }
}

private struct ByAccountCard: View {
    let rows: [(account: Account, totals: TokenUsageDelta)]
    let period: TokenUsagePeriod
    @Binding var expandedIDs: Set<UUID>

    var body: some View {
        GroupBox("By account") {
            if rows.isEmpty {
                Text("No account usage recorded for this period.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.account.id) { entry in
                        AccountUsageRow(
                            account: entry.account,
                            totals: entry.totals,
                            period: period,
                            expanded: expandedIDs.contains(entry.account.id),
                            onToggle: { toggle(entry.account.id) }
                        )
                        if entry.account.id != rows.last?.account.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }
}

private struct AccountUsageRow: View {
    let account: Account
    let totals: TokenUsageDelta
    let period: TokenUsagePeriod
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(account.label)
                        Text(account.provider.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(totals.requests) req")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTokens(totals.totalTokens))
                        .font(.system(.body, design: .monospaced))
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if expanded {
                let modelTotals = account.tokenUsageTotalsByModel(period: period)
                if modelTotals.isEmpty {
                    Text("No model breakdown available.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 24)
                } else {
                    ForEach(modelTotals) { item in
                        HStack {
                            Text(item.label)
                                .font(.caption)
                            Spacer()
                            Text("in \(formatTokens(item.totals.inputTokens))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("out \(formatTokens(item.totals.outputTokens))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(formatTokens(item.totals.totalTokens))
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding(.leading, 24)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ByProviderCard: View {
    let rows: [TokenUsageGroupTotal]

    var body: some View {
        GroupBox("By provider") {
            if rows.isEmpty {
                Text("No provider usage recorded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.label)
                            Spacer()
                            Text("\(row.totals.requests) req")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatTokens(row.totals.totalTokens))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
        }
    }
}

private func formatTokens(_ value: Int) -> String {
    switch value {
    case 1_000_000...:
        String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...:
        String(format: "%.1fK", Double(value) / 1_000)
    default:
        "\(value)"
    }
}
