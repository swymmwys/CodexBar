import CodexBarCore
import Foundation

/// An account's measured subscription allowance, never an API-dollar/token estimate.
struct CodexDailyBudget: Codable, Equatable {
    struct Schedule: Codable, Equatable {
        var startHour = 10
        var endHour = 20
        var weekdaysOnly = false

        func interval(on date: Date, calendar: Calendar) -> DateInterval? {
            let weekday = calendar.component(.weekday, from: date)
            guard !self.weekdaysOnly || (2...6).contains(weekday),
                  (0...23).contains(self.startHour), (1...24).contains(self.endHour),
                  self.startHour < self.endHour,
                  let start = calendar.date(bySettingHour: self.startHour, minute: 0, second: 0, of: date),
                  let end = self.endHour == 24
                  ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
                  : calendar.date(bySettingHour: self.endHour, minute: 0, second: 0, of: date)
            else { return nil }
            return DateInterval(start: start, end: end)
        }

        func workingSeconds(from start: Date, to end: Date, calendar: Calendar) -> TimeInterval {
            guard end > start else { return 0 }
            var day = calendar.startOfDay(for: start)
            var seconds: TimeInterval = 0
            // A Codex weekly allowance is bounded. Rejecting longer windows happens at admission.
            for _ in 0..<9 {
                guard day < end else { break }
                if let interval = self.interval(on: day, calendar: calendar) {
                    seconds += max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return seconds
        }
    }

    enum Risk: String {
        case unknown, safe, warning, critical
    }

    struct Display: Equatable {
        let remainingFraction: Double
        let remainingPercentPoints: Double
        let allowancePercentPoints: Double
        let risk: Risk
    }

    struct Sample: Codable, Equatable {
        let date: Date
        let usedPercent: Double
    }

    let day: Date
    let reset: Date
    let schedule: Schedule
    let timeZoneIdentifier: String
    let baselineUsedPercent: Double
    let allowancePercentPoints: Double
    var highWaterUsedPercent: Double
    var samples: [Sample]

    init?(window: RateWindow, sampledAt: Date, schedule: Schedule, calendar: Calendar) {
        guard let reset = window.resetsAt, reset > sampledAt,
              window.windowMinutes == 10080, !window.isSyntheticPlaceholder, window.usedPercent.isFinite,
              reset.timeIntervalSince(sampledAt) <= 8 * 86400,
              let today = schedule.interval(on: sampledAt, calendar: calendar)
        else { return nil }
        let start = max(sampledAt, today.start)
        let todaySeconds = max(0, min(reset, today.end).timeIntervalSince(start))
        let totalSeconds = schedule.workingSeconds(from: start, to: reset, calendar: calendar)
        guard todaySeconds > 0, totalSeconds > 0 else { return nil }
        self.day = calendar.startOfDay(for: sampledAt)
        self.reset = reset
        self.schedule = schedule
        self.timeZoneIdentifier = calendar.timeZone.identifier
        self.baselineUsedPercent = min(100, max(0, window.usedPercent))
        self.highWaterUsedPercent = self.baselineUsedPercent
        self.allowancePercentPoints = (100 - self.baselineUsedPercent) * todaySeconds / totalSeconds
        self.samples = [Sample(date: sampledAt, usedPercent: self.baselineUsedPercent)]
    }

    func belongs(to window: RateWindow, at now: Date, schedule: Schedule, calendar: Calendar) -> Bool {
        guard let reset = window.resetsAt else { return false }
        return calendar.isDate(self.day, inSameDayAs: now)
            && abs(self.reset.timeIntervalSince(reset)) < 60
            && self.schedule == schedule && self.timeZoneIdentifier == calendar.timeZone.identifier
    }

    mutating func record(window: RateWindow, sampledAt: Date) {
        guard window.usedPercent.isFinite, let last = self.samples.last, sampledAt > last.date else { return }
        // A correction must not refill the fixed daily budget or invent a negative burn rate.
        let used = max(self.highWaterUsedPercent, min(100, max(0, window.usedPercent)))
        self.highWaterUsedPercent = used
        self.samples.append(Sample(date: sampledAt, usedPercent: used))
        self.samples = Array(self.samples.suffix(120))
    }

    func display(at now: Date, calendar: Calendar, isStale: Bool) -> Display {
        let remaining = max(0, self.allowancePercentPoints - (self.highWaterUsedPercent - self.baselineUsedPercent))
        let fraction = self.allowancePercentPoints > 0 ? remaining / self.allowancePercentPoints : 0
        var risk: Risk = .unknown
        if !isStale, let last = self.samples.last, now >= last.date,
           now.timeIntervalSince(last.date) <= 20 * 60
        {
            if remaining == 0 {
                risk = .critical
            } else if let first = self.samples.first(where: { $0.date >= last.date.addingTimeInterval(-3600) }),
                      last.date.timeIntervalSince(first.date) >= 10 * 60,
                      let interval = self.schedule.interval(on: now, calendar: calendar)
            {
                let elapsed = self.schedule.workingSeconds(from: first.date, to: last.date, calendar: calendar)
                if elapsed >= 10 * 60 {
                    let burn = max(0, last.usedPercent - first.usedPercent) / elapsed
                    let workLeft = self.schedule.workingSeconds(
                        from: now, to: min(self.reset, interval.end), calendar: calendar)
                    let projected = burn * workLeft
                    if projected > remaining {
                        risk = .critical
                    } else if projected > remaining * 0.8 {
                        risk = .warning
                    } else {
                        risk = .safe
                    }
                }
            }
        }
        return Display(
            remainingFraction: min(1, max(0, fraction)),
            remainingPercentPoints: remaining,
            allowancePercentPoints: self.allowancePercentPoints,
            risk: risk)
    }
}

/// Persists fixed daily allocations per canonical account; switching accounts never shares a baseline.
@MainActor
final class CodexDailyBudgetStore {
    private let defaults: UserDefaults
    private var budgets: [String: CodexDailyBudget]
    private static let key = "codexDailyBudgetAccountsV1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.budgets = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: CodexDailyBudget].self, from: $0) } ?? [:]
    }

