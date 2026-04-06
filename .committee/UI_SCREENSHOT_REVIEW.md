# VPStudio UI Screenshot Review (QA Artifacts)

Scope: Visual QA from `/Users/openclaw/Projects/VPStudio/qa-artifacts` screenshots (current-pass and recent bug-lane captures).

## Executive summary
The product is visually close, but still has several **high-visibility polish gaps** that keep it from feeling fully premium in VisionOS contexts. Biggest risks are:
- missing art fallbacks in a media-first UI,
- control/menu ergonomics that feel uncertain for gaze/hand interaction,
- blocked/error states that still feel like dev/debug UX.

Search/Explore stability work appears structurally okay (no obvious layout regressions), but finish quality and affordance consistency still need work.

## Prioritized observations & recommendations

### 1) High: Image-backed art is still inconsistent (critical for trust)
**Evidence:**
- `20260320-bug9-art-grid-qa/01-before-genre-grid.png` (symbol fallback baseline), `02-after-genre-grid-art.png`, `03-after-genre-grid-with-art-fix.png`, `04-after-genre-grid-with-art-fix-installed.png` (bug #9) show clear before/after improvement but mixed behavior.
- `20260320-bug3-explore-art-lookup-cache/screenshots/01-search-idle-art-grid.png`, `02-query-results.png` still show some cards rendered as weak placeholders instead of posters.
- `20260319-bug4-library-cards/04-placeholder-without-spinner.png` shows a known “Dune” item still degraded to a generic placeholder tile.

**Recommendation:**
- Define a **single fallback strategy** for missing artwork (e.g., gradient + title initials + subtle shimmer), not a hard dark placeholder.
- Use one canonical art fetch policy so genre cards, search results, and library all follow identical fallback behavior.
- Add QA assertion for “no generic placeholder tiles above N% of visible cards” in seeded smoke runs.

### 2) High: Player controls/menu usability feels unstable and can become non-discoverable
**Evidence:**
- `20260319-bug1-stream-identity/screenshots/01-post-setup.png`, `04-search-flow.png`, `05-player-attempt.png`, `06-player-attempt-later.png`
- `20260319-bug1-visionos-engine-order/screenshots/player-compatibility-open.png`

Observed patterns:
- control surface appears to disappear in some states without obvious re-entry affordance,
- mixed icon/text control density (settings + metadata + playback controls) with weak visual grouping,
- small top-right menu/inline controls appear hard to target.

**Recommendation:**
- Keep a minimal persistent **control shell** (or explicit “tap/click to reveal controls” affordance) so control presence is never ambiguous.
- Reserve a stronger hierarchy for primary controls (Play/Pause/Seek/Back) and de-emphasize metadata toggles.
- Expand interactive areas for tiny controls (`...` menu, per-icon actions) while keeping visual icon small.

### 3) High: Error/setup empty states are informative but visually “interruption-style” not “premium-style”
**Evidence:**
- `current-pass/11-search-without-tmdb.png`, `current-pass/07-discover-invalid-tmdb.png`
- `20260320-bug3-first-keystroke-phase-gate/screenshots/03-unconfigured-search-setup-gate.png`
- `20260320-bug18-attempt-boundary-qa/screenshots/01-unconfigured-submitted-setup-gate.png`
- `manual/search-empty.png`, `manual/downloads-failed.png`, `current-pass/12-downloads-empty-state.png`

Observed patterns:
- central blocking modal dominates flow,
- messaging is functional but not user-friendly in tone,
- states give little immediate recovery action (scan-to-suggest, clear/search retry, direct jump CTA).

**Recommendation:**
- Keep shell visible; render state cards as **inline contextual panels** instead of full takeover where possible.
- Replace technical phrasing with concise user language and provide one clear primary action in each state.
- Add recovery chips for common next steps: Browse Genres, Retry Search, Go to Discover, Restore Search, etc.

### 4) Medium: Navigation bar/menu geometry is inconsistent between layouts and states
**Evidence:**
- nav comparisons: `20260319-item6-vision-nav-bars-qa-pass/compact-bottom-qa.png`, `before-bottom-qa.png`, `compact-sidebar-qa.png`, `before-sidebar-qa.png`, `interact-*`
- `nav-sidebar-current-final.png`, `nav-sidebar-safearea32.png`, `nav-sidebar-safearea-offset32.png`, `nav-bottom-safearea32.png`, `nav-diff-bottom-vs-sidebar-offset58.png`, `nav-diff-current-final.png`

Observed patterns:
- side vs bottom variants do not feel visually equivalent; sidebar consumes too much focus area on this layout,
- safe-area/edge padding and target separation varies by mode,
- bottom dock can look detached from content in some captures.

**Recommendation:**
- Standardize one layout as default for VPStudio on visionOS (likely compact bottom-first per capture comparison).
- Lock icon row height/width, inter-item spacing, and safe-area insets as constants.
- Increase separation from viewport edges and ensure nav container has consistent depth/blur relative to app body.

### 5) Medium: Control sizing and spacing regressions across search/pills/chips and card rows still feel uneven
**Evidence:**
- `20260320-bug18-clear-slot-stability/screenshots/01-configured-search-idle.png`, `02-configured-first-character.png`, `03-configured-query-results.png`
- `20260318-.../ordered/grid*`, `current-pass/ordered/grid2/test-*`, `current-pass/ordered/11-*.png`
- `20260319-bug10-on-demand-genres/screenshots/search-filter-open-qa.png`

Observed patterns:
- visual consistency is mostly intact, but hit-target spacing around pills/filter controls and control bars appears variable by state,
- button sizing weight shifts between “Explore/Run Setup/Quick Start” and controls in secondary tabs.

**Recommendation:**
- Introduce 2–3 size tokens for controls (`small`, `medium`, `large`) and apply them system-wide.
- Keep chip and button gutters fixed across all tabs; avoid implicit reflow by content state.

### 6) Medium: VisionOS-specific polish can be pushed further (2D panel feel in places)
**Evidence:**
- `20260319-item6-vision-nav-bars-qa-pass/comparison-collage-qa-pass.png`
- `20260320-bug5-player-resize-inspection/aspect-21-9.png`, `aspect-4-3.png`
- `20260319-bug1-visionos-engine-order/screenshots/player-compatibility-open.png`

Observed patterns:
- many screens still read as flat panels rather than spatial layers,
- some controls and overlays appear as dense UI noise instead of layered, float-on-glass behavior.

**Recommendation:**
- Increase material depth contrast (consistent blur/translucency + shadow depth) and apply stronger foreground/background separation.
- Keep compact modes for controls and avoid oversized flat clusters in front of media.

## Positive confirmations
- Search shell stability for bug #3 / #18 flows looks visually stable in reviewed states (no obvious clipping or hard layout breaks).
- Bug #9 art-grid lane clearly improved with image-backed cards after fix pass, indicating underlying rendering path can achieve premium output when available.

## Suggested quick QA pass checklist (next run)
1. Verify zero placeholder posters in top 12 cards on explore/search/library seeded states.
2. Validate no control-less player screens where actions are not explicitly accessible.
3. Validate nav layout in compact-bottom mode against safe-area constants at 2–3 simulator sizes.
4. Capture one screenshot each for error/setup/empty states with:
   - inline recovery CTA,
   - no blocking full-screen takeover,
   - user language copy.
5. Re-run with no-TMDB/no-stream credentials to ensure states remain premium and non-dev-like.
