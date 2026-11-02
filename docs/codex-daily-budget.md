---
summary: "Account-scoped Codex daily allowance and end-of-workday risk in the menu bar."
read_when:
  - Configuring or changing the Codex daily budget strip
---

# Codex daily budget

This fork adds a two-point strip underneath the existing Codex menu-bar item. The number above it still
shows the configured account quota. The strip instead shows how much of **today's allocation** remains.
It uses the same status item, preserves its icon/title layout, and does not intercept clicks.

Open **Settings → Menu Bar → Codex daily budget** to enable it and configure working hours, time zone,
and whether weekends count. Defaults are every day, 10:00–20:00, Europe/Minsk. The strip applies to
the local Codex account in a single-provider status item or the merged switcher's Codex selection.
It is not shown for plugins, remote fleet accounts, other providers, or stacked multi-provider items.

## Allocation

On the first fresh quota observation of a working day, remaining weekly allowance is distributed in
proportion to scheduled working time before the next weekly reset. The reset day contributes only the
working hours before the reset. For example, 50% remaining across two full ten-hour days and a final
five-hour day gives the first day 20 percentage points of the weekly allowance.

Starting tracking halfway through a day allocates the remaining workday, rather than pretending the
app measured earlier usage. Once established, the allocation stays fixed for that day. Subsequent
quota increases consume it; idle time and downward quota corrections do not refill it. Daily state is
persisted separately for each canonical account and survives restarting the app. A new day, changed
weekly reset, schedule, or time zone establishes a new allocation. No allocation starts after the
workday ends, on a disabled weekend, from a failed fetch, or from an expired/synthetic weekly window.

## Color

- **Green:** recent usage is projected to consume at most 80% of the remaining daily allocation.
- **Yellow:** projected consumption is between 80% and 100% of the remaining allocation.
- **Red:** projected consumption exceeds the remaining allocation, or today's allocation is exhausted.
- **Gray:** there is insufficient recent history, a failed/stale observation, or a counter correction.

Forecasts use quota observations from the trailing hour, requiring at least ten minutes of observed
scheduled time. Observations older than twenty minutes cannot produce a reassuring forecast.
The strip updates with quota refreshes and re-evaluates the forecast once a minute without an
additional provider request. Hover/accessibility help describes its meaning.

The forecast measures **actual account usage across all models, reasoning settings, speed modes, and
parallel sessions**. Switching to a more expensive configuration affects its forecast as fresh quota
observations arrive. It does not predict hypothetical model switches, attribute shared quota to a
specific chat, estimate developer output from lines of code, or convert API prices to subscription
percentages. The result is an estimate, especially with rounded provider percentages.

## Validation

Run `make test-fast FILTER='CodexDailyBudget|DailyBudgetStripView|daily budget refuses'` and `make check`.
The tests exercise fixed allocations, partial reset days, end-of-day risk, stale data, account
isolation, persistence, counter corrections, new days/resets, and working-hour settings. UI validation
should also cover light/dark appearance, highlighted menu state, switching providers, and disabling
the strip without altering status-item geometry.
