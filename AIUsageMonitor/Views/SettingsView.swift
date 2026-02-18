import SwiftUI
import Shared

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var newThreshold = ""
    @FocusState private var thresholdFieldFocused: Bool

    var body: some View {
        Form {
            Section("Authentication") {
                authSection
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Alert when usage exceeds:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(viewModel.notificationThresholds.sorted(), id: \.self) { threshold in
                    HStack(spacing: 2) {
                        Text("\(threshold)%")
                            .font(.caption)
                        Button {
                            viewModel.notificationThresholds.removeAll { $0 == threshold }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                TextField("Add %", text: $newThreshold)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .focused($thresholdFieldFocused)
                    .onSubmit(addThreshold)

                Button("Add", action: addThreshold)
                    .controlSize(.small)
                    .disabled(parsedThreshold == nil)
            }
        }
    }

    private var parsedThreshold: Int? {
        guard let v = Int(newThreshold.trimmingCharacters(in: .whitespaces)),
              (1...100).contains(v),
              !viewModel.notificationThresholds.contains(v)
        else { return nil }
        return v
    }

    private func addThreshold() {
        guard let v = parsedThreshold else { return }
        viewModel.notificationThresholds.append(v)
        newThreshold = ""
    }
}

// MARK: - FlowLayout

/// Simple left-to-right wrapping layout for threshold chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
