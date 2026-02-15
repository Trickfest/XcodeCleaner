# Release Smoke Checklist (Sprint 9)

## Distribution Model (Current)
- Source-first distribution via public GitHub repository.
- Target users are developers who build locally.
- Signed/notarized binary distribution is optional future work.

## Build and Test
- Build release artifacts:
  - `scripts/build_release_artifacts.sh`
- Run full tests:
  - `CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache swift test --disable-sandbox`
- Build CLI:
  - `swift run --disable-sandbox xcodecleaner-cli --help`
- Build app:
  - `swift run --disable-sandbox XcodeCleanerApp`

## CLI Functional Smoke
- Inventory scan:
  - `xcodecleaner-cli --no-progress`
- Dry run:
  - `xcodecleaner-cli --dry-run --plan-category derivedData`
- Execute guard mode:
  - `xcodecleaner-cli --execute --skip-if-tools-running --plan-category derivedData`
- Automation list/create/run:
  - `xcodecleaner-cli automation list`
  - `xcodecleaner-cli automation create --name smoke-policy --every-hours 12 --category derivedData`
  - `xcodecleaner-cli automation run-due --no-progress`

## Reporting Smoke
- Export history CSV:
  - `xcodecleaner-cli automation history --format csv --output /tmp/xcodecleaner-history.csv`
- Export trends JSON:
  - `xcodecleaner-cli automation trends --format json --output /tmp/xcodecleaner-trends.json`
- Verify report schema compatibility against `docs/REPORT_SCHEMA.md`.

## GUI Functional Smoke
- Deferred to Sprint 10 due planned UI reorganization.
- After Sprint 10 UI changes, run:
  - App launches and scan completes.
  - Progress bar updates throughout scan phases.
  - Automation section loads policies and history.
  - Automation trends show 7-day and 30-day windows.
  - Export buttons create files under `~/.xcodecleaner/exports`.

## Optional Future Packaging and Signing
- Build release artifacts for GUI and CLI.
- Optionally run signing/notarization helper when prebuilt binaries are being distributed:
  - `SIGNING_IDENTITY=\"Developer ID Application: ...\" APPLE_NOTARY_PROFILE=\"<profile>\" scripts/notarize_release.sh`
- Optionally verify signed/notarized artifact install on a clean macOS host.

## Acceptance
- No high-severity defects.
- All smoke checks complete and documented.
