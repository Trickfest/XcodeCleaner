#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${ROOT_DIR}/.build/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${ROOT_DIR}/.build/swift-module-cache}"

echo "Building release CLI..."
swift build --disable-sandbox -c release --product xcodecleaner-cli

echo "Building release app executable..."
swift build --disable-sandbox -c release --product XcodeCleanerApp

DIST_DIR="${ROOT_DIR}/dist"
mkdir -p "${DIST_DIR}"

cp "${ROOT_DIR}/.build/release/xcodecleaner-cli" "${DIST_DIR}/xcodecleaner-cli"
cp "${ROOT_DIR}/.build/release/XcodeCleanerApp" "${DIST_DIR}/XcodeCleanerApp"

chmod +x "${DIST_DIR}/xcodecleaner-cli" "${DIST_DIR}/XcodeCleanerApp"

echo "Release artifacts ready in ${DIST_DIR}:"
ls -la "${DIST_DIR}"
