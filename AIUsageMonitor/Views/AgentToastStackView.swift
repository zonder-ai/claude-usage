import Shared
import SwiftUI

struct AgentToastStackView: View {
    let toasts: [AgentToastItem]
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(toasts) { toast in
                AgentToastView(item: toast, onDismiss: onDismiss)
            }
        }
        .padding(12)
        .background(Color.clear)
    }
}
