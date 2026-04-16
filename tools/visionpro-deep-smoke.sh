#!/usr/bin/env bash
set -euo pipefail

# Vision Pro deep smoke harness for VPStudio
#
# What it does:
# 1) Boots Apple Vision Pro simulator
# 2) Optionally injects TMDB + Debrid credentials into simulator app DB
# 3) Runs targeted deep test packs (playback, environment, library import/export, sync)
# 4) Runs full Vision Pro test suite
# 5) Runs launch/tab stress loop
# 6) Captures screenshots for core tabs
# 7) Writes machine-readable summaries
#
# Required tools: xcodebuild, xcrun, sqlite3, python3

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="VPStudio.xcodeproj"
SCHEME="VPStudio"
BUNDLE_ID="com.tgk30.VPStudio"
DEVICE_NAME="${VPSTUDIO_VISION_DEVICE:-Apple Vision Pro}"
KEYCHAIN_SERVICE="com.vpstudio.credentials"

# Resolve a stable simulator UDID to avoid name ambiguity (Vision Pro simulator)
SIM_DEVICE_ID="$(xcrun simctl list -j devices available | python3 -c 'import json,sys,os
data=json.load(sys.stdin)
name=os.environ.get("VPSTUDIO_VISION_DEVICE") or "Apple Vision Pro"
best=""
for devs in (data.get("devices") or {}).values():
    for d in devs:
        if d.get("name")==name and d.get("isAvailable") is True:
            best=d.get("udid") or ""
            break
    if best:
        break
print(best)')"
SIM_DEVICE="${SIM_DEVICE_ID:-$DEVICE_NAME}"

# Prefer pinning xcodebuild to the specific simulator when possible
if [ -n "${SIM_DEVICE_ID:-}" ]; then
  DESTINATION="id=${SIM_DEVICE_ID}"
else
  DESTINATION="platform=visionOS Simulator,name=${DEVICE_NAME},OS=latest"
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)"
OUT_BASE="${VPSTUDIO_SMOKE_OUT:-$ROOT_DIR/.smoke-runs}"
RUN_DIR="$OUT_BASE/visionpro-$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
SHOT_DIR="$RUN_DIR/screenshots"
DERIVED_DATA_DIR="$RUN_DIR/DerivedData"
mkdir -p "$RUN_DIR" "$LOG_DIR" "$SHOT_DIR" "$DERIVED_DATA_DIR"

SUMMARY_JSON="$RUN_DIR/summary.json"
SUMMARY_TXT="$RUN_DIR/summary.txt"

echo "{" > "$SUMMARY_JSON"
echo "  \"runId\": \"$RUN_ID\"," >> "$SUMMARY_JSON"
echo "  \"device\": \"$DEVICE_NAME\"," >> "$SUMMARY_JSON"
echo "  \"destination\": \"$DESTINATION\"," >> "$SUMMARY_JSON"
echo "  \"packs\": {" >> "$SUMMARY_JSON"

append_pack_json() {
  local label="$1"
  local bundle_path="$2"
  local comma="$3"

  local result="unknown"
  local passed="null"
  local failed="null"
  local total="null"
  local first_failure=""

  if [ -d "$bundle_path" ]; then
    local tmp_json
    tmp_json="$RUN_DIR/${label}-summary.json"
    if xcrun xcresulttool get test-results summary --path "$bundle_path" > "$tmp_json" 2>/dev/null; then
      result="$(python3 - <<PY
import json
p='$tmp_json'
with open(p) as f:
    d=json.load(f)
print(d.get('result') or 'unknown')
PY
)"
      passed="$(python3 - <<PY
import json
p='$tmp_json'
with open(p) as f:
    d=json.load(f)
v=d.get('passedTests')
print('null' if v is None else v)
PY
)"
      failed="$(python3 - <<PY
import json
p='$tmp_json'
with open(p) as f:
    d=json.load(f)
v=d.get('failedTests')
print('null' if v is None else v)
PY
)"
      total="$(python3 - <<PY
import json
p='$tmp_json'
with open(p) as f:
    d=json.load(f)
v=d.get('totalTestCount')
print('null' if v is None else v)
PY
)"
      first_failure="$(python3 - <<PY
import json
p='$tmp_json'
with open(p) as f:
    d=json.load(f)
