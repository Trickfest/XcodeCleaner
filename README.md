# XcodeCleaner

GUI-first native macOS tooling (Swift + SwiftUI) to inventory, understand, and clean Xcode-related disk usage.

## Version

- Current version: `1.0`

This repository now presents itself as version `1.0`, while some cleanup, QA, documentation, and release-adjacent polish work is still ongoing.

## Requirements

- macOS 14 or newer
- A recent Xcode install with Swift 6.2 support
- Local access to the Xcode installs, simulator data, and developer caches you want to inspect

## Product Positioning

For `1.0`, the macOS GUI is the primary product surface.

- The GUI is the intended experience for most users.
- The GUI is where workflow polish, discoverability, and release quality are being prioritized.
- The CLI remains available as a secondary power-user surface for scripting, automation, JSON output, and development/testing.
- GUI and CLI share the same core engine, but they are not being treated as equal-scope surfaces for `1.0`, and full parity is not a release requirement.

## Distribution Model

Current distribution is source-first:

- Clone the repo.
- Build locally with SwiftPM or the included Xcode project.
- Launch the GUI app from SwiftPM or from the bundled Xcode build output.
- Use the CLI from SwiftPM when you want scripting, automation, or machine-readable output.

Prebuilt signed/notarized distribution is optional future work, not a current requirement.

## Source Layout

- `Sources/XcodeInventoryCore/`
  - Shared inventory, planning, execution, automation, stale-artifact detection, and reporting logic used by both app surfaces.
- `Sources/XcodeCleanerCLI/`
  - Secondary power-user interface: CLI entry points, option parsing, automation subcommands, JSON/CSV output, and progress rendering.
- `Sources/XcodeCleanerApp/`
  - `XcodeCleanerApp.swift`: app entry point.
  - `Views/ContentView.swift`: split-view shell and section navigation.
  - `App/`: app lifecycle helpers such as launch activation.
  - `ViewModels/`: GUI state coordination (`InventoryViewModel`).
  - `Views/Sections/`: workflow-oriented sections (`Overview`, `Cleanup`, `Automation`, `Reports`).
  - `Views/Components/`: status strip, execution report, and automation/reporting panels shared across sections.
  - `State/`: app-only cleanup and automation form state.
  - `Support/`: presentation helpers, formatting, default GUI cleanup categories, and section metadata.
- `XcodeCleaner.xcodeproj/`
  - Native macOS app project for bundle metadata, icon integration, and source-first GUI packaging.
- `Xcode/XcodeCleanerApp/`
  - `Info.plist` plus `Assets.xcassets` for the bundled GUI app target.
- `Scripts/build-xcodecleaner-app.sh`
  - Repeatable `xcodebuild` wrapper that produces `XcodeCleaner.app` under `.build/xcode/`.

## Current Capabilities

- Read-only inventory and accounting:
  - Xcode installs, active developer directory, version/build/path, ownership, and safety classification.
  - Storage categories: Xcode apps, Derived Data, MobileDevice Crash Logs, Archives, iOS device support, Simulator data.
  - Itemized simulator runtimes and simulator devices with metadata, size, stale markers, and running-state information.
  - Itemized physical device support directories with parsed metadata, modification dates, and size.
- Runtime telemetry:
  - Running Xcode instance count.
  - Running Simulator app instance count.
  - Per-device simulator running/booted visibility in the GUI cleanup guardrails.
- Shared scan progress:
  - GUI progress bar with phase and message.
  - CLI progress output on stderr with final JSON output on stdout.
  - CLI `--no-progress` support.
- Cleanup planning and execution:
  - Shared dry-run planning with deterministic ordering, reclaim estimates, and plan notes.
  - Move-to-trash first, with optional direct-delete fallback.
  - Known simulator runtimes and known simulator devices are removed through `simctl`; filesystem deletion remains for ordinary cache/artifact paths and orphaned leftovers.
  - Guardrails for active/running Xcode installs and running/booted simulator devices.
  - Optional global block while Xcode or the Simulator app is running.
- Targeted cleanup controls:
  - GUI aggregate category selection for Derived Data, MobileDevice Crash Logs, Archives, and Simulator Data.
  - GUI itemized selection for simulator runtimes, simulator devices, Xcode installs, and physical device support directories.
  - CLI selectors for categories, simulator devices, and Xcode installs.
  - CLI stale-artifact list/clean modes for stale simulator runtimes, orphaned simulator device data, and stale physical device support directories. Orphaned simulator runtimes are reported but not deleted in-app.
- Active Xcode switching:
  - GUI and CLI support using `xcode-select`, with result verification against the newly active developer directory.
- Automation and reporting:
  - GUI automation center for policy creation, enable/disable, delete, manual run, due-run evaluation, and status review.
  - CLI automation subcommands for list/create/run/run-due/history/trends.
  - Age and reclaim-threshold filters.
  - Optional skip while tools are running.
  - Shared run history, trend summaries, and JSON/CSV exports.
  - Schema documentation: `docs/REPORT_SCHEMA.md`.

## GUI Workflow

The current macOS app is organized into four workflow sections in the sidebar.

### Overview

