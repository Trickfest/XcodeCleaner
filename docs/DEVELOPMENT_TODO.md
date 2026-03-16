# Development TODO

Last updated: 2026-03-16

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
- [ ] Migrate cleanup of known simulator devices from direct filesystem deletion to `simctl` so registered CoreSimulator objects are removed through Apple-supported commands.
- [ ] Support both legacy version-first and newer model-prefixed `iOS DeviceSupport` directory names when detecting stale Device Support folders, preferring `Info.plist` metadata over folder-name-only parsing where possible.
- [ ] Decide and document the intended meaning of `Total Xcode Footprint`: all major standard Xcode-managed storage with non-trivial size, excluding tiny preference and personal-state data.
- [ ] Expand footprint accounting to include additional major Xcode-managed storage that is currently omitted, starting with `~/Library/Developer/Xcode/DocumentationCache`.
- [ ] Audit other standard Xcode storage roots for inclusion, such as result and log storage and similar non-trivial caches, and explicitly decide include versus exclude for each.
- [ ] Keep personal preference and state locations out of the normal footprint total for now, including Xcode preferences, saved application state, and small `UserData` state.
- [ ] Add tests that cover modern simulator runtime layouts, especially volume-backed runtime locations under `/Library/Developer/CoreSimulator/Volumes/...`.
- [ ] Add tests that verify aggregate totals match the union of tracked major storage roots and do not undercount when runtime bundle paths live outside the old hardcoded path.
- [ ] Update UI labeling and README wording so the footprint number's scope is explicit and matches the implementation.
- [ ] Expand cleanup scope in phases rather than all at once.
- [ ] First cleanup expansion candidate: make `DocumentationCache` visible and optionally cleanable, but not part of the default safe cleanup set.
- [ ] Classify new cleanup candidates by safety and recovery cost so the app distinguishes default-safe cleanup from explicit opt-in cleanup.
- [ ] Preserve the current default-safe cleanup posture for ordinary use; broadening accounting should not automatically broaden default deletion.
- [ ] Design a separate destructive full-removal workflow inside the app later, likely as an isolated destructive section within `Cleanup`, not as normal cleanup toggles.
- [ ] When the full-removal workflow is built, include explicit scope groups, strong warnings, dry-run preview, and confirmation steps for personal state and remove-everything actions.

## Next Milestones

- [ ] Do a post-packaging GUI QA and documentation pass.
- [ ] Make the repository public on GitHub.
- [ ] Finish post-1.0 cleanup and release follow-through.