f=d.get('testFailures') or []
print((f[0].get('testIdentifierString') if f else ''))
PY
)"
    fi
  fi

  {
    echo "${label}: result=$result passed=$passed failed=$failed total=$total"
    if [ -n "$first_failure" ]; then
      echo "${label}: first_failure=$first_failure"
    fi
  } >> "$SUMMARY_TXT"

  cat >> "$SUMMARY_JSON" <<JSON
    \"$label\": {
      \"result\": \"$result\",
      \"passed\": $passed,
      \"failed\": $failed,
      \"total\": $total,
      \"firstFailure\": \"$first_failure\"
    }$comma
JSON
}

run_pack() {
  local label="$1"
  shift
  local bundle_path="$RUN_DIR/${label}.xcresult"
  local log_path="$LOG_DIR/${label}.log"
  local requested_only_testing_count="$#"
  local filtered_args=()
  rm -rf "$bundle_path"

  echo "== Running $label ==" | tee -a "$SUMMARY_TXT"

  if [ "$requested_only_testing_count" -gt 0 ]; then
    while IFS= read -r arg; do
      [ -n "$arg" ] && filtered_args+=("$arg")
    done < <(filter_only_testing_args "$@")

    local executed_only_testing_count="${#filtered_args[@]}"
    local skipped_only_testing_count=$((requested_only_testing_count - executed_only_testing_count))
    echo "$label: requested_only_testing=$requested_only_testing_count executed_only_testing=$executed_only_testing_count skipped_stale=$skipped_only_testing_count" >> "$SUMMARY_TXT"

    if [ "$executed_only_testing_count" -eq 0 ]; then
      echo "$label: skipped_all_only_testing_targets_missing=1" >> "$SUMMARY_TXT"
      return 0
    fi
  fi

  set +e
  if [ "$requested_only_testing_count" -gt 0 ]; then
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA_DIR" test -resultBundlePath "$bundle_path" "${filtered_args[@]}" > "$log_path" 2>&1
  else
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA_DIR" test -resultBundlePath "$bundle_path" > "$log_path" 2>&1
  fi
  local code=$?
  set -e

  echo "$label: xcodebuild_exit=$code" >> "$SUMMARY_TXT"
}

filter_only_testing_args() {
  python3 - "$ROOT_DIR" "$@" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]) / "VPStudioTests"
available = set()
for path in root.rglob("*.swift"):
    try:
        text = path.read_text(errors="ignore")
    except OSError:
        continue
    for match in re.finditer(r"\b(?:class|struct)\s+([A-Za-z0-9_]+Tests)\b", text):
        available.add(match.group(1))

filtered = []
missing = []
for arg in sys.argv[2:]:
    if not arg.startswith("-only-testing:"):
      filtered.append(arg)
      continue

    spec = arg.split(":", 1)[1]
    bundle, _, remainder = spec.partition("/")
    test_name = remainder.split("/", 1)[0] if remainder else ""
    if bundle == "VPStudioTests" and test_name and test_name not in available:
        missing.append(test_name)
        continue
    filtered.append(arg)

for test_name in sorted(set(missing)):
    print(f"[visionpro-deep-smoke] Skipping stale test target: {test_name}", file=sys.stderr)

for arg in filtered:
    print(arg)
PY
}

upsert_app_setting() {
  local key="$1"
  local value="$2"
  python3 - "$DB_PATH" "$key" "$value" <<'PY'
import sqlite3
import sys

db_path, key, value = sys.argv[1:4]
with sqlite3.connect(db_path) as conn:
    conn.execute(
        "INSERT OR REPLACE INTO app_settings(key, value) VALUES(?, ?)",
        (key, value),
    )
    conn.commit()
PY
}

upsert_debrid_config() {
  local config_id="$1"
  local token_ref="$2"
  python3 - "$DB_PATH" "$config_id" "$token_ref" <<'PY'
import sqlite3
import sys

db_path, config_id, token_ref = sys.argv[1:4]
with sqlite3.connect(db_path) as conn:
    conn.execute("DELETE FROM debrid_configs WHERE serviceType = ?", ("real_debrid",))
    conn.execute(
        """
        INSERT INTO debrid_configs(
            id, serviceType, apiTokenRef, isActive, priority, createdAt, updatedAt
        ) VALUES(?, 'real_debrid', ?, 1, 0, datetime('now'), datetime('now'))
        """,
        (config_id, token_ref),
    )
    conn.commit()
PY
}

