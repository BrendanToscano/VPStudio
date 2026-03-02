#!/usr/bin/env bash
set -euo pipefail

# Build VPStudio against a supported simulator destination.
#
# Why this exists:
# - VPStudio is currently visionOS-only.
# - Running xcodebuild with an iOS simulator destination fails with code 70.
# - This helper auto-selects a valid destination from the active scheme.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="VPStudio.xcodeproj"
SCHEME="VPStudio"
CONFIGURATION="${CONFIGURATION:-Debug}"

DESTINATIONS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null || true)"

if printf '%s' "$DESTINATIONS" | grep -q "platform:visionOS Simulator"; then
  DEVICE_NAME="${VPSTUDIO_VISION_DEVICE:-Apple Vision Pro}"
  DESTINATION="platform=visionOS Simulator,name=${DEVICE_NAME},OS=latest"
else
  echo "error: No visionOS Simulator destination available for scheme '$SCHEME'." >&2
  echo "Install the visionOS runtime in Xcode > Settings > Components." >&2
  exit 1
fi

echo "Building $SCHEME ($CONFIGURATION) for: $DESTINATION"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  build
