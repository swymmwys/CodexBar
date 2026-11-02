import AppKit
import Testing
@testable import CodexBar

@MainActor
struct DailyBudgetStripViewTests {
    @Test(arguments: [false, true])
    func `strip stays below the existing content in either coordinate orientation`(flipped: Bool) {
        let bounds = NSRect(x: 0, y: 0, width: 56, height: 24)
        let frame = DailyBudgetStripView.frame(in: bounds, isFlipped: flipped)
        #expect(frame.height == 2)
        #expect(frame.width == 50)
        if flipped {
            #expect(frame.maxY == bounds.maxY - 1)
        } else {
            #expect(frame.minY == bounds.minY + 1)
        }
        let strip = DailyBudgetStripView(frame: frame)
        #expect(strip.hitTest(NSPoint(x: frame.midX, y: frame.midY)) == nil)
    }
}
