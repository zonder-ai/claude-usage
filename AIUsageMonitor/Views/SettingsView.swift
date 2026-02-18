import ServiceManagement
import Shared
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

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
            }

            Section("Notifications") {
                notificationsSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 300)
        .padding(.vertical, 8)
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

        case .authenticated(_, _, let expiresAt):
            HStack {
                Label("Signed in", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Spacer()
                Text("Expires \(expiresAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("Sign Out", role: .destructive) {
                viewModel.authManager.signOut()
            }
            .controlSize(.small)

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
