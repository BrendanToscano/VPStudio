#!/usr/bin/env bash
set -euo pipefail

# Smart build entrypoint for local automation.
#
# Usage:
#   ./tools/build-for-destination.sh "platform=visionOS Simulator,name=Apple Vision Pro"
#   ./tools/build-for-destination.sh "platform=iOS Simulator,name=iPhone 16"
#
# If an iOS simulator destination is requested, we fail fast with a clear root-cause
# explanation and the correct command to run, since VPStudio is currently visionOS-only.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="VPStudio.xcodeproj"
SCHEME="VPStudio"
CONFIGURATION="${CONFIGURATION:-Debug}"
REQUESTED_DESTINATION="${1:-platform=visionOS Simulator,name=Apple Vision Pro,OS=latest}"

if [[ "$REQUESTED_DESTINATION" == *"platform=iOS Simulator"* ]]; then
  echo "error: VPStudio does not support iOS Simulator destinations." >&2
  echo "root-cause: The Xcode target is configured for visionOS only (SUPPORTED_PLATFORMS=xros xrsimulator)." >&2
  echo "fix: Build against a visionOS simulator destination instead." >&2
  echo >&2
  echo "Try:" >&2
  echo "  ./tools/build-simulator.sh" >&2
  echo "or:" >&2
  echo "  xcodebuild -project $PROJECT -scheme $SCHEME -configuration $CONFIGURATION -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build" >&2
  exit 70
fi

echo "Building $SCHEME ($CONFIGURATION) for: $REQUESTED_DESTINATION"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$REQUESTED_DESTINATION" \
  build
