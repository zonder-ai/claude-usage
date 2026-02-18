import SwiftUI

@main
struct AIUsageApp: App {
    var body: some Scene {
        MenuBarExtra("AI Usage", systemImage: "chart.bar.fill") {
            Text("Loading...")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
