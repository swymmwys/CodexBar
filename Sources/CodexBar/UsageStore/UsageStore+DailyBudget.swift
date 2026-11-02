import CodexBarCore
import Foundation

extension UsageStore {
    /// A published quota must still belong to the selected runtime account before we persist it.
    /// A minute repaint can run after an external CLI account switch and before refresh reconciliation.
    func codexDailyBudgetDisplay(now: Date) -> CodexDailyBudget.Display? {
        let currentOwner = self.currentCodexAccountScopedRefreshGuard(
            preferCurrentSnapshot: false, allowLastKnownLiveFallback: false)
        guard let publishedOwner = self.lastCodexUsagePublicationGuard,
              Self.codexScopedRefreshGuardsMatchAccount(publishedOwner, currentOwner),
              let accountKey = CodexHistoryOwnership.canonicalKey(for: publishedOwner.identity),
              let snapshot = self.menuBarSnapshot(for: .codex),
              let window = self.codexConsumerProjection(surface: .menuBar, now: now).rateWindow(for: .weekly)
        else { return nil }
        return self.dailyBudgetStore.display(
            accountKey: accountKey,
            window: window,
            sampledAt: snapshot.updatedAt,
            now: now,
            schedule: self.settings.codexDailyBudgetSchedule,
            calendar: self.settings.codexDailyBudgetCalendar,
            isStale: self.isStale(provider: .codex))
    }
}