seed_simulator_keychain_secret() {
  local account="$1"
  local secret="$2"
  xcrun simctl spawn "$SIM_DEVICE" security delete-generic-password -a "$account" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
  xcrun simctl spawn "$SIM_DEVICE" security add-generic-password -a "$account" -s "$KEYCHAIN_SERVICE" -w "$secret" -U >/dev/null 2>&1
}

upsert_secret_setting() {
  local key="$1"
  local secret="$2"
  local account="settings.${key}"
  local secret_ref="keychain:${account}"

  if ! seed_simulator_keychain_secret "$account" "$secret"; then
    return 1
  fi

  if upsert_app_setting "$key" "$secret_ref"; then
    return 0
  fi

  xcrun simctl spawn "$SIM_DEVICE" security delete-generic-password -a "$account" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
  return 1
}

echo "Vision Pro Deep Smoke Run: $RUN_ID" > "$SUMMARY_TXT"
echo "Device: $DEVICE_NAME" >> "$SUMMARY_TXT"
echo "Destination: $DESTINATION" >> "$SUMMARY_TXT"
echo "Run dir: $RUN_DIR" >> "$SUMMARY_TXT"
echo "" >> "$SUMMARY_TXT"

# 0) Boot simulator
xcrun simctl boot "$SIM_DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_DEVICE" -b >/dev/null

# 1) Ensure app container exists
xcrun simctl launch "$SIM_DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$SIM_DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
APP_DATA="$(xcrun simctl get_app_container "$SIM_DEVICE" "$BUNDLE_ID" data)"
DB_PATH="$APP_DATA/Library/Application Support/VPStudio/vpstudio.sqlite"

echo "DB path: $DB_PATH" >> "$SUMMARY_TXT"

# 2) Optional secure credential injection for Discover/debrid user-like smoke
# Provide credentials via env vars before running script:
#   VPSTUDIO_TMDB_API_KEY=... VPSTUDIO_DEBRID_TOKEN=... tools/visionpro-deep-smoke.sh
if [ -n "${VPSTUDIO_TMDB_API_KEY:-}" ] && [ -f "$DB_PATH" ]; then
  if upsert_secret_setting "tmdb_api_key" "$VPSTUDIO_TMDB_API_KEY"; then
    echo "Configured tmdb_api_key via simulator keychain reference" >> "$SUMMARY_TXT"
  else
    echo "Unable to seed simulator keychain for tmdb_api_key; skipping secure TMDB injection" >> "$SUMMARY_TXT"
  fi
else
  echo "TMDB key not provided; Discover may show API key error" >> "$SUMMARY_TXT"
fi

if [ -n "${VPSTUDIO_DEBRID_TOKEN:-}" ] && [ -f "$DB_PATH" ]; then
  CFG_ID="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  SECRET_ACCOUNT="debrid.real_debrid.${CFG_ID}"
  SECRET_REF="keychain:${SECRET_ACCOUNT}"
  if seed_simulator_keychain_secret "$SECRET_ACCOUNT" "$VPSTUDIO_DEBRID_TOKEN"; then
    upsert_debrid_config "$CFG_ID" "$SECRET_REF" || true
    upsert_app_setting "default_debrid_service" "real_debrid" || true
    echo "Configured active real_debrid token via simulator keychain" >> "$SUMMARY_TXT"
  else
    echo "Unable to seed simulator keychain for debrid token; skipping secure debrid injection" >> "$SUMMARY_TXT"
  fi
else
  echo "Debrid token not provided; debrid playback path may be limited" >> "$SUMMARY_TXT"
fi

echo "" >> "$SUMMARY_TXT"

