#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${ROOT_DIR}/.build/xcode"
SOURCE_PACKAGES_PATH="${DERIVED_DATA_PATH}/SourcePackages"
CLANG_CACHE_PATH="${ROOT_DIR}/.build/clang-module-cache"
SWIFT_MODULE_CACHE_PATH="${ROOT_DIR}/.build/swift-module-cache"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCH="${ARCH:-arm64}"

usage() {
  cat <<'EOF'
Usage: Scripts/build-xcodecleaner-app.sh [--arch arm64|x86_64]

Builds the XcodeCleaner macOS app bundle into .build/xcode/Build/Products/.

Options:
  --arch <arch>   Build for the selected macOS architecture. Defaults to arm64.
  -h, --help      Show this help text.

You can also override the default with ARCH=arm64 or ARCH=x86_64.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      if [[ $# -lt 2 ]]; then
        printf 'error: --arch requires a value\n' >&2
        usage >&2
        exit 1
      fi
      ARCH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "${ARCH}" in
  arm64|x86_64)
    ;;
  *)
    printf 'error: unsupported architecture: %s\n' "${ARCH}" >&2
    usage >&2
    exit 1
    ;;
esac

mkdir -p "${DERIVED_DATA_PATH}" "${SOURCE_PACKAGES_PATH}" "${CLANG_CACHE_PATH}" "${SWIFT_MODULE_CACHE_PATH}"

export CLANG_MODULE_CACHE_PATH="${CLANG_CACHE_PATH}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFT_MODULE_CACHE_PATH}"

xcodebuild \
  -project "${ROOT_DIR}/XcodeCleaner.xcodeproj" \
  -scheme XcodeCleaner \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${SOURCE_PACKAGES_PATH}" \
  -destination "platform=macOS,arch=${ARCH}" \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/XcodeCleaner.app"
printf 'Built app bundle (%s): %s\n' "${ARCH}" "${APP_PATH}"
