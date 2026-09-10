import SwiftUI
import CoderSwitchCore
import Charts

struct UsageTab: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(RequestLogStore.self) private var requestLogStore
    @State private var period: TokenUsagePeriod = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(TokenUsagePeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                TotalsCard(totals: requestLogStore.tokenUsageTotal(period: period), period: period)

                DailyChartCard(series: requestLogStore.tokenUsageDailySeries(period: period))

                UsageRowsCard(
                    title: "By coding tool",
                    emptyMessage: "No tool usage recorded for this period.",
                    rows: requestLogStore.tokenUsageTotalsByCodingTool(period: period)
                )

                UsageRowsCard(
                    title: "By provider",
                    emptyMessage: "No provider usage recorded for this period.",
                    rows: requestLogStore.tokenUsageTotalsByProvider(period: period)
                )

                UsageRowsCard(
                    title: "By account",
                    emptyMessage: "No account usage recorded for this period.",
                    rows: accountRows()
                )

                UsageRowsCard(
                    title: "By model",
                    emptyMessage: "No model usage recorded for this period.",
                    rows: requestLogStore.tokenUsageTotalsByModel(period: period)
                )
            }
            .padding()
        }
    }

    private func accountRows() -> [TokenUsageGroupTotal] {
        let accountsByID = Dictionary(uniqueKeysWithValues: accountStore.accounts.map { ($0.id, $0) })
        return requestLogStore.tokenUsageTotalsByAccount(period: period).map { row in
            let account = accountsByID[row.accountID]
            let label = account.map { "\($0.label) · \($0.provider.displayName)" } ?? row.accountID.uuidString
            return TokenUsageGroupTotal(id: row.accountID.uuidString, label: label, totals: row.totals)
        }
    }
}

private struct TotalsCard: View {
    let totals: TokenUsageDelta
    let period: TokenUsagePeriod

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 12, alignment: .leading)
    ]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(period.displayName)
                        .font(.headline)
                    Spacer()
                    Text(formatTokens(totals.processedTokens))
                        .font(.system(.title2, design: .monospaced))
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    StatBlock(label: "Requests", value: "\(totals.requests)")
                    StatBlock(label: "Input", value: formatTokens(totals.inputTokens))
                    StatBlock(label: "Output", value: formatTokens(totals.outputTokens))
                    StatBlock(label: "Cache write", value: formatTokens(totals.cacheWriteTokens))
                    StatBlock(label: "Cache read", value: formatTokens(totals.cacheReadTokens))
                    if totals.uncategorizedTokens > 0 {
                        StatBlock(label: "Other", value: formatTokens(totals.uncategorizedTokens))
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
                        BarMark(
                            x: .value("Day", entry.day),
                            y: .value("Cache write", entry.totals.cacheWriteTokens)
                        )
                        .foregroundStyle(by: .value("Kind", "Cache write"))
                        BarMark(
                            x: .value("Day", entry.day),
                            y: .value("Cache read", entry.totals.cacheReadTokens)
                        )
                        .foregroundStyle(by: .value("Kind", "Cache read"))
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 180)
            }
        }
    }
}

private struct UsageRowsCard: View {
    let title: String
    let emptyMessage: String
    let rows: [TokenUsageGroupTotal]

    var body: some View {
        GroupBox(title) {
            if rows.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        UsageBreakdownRow(row: row)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct UsageBreakdownRow: View {
    let row: TokenUsageGroupTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(row.totals.requests) req")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatTokens(row.totals.processedTokens))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            HStack(spacing: 10) {
                MiniStat(label: "in", value: row.totals.inputTokens)
                MiniStat(label: "out", value: row.totals.outputTokens)
                MiniStat(label: "cw", value: row.totals.cacheWriteTokens)
                MiniStat(label: "cr", value: row.totals.cacheReadTokens)
                if row.totals.uncategorizedTokens > 0 {
                    MiniStat(label: "other", value: row.totals.uncategorizedTokens)
                }
            }
        }
        .padding(.vertical, 7)
    }
}

private struct MiniStat: View {
    let label: String
    let value: Int

    var body: some View {
        Text("\(label) \(formatTokens(value))")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private func formatTokens(_ value: Int) -> String {
    switch value {
    case 1_000_000_000...:
        String(format: "%.1fB", Double(value) / 1_000_000_000)
    case 1_000_000...:
        String(format: "%.1fM", Double(value) / 1_000_000)
    case 1_000...:
        String(format: "%.1fK", Double(value) / 1_000)
    default:
        "\(value)"
    }
}
