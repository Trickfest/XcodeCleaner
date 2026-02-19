# AGENTS.md

Guidance for coding agents working in this repository.

## Project Summary
- Product: `XcodeCleaner`
- Language/stack: Swift + SwiftUI (macOS 14+), SwiftPM
- Deliverables:
- `XcodeCleanerApp` (GUI)
- `xcodecleaner-cli` (CLI)
- Distribution model: source-first (clone + local build). Signing/notarization is optional future work, not a current gate.

## Current Planning Context
- Sprint-based delivery with incremental value each chunk.
- Sprint 10 focus: UI organization and workflow clarity.
- Keep CLI and GUI parity for shared capabilities when technically applicable.

## Required Workflow
- Do not commit or push unless the user explicitly asks.
- For chunked sprint work:
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

## Key Files
- `Package.swift`: package/products/targets.
- `Sources/XcodeInventoryCore/*`: scanner, models, planning, execution, automation core.
- `Sources/XcodeCleanerCLI/*`: CLI modes, options, output/progress behavior.
- `Sources/XcodeCleanerApp/XcodeCleanerApp.swift`: SwiftUI app shell and section views (currently centralized).
- `docs/IMPLEMENTATION_ROADMAP.md`: sprint roadmap.
- `docs/SPRINT_10.md`: current sprint chunk plan and acceptance criteria.

## Documentation Expectations
- Update sprint docs/roadmap when scope or sprint ordering changes.
- Keep release/readme docs aligned with implemented behavior (especially GUI/CLI parity and distribution assumptions).
