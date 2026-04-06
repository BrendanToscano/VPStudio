# VPStudio Review Note — 2026-03-19 (Kimi review lane)

## Target item
- **BUG #1** — Playback can fail with network error when starting a video

## Evidence reviewed
- `git diff` for current working tree in the VPStudio repo.
- `qa-artifacts/20260319-bug1-stream-link-refresh-regression/` screenshots + sql artifacts.
- `qa-artifacts/20260319-bug1-stream-failover-qa/` summary.
- Focused XCTest run:
  - `swift test --package-path . --filter 'PlayerStreamLinkRecoveryTests|DetailLifecycleBehaviorTests|PlayerSessionRoutingTests|PlayerStreamFailoverTests|PlayerEngineSelectorMatrixTests|ModelTests'` ✅
  - `xcodebuild ... test -only-testing:VPStudioTests/Player/PlayerStreamLinkRecoveryTests -only-testing:VPStudioTests/ViewModels/DetailLifecycleBehaviorTests/resolveStreamAttachesRecoveryContextForDebridLinkRefresh -only-testing:VPStudioTests/Player/PlayerSessionRoutingTests/streamPoolKeepsDistinctResolvedURLsForSameReleaseMetadata` ✅

## Diff-based strengths
- Recovery path is focused and minimal:
  - `StreamInfo` now carries `StreamRecoveryContext` for debrid-backed streams.
  - `DetailViewModel` resolves streams with provenance (provider/hash/season/episode) and threads it through playback state.
  - `PlayerView` adds a **single** retry attempt via `PlayerStreamLinkRecovery.refreshContext(...)` before normal failover.
- Existing player engine fallback behavior is preserved (`tryAutomaticFailover` still executes when refresh is unavailable/unhelpful), minimizing risk of regression in the old failure path.
- Coverage exists in unit tests and regression artifacts and explicitly validates:
  - dedup by logical stream identity across URL token churn,
  - recovery context preservation in session routing,
  - playback queue behavior after refreshed stream replacement.

## Risks / confidence checks
- The remaining high-value validation is still missing: no controlled real-provider expired-link/403 case in this pass. Current QA confirms flow glue and queue churn behavior, not the true-time failure shape of production debrid links.
- In `search-link`/detail queue transitions, refresh attempts are keyed by `StreamInfo.id` (which intentionally ignores volatile URL query/fragment); this is likely correct for token churn but could still allow replay edge cases if the underlying logical identity changes less predictably than expected.

## Next safest step
- Add one short, explicit QA case for a real debrid expiring link (or controlled synthetic 403/expired fixture) and document pass/fail in a new artifact folder.
- If it passes, move `BUG #1` status from **Fixed pending QA** to **Fixed**.
