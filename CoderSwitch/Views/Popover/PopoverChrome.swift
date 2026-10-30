import SwiftUI

struct PopoverHeader: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("CoderSwitch")
                    .font(.headline)
                Text(isRefreshing ? "Refreshing…" : UsageFormat.updated(lastUpdated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                SpinningRefreshIcon(isSpinning: isRefreshing)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help("Refresh usage now")
            .accessibilityLabel("Refresh usage")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct SpinningRefreshIcon: View {
    let isSpinning: Bool
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .semibold))
            .rotationEffect(.degrees(angle))
            .onChange(of: isSpinning, initial: true) { _, spinning in
                if spinning {
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { angle = 360 }
                } else {
                    withAnimation(.none) { angle = 0 }
                }
            }
    }
}

struct PopoverFooter: View {
    let onAddAccount: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onAddAccount) {
                Label("Add account…", systemImage: "plus")
            }
            Button(action: onOpenSettings) {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Spacer()
            Button(action: onQuit) {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
