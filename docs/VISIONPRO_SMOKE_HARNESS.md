# Vision Pro Deep Smoke Harness

Script: `tools/visionpro-deep-smoke.sh`

A dedicated Vision Pro simulator smoke harness for VPStudio that runs:

- Playback/debrid/subtitles/download packs
- Environment/immersive packs
- Library import/export packs
- Sync/scrobble/trakt/simkl packs
- Full-suite rerun
- Launch/tab stress loop
- Per-tab screenshots
- Recent crash-log scan

## Usage

```bash
cd /Users/openclaw/Projects/VPStudio

# Optional: provide credentials so Discover/debrid paths are exercised
export VPSTUDIO_TMDB_API_KEY="<tmdb-key>"
export VPSTUDIO_DEBRID_TOKEN="<debrid-token>"

./tools/visionpro-deep-smoke.sh
```

## Output

The run writes artifacts under:

- `.smoke-runs/visionpro-<timestamp>/summary.txt`
- `.smoke-runs/visionpro-<timestamp>/summary.json`
- `.smoke-runs/visionpro-<timestamp>/logs/*.log`
- `.smoke-runs/visionpro-<timestamp>/screenshots/*.png`

## Notes

- This harness is simulator-driven (`xcodebuild` + `simctl`) and does not require desktop click automation.
- Credentials are injected into the simulator app database only for testability of credential-gated paths.
- A full-suite run can still fail if there are flaky tests; check `summary.txt` + per-pack logs for details.