    // Keep the account, measured observation, evaluation clock, and schedule explicit at this boundary.
    // swiftlint:disable:next function_parameter_count
    func display(
        accountKey: String,
        window: RateWindow,
        sampledAt: Date,
        now: Date,
        schedule: CodexDailyBudget.Schedule,
        calendar: Calendar = .current,
        isStale: Bool) -> CodexDailyBudget.Display?
    {
        guard !accountKey.isEmpty, let reset = window.resetsAt, reset > now,
              window.windowMinutes == 10080, !window.isSyntheticPlaceholder, window.usedPercent.isFinite,
              sampledAt <= now, calendar.isDate(sampledAt, inSameDayAs: now) else { return nil }
        let previous = self.budgets[accountKey]
        var budget: CodexDailyBudget
        if let previous, previous.belongs(to: window, at: now, schedule: schedule, calendar: calendar) {
            budget = previous
            if !isStale { budget.record(window: window, sampledAt: sampledAt) }
        } else {
            guard !isStale, now.timeIntervalSince(sampledAt) <= 20 * 60,
                  let initial = CodexDailyBudget(
                      window: window, sampledAt: sampledAt, schedule: schedule, calendar: calendar)
            else { return nil }
            budget = initial
        }
        if budget != previous {
            self.budgets = self.budgets.filter { now.timeIntervalSince($0.value.day) < 8 * 86400 }
            self.budgets[accountKey] = budget
            if let data = try? JSONEncoder().encode(self.budgets) { self.defaults.set(data, forKey: Self.key) }
        }
        return budget.display(
            at: now,
            calendar: calendar,
            isStale: isStale || window.usedPercent < budget.highWaterUsedPercent)
    }
}
