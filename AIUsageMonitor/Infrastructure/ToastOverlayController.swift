import AppKit
import Shared
import SwiftUI

final class ToastOverlayController {
    private let margin: CGFloat = 20
    private let minWidth: CGFloat = 340
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AgentToastStackView>?
    private var latestToasts: [AgentToastItem] = []

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(toasts: [AgentToastItem], onDismiss: @escaping (String) -> Void) {
        latestToasts = toasts

        guard !toasts.isEmpty else {
            hide()
            return
        }

        if panel == nil {
            let newPanel = makePanel()
            panel = newPanel
            hostingView = NSHostingView(rootView: AgentToastStackView(toasts: toasts, onDismiss: onDismiss))
            newPanel.contentView = hostingView
        } else {
            hostingView?.rootView = AgentToastStackView(toasts: toasts, onDismiss: onDismiss)
        }

        panel?.orderFrontRegardless()
        reposition()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    @objc private func handleScreenChange() {
        guard !latestToasts.isEmpty else { return }
        reposition()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: minWidth, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        return panel
    }

    private func reposition() {
        guard let panel else { return }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        panel.contentView?.layoutSubtreeIfNeeded()
        let fittingSize = panel.contentView?.fittingSize ?? NSSize(width: minWidth, height: 120)
        let width = max(minWidth, fittingSize.width)
        let height = max(1, fittingSize.height)
        panel.setContentSize(NSSize(width: width, height: height))

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.maxX - width - margin,
            y: visibleFrame.minY + margin
        )
        panel.setFrameOrigin(origin)
    }
}
