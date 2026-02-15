#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
ZIP_PATH="${ROOT_DIR}/dist/xcodecleaner-release.zip"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
APPLE_NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"

if [[ -z "${SIGNING_IDENTITY}" ]]; then
  echo "error: SIGNING_IDENTITY is required (codesign identity name)." >&2
  exit 2
fi

if [[ -z "${APPLE_NOTARY_PROFILE}" ]]; then
  echo "error: APPLE_NOTARY_PROFILE is required (xcrun notarytool keychain profile)." >&2
  exit 2
fi

if [[ ! -x "${DIST_DIR}/xcodecleaner-cli" || ! -x "${DIST_DIR}/XcodeCleanerApp" ]]; then
  echo "error: release artifacts not found in ${DIST_DIR}. Run scripts/build_release_artifacts.sh first." >&2
  exit 2
fi

echo "Signing release binaries..."
codesign --force --timestamp --options runtime --sign "${SIGNING_IDENTITY}" "${DIST_DIR}/xcodecleaner-cli"
codesign --force --timestamp --options runtime --sign "${SIGNING_IDENTITY}" "${DIST_DIR}/XcodeCleanerApp"

echo "Creating notarization zip..."
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${DIST_DIR}" "${ZIP_PATH}"

echo "Submitting for notarization (profile: ${APPLE_NOTARY_PROFILE})..."
xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${APPLE_NOTARY_PROFILE}" --wait

echo "Notarization completed successfully for ${ZIP_PATH}."
