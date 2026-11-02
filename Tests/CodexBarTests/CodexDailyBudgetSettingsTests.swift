import Testing
@testable import CodexBar

@MainActor
struct CodexDailyBudgetSettingsTests {
    @Test
    func `settings persist daily hours without touching the existing icon layout`() {
        let defaults = InMemoryUserDefaults()
        let settings = testSettingsStore(suiteName: "daily-budget", userDefaults: defaults)
        let layout = settings.menuBarLayout
        #expect(settings.codexDailyBudgetStartHour == 10)
        #expect(settings.codexDailyBudgetEndHour == 20)
        #expect(settings.codexDailyBudgetTimeZoneIdentifier == "Europe/Minsk")
        settings.codexDailyBudgetEnabled = false
        settings.codexDailyBudgetStartHour = 22
        #expect(settings.codexDailyBudgetEndHour == 23)
        let restored = testSettingsStore(suiteName: "daily-budget-restored", userDefaults: defaults)
        #expect(!restored.codexDailyBudgetEnabled)
        #expect(restored.codexDailyBudgetStartHour == 22)
        #expect(restored.menuBarLayout == layout)
    }
}
