import SwiftUI
import Shared

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(viewModel: viewModel) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(viewModel.usageLevel.color)
                Text(viewModel.menuBarText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
