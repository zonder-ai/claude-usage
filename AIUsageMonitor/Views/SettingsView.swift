import ServiceManagement
import Shared
import Sparkle
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    let updater: SPUUpdater
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @AppStorage("agentToastsEnabled") private var agentToastsEnabled = true

    private let fixedThresholds = [50, 75, 90, 100]

    var body: some View {
        Form {
            Section("Authentication") {
                authSection
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled // revert on failure
                        }
                    }

                Toggle("Agent Activity Toasts", isOn: $agentToastsEnabled)
                    .onChange(of: agentToastsEnabled) { enabled in
                        viewModel.setAgentToastsEnabled(enabled)
                    }
            }

            Section("Notifications") {
                notificationsSection
            }

            Section("Updates") {
                CheckForUpdatesView(updater: updater)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
        .padding(.vertical, 8)
        .onAppear {
            viewModel.setAgentToastsEnabled(agentToastsEnabled)
        }
    }

    // MARK: - Auth Section

    @State private var isRetrying = false

    @ViewBuilder
    private var authSection: some View {
        switch viewModel.authManager.state {
        case .notAuthenticated:
            VStack(alignment: .leading, spacing: 6) {
                Label("Not signed in", systemImage: "person.slash")
                    .foregroundColor(.secondary)

                if let refreshError = viewModel.authManager.lastRefreshError {
                    Text(refreshError)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Text("Run `claude auth login` in Terminal, then retry.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button {
                        isRetrying = true
                        Task {
                            await viewModel.authManager.ensureValidToken()
                            if viewModel.authManager.state.isAuthenticated {
                                viewModel.fetchUsage()
                            }
                            isRetrying = false
                        }
                    } label: {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Text("Retry")
                        }
                    }
                    .controlSize(.small)
                    .disabled(isRetrying)

                    Button("Open Terminal") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                    .controlSize(.small)
                }
            }

        case .authenticated(_, _, _, _):
            HStack {
                Label("Signed in via \(viewModel.authSourceDescription ?? "Claude Code")", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Spacer()
                Button("Sign Out", role: .destructive) {
                    viewModel.authManager.signOut()
                }
                .controlSize(.small)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)

                Text("Run `claude auth login` in Terminal, then retry.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    isRetrying = true
                    Task {
                        await viewModel.authManager.ensureValidToken()
                        if viewModel.authManager.state.isAuthenticated {
                            viewModel.fetchUsage()
                        }
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Text("Retry")
                    }
                }
                .controlSize(.small)
                .disabled(isRetrying)
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(fixedThresholds, id: \.self) { threshold in
                Toggle("\(threshold)%", isOn: Binding(
                    get: { viewModel.notificationThresholds.contains(threshold) },
                    set: { enabled in
                        if enabled {
                            viewModel.notificationThresholds.append(threshold)
                        } else {
                            viewModel.notificationThresholds.removeAll { $0 == threshold }
                        }
                    }
                ))
            }
        }
    }
}