# 3) Deep packs
run_pack "playback-pack" \
  -only-testing:VPStudioTests/PlayerCapabilityTests \
  -only-testing:VPStudioTests/PlayerEngineFallbackTests \
  -only-testing:VPStudioTests/PlayerEngineSelectorMatrixTests \
  -only-testing:VPStudioTests/PlayerSessionRoutingTests \
  -only-testing:VPStudioTests/PlayerSessionRoutingConcurrencyTests \
  -only-testing:VPStudioTests/PlayerSessionRoutingFallbackScoringTests \
  -only-testing:VPStudioTests/PlayerStreamFailoverTests \
  -only-testing:VPStudioTests/PlayerStreamFailoverPlannerMatrixTests \
  -only-testing:VPStudioTests/PlayerLifecyclePolicyTests \
  -only-testing:VPStudioTests/PlayerLoadingStatusTests \
  -only-testing:VPStudioTests/PlayerTransportControlsPolicyTests \
  -only-testing:VPStudioTests/PlayerCinematicChromePolicyTests \
  -only-testing:VPStudioTests/PlayerCinematicVisualPolicyTests \
  -only-testing:VPStudioTests/VPPlayerEngineImmersiveTests \
	-only-testing:VPStudioTests/VPPlayerEngineSubtitleLoadingTests \
	-only-testing:VPStudioTests/VPPlayerEngineSubtitleTimingTests \
	-only-testing:VPStudioTests/ExternalPlayerRoutingTests \
	-only-testing:VPStudioTests/PlayerResourceTeardownContractTests \
	-only-testing:VPStudioTests/DownloadManagerTests \
	-only-testing:VPStudioTests/DownloadDatabaseTests \
	-only-testing:VPStudioTests/RealDebridServiceTests \
	-only-testing:VPStudioTests/DebridAddMagnetHashValidationTests \
	-only-testing:VPStudioTests/AllDebridServiceTests \
	-only-testing:VPStudioTests/TorBoxServiceTests \
	-only-testing:VPStudioTests/PremiumizeServiceTests \
	-only-testing:VPStudioTests/EasyNewsServiceTests \
	-only-testing:VPStudioTests/DebridLinkServiceURLEncodingTests \
	-only-testing:VPStudioTests/PremiumizeServiceURLEncodingTests \
	-only-testing:VPStudioTests/DebridErrorTests \
	-only-testing:VPStudioTests/CacheStatusTests \
	-only-testing:VPStudioTests/OpenSubtitlesSearchTests \
	-only-testing:VPStudioTests/OpenSubtitlesAuthTests \
	-only-testing:VPStudioTests/OpenSubtitlesDownloadTests \
	-only-testing:VPStudioTests/OpenSubtitlesErrorTests \
	-only-testing:VPStudioTests/SubtitleModelTests \
	-only-testing:VPStudioTests/SubtitleFormatParseTests

run_pack "library-pack" \
  -only-testing:VPStudioTests/LibraryCSVImportServiceTests \
  -only-testing:VPStudioTests/LibraryCSVImportFolderTests \
  -only-testing:VPStudioTests/LibraryCSVMultiImportTests \
  -only-testing:VPStudioTests/CSVExportEscapeTests \
  -only-testing:VPStudioTests/CSVExportSummaryTests \
  -only-testing:VPStudioTests/CSVExportIntegrationTests \
  -only-testing:VPStudioTests/LibraryTaskLifecycleTests \
  -only-testing:VPStudioTests/LibrarySortPolicyTests \
  -only-testing:VPStudioTests/LibraryLayoutPolicyTests \
  -only-testing:VPStudioTests/LibraryGridPolicyTests \
  -only-testing:VPStudioTests/LibraryFolderSortOrderTests \
  -only-testing:VPStudioTests/LibraryEmptyStateCTAPolicyTests

