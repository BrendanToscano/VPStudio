#!/usr/bin/env bash
set -euo pipefail

# Build VPStudio against a supported simulator destination.
#
# Defaults to visionOS Simulator (Apple Vision Pro). To target iOS Simulator,
# set VPSTUDIO_SIM_PLATFORM="iOS Simulator" and optionally VPSTUDIO_SIM_DEVICE.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="VPStudio.xcodeproj"
SCHEME="VPStudio"
CONFIGURATION="${CONFIGURATION:-Debug}"
PLATFORM="${VPSTUDIO_SIM_PLATFORM:-visionOS Simulator}"

DESTINATIONS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null || true)"

if [[ "$PLATFORM" == "visionOS Simulator" ]]; then
  DEVICE_NAME="${VPSTUDIO_SIM_DEVICE:-Apple Vision Pro}"
elif [[ "$PLATFORM" == "iOS Simulator" ]]; then
  DEVICE_NAME="${VPSTUDIO_SIM_DEVICE:-iPhone 17}"
else
  echo "error: Unsupported simulator platform '$PLATFORM'. Use 'visionOS Simulator' or 'iOS Simulator'." >&2
  exit 2
fi

if ! printf '%s' "$DESTINATIONS" | grep -q "platform:${PLATFORM}"; then
  echo "error: No ${PLATFORM} destination available for scheme '$SCHEME'." >&2
  if [[ "$PLATFORM" == "visionOS Simulator" ]]; then
    echo "Install the visionOS runtime in Xcode > Settings > Components." >&2
  else
    echo "Install an iOS simulator runtime/device in Xcode > Settings > Components." >&2
  fi
  exit 1
fi

DESTINATION="platform=${PLATFORM},name=${DEVICE_NAME},OS=latest"

echo "Building $SCHEME ($CONFIGURATION) for: $DESTINATION"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  build
