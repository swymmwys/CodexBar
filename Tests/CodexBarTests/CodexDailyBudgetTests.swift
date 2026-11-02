import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexDailyBudgetTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func window(_ used: Double, reset: Date) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: 10080, resetsAt: reset, resetDescription: nil)
    }

    @Test
    func `budget divides remaining quota by working time including a partial reset day`() throws {
        let now = self.date("2026-11-02T10:00:00+03:00")
        let reset = self.date("2026-11-04T15:00:00+03:00")
        let budget = try #require(CodexDailyBudget(
            window: self.window(50, reset: reset), sampledAt: now, schedule: .init(), calendar: self.calendar))
        // Monday 10h + Tuesday 10h + Wednesday 5h: today's allocation is 20 percentage points.
        #expect(abs(budget.allowancePercentPoints - 20) < 0.001)
        #expect(budget.display(at: now, calendar: self.calendar, isStale: false).risk == .unknown)
    }

    @Test
    func `length is fixed budget remaining and idle time never refills it`() throws {
        let now = self.date("2026-11-02T10:00:00+03:00")
        let reset = self.date("2026-11-04T15:00:00+03:00")
        var budget = try #require(CodexDailyBudget(
            window: self.window(50, reset: reset), sampledAt: now, schedule: .init(), calendar: self.calendar))
        let later = now.addingTimeInterval(3600)
        budget.record(window: self.window(55, reset: reset), sampledAt: later)
        let display = budget.display(at: later, calendar: self.calendar, isStale: false)
        #expect(display.allowancePercentPoints == 20)
        #expect(display.remainingPercentPoints == 15)
        #expect(display.remainingFraction == 0.75)
        #expect(display.risk == .critical)
        #expect(budget.display(at: later.addingTimeInterval(3600), calendar: self.calendar, isStale: false)
            .remainingFraction == 0.75)
        #expect(budget.display(at: later.addingTimeInterval(3600), calendar: self.calendar, isStale: false)
            .risk == .unknown)
    }

    @Test(arguments: [(51.0, CodexDailyBudget.Risk.safe), (51.7, .warning), (53.0, .critical)])
    func `risk follows recent actual account burn`(used: Double, expected: CodexDailyBudget.Risk) throws {
        let start = self.date("2026-11-02T10:00:00+03:00")
        let reset = self.date("2026-11-04T15:00:00+03:00")
        var budget = try #require(CodexDailyBudget(
            window: self.window(50, reset: reset), sampledAt: start, schedule: .init(), calendar: self.calendar))
        let now = start.addingTimeInterval(3600)
        budget.record(window: self.window(used, reset: reset), sampledAt: now)
        #expect(budget.display(at: now, calendar: self.calendar, isStale: false).risk == expected)
        #expect(budget.display(at: now, calendar: self.calendar, isStale: true).risk == .unknown)
    }

    @Test
    func `depletion stays red and counter correction never refills a daily budget`() throws {
        let start = self.date("2026-11-02T10:00:00+03:00")
        let reset = self.date("2026-11-04T15:00:00+03:00")
        var budget = try #require(CodexDailyBudget(
            window: self.window(50, reset: reset), sampledAt: start, schedule: .init(), calendar: self.calendar))
        budget.record(window: self.window(75, reset: reset), sampledAt: start.addingTimeInterval(600))
        budget.record(window: self.window(60, reset: reset), sampledAt: start.addingTimeInterval(1200))
        let display = budget.display(at: start.addingTimeInterval(1200), calendar: self.calendar, isStale: false)
        #expect(display.remainingFraction == 0)
        #expect(display.risk == .critical)
    }

    @Test
    func `restart restores allocation account isolation and next day creates a new budget`() {
        let defaults = InMemoryUserDefaults()
        let start = self.date("2026-11-02T10:00:00+03:00")
        let reset = self.date("2026-11-04T15:00:00+03:00")
        let store = CodexDailyBudgetStore(defaults: defaults)
        func read(
            _ store: CodexDailyBudgetStore,
            _ account: String,
            _ used: Double,
            _ now: Date,
            reset: Date) -> CodexDailyBudget.Display?
        {
            store.display(
                accountKey: account,
                window: self.window(used, reset: reset),
                sampledAt: now,
                now: now,
                schedule: .init(),
                calendar: self.calendar,
                isStale: false)
        }
        #expect(read(store, "A", 50, start, reset: reset)?.allowancePercentPoints == 20)
        let later = start.addingTimeInterval(3600)
        #expect(read(store, "A", 55, later, reset: reset)?.remainingFraction == 0.75)
        let restored = CodexDailyBudgetStore(defaults: defaults)
        #expect(read(restored, "A", 55, later, reset: reset)?.remainingFraction == 0.75)
        #expect(read(restored, "B", 55, later, reset: reset)?.remainingFraction == 1)
        let tomorrow = start.addingTimeInterval(86400)
        #expect(read(restored, "A", 60, tomorrow, reset: reset)?.remainingFraction == 1)
        let newReset = tomorrow.addingTimeInterval(7 * 86400)
        #expect(read(restored, "A", 0, tomorrow, reset: newReset)?.remainingFraction == 1)
    }

    @Test
    func `expired stale and previous day samples cannot start an allocation`() {
        let store = CodexDailyBudgetStore(defaults: InMemoryUserDefaults())
        let now = self.date("2026-11-02T10:00:00+03:00")
        let reset = self.date("2026-11-04T15:00:00+03:00")
        #expect(store.display(
            accountKey: "A",
            window: self.window(50, reset: reset),
            sampledAt: now,
            now: now,
            schedule: .init(),
            calendar: self.calendar,
            isStale: true) == nil)
        #expect(store.display(
            accountKey: "A",
            window: self.window(50, reset: reset),
            sampledAt: now.addingTimeInterval(-86400),
            now: now,
            schedule: .init(),
            calendar: self.calendar,
            isStale: false) == nil)
        #expect(store.display(
            accountKey: "A",
            window: self.window(50, reset: now),
            sampledAt: now,
            now: now,
            schedule: .init(),
            calendar: self.calendar,
            isStale: false) == nil)
    }

    @Test
    func `weekend and workday end cannot borrow tomorrow's budget`() {
        let schedule = CodexDailyBudget.Schedule(weekdaysOnly: true)
        let saturday = self.date("2026-11-07T10:00:00+03:00")
        #expect(CodexDailyBudget(
            window: self.window(50, reset: saturday.addingTimeInterval(86400)),
            sampledAt: saturday,
            schedule: schedule,
            calendar: self.calendar) == nil)
        let evening = self.date("2026-11-02T20:00:00+03:00")
        #expect(CodexDailyBudget(
            window: self.window(50, reset: evening.addingTimeInterval(86400)),
            sampledAt: evening,
            schedule: .init(),
            calendar: self.calendar) == nil)
    }
}
