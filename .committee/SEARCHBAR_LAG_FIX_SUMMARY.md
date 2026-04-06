# Search bar lag fix summary

Date: 2026-03-20

## What changed
- Made the whole Search pill focus the text field via `@FocusState` in `SearchQueryBar`, so the first tap is no longer limited to the tight text glyph hit area.
- Stopped the outer `SearchView` shell from observing `hasQueryText` for the TMDB setup gate. The gate now keys off `hasAttemptedTextSearch` only, which removes an unnecessary shell invalidation on the very first typed character.
- Deferred `loadUserRatings()` until the results section actually appears, instead of doing that work immediately when the Search page opens.

## Why this should help
- First focus should register more reliably because the entire pill now forwards taps into the field.
- Initial typing should avoid a visible hitch from the Search shell re-evaluating on the first non-empty character.
- Entering the Search page now does less up-front work before the user starts interacting.

## Files changed
- `VPStudio/Views/Windows/Search/SearchView.swift`
- `/.committee/BUGS.md`

## Validation
- Passed hosted targeted tests:
  - `SearchViewModelPerformanceTests`
  - `SearchViewModelExplorePhaseTests`
- Passed hosted app build
- Logs:
  - `qa-artifacts/20260320-bug18-focus-hit-target/logs/xcode-targeted-tests.log`
  - `qa-artifacts/20260320-bug18-focus-hit-target/logs/xcode-build.log`

## QA artifact note
- I also ran a simulator screenshot script in `qa-artifacts/20260320-bug18-focus-hit-target/`, but the PNGs captured the visionOS home environment instead of the VPStudio Search window. I kept that run documented in `qa-inspection.txt`, but it should not be treated as visual proof of the Search UI.

## Honest status
- The code now directly targets both the first-focus hit target and the first-keystroke churn.
- I left BUG #18 as **In progress** until someone does a final hands-on feel check in the simulator/device and confirms the subjective latency is actually gone.
