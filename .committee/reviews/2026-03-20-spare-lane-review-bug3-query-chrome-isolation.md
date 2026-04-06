# 2026-03-20 Review: BUG #3 — Search query chrome isolation

## Scope reviewed
- `.committee/BUGS.md` entry #3
- `git diff` for:
  - `VPStudio/Views/Windows/Search/SearchView.swift`
  - `VPStudio/ViewModels/Search/SearchViewModel.swift`
  - `VPStudioTests/ViewModels/SearchViewModelPerformanceTests.swift`
  - `VPStudioTests/ViewModels/SearchViewModelExplorePhaseTests.swift`
  - `VPStudioTests/ViewModels/SearchViewModelTests.swift`
- QA artifacts in `qa-artifacts/20260320-bug3-query-chrome-isolation/`
- Targeted test log: `qa-artifacts/20260320-bug3-query-chrome-isolation/logs/xcode-targeted-tests.log`

## Findings

### Strengths
- The latest pass is narrowly scoped in the right place: it reduces outer Search-shell churn instead of piling more behavior into the already-hot results/layout path.
- `SearchViewModel` now exposes lower-churn UI signals (`hasQueryText`, `submittedQuery`, stored `explorePhase`) so the parent Search shell no longer has to observe every raw keystroke.
- `SearchView` cleanly moves the text field into `SearchQueryBar`, and the inline quick-filter row now keys off `displayedExplorePhase` rather than raw `query` text. That matches the intended UX: no chip row before a real search, but chips reappear once results are active.
- The QA evidence is coherent:
  - `01-configured-search-idle.png` shows the configured idle Explore state without the extra quick-filter row.
  - `02-configured-query-results.png` shows populated results with the quick-filter row restored in the active-results state.
  - `03-unconfigured-search-setup-gate.png` shows the expected setup gate instead of a broken empty shell.
- The targeted hosted run succeeded, and the log shows the narrowed Search suites passing (`SearchViewModelTests`, `SearchViewModelPerformanceTests`, `SearchViewModelExplorePhaseTests`; 114 tests across 3 suites).
- The new observation-oriented tests are valuable, especially the checks that:
  - `explorePhase` stays idle while raw typing begins, and
  - `hasQueryText` only invalidates at the empty/non-empty boundary.

### Risks / open questions
- This pass improves shell invalidation behavior, but it is not strong evidence that BUG #3 as a whole is closed. It does not directly measure the user-reported first-focus / first-input hitch.
- The unconfigured path still intentionally swaps to the setup gate on the first typed character because `isSearchSetupRequired` keys off `hasQueryText`, not a submitted query. That may be acceptable UX, but it means the first-keystroke phase swap still exists in that branch by design.
- There is still no timing/profile artifact here (signposts, Instruments trace, frame-time capture, or even a scripted before/after latency measure), so the broader “like 360hz” goal remains unproven.
- The Search lane is still sitting inside a very broad dirty tree, so even good local evidence should be treated as a narrow confidence gain rather than a reason to broaden the refactor again.

### Next safest step
- Keep BUG #3 open.
- Treat the next narrow closure step as measurement for the remaining first-focus / first-input hitch (effectively BUG #18 territory), not another broad Search refactor.
- Safest follow-up:
  1. capture a tiny before/after timing pass around first focus + first character entry,
  2. verify whether the unconfigured first-keystroke setup-gate swap contributes meaningfully to the hitch,
  3. only then decide whether to defer that behavior, isolate it further, or leave it as-is.