run_pack "sync-pack" \
  -only-testing:VPStudioTests/SimklSyncServiceTests \
  -only-testing:VPStudioTests/TraktOAuthTests \
  -only-testing:VPStudioTests/TraktAPICallTests \
  -only-testing:VPStudioTests/TraktErrorTests \
  -only-testing:VPStudioTests/TraktModelTests \
  -only-testing:VPStudioTests/SimklOAuthTests \
  -only-testing:VPStudioTests/SimklAPICallTests \
  -only-testing:VPStudioTests/SimklErrorTests \
  -only-testing:VPStudioTests/SimklModelTests \
  -only-testing:VPStudioTests/TraktListMappingModelTests \
  -only-testing:VPStudioTests/TraktListMappingDBTests \
  -only-testing:VPStudioTests/SyncResultFolderFieldsTests \
  -only-testing:VPStudioTests/TraktFolderSyncIntegrationTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorPullTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorPushTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorToggleTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorErrorResilienceTests \
  -only-testing:VPStudioTests/SyncResultTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorHistoryPullWatchHistoryTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorHistoryPushTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorHistoryPaginationTests \
  -only-testing:VPStudioTests/TraktSyncOrchestratorBidirectionalHistoryTests \
  -only-testing:VPStudioTests/TraktAddRatingTests \
  -only-testing:VPStudioTests/TraktTokenRefreshCallbackTests \
  -only-testing:VPStudioTests/TraktHistoryPaginationTests \
  -only-testing:VPStudioTests/TraktAddToWatchlistBodyTests \
  -only-testing:VPStudioTests/TraktDeviceCodeFlowTests \
  -only-testing:VPStudioTests/TraktErrorDeviceCodeTests \
  -only-testing:VPStudioTests/DeviceCodeResponseTests \
  -only-testing:VPStudioTests/TraktDefaultsTests \
  -only-testing:VPStudioTests/ScrobbleCoordinatorDisabledTests \
  -only-testing:VPStudioTests/ScrobbleCoordinatorActiveTests \
  -only-testing:VPStudioTests/ScrobbleCoordinatorHistoryTests \
  -only-testing:VPStudioTests/ScrobbleCoordinatorSettingsGateTests \
  -only-testing:VPStudioTests/ScrobbleCoordinatorErrorResilienceTests

run_pack "environment-pack" \
  -only-testing:VPStudioTests/EnvironmentAutoOpenTests \
  -only-testing:VPStudioTests/EnvironmentCatalogTests \
  -only-testing:VPStudioTests/EnvironmentLoaderTaskLifecycleTests \
  -only-testing:VPStudioTests/HDRIEnvironmentTypeTests \
  -only-testing:VPStudioTests/CuratedEnvironmentProviderTests \
  -only-testing:VPStudioTests/EnvironmentAssetYawOffsetTests \
  -only-testing:VPStudioTests/CuratedEnvironmentPresetTests \
  -only-testing:VPStudioTests/EnvironmentPresetCurationTests \
  -only-testing:VPStudioTests/EnvironmentCatalogCuratedDefaultsTests \
  -only-testing:VPStudioTests/EnvironmentImmersiveSpaceRoutingTests \
  -only-testing:VPStudioTests/ImmersiveControlsPolicyTests \
  -only-testing:VPStudioTests/ImmersiveNotificationTests \
  -only-testing:VPStudioTests/VPPlayerEngineImmersiveTests \
  -only-testing:VPStudioTests/AppStateImmersiveLifecycleTests \
  -only-testing:VPStudioTests/AppStateImmersiveDismissReasonTests \
  -only-testing:VPStudioTests/AppStateActivateEnvironmentAssetTests

# Full-suite rerun
run_pack "full-suite"

# Ensure app is installed on the named simulator device (xcode tests may run on clones)
APP_BUNDLE_PATH="$DERIVED_DATA_DIR/Build/Products/Debug-xrsimulator/VPStudio.app"
if [ ! -d "$APP_BUNDLE_PATH" ]; then
  APP_BUNDLE_PATH="$(find "$DERIVED_DATA_DIR/Build/Products" -path "*/VPStudio.app" | sort | tail -1 || true)"
fi
if [ -n "${APP_BUNDLE_PATH:-}" ] && [ -d "$APP_BUNDLE_PATH" ]; then
  xcrun simctl install "$SIM_DEVICE" "$APP_BUNDLE_PATH" >/dev/null 2>&1 || true
fi

# Ensure simulator is booted before stress/screenshots (xcodebuild may use/shutdown clones)
xcrun simctl boot "$SIM_DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_DEVICE" -b >/dev/null || true

# 4) Launch/tab stress loop
if [ -f "$DB_PATH" ]; then
  tabs=(Discover Explore Search Library Downloads Settings)
  launch_failures=0
  cycles=24
  for ((i=0; i<cycles; i++)); do
    tab="${tabs[$((i % ${#tabs[@]}))]}"
    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO app_settings(key,value) VALUES('last_selected_tab','${tab}');" || true
    if ! xcrun simctl launch --terminate-running-process "$SIM_DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
      launch_failures=$((launch_failures+1))
    fi
    sleep 0.6
  done
  echo "stressLoop: cycles=$cycles launchFailures=$launch_failures" >> "$SUMMARY_TXT"
