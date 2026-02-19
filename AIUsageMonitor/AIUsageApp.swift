import ServiceManagement
import Shared
import SwiftUI

@main
struct AIUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @AppStorage("menuBarStyle") private var menuBarStyle = MenuBarStyle.percentage

    var body: some Scene {
        MenuBarExtra {
            UsageDropdownView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.authManager.handleOAuthCallback(url: url)
                }
        } label: {
            if menuBarStyle == .percentage {
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
                    viewModel.startPolling()
                    if SMAppService.mainApp.status == .notRegistered {
                        try? SMAppService.mainApp.register()
                    }
                }
            } else {
                // NSStatusItem supports only one image + one title.
                // Composite logo + progress indicator into a single NSImage.
                Image(nsImage: compositeMenuBarImage(
                    style: menuBarStyle,
                    utilization: viewModel.usage?.fiveHour.utilization ?? 0,
                    color: viewModel.usageLevel.color
                ))
                .task {
                    viewModel.startPolling()
                    if SMAppService.mainApp.status == .notRegistered {
                        try? SMAppService.mainApp.register()
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
        }
        .defaultSize(width: 380, height: 360)
        .windowResizability(.contentSize)
    }
}

// MARK: - Composite menu bar image
// NSStatusItem only supports one image + one title. For circle/bar styles we
// composite the logo and the progress indicator into a single bitmap NSImage.

private func compositeMenuBarImage(style: MenuBarStyle, utilization: Double, color: Color) -> NSImage {
    let logo = NSImage(named: "ClaudeLogo") ?? NSImage()
    logo.size = NSSize(width: 16, height: 16)

    let gap: CGFloat = 4
    let logoSize: CGFloat = 16

    let indicatorW: CGFloat = style == .circle ? 14 : 50
    let indicatorH: CGFloat = style == .circle ? 14 : 6
    let totalW = logoSize + gap + indicatorW
    let totalH = logoSize  // tallest element

    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let pw = Int(totalW * scale)
    let ph = Int(totalH * scale)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: Int(totalW), height: Int(totalH))

    let gfx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gfx
    let cg = gfx.cgContext

    // All drawing uses black. isTemplate=true lets macOS invert to white on dark
    // menu bars automatically, matching every other standard menu bar icon.
    let opaque = NSColor.black.cgColor
    let dim    = NSColor.black.withAlphaComponent(0.3).cgColor

    // Draw logo
    cg.saveGState()
    let logoRect = CGRect(x: 0, y: (totalH - logoSize) / 2, width: logoSize, height: logoSize)
        .applying(CGAffineTransform(scaleX: scale, y: scale))
    if let cgLogo = logo.cgImage(forProposedRect: nil, context: gfx, hints: nil) {
        cg.clip(to: logoRect, mask: cgLogo)
        cg.setFillColor(opaque)
        cg.fill(logoRect)
    }
    cg.restoreGState()

    // Draw progress indicator
    let indX = (logoSize + gap) * scale
    let indY = ((totalH - indicatorH) / 2) * scale
    let indW = indicatorW * scale
    let indH = indicatorH * scale
    let fraction = CGFloat(min(max(utilization / 100.0, 0), 1))

    if style == .circle {
        let lineWidth: CGFloat = 2 * scale
        let circleRect = CGRect(x: indX, y: indY, width: indW, height: indH)
            .insetBy(dx: lineWidth / 2, dy: lineWidth / 2)

        // Track
        cg.setStrokeColor(dim)
        cg.setLineWidth(lineWidth)
        cg.strokeEllipse(in: circleRect)

        // Arc
        if fraction > 0 {
            let center = CGPoint(x: indX + indW / 2, y: indY + indH / 2)
            let radius = (indW - lineWidth) / 2
            let startAngle = CGFloat.pi / 2
            let endAngle = startAngle - fraction * 2 * .pi
            cg.setStrokeColor(opaque)
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)
            cg.addArc(center: center, radius: radius,
                       startAngle: startAngle, endAngle: endAngle, clockwise: true)
            cg.strokePath()
        }
    } else {
        let barRect = CGRect(x: indX, y: indY, width: indW, height: indH)
        let radius: CGFloat = 2 * scale

        // Track
        let bgPath = CGPath(roundedRect: barRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.setFillColor(dim)
        cg.addPath(bgPath)
        cg.fillPath()

        // Fill
        if fraction > 0 {
            let fillRect = CGRect(x: indX, y: indY, width: indW * fraction, height: indH)
            let fillPath = CGPath(roundedRect: fillRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            cg.setFillColor(opaque)
            cg.addPath(fillPath)
            cg.fillPath()
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    let img = NSImage(size: NSSize(width: Int(totalW), height: Int(totalH)))
    img.addRepresentation(rep)
    img.isTemplate = true
    return img
}
