import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

extension CodexAccountScopedRefreshTests {
    @Test
    func `daily budget refuses a published quota after an external account switch`() throws {
        let settings = self.makeSettingsStore(suite: "daily-budget-owner")
        settings.refreshFrequency = .manual
        settings._test_liveSystemCodexAccount = self.liveAccount(email: "alpha@example.com")
        let store = self.makeUsageStore(settings: settings)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-02T10:00:00+03:00"))
        let reset = now.addingTimeInterval(2 * 86400)
        func snapshot(email: String, used: Double) -> UsageSnapshot {
            UsageSnapshot(
                primary: nil,
                secondary: RateWindow(
                    usedPercent: used, windowMinutes: 10080, resetsAt: reset, resetDescription: nil),
                updatedAt: now,
                identity: ProviderIdentitySnapshot(
                    providerID: .codex, accountEmail: email, accountOrganization: nil, loginMethod: "Pro"))
        }
        store._setSnapshotForTesting(snapshot(email: "alpha@example.com", used: 70), provider: .codex)
        store.lastCodexUsagePublicationGuard = store.currentCodexAccountScopedRefreshGuard(
            preferCurrentSnapshot: false, allowLastKnownLiveFallback: false)
        #expect(store.codexDailyBudgetDisplay(now: now) != nil)
        let saved = settings.userDefaults.data(forKey: "codexDailyBudgetAccountsV1")

        settings._test_liveSystemCodexAccount = self.liveAccount(email: "beta@example.com")
        settings.invalidateCodexAccountReconciliationSnapshotCache()
        #expect(store.codexDailyBudgetDisplay(now: now) == nil)
        #expect(settings.userDefaults.data(forKey: "codexDailyBudgetAccountsV1") == saved)

        store._setSnapshotForTesting(snapshot(email: "beta@example.com", used: 10), provider: .codex)
        store.lastCodexUsagePublicationGuard = store.currentCodexAccountScopedRefreshGuard(
            preferCurrentSnapshot: false, allowLastKnownLiveFallback: false)
        let beta = try #require(store.codexDailyBudgetDisplay(now: now))
        #expect(beta.remainingFraction == 1)
        #expect(abs(beta.allowancePercentPoints - 45) < 0.001)
    }
}
