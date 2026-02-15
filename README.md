# XcodeCleaner

Native macOS tooling (Swift + SwiftUI) to inventory, understand, and clean Xcode-related disk usage.

## Distribution Model

Current distribution is source-first:
- Clone the repo.
- Build locally with SwiftPM/Xcode.
- Run the CLI binary and/or app from local build outputs.

Prebuilt signed/notarized artifact distribution is optional future work, not required for current V1 usage.

## Sprint Status

Implemented through Sprint 8, plus Sprint 9 reporting foundation:
- Read-only Xcode installation inventory scanner.
- Active developer directory detection (`xcode-select -p`).
- Read-only storage accounting for:
- Xcode application bundles.
- DerivedData.
- Archives.
- iOS DeviceSupport.
- Simulator data (devices, caches, runtimes path).
- Ownership attribution and safety classification for storage categories and simulator artifacts.
- Runtime telemetry:
- Per-Xcode running instance count.
- Per-simulator-device running/booted state and instance count.
- Itemized simulator inventory:
- Per runtime metadata and size.
- Per device metadata and size.
- Scan progress instrumentation:
- Shared scan phases and monotonic progress events from core scanner.
- GUI progress bar with percentage and current phase/status message.
- CLI progress/status output on stderr while keeping final JSON on stdout.
- CLI `--no-progress` switch to suppress progress output when desired.
- Dry-run planning:
- Shared dry-run planner with deterministic item ordering and reclaim estimates.
- Exact path previews for each dry-run item.
- Selective simulator-device planning by UDID.
- Selective per-install Xcode planning by install path.
- GUI dry-run section with category/device/Xcode-install selection and live plan preview.
- CLI dry-run output mode via `--dry-run`, with `--plan-category`, `--plan-simulator-device`, and `--plan-xcode-install`.
- Safe execution:
- Shared cleanup execution engine with per-item action log records.
- Move-to-trash first with optional direct-delete fallback.
- Guardrails for active/running Xcode installs and booted/running simulator devices.
- GUI execute flow with per-item success/blocked/failed feedback.
- CLI execute mode via `--execute` with machine-readable execution report JSON.
- Modification tools:
- Active Xcode switching via `xcode-select` with verification/result reporting.
- Stale artifact detection for simulator runtimes and Device Support directories.
- GUI stale-artifact selection and cleanup execution.
- CLI stale-artifact listing/cleanup modes via `--list-stale-artifacts` and `--clean-stale-artifacts`.
- CLI active-Xcode switch mode via `--switch-active-xcode <path>`.
- Automation policies:
- Shared automation policy model with schedule, category, age, and reclaim-threshold rules.
- Guarded automation execution that can skip when Xcode/Simulator tools are running.
- CLI automation workflows via `automation list|create|run|run-due|history`.
- SwiftUI automation section for policy create/enable/disable/delete, manual run, run-due, recent run history, and trend summaries.
- Sprint 9 reporting foundation:
- Shared automation trend summaries (7-day and 30-day windows by default).
- Shared CSV export for automation history and trends.
- CLI export workflows:
- `automation history --format json|csv [--output <path>]`
- `automation trends --format json|csv [--days <n> ...] [--output <path>]`
- Report schema documentation in `docs/REPORT_SCHEMA.md`.
- Release smoke checklist in `docs/RELEASE_SMOKE_CHECKLIST.md`.
- Release artifact build helper: `scripts/build_release_artifacts.sh` (outputs `dist/`).
- Optional future notarization helper (requires credentials): `scripts/notarize_release.sh`.
- GUI export actions for automation history/trends to `~/.xcodecleaner/exports`.
- SwiftUI app shell showing inventory and storage totals.
- CLI JSON output with inventory and storage models.
- Unit tests for multi-Xcode discovery, storage categorization, telemetry, simulator itemization, progress phase ordering, dry-run planning, cleanup execution guardrails, active-Xcode switching, stale-artifact workflows, and automation policy execution/storage logic.
- Unit tests for automation history/trend reporting and CSV export formatting.

## Quick Start

Run tests:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift test --disable-sandbox
```

Run CLI inventory output:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli
```

Run SwiftUI app shell:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox XcodeCleanerApp
```

Automation report examples:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli automation history --format csv --output /tmp/xcodecleaner-history.csv

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli automation trends --format json
```
