# 2026-03-20 Review: BUG #18 — Search submitted-query attempt boundary

## Scope reviewed
- `.committee/BUGS.md` entry #18
- `git status -sb` / current dirty-tree context
- `git diff` for:
  - `VPStudio/ViewModels/Search/SearchViewModel.swift`
  - `VPStudio/Views/Windows/Search/SearchView.swift`
  - `VPStudio/Core/Support/QARuntimeOptions.swift`
  - `VPStudioTests/ViewModels/SearchViewModelPerformanceTests.swift`
  - `VPStudioTests/ViewModels/SearchViewModelExplorePhaseTests.swift`
- Recent QA artifacts in:
  - `qa-artifacts/20260320-bug18-attempt-boundary-qa/`
  - `qa-artifacts/20260320-bug18-first-input-gate-deferral/`
  - `qa-artifacts/20260320-bug18-draft-query-commit/`

## Findings

### Strengths
- The latest change is genuinely narrow and lines up with the bug’s current theory: `hasAttemptedTextSearch` now follows the submitted-query boundary instead of flapping on every post-submit edit, which matches how `SearchView.isSearchSetupRequired` gates the setup overlay.
- `queryDraft` / `submittedQuery` / `hasAttemptedTextSearch` responsibilities are clearer now:
  - live typing stays in `queryDraft`
  - committed search intent stays in `submittedQuery`
  - the setup gate only reappears when the edited draft again matches an actually submitted query
- QA automation for the new scenario is appropriately isolated behind QA-only env flags (`VPSTUDIO_QA_POST_SUBMIT_DRAFT_QUERY*`), so the production path is not taking on extra runtime behavior.
- Evidence is coherent across code, tests, and screenshots:
  - targeted Search suites pass in `qa-artifacts/20260320-bug18-attempt-boundary-qa/logs/xcode-targeted-tests.log`
  - `queryEditAfterUnconfiguredAttemptReturnsPhaseToIdleUntilNextSearch` still protects the edited-back-to-idle behavior
  - `hasAttemptedTextSearchOnlyInvalidatesOnSubmitBoundary` locks in the narrower invalidation boundary
  - the reviewed screenshots show the three expected shells still intact: submitted setup gate, edited-back idle Explore state, and configured results

### Risks / open questions
- This is still not direct proof that the original first-focus / first-input hitch is gone. The evidence here is about state-boundary churn after submit/edit transitions, not the raw first tap / first keystroke feel.
- `hasAttemptedTextSearch` is currently derived from exact trimmed equality with `submittedQuery`. That is fine for today’s behavior, but it is a seam worth watching if future query normalization/autocorrect changes land.
- The Search lane is still sitting inside a broad dirty tree with heavy `SearchView` / `SearchViewModel` overlap, so even good narrow fixes are carrying elevated merge/regression risk until more of the tree lands.

### Next safest step
- Keep this patch as a narrow confidence gain, not closure.
- Do one dedicated first-focus verification pass that measures or visibly records the raw path before submit:
  1. fresh Search open
  2. first tap into the field
  3. first typed character with no submit
- If the hitch is still perceptible, profile or instrument the focus-path invalidation/render work around the search shell and query bar before making another behavioral change. If it feels clean, capture that explicit evidence and then consider closing BUG #18.
