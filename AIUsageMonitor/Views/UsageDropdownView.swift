import SwiftUI
import Charts
import Shared

struct UsageDropdownView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage")
                        .font(.headline)
                    if let lastUpdated = viewModel.lastUpdated {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(formattedLastUpdated(lastUpdated))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    viewModel.fetchUsage()
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }

            // MARK: Error
            if let errorMessage = viewModel.error {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)
            }

            // MARK: Usage rows
            if let usage = viewModel.usage {
                UsageRowView(label: "5-hour", window: usage.fiveHour)
                UsageRowView(label: "Weekly", window: usage.sevenDay)
            } else if viewModel.error == nil {
                Text("Loading usage data…")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }

            // MARK: Claude activity
            if !viewModel.activity.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Claude activity")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    ForEach(viewModel.activity.prefix(5)) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 5)
                            Text(item.text)
                                .font(.caption)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(formattedActivityTimestamp(item.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else if let activityError = viewModel.activityError {
                Label(activityError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .lineLimit(2)
            }

            // MARK: Sparkline (5-hour trend)
            if viewModel.history.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("5-hour trend")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Chart(viewModel.history) { snapshot in
                        AreaMark(
                            x: .value("Time", snapshot.timestamp),
                            y: .value("Usage", snapshot.fiveHourUtilization)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("Time", snapshot.timestamp),
                            y: .value("Usage", snapshot.fiveHourUtilization)
                        )
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .frame(height: 44)
                }
            }

            // MARK: Token countdown (only if API returns counts)
            if let usage = viewModel.usage,
               let remaining = usage.fiveHour.tokensRemaining,
               let limit = usage.fiveHour.tokensLimit {
                HStack {
                    Text("Tokens left:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(remaining.formatted()) / \(limit.formatted())")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            Button {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(MenuRowButtonStyle())

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut("q")

            Divider()

            HStack(spacing: 5) {
                Text("powered by")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image("ZonderLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("zonder.ai")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
        }
        .padding()
        .frame(width: 270)
    }

    private func formattedLastUpdated(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60  { return "Updated \(Int(elapsed))s ago" }
        if elapsed < 300 { return "Updated \(Int(elapsed / 60))m ago" }
        return "Updated >5m ago"
    }

    private func formattedActivityTimestamp(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))h" }
        return "\(Int(elapsed / 86_400))d"
    }
}

// MARK: - Hover-aware button style

struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered || configuration.isPressed
                          ? Color.accentColor
                          : Color.clear)
            )
            .foregroundColor(isHovered || configuration.isPressed ? .white : .primary)
            .onHover { isHovered = $0 }
    }
}

// MARK: - UsageRowView

struct UsageRowView: View {
    let label: String
    let window: UsageWindow

    @State private var animatedUtilization: Double = 0

    private var level: UsageLevel { UsageLevel.from(utilization: window.utilization) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .frame(width: 52, alignment: .leading)

                ProgressView(value: min(animatedUtilization / 100.0, 1.0))
                    .tint(level.color)
                    .animation(.easeInOut(duration: 0.4), value: animatedUtilization)

                Text("\(Int(window.utilization.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(level.color)
                    .frame(width: 38, alignment: .trailing)
            }

            Text(window.formattedTimeUntilReset)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 60)
        }
        .onAppear {
            animatedUtilization = window.utilization
        }
        .onChange(of: window.utilization) { newValue in
            animatedUtilization = newValue
        }
    }
}
