import ServiceManagement
import Shared
import Sparkle
import SwiftUI

@main
struct AIUsageApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("agentToastsEnabled") private var agentToastsEnabled = true
    private let toastOverlayController = ToastOverlayController()

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
                Text(viewModel.menuBarText)
                    .monospacedDigit()
                    .padding(.leading, 6)
            }
            .task {
                bindToastOverlay()
                viewModel.setAgentToastsEnabled(agentToastsEnabled)
                viewModel.startPolling()
                if SMAppService.mainApp.status == .notRegistered {
                    try? SMAppService.mainApp.register()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel, updater: updaterController.updater)
        }
        .defaultSize(width: 380, height: 420)
        .windowResizability(.contentSize)
    }

    private func bindToastOverlay() {
        viewModel.onAgentToastsChanged = { [weak toastOverlayController, weak viewModel] toasts in
            toastOverlayController?.update(toasts: toasts) { toastID in
                Task { @MainActor in
                    viewModel?.dismissAgentToast(id: toastID)
                }
            }
        }
    }
}