- Runtime telemetry summary with running Xcode count, running Simulator app count, stale runtime count, and stale device count.
- Orphaned simulator runtime reporting, including on-disk paths for manual cleanup when detected.
- Storage overview cards for every scanned category, including path lists, ownership summaries, and safety classification.
- Xcode install inventory with active/running badges, version/build metadata, and install paths.
- Active Xcode switch panel with a target picker, action button, and last switch result/status.
- Simulator inventory with separate runtime and device lists, including stale labels, availability, size, and path/identifier metadata.

### Cleanup

- Shared dry-run plan preview with estimated reclaim size, planned item list, and any plan notes.
- Execute controls for:
  - Blocking cleanup while Xcode or the Simulator app is running.
  - Allowing direct-delete fallback when move-to-trash fails.
- Aggregate category toggles for:
  - `Derived Data`
  - `MobileDevice Crash Logs`
  - `Archives`
  - `Simulator Data`
- Itemized selection for:
  - Simulator runtimes
  - Simulator devices
  - Xcode installs
  - Physical device support directories
- Inline stale markers for simulator runtimes and devices.
- Cleanup execution status and the latest execution report.

### Automation

- Operations panel with policy counts, due-now count, history count, status messaging, and a note about overdue schedule behavior.
- Buttons to run all due policies immediately and refresh automation state from disk.
- Configured policy list with:
  - Enabled/disabled toggle
  - Due badge
  - Run-now action
  - Delete action
  - Schedule/category/threshold/status metadata
- Policy creation form with:
  - Name
  - Schedule in hours (or manual-only)
  - Minimum age threshold
  - Minimum reclaim threshold
  - Category selection
  - Skip-if-tools-running and direct-delete toggles
- Shortcut to the Reports section for exports and historical reporting.

### Reports

- Report status summary showing loaded history/trend counts and the last cleanup reclaim total when available.
- All-time and rolling-window automation trend summaries.
- Recent automation run history.
- Export actions for:
  - Automation history JSON
  - Automation history CSV
  - Automation trends JSON
  - Automation trends CSV
- The latest cleanup execution report, mirrored from the cleanup workflow.

## Quick Start

Run tests:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift test --disable-sandbox
```

Run GUI app:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox XcodeCleanerApp
```

Build the bundled macOS GUI app:

```bash
Scripts/build-xcodecleaner-app.sh
```

