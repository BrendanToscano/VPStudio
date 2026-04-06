# QUEUE.md — VPStudio Coordination Notes
**Updated:** 2026-03-21 02:12 UTC (queue steward)

## Repo truth at this pass
- HEAD: `a2b7bc1` — "Revert visionOS nav chrome to baseline layout" (local revert; clean, no new code)
- Dirty tree: **57 tracked files** changed, **12+ untracked paths** (Build/, qa-artifacts/, .swiftpm/, device-backups/, VPStudio/Assets.xcassets/GenreArtwork/, .orig/.patch files, etc.)
- `main...origin/main` still showing significant ahead count from prior session series
- `PlayerView.swift` still one of the hottest files in the tree; #5 collision surface is somewhat reduced by the revert but #5 itself remains open

## Bug tracker status summary

| # | Bug | Status | Lane |
|---|-----|--------|------|
| 1 | Playback fails with network error | **Fixed** | — |
| 2 | Indexer quality/fetch strategy | **Fixed** | — |
| 3 | Explore/Search page laggy | **In progress** | Search (Kimi/Spark) |
| 4 | Library title cards load slowly | **Fixed** | — |
| 5 | Player resizing mismatch | **In progress** | PlayerView collision zone |
| 6 | Vision Pro control bar sizing | **Fixed** | — |
| 7 | Embedded torrent audio/subtitle tracks | **Open** | No lane assigned |
| 8 | Freeflow aspect-ratio toggle | **Fixed** | — |
| 9 | Art-backed UI imagery | **Fixed** | — |
| 10 | Genre/mood on-demand loading | **Fixed** | QA-verified |
| 11 | Settings IA reorganization | **Fixed** | — |
| 12 | Trakt sync local DB update | **Fixed** | — |
| 13 | Trakt Client ID paste button | **Open** | No lane assigned |
| 14 | OpenRouter + live model lists | **Open** | No lane assigned |
| 15 | IMDb sync option | **Open** | No lane assigned |
| 16 | CSV import + AI header matching | **Open** | No lane assigned |
| 17 | Player top-right menu glitch | **Fixed** | — |
| 18 | Search bar first-focus/input lag | **In progress** | Search lane |

## Lane recommendations

### 🔍 Search lane (BUG #3, #18)
Both bugs are tightly coupled through `SearchView` / `SearchViewModel`. Stronger to keep one owner on both through to closure rather than splitting.
- **#3:** Many focused passes landed; the core Search responsiveness architecture is substantially improved. The honest remaining step is a final human-feel pass on the first-focus / first-keystroke interaction, not another code refactor.
- **#18:** Same Search shell. The code now directly addresses the first-focus hit target, the clear-button slot stability, and the first-keystroke churn. **One blocker remains:** the configured search path crashes at `GlassCard.swift:255` (`ArtworkFallbackStyle.palette(for:type:)` arithmetic overflow) before screenshot QA can confirm the configured results state. This crash is **pre-existing and unrelated to the Search changes** — it needs a fix in `GlassCard` art fallback arithmetic before #18 configured-path QA can close.
- **Recommendation:** Keep Kimi/Spark on Search closure. Next steps: (1) fix `GlassCard` overflow crash, (2) capture configured-path screenshots for #18, (3) human-feel first-tap check for both #3 and #18.

### 🎬 Player lane (BUG #5)
`PlayerView` is still a hot collision surface with 57 dirty files in the tree. The revert partially reduced collateral risk, but #5 itself is still open and needs a dedicated owner push. Multiple `PlayerView_Bug5_Fix*.patch` files in the working tree suggest some prior attempts that may not have landed cleanly.
- **Recommendation:** Single owner on `PlayerView` only — no parallel edits in that file. Wait for the Search lane to clear more of the tree first if collision risk is a concern.

### 🤖 Gemini / UI QA lane
Currently degraded from repeated `call_id` malformed failures; remediated to `MiniMax-M2.7` per prior notes. Screenshot-driven UI polish passes (visible in `qa-artifacts/20260320-ui-ux-fix-pass/`, `qa-artifacts/20260320-bug17-top-right-menu-stability/`) are within scope for this lane without triggering more Search/Player churn.
- **Recommendation:** Keep Gemini on screenshot review + closure evidence gathering. Not the right lane for new code.

### 🚫 Open items without lanes (#7, #13, #14, #15, #16)
None of these are assigned. They are all genuine feature asks that don't overlap with the current Search/Player hot paths.
- **#13 (Trakt paste button):** Likely a one-session fix — just add a paste button to the Trakt Client ID `TextField`. Good starter item.
- **#7 (Audio/subtitle tracks):** More involved; requires understanding of current torrent track detection.
- **#14 (OpenRouter + live models):** Backend/AI settings work.
- **#15 (IMDb sync) / #16 (CSV AI header matching):** Both need research before implementation.

## Blocker / attention needed

1. **`GlassCard.swift:255` overflow crash** — `ArtworkFallbackStyle.palette(for:type:)` arithmetic overflow crashes the configured search path in simulator. Pre-existing, not caused by Search changes. Blocks #18 configured-path QA closure. Fix is a small arithmetic guard — not a major refactor.

2. **`ExploreGenreCatalogTests` compile failure** — `missing argument for parameter 'artImageName'` was previously noted. This may have been updated in later test passes but is flagged here as needing confirmation if the hosted test path is still failing.

3. **Repo collision risk remains high** — 57 dirty tracked files. The broad tree makes it easy for two lanes to edit the same file simultaneously. Until more of this tree lands on `main`, prefer serializing hot files (`PlayerView`, `SearchView`, `SearchViewModel`, `ContentView`) behind one owner per file.

## What's honest from this pass
No new source edits, no new QA folders, no status flips. The most recent artifact bundle (`20260320-bug3-search-shell-lightweight/`) confirms a real narrow improvement for BUG #3. The repo is still in the same state: broad dirty tree, two Search bugs close to honest closure pending the GlassCard fix + human-feel check, one Player bug needing a dedicated owner, and four open feature items with no lane.
