# 2026-03-19 Review note (Kimi spare lane)

## Scope
- Review fixed-pending item **#6** (Vision Pro side and bottom control bars) from `.committee/BUGS.md`.
- Reviewed current code changes in:
  - `VPStudio/Views/Windows/ContentView.swift`
  - `VPStudio/Views/Windows/Navigation/VPSidebarView.swift`
- Reviewed recent QA artifacts:
  - `qa-artifacts/20260319-item6-vision-nav-bars/before-bottom.png`
  - `qa-artifacts/20260319-item6-vision-nav-bars/after-bottom.png`
  - `qa-artifacts/20260319-item6-vision-nav-bars/after-bottom-v2.png`
  - `qa-artifacts/20260319-item6-vision-nav-bars/before-sidebar.png`
  - `qa-artifacts/20260319-item6-vision-nav-bars/after-sidebar.png`
  - `qa-artifacts/20260319-item6-vision-nav-bars/after-sidebar-v2.png`
  - `qa-artifacts/20260319-item6-vision-nav-bars/comparison-collage(-v2).png`

## Strengths
- VisionOS-only scaling is centralized into `chromeScale` / `scaledForViewport`, keeping macOS behavior untouched.
- Bottom bar sizing changes are coherent: icon size, spacing, tab width/height, separator height, and badge offsets are all scaled together, reducing hit-target imbalance.
- Sidebar scaling mirrors the same policy (`sidebarWidth`, icon frame, corner radius, badge and spacing), so side and bottom controls now feel like one pass instead of two separate tweaks.
- Evidence indicates visible difference in bottom-bar pass (`after-bottom-v2`) vs `before-bottom` (nontrivial pixel-level change), so UI change is actually present in the artifacts.

## Risks
- The new scale is effectively binary (`compact` => `1`, non-compact => `1.25`) rather than truly viewport-proportional; this may still look too small on some larger VisionOS layouts and too large on tighter split-window layouts.
- Sidebar capture variants include a redundant pair (`after-sidebar-v2` is byte-identical to `after-sidebar`), so there is no independent v2 delta for that view.
- Bottom/siderbar screenshots are useful, but there is no accompanying run log showing click/tap interactions, and no explicit compact-mode QA pass; with large change regions in captures, confidence is limited to visual diff only.

## Next safest step
- Keep #6 in `Fixed pending QA`.
- Add a dedicated compact-mode QA pass (pre/post screenshots from the same scene state) and one interaction capture for both bottom tab and sidebar taps.
- If scaling remains binary, gate by a second metric (e.g. scene bounds / window width) so the size changes remain proportional across VisionOS viewport sizes.
