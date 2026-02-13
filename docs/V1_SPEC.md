# XcodeCleaner V1 Specification

## 1) Product Goal
Ship a native macOS app (Swift + SwiftUI) that helps users understand and control all Xcode-related disk usage on their Mac, with safe cleanup and modification workflows.

## 2) Platform and Distribution Requirements
- Built with Swift and SwiftUI.
- Runs on macOS (target: macOS 14+ unless changed).
- Distribution format: signed, notarized drag-and-drop `.app` bundle (zip or dmg container).
- App must be usable without command-line setup.
- V1 release must include two supported artifacts from the same codebase:
- `XcodeCleanerApp` (SwiftUI GUI app).
- `xcodecleaner-cli` (CLI for scripting/automation with JSON output).
- Any capability delivered in V1 must be available in both artifacts when technically applicable.

## 3) Scope: V1 Must Include

### 3.1 Full Xcode Inventory
- Discover all installed Xcode app bundles (stable/beta/renamed installs).
- Show version, build number, path, size, install date, and active status.
- Detect active developer directory and selected Command Line Tools.
- Show per-install runtime status: whether each Xcode install is currently running and its instance count.

### 3.2 Complete Storage Accounting
- Scan and report all major Xcode-related storage classes:
- Xcode app bundles.
- DerivedData.
- Archives.
- DeviceSupport.
- iOS/tvOS/watchOS/visionOS simulator runtimes and devices.
- SourcePackages caches/checkouts.
- CoreSimulator caches.
- Additional Xcode caches/logs discovered from known paths.
- Show per-category totals and grand total.
- For Simulator data, provide detailed itemized inventory (per runtime and per device) with size and identifying metadata.
- For each simulator device, show runtime/booted state and running instance count.

### 3.3 Ownership Mapping
- Attribute files/folders to:
- A specific Xcode version.
- A specific project/workspace when possible.
- Shared resources.
- Orphaned/stale resources.

### 3.4 Safety Classification
- Every category/item must carry one of:
- `Regenerable`.
- `Conditionally Safe`.
- `Destructive`.
- App must explain classification and likely impact.

### 3.5 Cleanup and Modification Actions
- Per-item and per-category selection.
- Dry-run preview before execution with exact path list and estimated reclaim.
- Support move-to-Trash where possible.
- Direct delete only when trash is not feasible or user opts in.
- Switch active Xcode (developer directory) from the UI.
- Optional uninstall flow for selected Xcode bundle(s) with guardrails.
- Support selective deletion of one or more simulator devices in a single operation.

### 3.6 Automation
- Rule-based cleanup policies (age-based, size-based, category-based).
- Policy execution only when Xcode/simulator/build tools are not running.
- Scheduled and manual run modes.

### 3.7 History and Reporting
- Keep local snapshots of usage over time.
- Show trend chart for growth and reclaim.
- Export report (JSON and CSV) including inventory and action history.

### 3.8 Trust and Transparency
- Show exact file paths for all actions.
- Show confirmation dialogs for non-regenerable data.
- Maintain action log: timestamp, action, outcome, bytes reclaimed.
- Privacy statement: local-first, no cloud dependency by default.

## 4) Non-Functional Requirements
- Initial scan completes in under 20 seconds on a typical developer machine with one Xcode install.
- Rescan updates incrementally and keeps UI responsive.
- Cleanup operations are cancellable where practical.
- App survives partial failures and reports per-item errors.

## 5) Guardrails
- Block cleanup when Xcode process is active, unless action is explicitly safe while running.
- Block risky simulator/runtime changes while simulator is running.
- Block deletion of booted simulator devices and clearly identify why action is blocked.
- Use live Xcode and simulator instance counts when evaluating destructive-action eligibility.
- Never touch paths outside explicit allowlisted roots.
- No silent destructive actions.

## 6) UX Requirements
- Single dashboard with:
- Total Xcode footprint.
- Per-category breakdown.
- Per-Xcode comparison.
- High-priority recommendations.
- Dedicated details panel for each category:
- What it is.
- Why it exists.
- Consequences of cleanup.
- Recovery path.

## 7) Acceptance Criteria (Release Gate)
- User with multiple Xcodes can see all installs, versions, paths, and sizes.
- User can see per-install Xcode running status and instance count.
- User can identify temporary vs non-temporary storage with clear rationale.
- User can see simulator devices individually (not only aggregate simulator totals).
- User can see per-device simulator running/booted status and instance count.
- User can select and delete one or more simulator devices with accurate reclaim reporting.
- User can run dry-run preview and verify exact paths before cleanup.
- User can safely execute cleanup and see accurate reclaimed space.
- User can switch active Xcode from app and verify with `xcode-select -p`.
- User can export a full inventory + action report.
- GUI and CLI both expose the full V1 inventory model and produce consistent values.
- Critical flows covered by automated tests; no P0/P1 open defects.

## 8) Test Strategy
- Unit tests:
- Path discovery/parsing.
- Ownership attribution logic.
- Safety classification rules.
- Size accounting and formatting.
- Integration tests:
- Scan on fixture trees representing single and multi-Xcode setups.
- Cleanup dry-run and execute workflows.
- Selective simulator-device deletion workflows, including blocked booted-device cases.
- Runtime telemetry tests covering Xcode instance counts and simulator state/count signals.
- Guardrail behavior with mocked running processes.
- End-to-end smoke tests:
- Fresh install, scan, cleanup, export report.

## 9) Definition of Done
- All V1 acceptance criteria pass.
- Signed + notarized GUI distribution artifact produced and CLI release binary packaged.
- Release notes and known limitations documented.
