import ServiceManagement
import Shared
import Sparkle
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    let updater: SPUUpdater
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage
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

            Section("Menu Bar Style") {
                Picker("Style", selection: $menuBarStyle) {
                    Label("Percentage", systemImage: "percent")
                        .tag(MenuBarStyle.percentage)
                    Label("Circle", systemImage: "circle.dotted")
                        .tag(MenuBarStyle.circle)
                    Label("Bar", systemImage: "slider.horizontal.3")
                        .tag(MenuBarStyle.bar)
                }
                .pickerStyle(.radioGroup)
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

    @ViewBuilder
    private var authSection: some View {
        switch viewModel.authManager.state {
        case .notAuthenticated:
            HStack {
                Label("Not signed in", systemImage: "person.slash")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Sign In…") {
                    viewModel.authManager.startOAuthFlow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .authenticated(_, _, _):
            HStack {
                Label("Signed in", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Spacer()
                Button("Sign Out", role: .destructive) {
                    viewModel.authManager.signOut()
                }
                .controlSize(.small)
            }

        case .error(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button("Retry") {
                    viewModel.authManager.startOAuthFlow()
                }
                .controlSize(.small)
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
