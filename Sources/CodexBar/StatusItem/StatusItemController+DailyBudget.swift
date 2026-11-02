import AppKit
import CodexBarCore

extension StatusItemController {
    func updateDailyBudgetStrip(for button: NSButton, providers: [UsageProvider], now: Date = .init()) {
        let existing = button.subviews.compactMap { $0 as? DailyBudgetStripView }.first
        guard providers == [.codex], self.settings.codexDailyBudgetEnabled,
              !self.menuBarUsageSource(for: .codex).isFleet,
              let display = self.store.codexDailyBudgetDisplay(now: now)
        else {
            existing?.removeFromSuperview()
            return
        }
        let strip = existing ?? DailyBudgetStripView()
        strip.frame = DailyBudgetStripView.frame(in: button.bounds, isFlipped: button.isFlipped)
        strip.autoresizingMask = button.isFlipped ? [.width, .minYMargin] : [.width, .maxYMargin]
        strip.display = display
        let remaining = Int((display.remainingFraction * 100).rounded())
        let risk = switch display.risk {
        case .unknown: "Collecting recent pace; forecast unavailable"
        case .safe: "Expected to last until the end of the workday"
        case .warning: "Close to today's budget at the recent pace"
        case .critical: "Today's budget may run out before the workday ends"
        }
        let description = "Daily budget: \(remaining)% left. \(risk). Based on recent account usage across all models."
        strip.toolTip = description
        button.setAccessibilityHelp(description)
        if existing == nil { button.addSubview(strip) }
    }
}
