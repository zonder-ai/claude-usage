import Shared
import SwiftUI

struct AgentToastView: View {
    let item: AgentToastItem
    let onDismiss: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.status == .running ? "Agent working" : "Task done")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Text(item.title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                onDismiss(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 320, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(.blue)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }

    private var backgroundColor: Color {
        switch item.status {
        case .running:
            return Color(NSColor.windowBackgroundColor).opacity(0.98)
        case .done:
            return Color.green.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch item.status {
        case .running:
            return Color.blue.opacity(0.3)
        case .done:
            return Color.green.opacity(0.3)
        }
    }
}
