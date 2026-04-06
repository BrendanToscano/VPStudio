# 2026-03-19 Review: BUG #10 — Search menu genre/mood on-demand loading

## Scope reviewed
- `.committee/BUGS.md` entry #10
- `git diff` for `VPStudio/Views/Windows/Search/SearchView.swift`
- `git diff` for `VPStudioTests/ViewModels/SearchViewModelTests.swift`
- `VPStudio/Core/Support/QARuntimeOptions.swift` (new QA automation flags)
- Recent QA artifacts in `qa-artifacts/20260319-bug10-on-demand-genres/`
- `xcodebuild ... test -only-testing:VPStudioTests/SearchViewModelTests/genreLoadingIsLazyUntilExplicitRequest` (passes)

## Findings

### Strengths
- The eager `.task { loadGenres() }` trigger was removed from the search header path, so browse genres are no longer requested during normal idle/search entry.
- `SearchView` now loads genres only when user-visible interactions imply intent:
  - opening the filter sheet (`isShowingFilters`), and
  - explicit genre/mood context changes (e.g., selected genre + type flip).
- QA-only flags in `QARuntimeOptions` cleanly gate automation for the filter sheet and auto-select flows without affecting regular runtime paths.
- New unit coverage (`genreLoadingIsLazyUntilExplicitRequest`) explicitly verifies:
  - no genre request from search flow
  - exactly one request when `loadGenres()` is invoked
  - no duplicate requests on repeated calls.

### Risks / open questions
- The current QA run in `qa-artifacts/20260319-bug10-on-demand-genres` is still not an end-to-end proof of real TMDB-driven genre/mood retrieval.
  - `search-idle-qa.png` and OCR output show a TMDB setup prompt / missing-key messaging, which can mask whether on-demand code paths hit the network in realistic conditions.
- UI artifact evidence confirms state transitions (screenshots differ), but OCR is too weak to verify the intended genre/mood content changed correctly.
- In `applyQASearchIfNeeded`, automation proceeds to open filters and attempt genre/mood interactions even if TMDB is unavailable; this is acceptable for tooling but hides regressions unless the setup path is explicitly seeded.

### Next safest step
- Re-run the bug #10 QA pass with a valid TMDB key (or deterministic stubbed TMDB service in QA) and manually inspect at least:
  1. filter-sheet-open state
  2. genre-result state after first genre selection
  3. mood-result state after mood card selection
- If these all show expected populated content, promote status to `Fixed`; if not, inspect the `SearchViewModel.loadGenres()` + `selectGenre()` async sequencing.