Optional: run CLI (inventory JSON):

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli
```

This defaults to an Apple Silicon build (`arm64`).

If you need an Intel build on an older Mac, pass the architecture explicitly:

```bash
Scripts/build-xcodecleaner-app.sh --arch x86_64
```

The packaged app bundle is written to:

```bash
.build/xcode/Build/Products/Release/XcodeCleaner.app
```

## Advanced CLI

The CLI is a secondary interface intended for scripting, automation, and machine-readable output. It is useful, but it is not the primary `1.0` user experience.

Primary modes:

- Inventory/snapshot:
  - `xcodecleaner-cli`
- Dry-run / execute:
  - `xcodecleaner-cli --dry-run ...`
  - `xcodecleaner-cli --execute ...`
- Stale artifacts:
  - `xcodecleaner-cli --list-stale-artifacts`
  - `xcodecleaner-cli --clean-stale-artifacts [--stale-artifact <id> ...]`
- Active Xcode switch:
  - `xcodecleaner-cli --switch-active-xcode <path>`
- Automation:
  - `xcodecleaner-cli automation list [--output <path>]`
  - `xcodecleaner-cli automation create --name <name> ... [--output <path>]`
  - `xcodecleaner-cli automation run --id <policy-id> [--output <path>]`
  - `xcodecleaner-cli automation run-due [--output <path>]`
  - `xcodecleaner-cli automation history [--limit <n>] [--format json|csv] [--output <path>]`
  - `xcodecleaner-cli automation trends [--days <n> ...] [--format json|csv] [--output <path>]`

## Practical CLI Tasks

These examples are meant to be realistic cleanup workflows rather than option-reference snippets.
Use the CLI when you specifically want repeatable commands, JSON output, or non-GUI automation.

If you are running from the repo root, this shell helper keeps the examples shorter:

```bash
xc() {
  CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
  swift run --disable-sandbox xcodecleaner-cli "$@"
}
```

Examples below use `jq` for readability when it helps, but the CLI itself does not require `jq`.

### 1. Inspect your current Xcode footprint

Show top-level storage totals:

```bash
xc | jq '.storage.categories | map({kind, title, bytes})'
```

List detected Xcode installs:

```bash
xc | jq -r '.installs[] | [.displayName, (.version // "unknown"), (.build // "unknown"), .path, ("active=" + (.isActive|tostring))] | @tsv'
```

List simulator devices with UDIDs before targeting one device:

```bash
xc | jq -r '.simulator.devices[] | [.name, .udid, .state, (.sizeInBytes|tostring)] | @tsv'
```

### 2. Preview the default safe cleanup

If you do not pass any explicit selectors, the CLI defaults to the same safe starting categories used by the app: `derivedData` and `archives`.

```bash
xc --dry-run | jq '{totalReclaimableBytes, notes, items: [.items[] | {kind, title, reclaimableBytes}]}'
```

This is the quickest way to answer, "What would XcodeCleaner remove if I let it do the obvious low-risk cleanup?"

### 3. Execute the default safe cleanup

Run the same default cleanup for real, but skip execution if Xcode or Simulator is active:

```bash
xc --execute --skip-if-tools-running
```

If you want to permit direct delete when move-to-trash fails:

```bash
xc --execute --skip-if-tools-running --allow-direct-delete
```

### 4. Clean one specific simulator device

First find the device UDID:

```bash
xc | jq -r '.simulator.devices[] | [.name, .udid, .state] | @tsv'
```

Preview cleanup for one simulator device:

```bash
xc --dry-run --plan-simulator-device <UDID>
```

Execute cleanup for that device:

```bash
xc --execute --skip-if-tools-running --plan-simulator-device <UDID>
```

This removes the selected registered simulator device through `simctl`, which deletes that device and its apps/files/state, but not all simulator data or simulator runtimes.

### 5. Remove one old Xcode install

First inspect install paths and active status:

```bash
xc | jq -r '.installs[] | [.displayName, (.version // "unknown"), .path, ("active=" + (.isActive|tostring)), ("running=" + (.runningInstanceCount|tostring))] | @tsv'
```

Preview uninstall of one install:

```bash
xc --dry-run --plan-xcode-install /Applications/Xcode-16.2.app
```

Execute uninstall of that install:

```bash
xc --execute --skip-if-tools-running --plan-xcode-install /Applications/Xcode-16.2.app
```

Active installs and installs with running instances are guarded and can be blocked by the executor.

### 6. Clean stale artifacts

List stale cleanup candidates:

```bash
xc --list-stale-artifacts | jq
```

Clean every stale candidate currently reported:

```bash
xc --clean-stale-artifacts --skip-if-tools-running
```

Clean only one stale candidate by ID:

```bash
xc --clean-stale-artifacts --skip-if-tools-running --stale-artifact <CANDIDATE_ID>
```

This is currently the CLI path for targeted cleanup of stale simulator runtimes, orphaned simulator device data, and stale physical device support directories. Orphaned simulator runtimes stay report-only.

### 7. Switch the active Xcode

Preview available installs first:

```bash
xc | jq -r '.installs[] | [.displayName, .path, .developerDirectoryPath, ("active=" + (.isActive|tostring))] | @tsv'
```

Switch the active developer directory to a different install:

```bash
xc --switch-active-xcode /Applications/Xcode-16.3.app
```

The command verifies the resulting active developer directory after `xcode-select` runs.

## Cleanup Scope Semantics

- GUI default cleanup selection starts with:
  - `Derived Data`
  - `Archives`
- GUI aggregate category cleanup is available for:
  - `Derived Data`
  - `MobileDevice Crash Logs`
  - `Archives`
  - `Simulator Data`
- GUI itemized cleanup is available for:
  - Simulator runtimes
  - Simulator devices
  - Xcode installs
  - Physical Device Support directories (`~/Library/Developer/Xcode/iOS DeviceSupport/*`)
- GUI intentionally does not expose aggregate cleanup toggles for:
  - `Xcode Applications`
  - Aggregate `Device Support`
- GUI automation policy creation follows the same category list and therefore also excludes aggregate `xcodeApplications` and aggregate `deviceSupport`.
- CLI dry-run/execute selectors currently support:
  - `--plan-category <kind>`
  - `--plan-simulator-device <udid>`
  - `--plan-xcode-install <path>`
- Current GUI/CLI parity gaps to be aware of:
  - The GUI can select individual simulator runtimes for cleanup; the main CLI dry-run/execute path cannot. In the CLI, simulator runtimes are only directly targetable through stale-artifact cleanup when they are reported as stale.
  - The GUI can select individual physical device support directories for cleanup; the main CLI dry-run/execute path cannot. In the CLI, those directories are directly targetable only through stale-artifact cleanup when they are reported as stale.
  - The GUI can build mixed itemized cleanup plans that include simulator runtimes and physical device support directories together with other selections. The CLI currently splits that experience between main planning mode and stale-artifact mode.
- Those gaps are acceptable for the current product direction because the GUI is the primary cleanup surface and the CLI is positioned as an advanced companion, not a full mirror of every GUI workflow.
- CLI stale-artifact cleanup covers stale simulator runtimes, orphaned simulator device data, and stale physical device support directories. Orphaned simulator runtimes are report-only.
- When aggregate and itemized selections would double count the same reclaimable bytes, the planner removes the aggregate entry and records a plan note.

## Automation and Report State

- Default shared state directory: `~/.xcodecleaner`
- Files:
  - `automation-policies.json`
  - `automation-run-history.json`
  - `exports/`
- GUI and CLI share this state by default.
- CLI can override the state directory with `XCODECLEANER_STATE_DIR`.
- GUI export actions write timestamped JSON/CSV files into `~/.xcodecleaner/exports/`.

Report examples:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli automation history --format csv --output /tmp/xcodecleaner-history.csv

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli automation trends --format json
```
