# Development TODO

Last updated: 2026-03-17

## Recently Completed

- [x] Reorganize the GUI app target into app shell, view model, section views, shared components, and app-local state/support files.
- [x] Align repository docs with the reorganized app structure and current work ordering.
- [x] Generate the first-pass Xcode-inspired broom-and-dust-sweep icon assets for `XcodeCleaner`.
- [x] Add a repo-local Xcode project and bundled macOS app build path for the GUI app.
- [x] Wire the generated app icon assets into the bundled GUI app target.

## Accounting And Cleanup Follow-Up

- [x] Fix simulator runtime accounting so `Total Xcode Footprint` includes runtime storage from the actual runtime bundle paths reported by `simctl`, not just `/Library/Developer/CoreSimulator/Profiles/Runtimes`.
- [x] Make `Simulator Data` equal the true non-overlapping total of simulator devices, simulator caches, and simulator runtimes across modern CoreSimulator layouts, so the aggregate total and itemized rows stay consistent.
- [x] Detect orphaned simulator artifacts by diffing on-disk device and runtime directories against the current simulator inventory, report them explicitly, and make cleanup opt-in rather than folding them invisibly into normal simulator rows.
- [x] Verify simulator runtime cleanup on modern CoreSimulator layouts, since plain Trash/direct-delete file removal may be blocked by macOS for volume-backed runtimes; confirm whether a system-supported removal path is required before treating runtime cleanup as fully supported.
- [x] Migrate cleanup of known simulator devices from direct filesystem deletion to `simctl` so registered CoreSimulator objects are removed through Apple-supported commands.
- [x] Improve physical `iOS DeviceSupport` inventory metadata for both legacy version-first and newer model-prefixed directory names, using folder parsing plus `Info.plist` fallback where helpful, and leave cleanup decisions to the user instead of stale-device heuristics.
- [x] Decide and document the intended meaning of `Total Xcode Footprint` in the README and in-app help: all standard Xcode/CoreSimulator-managed storage on this Mac, even when some counted roots are not normal cleanup candidates.
- [x] Expand footprint accounting to include additional major Xcode-managed storage that is currently omitted, starting with `~/Library/Developer/Xcode/DocumentationCache`.
- [x] Add an in-app info popover next to `Total Xcode Footprint` that lists the roots currently included in the calculation and makes it explicit that counted roots are not automatically cleanup targets.
- [x] Count standard Xcode-managed support content such as `~/Library/Developer/Packages`, `~/Library/Developer/DVTDownloads`, and `~/Library/Developer/XCTestDevices` in `Total Xcode Footprint`, while leaving cleanup-candidate research for later.
- [x] Revisit whether `~/Library/Developer/XCPGDevices` should count toward `Total Xcode Footprint`, since it appears to be Playground-related developer state and may not belong under an Xcode-only footprint definition.
- [x] Keep external preference and saved-state locations out of the normal footprint total for now, but allow small standard Xcode-managed roots under `~/Library/Developer/Xcode` to roll into count-only footprint state where appropriate.
- [x] Audit standard Xcode result/log storage roots and include the relevant ones in `Total Xcode Footprint`.
- [x] Add explicit opt-in cleanup support for standard Xcode result/log storage that is safe to remove, without making it part of the default-safe cleanup set.
- [x] Expand simulator-accounting regression tests to cover modern volume-backed CoreSimulator layouts and total-footprint invariants, including no undercounting and no double counting.
- [x] Update UI labeling and README wording so the footprint number's scope is explicit and matches the implementation.
- [x] First cleanup expansion candidate: make `DocumentationCache` visible and optionally cleanable, but not part of the default safe cleanup set.
- [x] Centralize cleanup policy and user-facing descriptions so default selections, explicit opt-in cleanup eligibility, affected-root summaries, and help text come from one shared source of truth.
- [ ] Design the destructive Full Xcode Removal workflow as an isolated Cleanup section with scope groups, dry-run preview, and strong confirmation for personal-state/delete-everything actions.

## Next Milestones

- [ ] Do a post-packaging GUI QA and documentation pass.
- [ ] Make the repository public on GitHub.
- [ ] Finish post-1.0 cleanup and release follow-through.
