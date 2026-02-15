# Sprint 8 Plan and Exit Gate

## Sprint Goal
Deliver policy-based automation so cleanup can run on-demand or on schedule with strict "only when tools are closed" safeguards.

## Scope
- Shared automation policy model used by GUI and CLI.
- Policy dimensions:
  - Category selection.
  - Age threshold (`minAgeDays`).
  - Reclaim threshold (`minTotalReclaimBytes`).
- Run modes:
  - Manual "run now".
  - Scheduled evaluation (`run-due`) for use with `launchd`/cron.
- Guard conditions:
  - Skip when Xcode is running.
  - Skip when Simulator app is running.
  - Skip when simulator devices are booted/running.
- Run audit/history:
  - Record start/end, trigger type, status, skip reason, and reclaimed bytes.

## Deliverables
- `XcodeInventoryCore`:
  - `AutomationPolicy`, `AutomationPolicySchedule`, `AutomationPolicyRunRecord`.
  - `AutomationPolicyRunner` with guard checks and threshold filtering.
  - JSON persistence store for policies and run history.
- `xcodecleaner-cli` automation commands:
  - `automation list`
  - `automation create`
  - `automation run`
  - `automation run-due`
  - `automation history`
- `XcodeCleanerApp` automation panel:
  - Create policy.
  - Enable/disable policy.
  - Delete policy.
  - Run single policy now.
  - Run all due policies now.
  - Display recent run history.
- Tests:
  - Due-policy selection logic.
  - Skip behavior when tools are running.
  - Threshold behavior (age + min reclaim).
  - JSON policy/history persistence.

## Exit Criteria
- User can define at least one automation policy from GUI and CLI.
- User can run policy manually and receive deterministic JSON execution output (CLI) and visible status (GUI).
- Due/scheduled policy evaluation can be executed via `automation run-due`.
- Policy runs are skipped (not executed) when Xcode/Simulator/booted devices are detected, with explicit skip reason.
- Automation executes via existing guardrailed cleanup engine and reports reclaimed bytes.
- New automation behavior is covered by automated tests.

## Out of Scope
- Long-term trend charts.
- CSV/JSON export packaging polish.
- Notarization/signing and release packaging.

## Follow-On
Sprint 9 (V1 GA) targets history/trends UX, report export polish, and release packaging hardening.
