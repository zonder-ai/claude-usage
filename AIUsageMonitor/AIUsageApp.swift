import SwiftUI
import Shared

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(viewModel: viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(viewModel.usageLevel.color)
                Text(viewModel.menuBarText)
                    .monospacedDigit()
            }
            .task { viewModel.startPolling() }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 380, height: 300)
        .windowResizability(.contentSize)
    }
}
