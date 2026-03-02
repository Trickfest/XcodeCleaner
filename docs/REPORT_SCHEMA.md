# Automation Report Schema

## Purpose
Defines the current machine-readable output for automation history and trend reports.

This schema is shared by:
- CLI exports:
  - `xcodecleaner-cli automation history [--limit <n>] [--format json|csv] [--output <path>]`
  - `xcodecleaner-cli automation trends [--days <n> ...] [--format json|csv] [--output <path>]`
- GUI exports from the Reports section:
  - `automation-history-<timestamp>.json|csv`
  - `automation-trends-<timestamp>.json|csv`
  - written to `~/.xcodecleaner/exports`

Both GUI and CLI read from the same run-history store: `~/.xcodecleaner/automation-run-history.json`
(CLI can override the state directory with `XCODECLEANER_STATE_DIR`).

## History JSON
Top-level type:
- Array of `AutomationPolicyRunRecord`

Fields per record:
- `runID` (`String`): unique run identifier.
- `policyID` (`String`): policy identifier.
- `policyName` (`String`): policy display name at run time.
- `trigger` (`"manual" | "scheduled"`): run trigger source.
- `startedAt` (`ISO-8601 String`): run start timestamp.
- `finishedAt` (`ISO-8601 String`): run finish timestamp.
- `status` (`"executed" | "skipped" | "failed"`): run result.
- `skippedReason` (`String?`): populated when run is skipped.
- `message` (`String`): summary run message.
- `totalReclaimedBytes` (`Int64`): reclaimed byte count for that run.
- `advancesSchedule` (`Bool`): whether this run advanced policy scheduling state.
- `executionReport` (`CleanupExecutionReport?`): nested execution details for executed runs.

Notes:
- CLI JSON uses pretty-printed, sorted keys, ISO-8601 dates.
- GUI JSON exports use the same encoded model and date format for history.

## History CSV
Header:
`runID,policyID,policyName,trigger,status,startedAt,finishedAt,totalReclaimedBytes,skippedReason,message`

Row behavior:
- Every field is quoted.
- Embedded quotes are escaped as `""`.
- `startedAt` and `finishedAt` use ISO-8601 internet date-time.

## Trends JSON
Top-level type:
- Array of `AutomationHistoryWindowSummary`

Fields per summary:
- `windowDays` (`Int`): rolling window size in days.
- `totalRuns` (`Int`): total runs in window.
- `executedRuns` (`Int`): executed runs in window.
- `skippedRuns` (`Int`): skipped runs in window.
- `failedRuns` (`Int`): failed runs in window.
- `totalReclaimedBytes` (`Int64`): reclaimed byte sum in window.

## Trends CSV
Header:
`windowDays,totalRuns,executedRuns,skippedRuns,failedRuns,totalReclaimedBytes`

Row behavior:
- Numeric, comma-separated rows (no quoting).

## CLI Option Semantics
- `--format` defaults to `json` for `history` and `trends`.
- `history`:
  - optional `--limit <n>` where `n >= 0`
  - optional `--format json|csv`
- `trends`:
  - optional `--days <n> ...` where each `n > 0`
  - optional `--format json|csv`
  - `--limit` is not supported
- Without `--output`, output is written to stdout.
- With `--output`, parent directories are created automatically.

## Trend Window Defaults
- `automation trends` defaults to windows `[7, 30]` when `--days` is not provided.
- GUI trend exports use the same `[7, 30]` default windows.
