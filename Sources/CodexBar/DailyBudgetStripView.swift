import AppKit
import CodexBarCore

/// A separate view preserves the existing icon/title geometry and native menu highlighting.
@MainActor
final class DailyBudgetStripView: NSView {
    static func frame(in bounds: NSRect, isFlipped: Bool) -> NSRect {
        NSRect(
            x: bounds.minX + 3,
            y: isFlipped ? bounds.maxY - 3 : bounds.minY + 1,
            width: max(0, bounds.width - 6),
            height: 2)
    }

    var display: CodexDailyBudget.Display? {
        didSet { self.needsDisplay = true }
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func draw(_: NSRect) {
        guard let display = self.display else { return }
        let track = NSBezierPath(roundedRect: self.bounds, xRadius: 1, yRadius: 1)
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        track.fill()
        let color: NSColor = switch display.risk {
        case .unknown: .secondaryLabelColor
        case .safe: .systemGreen
        case .warning: .systemYellow
        case .critical: .systemRed
        }
        color.setFill()
        let width = self.bounds.width * display.remainingFraction
        if width > 0 {
            NSBezierPath(
                roundedRect: NSRect(x: 0, y: 0, width: width, height: self.bounds.height),
                xRadius: 1,
                yRadius: 1).fill()
        } else if display.risk == .critical {
            // Depleted must remain distinguishable from missing data.
            track.stroke()
        }
    }
}
