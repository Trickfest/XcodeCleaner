# Automation Report Schema

## Purpose
Defines machine-readable output shapes for Sprint 9 automation history/trend reporting.

## CLI Commands
- `xcodecleaner-cli automation history [--limit <n>] [--format json|csv] [--output <path>]`
- `xcodecleaner-cli automation trends [--days <n> ...] [--format json|csv] [--output <path>]`

## History JSON
Array of `AutomationPolicyRunRecord` objects.

Fields:
- `runID` (`String`): unique run identifier.
- `policyID` (`String`): policy identifier.
- `policyName` (`String`): policy display name at run time.
- `trigger` (`"manual" | "scheduled"`): run trigger source.
- `startedAt` (`ISO-8601 String`): run start timestamp.
- `finishedAt` (`ISO-8601 String`): run finish timestamp.
- `status` (`"executed" | "skipped" | "failed"`): run result.
- `skippedReason` (`String?`): explicit reason when `status == "skipped"`.
- `message` (`String`): summary status message.
- `totalReclaimedBytes` (`Int64`): bytes reclaimed by this run.
- `executionReport` (`CleanupExecutionReport?`): detailed execution report when applicable.

## History CSV
Header:
`runID,policyID,policyName,trigger,status,startedAt,finishedAt,totalReclaimedBytes,skippedReason,message`

Notes:
- All fields are quoted for CSV stability.
- Embedded quotes are escaped using `""`.
- Date fields use ISO-8601 internet date-time format.

## Trends JSON
Array of `AutomationHistoryWindowSummary` objects.

Fields:
- `windowDays` (`Int`): rolling window size in days.
- `totalRuns` (`Int`): total runs in window.
- `executedRuns` (`Int`): executed runs in window.
- `skippedRuns` (`Int`): skipped runs in window.
- `failedRuns` (`Int`): failed runs in window.
- `totalReclaimedBytes` (`Int64`): reclaimed bytes sum in window.

## Trends CSV
Header:
`windowDays,totalRuns,executedRuns,skippedRuns,failedRuns,totalReclaimedBytes`

## Defaults
- `automation trends` defaults to windows `[7, 30]` when `--days` is not provided.
- `--format` defaults to `json`.
- Without `--output`, reports are printed to stdout.
