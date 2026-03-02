#!/usr/bin/env bash
set -euo pipefail

# Smart build entrypoint for local automation.
#
# Usage:
#   ./tools/build-for-destination.sh "platform=visionOS Simulator,name=Apple Vision Pro"
#   ./tools/build-for-destination.sh "platform=iOS Simulator,name=iPhone 17"
#
# Supports both iOS and visionOS simulator destinations. If a destination cannot
# be resolved (exit 70), prints a root-cause hint and nearby valid destinations.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="VPStudio.xcodeproj"
SCHEME="VPStudio"
CONFIGURATION="${CONFIGURATION:-Debug}"
REQUESTED_DESTINATION="${1:-platform=visionOS Simulator,name=Apple Vision Pro,OS=latest}"

echo "Building $SCHEME ($CONFIGURATION) for: $REQUESTED_DESTINATION"

set +e
BUILD_OUTPUT="$(xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$REQUESTED_DESTINATION" \
  build 2>&1)"
BUILD_EXIT=$?
set -e

printf '%s\n' "$BUILD_OUTPUT"

if [[ $BUILD_EXIT -eq 0 ]]; then
  exit 0
fi

if [[ $BUILD_EXIT -eq 70 && "$BUILD_OUTPUT" == *"Unable to find a device matching the provided destination specifier"* ]]; then
  REQUESTED_PLATFORM="$(printf '%s' "$REQUESTED_DESTINATION" | sed -n 's/.*platform=\([^,]*\).*/\1/p')"
  if [[ -z "$REQUESTED_PLATFORM" ]]; then
    REQUESTED_PLATFORM="Simulator"
  fi

  echo >&2
  echo "root-cause: requested simulator destination is not installed/available in this Xcode runtime." >&2
  echo "fix: choose a currently available destination from -showdestinations output." >&2

  DESTINATIONS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null || true)"
  SUGGESTIONS="$(printf '%s\n' "$DESTINATIONS" | grep "platform:${REQUESTED_PLATFORM}" | sed -E 's/^\s*\{\s*//; s/\s*\}\s*$//')"

  if [[ -n "$SUGGESTIONS" ]]; then
    echo >&2
    echo "Available ${REQUESTED_PLATFORM} destinations:" >&2
    printf '%s\n' "$SUGGESTIONS" >&2
  fi
fi

exit $BUILD_EXIT
