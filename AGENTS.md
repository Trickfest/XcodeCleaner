# AGENTS.md

Guidance for coding agents working in this repository.

## Project Summary
- Product: `XcodeCleaner`
- Language/stack: Swift + SwiftUI (macOS 14+), SwiftPM + Xcode project for GUI packaging
- Deliverables:
- `XcodeCleanerApp` (GUI)
- `xcodecleaner-cli` (CLI)
- Distribution model: source-first (clone + local build). Signing/notarization is optional future work, not a current gate.

## Current Planning Context
- Work in small, reviewable chunks with incremental value.
- Current sequencing:
  - Keep the GUI codebase organized and workflow-oriented.
  - Update docs after structural changes.
  - Do packaging/icon/release work after the codebase and docs are aligned.
- Keep CLI and GUI parity for shared capabilities when technically applicable.

## Required Workflow
- Do not commit or push unless the user explicitly asks.
- For chunked work:
- Implement chunk.
- Run tests.
- Provide a concise review checklist.
- Wait for user approval before committing.
- If user asks to commit after each chunk, follow that exactly.

## Commit Message Style
- Do not prepend Conventional Commit prefixes (for example, `fix(app):`) unless the user explicitly asks for that format.
- Use a concise plain-language subject line by default.

## Safety and Behavior Constraints
- Preserve cleanup guardrails:
- Protect active/running Xcode installs.
- Protect booted/running simulator devices.
- Move to Trash first; direct-delete fallback only when explicitly enabled.
- Avoid destructive commands unless explicitly requested.
- Do not remove user changes you did not create.

## Build/Test Commands
- Use local module cache env vars for SwiftPM commands:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift test --disable-sandbox
```

- Run CLI:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox xcodecleaner-cli
```

- Run GUI:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/swift-module-cache \
swift run --disable-sandbox XcodeCleanerApp
```

- Build the bundled GUI app:

```bash
Scripts/build-xcodecleaner-app.sh
```

## Key Files
- `Package.swift`: package/products/targets.
- `XcodeCleaner.xcodeproj`: macOS app project for the bundled GUI target.
- `Xcode/XcodeCleanerApp/*`: bundle metadata and `Assets.xcassets` for the GUI app.
- `Scripts/build-xcodecleaner-app.sh`: repeatable `xcodebuild` wrapper for `XcodeCleaner.app`.
- `Sources/XcodeInventoryCore/*`: scanner, models, planning, execution, automation core.
- `Sources/XcodeCleanerCLI/*`: CLI modes, options, output/progress behavior.
- `Sources/XcodeCleanerApp/XcodeCleanerApp.swift`: app entry point.
- `Sources/XcodeCleanerApp/App/*`: app lifecycle helpers.
- `Sources/XcodeCleanerApp/ViewModels/*`: GUI state coordination.
- `Sources/XcodeCleanerApp/Views/Sections/*`: workflow-specific section views.
- `Sources/XcodeCleanerApp/Views/Components/*`: shared app UI panels.
- `Sources/XcodeCleanerApp/State/*`: app-only form and selection state.
- `Sources/XcodeCleanerApp/Support/*`: app-only presentation helpers and section metadata.
- `docs/DEVELOPMENT_TODO.md`: current milestone ordering and release-adjacent follow-up work.
- `docs/REPORT_SCHEMA.md`: report/export schema details.

## Documentation Expectations
- Update `README.md`, `AGENTS.md`, and `docs/DEVELOPMENT_TODO.md` when structure or milestone ordering changes.
- Keep release/readme docs aligned with implemented behavior (especially GUI/CLI parity and distribution assumptions).
