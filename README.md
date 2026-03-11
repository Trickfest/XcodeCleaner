# XcodeCleaner

Native macOS tooling (Swift + SwiftUI) to inventory, understand, and clean Xcode-related disk usage.

## Version

- Current pre-release: `0.90`
- Target: `1.0`

This project is close to the `1.0` scope but still in pre-release iteration.

## Distribution Model

Current distribution is source-first:
- Clone the repo.
- Build locally with SwiftPM or Xcode.
- Run the CLI and/or GUI from local build outputs.

Prebuilt signed/notarized distribution is optional future work, not required for current usage.

## Source Layout

- `Sources/XcodeInventoryCore/`
  - Shared inventory, planning, execution, automation, and reporting logic used by both app surfaces.
- `Sources/XcodeCleanerCLI/`
  - CLI entry points, option parsing, output formatting, and progress rendering.
- `Sources/XcodeCleanerApp/`
  - `XcodeCleanerApp.swift`: app entry point.
  - `App/`: app lifecycle helpers such as launch activation.
  - `ViewModels/`: GUI state coordination (`InventoryViewModel`).
  - `Views/Sections/`: workflow-oriented sections (`Overview`, `Cleanup`, `Automation`, `Reports`).
  - `Views/Components/`: shared SwiftUI panels used across sections.
  - `State/`: app-only form and selection state.
  - `Support/`: app-only presentation helpers, formatting, and section metadata.

## Current Capabilities

- Read-only inventory and accounting:
  - Xcode installs, active developer directory, version/build/path.
  - Storage categories: Xcode apps, Derived Data, MobileDevice Crash Logs, Archives, iOS Device Support, Simulator data.
  - Itemized simulator runtimes and devices (with metadata and size).
  - Itemized physical Device Support directories (with metadata and size).
- Runtime telemetry:
  - Running Xcode instance count.
  - Running Simulator app instance count.
  - Per-device simulator state/instance count.
- Shared scan progress:
  - GUI progress bar with phase/message.
  - CLI progress output on stderr with final JSON output on stdout.
  - CLI `--no-progress` support.
- Cleanup planning and execution:
  - Shared dry-run planning with deterministic ordering and reclaim estimates.
  - Move-to-trash first, with optional direct-delete fallback.
  - Guardrails for active/running Xcode installs and running/booted simulator devices.
  - Optional global block while Xcode/Simulator tools are running.
- Targeted cleanup controls:
  - GUI itemized selection for simulator runtimes/devices, Xcode installs, and physical Device Support directories.
  - CLI selectors for categories/devices/Xcode installs plus stale-artifact selection.
- Active Xcode switching:
  - GUI and CLI support using `xcode-select` with result verification.
- Stale artifact workflows:
  - Stale detection for simulator runtimes/devices and physical Device Support directories.
  - GUI stale badges/labels and explicit selection.
  - CLI list/clean modes.
- Automation:
  - Policy create/list/enable/disable/delete and manual/scheduled evaluation.
  - Age and reclaim-threshold filters.
  - Optional skip when tools are running.
  - Shared run history and trend summaries.
- Reports:
  - JSON/CSV export for automation history and trends in GUI and CLI.
  - Schema documentation: `docs/REPORT_SCHEMA.md`.

## Quick Start

Run tests:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift test --disable-sandbox
```

Run CLI (inventory JSON):

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli
```

Run GUI app:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox XcodeCleanerApp
```

## CLI Overview

Primary modes:
- Inventory/dry-run/execute:
  - `xcodecleaner-cli`
  - `xcodecleaner-cli --dry-run ...`
  - `xcodecleaner-cli --execute ...`
- Stale artifacts:
  - `xcodecleaner-cli --list-stale-artifacts`
  - `xcodecleaner-cli --clean-stale-artifacts [--stale-artifact <id> ...]`
- Active Xcode switch:
  - `xcodecleaner-cli --switch-active-xcode <path>`
- Automation:
  - `xcodecleaner-cli automation list`
  - `xcodecleaner-cli automation create --name <name> ...`
  - `xcodecleaner-cli automation run --id <policy-id>`
  - `xcodecleaner-cli automation run-due`
  - `xcodecleaner-cli automation history [--limit <n>] [--format json|csv] [--output <path>]`
  - `xcodecleaner-cli automation trends [--days <n> ...] [--format json|csv] [--output <path>]`

## Cleanup Scope Semantics

- GUI category cleanup is aggregate for:
  - `Derived Data`
  - `MobileDevice Crash Logs`
  - `Archives`
  - `Simulator Data`
- GUI itemized cleanup is explicit per-item for:
  - Simulator runtimes
  - Simulator devices
  - Xcode installs
  - Physical Device Support directories (`~/Library/Developer/Xcode/iOS DeviceSupport/*`)
- GUI intentionally does not expose aggregate `Device Support` cleanup in the category checklist.
- CLI keeps aggregate `deviceSupport` category behavior:
  - `--plan-category deviceSupport` plans one-shot cleanup of all physical Device Support directories under the root.
  - Use GUI itemized selection when you want fine-grained physical Device Support cleanup.

## Automation and Report State

- Default shared state directory: `~/.xcodecleaner`
- Files:
  - `automation-policies.json`
  - `automation-run-history.json`
  - `exports/`
- GUI and CLI share this state by default.
- CLI can override state location via `XCODECLEANER_STATE_DIR`.

Report examples:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli automation history --format csv --output /tmp/xcodecleaner-history.csv

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli automation trends --format json
```

## Near-Term Roadmap

- Finish GUI packaging work now that the app target is organized into section-specific files.
- Add the app icon and packaging-facing polish after the bundle workflow is in place.
- Run a packaging-aware GUI QA and documentation pass before making the repository public.
- Cut the `1.0` release after packaging, docs, and QA are aligned.