else
  echo "stressLoop: skipped (missing DB at $DB_PATH)" >> "$SUMMARY_TXT"
fi

# Re-assert boot before screenshot capture
xcrun simctl boot "$SIM_DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM_DEVICE" -b >/dev/null || true

# 5) Screenshot capture by tab
if [ -f "$DB_PATH" ]; then
  tabs=(Discover Explore Search Library Downloads Settings)
  for tab in "${tabs[@]}"; do
    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO app_settings(key,value) VALUES('last_selected_tab','${tab}');" || true
    xcrun simctl launch --terminate-running-process "$SIM_DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    sleep 2.5
    tab_lower="$(echo "$tab" | tr "[:upper:]" "[:lower:]")"
    out_path="$SHOT_DIR/vpstudio-vision-${tab_lower}.png"
    for attempt in 1 2 3; do
      xcrun simctl io "$SIM_DEVICE" screenshot "$out_path" >/dev/null 2>&1 || true
      if [ -f "$out_path" ] && [ "$(stat -f%z "$out_path" 2>/dev/null || echo 0)" -gt 10000 ]; then
        break
      fi
      sleep 2
    done

  done
  echo "screenshots: $SHOT_DIR" >> "$SUMMARY_TXT"
fi

# 6) Crash scan (recent 6h)
python3 - <<PY >> "$SUMMARY_TXT" || true
import os, time
crash_dir=os.path.expanduser('~/Library/Logs/DiagnosticReports')
count=0
print('recentCrashLogs:')
if os.path.isdir(crash_dir):
    now=time.time()
    items=[]
    for fn in os.listdir(crash_dir):
        if 'VPStudio' in fn and (fn.endswith('.crash') or fn.endswith('.ips')):
            p=os.path.join(crash_dir,fn)
            try:
                m=os.path.getmtime(p)
            except Exception:
                continue
            if now-m < 6*3600:
                items.append((m,fn))
    items.sort(reverse=True)
    for _,fn in items[:20]:
        print('  -',fn)
        count += 1
print(f'recentCrashLogCount={count}')
PY

# 7) Build JSON summary entries
append_pack_json "playback-pack" "$RUN_DIR/playback-pack.xcresult" ","
append_pack_json "library-pack" "$RUN_DIR/library-pack.xcresult" ","
append_pack_json "sync-pack" "$RUN_DIR/sync-pack.xcresult" ","
append_pack_json "environment-pack" "$RUN_DIR/environment-pack.xcresult" ","
append_pack_json "full-suite" "$RUN_DIR/full-suite.xcresult" ""

echo "  }," >> "$SUMMARY_JSON"

# Include stress loop + artifacts in JSON
python3 - <<PY >> "$SUMMARY_JSON"
import os, re
summary_txt = "$SUMMARY_TXT"
run_dir = "$RUN_DIR"
shot_dir = "$SHOT_DIR"
cycles = None
failures = None
with open(summary_txt) as f:
    txt=f.read()
m=re.search(r'stressLoop: cycles=(\d+) launchFailures=(\d+)', txt)
if m:
    cycles=int(m.group(1))
    failures=int(m.group(2))
shots=[]
if os.path.isdir(shot_dir):
    for fn in sorted(os.listdir(shot_dir)):
        if fn.endswith('.png'):
            shots.append(os.path.join(shot_dir, fn))
print('  "stressLoop": {')
print(f'    "cycles": {"null" if cycles is None else cycles},')
print(f'    "launchFailures": {"null" if failures is None else failures}')
print('  },')
print('  "artifacts": {')
print(f'    "runDir": "{run_dir}",')
print(f'    "summaryTxt": "{summary_txt}",')
print('    "screenshots": [')
for i,p in enumerate(shots):
    comma=',' if i < len(shots)-1 else ''
    print(f'      "{p}"{comma}')
print('    ]')
print('  }')
print('}')
PY

echo ""
echo "✅ Vision Pro deep smoke complete"
echo "Run dir: $RUN_DIR"
echo "Text summary: $SUMMARY_TXT"
echo "JSON summary: $SUMMARY_JSON"
echo "Screenshots: $SHOT_DIR"
