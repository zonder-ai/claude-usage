import ServiceManagement
import Shared
import SwiftUI

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.authManager.handleOAuthCallback(url: url)
                }
        } label: {
            HStack(spacing: 0) {
                Image(nsImage: {
                    let img = NSImage(named: "ClaudeLogo") ?? NSImage()
                    img.isTemplate = true
                    img.size = NSSize(width: 16, height: 16)
                    return img
                }())

                if menuBarStyle == .percentage {
                    Text(viewModel.menuBarText)
                        .monospacedDigit()
                        .padding(.leading, 6)
                } else if menuBarStyle == .circle {
                    CircleProgressView(
                        utilization: viewModel.usage?.fiveHour.utilization ?? 0,
                        color: viewModel.usageLevel.color
                    )
                    .padding(.leading, 4)
                } else {
                    BarProgressView(
                        utilization: viewModel.usage?.fiveHour.utilization ?? 0,
                        color: viewModel.usageLevel.color
                    )
                    .padding(.leading, 4)
                }
            }
            .task {
                viewModel.startPolling()
                if SMAppService.mainApp.status == .notRegistered {
                    try? SMAppService.mainApp.register()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 380, height: 360)
        .windowResizability(.contentSize)
    }
}

// MARK: - Circle progress ring (14×14 pt)

private struct CircleProgressView: View {
    let utilization: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(utilization / 100.0, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Horizontal progress bar (50×6 pt)

private struct BarProgressView: View {
    let utilization: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.3))
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 50 * min(utilization / 100.0, 1.0))
        }
        .frame(width: 50, height: 6)
    }
}
