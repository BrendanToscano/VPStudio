# 2026-03-19 Spare-lane review (Kimi)

## Scope reviewed
- In-progress item #5 (player resize behavior)
- Fixed-pending-QA #1 (stream identity)
- Fixed-pending-QA #10 (on-demand genre loading)
- Also rechecked Fixed-pending-QA #4 QA notes for signal consistency

### #1 Playback failover stream identity
**Strengths**
- `StreamInfo.id` now includes normalized transport identity (`streamURL` without query/fragment), so token-only URL churn no longer collapses streams while path changes stay distinct.
- New focused tests cover this behavior in `ModelTests`, `PlayerSessionRoutingTests`, and `DetailFeatureStateTests`.
- Added `DatabaseManager.fetchMediaItemsResolvingAliases()` and alias-driven hydration path so metadata can be reused across canonical and TMDB-keyed IDs.

**Risks**
- QA and build evidence is still simulation-oriented; no full real-debrid/network failover path has been exercised yet.
- Targeted `xcodebuild test` still fails before execution (`TEST_HOST ... VPStudio.app/VPStudio`), so confidence in end-to-end behavior remains lower than desired.
- `URLComponents` normalization may still be affected by unusual URLs (e.g., path-embedded mutable tokens) not represented in tests.

**Next safest step**
- Resolve the test-host issue, then run the targeted and broader tests for playback-routing and stream-state.
- Add one real-world smoke playback case (debrid-resolved links with multiple transient URL variants) before clearing #1.

### #10 Search genres/moods on demand
**Strengths**
- Removed eager `loadGenres()` from `SearchView` startup path.
- Keeps explicit load paths (filter-sheet open / type/mood actions) present so feature behavior remains functional.
- Build passes (`xcodebuild build`) and QA artifact path exists: `qa-artifacts/20260319-bug10-on-demand-genres/`.

**Risks**
- Existing QA artifact only captures idle-search screen; it does **not** validate the on-open interactive flow where the requirement is most important.
- No evidence yet that no premature network request occurs before user interaction.

**Next safest step**
- Run interactive QA that opens the filter sheet and performs a mood/genre action, with screenshots before/after first interaction to confirm deferred loading.

### #5 Player resize behavior (in progress)
**Strengths**
- VisionOS geometry update now tracks a scene identity and cancels stale requests, reducing race conditions when scene/window updates happen.
- Uses a temporary forced geometry update followed by a relaxed bound, similar to prior behavior.

**Risks**
- `currentWidth` is hard-clamped with `max(bounds.width, 1400)`, which can force an unexpectedly large base width on smaller contexts.
- No screenshot-based validation attached for the specific player-resize/ratio-matching requirement before marking fixed.

**Next safest step**
- Keep item #5 `In progress` until a dedicated VisionOS size regression sweep passes for 16:9 and 4:3 streams (with screenshots validating matching behavior).

### #4 QA evidence consistency check
**Strengths**
- Existing screenshots/SQL in `qa-artifacts/20260319-bug4-library-cards/` still align with the claimed alias-resolution + hydration behavior.

**Risks**
- None new from this pass; no broader user-flow evidence beyond seeded cases.

**Next safest step**
- Optional: add a small happy-path spot-check of library card rendering with mixed source IDs to reduce chance of regression from cache alias changes.
