import ServiceManagement
import Shared
import SwiftUI

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.authManager.handleOAuthCallback(url: url)
                }
        } label: {
            HStack(spacing: 4) {
                Image("ClaudeLogo")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(viewModel.usageLevel.color)
                Text(viewModel.menuBarText)
                    .monospacedDigit()
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
        .defaultSize(width: 380, height: 300)
        .windowResizability(.contentSize)
    }
}
