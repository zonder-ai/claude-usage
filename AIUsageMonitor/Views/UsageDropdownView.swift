import SwiftUI
import Shared

struct UsageDropdownView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if let errorMessage = viewModel.error {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)
            }

            if let usage = viewModel.usage {
                UsageRowView(label: "5-hour", window: usage.fiveHour)
                UsageRowView(label: "7-day", window: usage.sevenDay)
            } else if viewModel.error == nil {
                Text("Loading usage data…")
                    .foregroundColor(.secondary)
                    .font(.callout)
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
        }
        .padding()
        .frame(width: 270)
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

    private var level: UsageLevel { UsageLevel.from(utilization: window.utilization) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .frame(width: 52, alignment: .leading)

                ProgressView(value: min(window.utilization / 100.0, 1.0))
                    .tint(level.color)

                Text("\(Int(window.utilization.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(level.color)
                    .frame(width: 38, alignment: .trailing)
            }

            Text("Resets in \(window.formattedTimeUntilReset)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 60)
        }
    }
}
