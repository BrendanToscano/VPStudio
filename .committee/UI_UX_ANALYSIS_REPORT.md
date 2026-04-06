# VPStudio UI/UX Analysis Report

Date: 2026-03-20  
Scope: current working tree, `.committee/BUGS.md`, `RELEASE_NOTES_v1.1_DRAFT.md`, recent QA artifacts, and key UI/view-model files.

## Evidence reviewed

### Tracker / release framing
- `/Users/openclaw/Projects/VPStudio/.committee/BUGS.md`
- `/Users/openclaw/Projects/VPStudio/RELEASE_NOTES_v1.1_DRAFT.md`

### Recent QA artifacts reviewed
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260319-followthrough-current/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260319-item6-vision-nav-bars/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260319-item6-vision-nav-bars-qa-pass/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260319-bug4-library-cards/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug3-explore-art-lookup-cache/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug3-first-keystroke-phase-gate/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug3-query-chrome-isolation/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug3-config-reload-lightweight/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug9-art-grid-qa/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug10-populated-proof/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug12-trakt-sync-refresh-rerun/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug17-top-right-menu-stability/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug18-clear-slot-stability/`
- `/Users/openclaw/Projects/VPStudio/qa-artifacts/20260320-bug18-attempt-boundary-qa/`

### Key code reviewed
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Discover/DiscoverView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Search/SearchView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/ViewModels/Search/SearchViewModel.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Search/ExploreGenreGrid.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Components/MediaCardView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Player/PlayerView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Services/Player/Policies/PlayerAspectRatioPolicy.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Library/LibraryView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Settings/Core/SettingsNavigationCatalog.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Settings/Root/SettingsRootView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Settings/Destinations/TraktSettingsView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/ContentView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/Views/Windows/Navigation/VPSidebarView.swift`
- `/Users/openclaw/Projects/VPStudio/VPStudio/App/AppState.swift`

---

## Executive verdict

VPStudio is **visibly better than it was even a few days ago**. A lot of the right polish work has landed:
- navigation sizing on Vision Pro is better,
- library cards are more honest and less broken,
- settings IA is cleaner,
- Trakt refresh trust is meaningfully better,
- search/explore art is no longer as placeholder-looking,
- and the player’s top-right menu is at least no longer obviously glitching in the captured QA.

But the app still does **not** feel fully polished end-to-end.

My blunt read: **Discover and global chrome are approaching a credible 1.1-level polish, while Search and Player still drag the product back toward “promising but rough.”**

If this shipped as `1.1`, I would describe it as a **substantial improvement release** rather than a truly “finished-feeling” refinement release. It reads more like a strong late beta / rough 1.1 candidate than a calm, luxurious, fully-baked Vision Pro media app.

---

## 1) Current overall UX quality and consistency

## What is working

### 1. Discover is the strongest, most coherent surface
`DiscoverView.swift` is the clearest example of the product’s intended premium direction:
- large hero carousel,
- clear cinematic rows,
- decent spacing,
- consistent glass styling,
- good content-first hierarchy.

This is the part of the app that most feels like a consumer media product rather than a tool panel.

### 2. Global visual language is now reasonably consistent
Across `ContentView.swift`, `VPSidebarView.swift`, `MediaCardView.swift`, Settings, and Search, the app is mostly committed to one language:
- dark/translucent glass,
- rounded cards,
- subdued accenting,
- poster-forward browsing,
- pill-style controls.

That consistency matters. The app no longer feels like a random stack of unrelated screens.

### 3. Navigation scale is materially improved on Vision Pro
Bug #6 looks real and worthwhile. The before/after evidence in:
- `qa-artifacts/20260319-item6-vision-nav-bars/`
- `qa-artifacts/20260319-item6-vision-nav-bars-qa-pass/`

plus the scaling logic in `ContentView.swift` and `VPSidebarView.swift` show a product that is more appropriate for gaze/tap interaction than before.

## What still hurts consistency

### 1. The app still alternates between “premium media app” and “admin console”
- Discover looks premium.
- Search is mid-transition.
- Library is functional but a little management-heavy.
- Settings still often feels like a setup/control panel more than a polished consumer settings experience.

So the app is consistent in **styling**, but not yet in **product tone**.

### 2. Control density is still too high in some places
The visual language is consistent, but several screens still ask the user to parse too many pills, chips, menus, or tiny icon-only controls at once.
That is especially noticeable on:
- Search header / query chrome,
- Library header,
- Player controls,
- advanced settings forms.

### 3. The release narrative is slightly behind the repo reality
`RELEASE_NOTES_v1.1_DRAFT.md` is already stale relative to `BUGS.md`.
It still describes some items as open/in-progress/pending QA that are now fixed in the tracker (notably #9, #10, #17). That is not a UI bug, but it does contribute to the feeling that the project is still in a fast-moving, unfinished state.

### Overall score
If I had to summarize the current UX quality in one sentence:

**Strong direction, noticeably better execution, but still too many rough edges in the two most interaction-heavy surfaces: Search and Player.**

---

## 2) What has visibly improved vs. what is still underwhelming

## Visibly improved

### A. Vision Pro navigation chrome
Evidence:
- `qa-artifacts/20260319-item6-vision-nav-bars/`
- `qa-artifacts/20260319-item6-vision-nav-bars-qa-pass/`
- `ContentView.swift`
- `VPSidebarView.swift`

This is a real upgrade. The nav bars look less toy-sized and less awkward in space. This is one of the clearest “yes, that’s better” changes.

### B. Search/Explore art direction
Evidence:
- `qa-artifacts/20260320-bug9-art-grid-qa/`
- `ExploreGenreGrid.swift`

The shift from fallback symbol tiles toward art-backed genre/mood cards is one of the biggest visible wins. The “before” looked placeholder-ish; the “after” looks more productized.

### C. Search behavior is less obviously wasteful than before
Evidence:
- `SearchView.swift`
- `SearchViewModel.swift`
- `qa-artifacts/20260320-bug3-query-chrome-isolation/`
- `qa-artifacts/20260320-bug10-populated-proof/`
- `qa-artifacts/20260320-bug18-clear-slot-stability/`

A lot of smart engineering has landed:
- draft query vs committed query,
- on-demand genre loading,
- less shell invalidation,
- hidden quick-filter row in pre-search idle state,
- reserved clear-button slot.

This is all good work. The current Search implementation is clearly more disciplined than a naive state soup.

### D. Library cards now feel more honest and more resilient
Evidence:
- `qa-artifacts/20260319-bug4-library-cards/`
- `LibraryView.swift`
- `MediaCardView.swift`

The no-spinner honesty state and background metadata hydration are meaningful UX improvements. Broken or forever-loading cards are poison in a media app; this is one of the most important “boring but valuable” fixes in the whole repo.

### E. Settings IA is cleaner
Evidence:
- `qa-artifacts/settings-item11-ia/screenshots/`
- `SettingsNavigationCatalog.swift`
- `SettingsRootView.swift`

The new categorization is more legible, especially moving Environments into Immersive. This is a good cleanup pass.

### F. Trakt sync feels more trustworthy than before
Evidence:
- `qa-artifacts/20260320-bug12-trakt-sync-refresh-rerun/`
- `AppState.swift`
- `TraktSettingsView.swift`

The fact that `Continue Watching` can appear live after sync without relaunch is a big trust improvement. This changes sync from “maybe it worked” to “I saw the UI actually update.”

### G. Player top-right menu stability is better
Evidence:
- `qa-artifacts/20260320-bug17-top-right-menu-stability/`
- `PlayerView.swift`

The obvious flicker/glitch problem appears materially improved in the QA capture set.

## Still underwhelming

### A. Search still feels like an engineering fight, not a finished UX
Search has many good micro-fixes, but the total experience still reads as “carefully patched” rather than “obviously effortless.”
Bug #3 and #18 both still being in progress is honest.

### B. Player controls still feel overloaded and not fully clarified
The glitch is less bad, but the deeper player UX issues are not solved just by making one menu stable.

### C. Settings still leans utilitarian
The IA is improved, but Settings still feels like credential/setup infrastructure more than a premium app settings experience.

### D. Library is reliable but not yet elegant
It works better than before, but the surface still feels somewhat operational rather than delightfully browseable.

---

## 3) Search / Explore UX problems

This remains the most important UX weakness in the app.

## What has improved

The code and QA clearly show several good moves:
- `SearchViewModel` now separates `queryDraft` from submitted search state.
- `SearchView` isolates `SearchQueryBar` from broader shell churn.
- quick filters are hidden before a search starts.
- genre loading is on-demand instead of eager.
- clear-button appearance no longer changes the row width.

Key evidence:
- `VPStudio/ViewModels/Search/SearchViewModel.swift`
- `VPStudio/Views/Windows/Search/SearchView.swift`
- `qa-artifacts/20260320-bug3-first-keystroke-phase-gate/`
- `qa-artifacts/20260320-bug3-query-chrome-isolation/`
- `qa-artifacts/20260320-bug10-populated-proof/`
- `qa-artifacts/20260320-bug18-clear-slot-stability/`

## The remaining UX problems

### 1. The first-focus / first-input hitch is still not convincingly closed
This is the biggest unresolved Search issue.

The code now avoids some layout churn, and the screenshots in `20260320-bug18-clear-slot-stability/` are encouraging, but the tracker itself is honest: there is still no explicit proof that the original raw first-focus latency is gone.

That matters because Search is where responsiveness is most emotionally visible. If the first tap or first character hesitates, the whole app feels cheap.

### 2. Search still feels too chrome-heavy relative to the content payoff
The query row carries a lot:
- magnifying glass,
- text field,
- clear affordance,
- AI button,
- filter button,
- type segmented control,
- then sometimes a quick-filter row.

Even after the isolation passes, the user still sees a lot of utility chrome before they see a magical search experience.

### 3. Explore cards are improved, but still not fully premium
`ExploreGenreGrid.swift` is better now because the cards can show actual art.
But the current card treatment still has a few issues:
- fixed 120pt height is a bit stubby,
- subtitles are tiny (`.system(size: 9, weight: .semibold)`),
- the cards still read more like utility shortcuts than rich browse destinations,
- fallback and art-backed states may still feel visually uneven.

So bug #9 improved the surface, but did not magically make Explore luxurious.

### 4. Search result hierarchy is still a little flat
The results grid in `SearchView.swift` works, but it is still mostly a flat poster wall with chips above it.
There is not much hierarchy between:
- typed search results,
- mood-driven results,
- genre-driven results,
- AI picks.

The result is functional, but not especially expressive.

### 5. The current Search UX is optimized for avoiding bad behavior, not for delight
This is the deeper issue.
A lot of recent work is defensive and performance-oriented, which was necessary. But the visible experience still feels like it is avoiding jank rather than confidently presenting a premium search/browse journey.

## Bottom line on Search

**Much better engineered, still not fully great to use.**

I would call Search:
- improved,
- materially less wasteful,
- visually less placeholder-like,
- but still the main reason the app does not yet feel “finished.”

---

## 4) Player UX problems

The player is improved, but still not calm enough.

## What has improved

### 1. The top-right menu looks more stable than before
Evidence:
- `qa-artifacts/20260320-bug17-top-right-menu-stability/`

This is important because a playback control that visibly flickers or fades during video destroys trust.

### 2. Freeflow / aspect controls now exist and are exposed
Evidence:
- `PlayerView.swift`
- `PlayerAspectRatioPolicy.swift`
- bug #8 in `BUGS.md`

This is a good functional addition.

## Remaining UX problems

### 1. The top-right ellipsis menu is doing too much
In `PlayerView.swift`, the single ellipsis menu contains:
- stream switching,
- aspect ratio controls,
- freeflow toggle,
- environment selection,
- fullscreen on macOS.

Even if the menu is stable now, this is still a lot of conceptual load in one tiny target.

For a Vision Pro media app, these are not all the same kind of action:
- stream quality is playback selection,
- aspect ratio is presentation geometry,
- environment is spatial mode.

Bundling them together makes the player feel more like a control tray than a refined cinema surface.

### 2. Resize / aspect behavior is still not fully trustworthy
Bug #5 remains open, and that matches the code.

`PlayerView.swift` still performs geometry updates in a way that can plausibly feel jumpy or hard to reason about:
- immediate scene geometry update,
- then a delayed “re-lock” pass,
- and different behavior between locked presets and freeform.

That may be technically correct, but it does not read as simple or confidently settled UX.

### 3. “Freeflow Resize” reads like internal language, not polished product language
The feature is useful, but the label still feels a little implementation-ish. It sounds like dev shorthand rather than the clearest end-user phrasing.

### 4. Too many player affordances are icon-only
The info pills row uses:
- playback rate text,
- captions icon,
- audio icon,
- environment icon.

That row is compact, but it is not especially self-explanatory for less technical users. On Vision Pro, icon-only controls can be elegant, but only if they are extremely obvious. These are only partly there.

### 5. Audio/subtitle defaults are still an open trust gap
Bug #7 is still open. That matters because even if the picker UI exists, the player still does not feel polished if it often chooses the wrong default audio or subtitle track.

That is exactly the kind of bug users remember as “the player is flaky.”

### 6. Fixed-ratio behavior may still be conceptually confusing
`PlayerAspectRatioPolicy.swift` uses `.resizeAspectFill` for auto and fixed presets, with freeform switching to `.resizeAspect`.
That makes sense technically, but from a user perspective it blends two things together:
- window geometry,
- content framing behavior.

If the user forces a ratio and the presentation changes in a way that feels cropped or inconsistent, it may not be obvious why.

## Bottom line on Player

**The player no longer looks obviously broken in the same way, but it still does not feel elegantly solved.**

The remaining work is less about “can it do aspect ratio and menus?” and more about:
- making those concepts clearer,
- reducing overload,
- and restoring trust that the player will behave predictably during playback.

---

## 5) Library / Settings / Sync UX issues

## Library

### What is better
Evidence:
- `qa-artifacts/20260319-bug4-library-cards/`
- `LibraryView.swift`
- `MediaCardView.swift`

Real improvements:
- alias-aware card resolution,
- background hydration for missing posters,
- honest placeholder when no poster exists,
- live reload on `.libraryDidChange`.

This is good work and directly improves perceived quality.

### What still feels rough

#### 1. The header is too busy
`LibraryView.swift` puts a lot at the top of the screen:
- sort menu,
- export,
- import,
- refresh,
- list picker,
- folder controls.

That is functional, but visually dense. It gives the surface a management-tool feeling.

#### 2. Library browsing is still more operational than aspirational
The cards are better, but the overall Library experience is still mostly “manage lists and folders” rather than “sink into your collection.”

#### 3. Empty states are competent, not memorable
The empty-state work is fine and much better than broken placeholders, but it still reads as product infrastructure rather than a polished, emotionally designed moment.

## Settings

### What is better
Evidence:
- `qa-artifacts/settings-item11-ia/screenshots/`
- `SettingsNavigationCatalog.swift`
- `SettingsRootView.swift`

The IA is cleaner now:
- Services,
- Playback,
- Immersive,
- Intelligence,
- Sync.

The Settings root also has a decent configuration-health summary and searchable navigation, which helps.

### What still feels rough

#### 1. Settings still feels like setup plumbing
The root view is organized, but it still has a “control center for provider credentials” vibe. That is not inherently bad, but it is less polished than the browsing surfaces.

#### 2. The configuration-health framing is useful but slightly admin-like
The progress/warnings summary is functional, but it reinforces the feeling that the user is administering a system rather than using a finished entertainment product.

#### 3. Some credential ergonomics are still inconsistent
Most notably, `TraktSettingsView.swift` still gives `PasteFieldButton` only to the Client Secret field, not the Client ID field.
That is tracked honestly as bug #13, and it is exactly the kind of small affordance inconsistency that makes settings feel unfinished.

## Sync

### What is better
Evidence:
- `qa-artifacts/20260320-bug12-trakt-sync-refresh-rerun/`
- `AppState.swift`
- `TraktSettingsView.swift`

This is one of the cleaner recent wins. The local refresh invalidation path is much better and the UI can visibly update without relaunch.

### What still feels rough

#### 1. Sync feedback is still relatively thin
The trust improvement is real, but the UI still mostly tells the user “sync completed” rather than:
- what changed,
- how many items updated,
- what source was applied,
- whether anything failed partially.

#### 2. Sync scope is still incomplete at the product level
Open bugs #14, #15, and #16 are not pure UI issues, but they affect the perceived completeness of Settings/Sync heavily:
- OpenRouter provider/model UX still open,
- IMDb sync absent,
- CSV robustness still not fully revalidated.

That means the settings/sync experience still feels like an actively evolving platform rather than a settled product.

---

## 6) Vision Pro-specific usability observations

## What feels appropriately Vision Pro-aware

### 1. Bigger navigation chrome was absolutely the right move
The improved bottom bar and sidebar sizing are a real Vision Pro usability win.
This is one of the most clearly successful platform-specific changes in the repo.

### 2. Reduced hover stacking was the right cleanup
The Search work that stops stacking multiple hover reactions is exactly the kind of thing that matters on Vision Pro. Too much hover motion makes the UI feel nervous.

### 3. Discover’s composition fits the platform best
The large hero + rails structure in `DiscoverView.swift` is the surface that best leverages a wide spatial window without feeling claustrophobic.

## What still does not feel fully Vision Pro-native

### 1. Too many small pills and icon-only controls remain
Vision Pro can handle compact chrome, but gaze/tap comfort depends on clarity and generous target size. Search header controls, Library actions, and Player control pills still lean a little too small/dense in spirit.

### 2. Several surfaces still behave like flat desktop forms in space
Settings and parts of Library especially still feel like a 2D settings panel floating in space, not a deeply spatial-first interface.

### 3. Search still does not feel physically effortless
This is the biggest Vision Pro-specific issue because input latency or perceived hitch is even more noticeable in spatial UI than on a desktop keyboard app.

### 4. Player geometry is especially important on Vision Pro, and it still feels unsettled
Aspect-lock vs freeflow is not a small detail on this platform; it is part of the core experience of placing and living with a media window in space. Because bug #5 is still open, the product still feels slightly unresolved in one of the most Vision Pro-specific behaviors it has.

---

## 7) Does this currently feel like a polished 1.1, or still too rough?

## Short answer

**It feels like a credible 1.1 in scope, but not yet like a fully polished 1.1 in feel.**

## Longer answer

If the question is:
- “Is this more like 1.1 than 2.0?” → **Yes. Definitely.**
- “Does it already feel smooth, cohesive, and premium enough to market as a polished 1.1?” → **Not quite.**

### Why it can still be called 1.1
Because the work really is meaningful:
- major bug fixing,
- navigation usability improvements,
- search stabilization work,
- library card correctness,
- settings cleanup,
- sync correctness,
- player menu stabilization.

That is exactly minor-release territory.

### Why it still feels rough
Because the parts users interact with most intensely still have visible unresolved friction:
- Search still has unresolved feel issues (#3, #18).
- Player still has unresolved resize/clarity issues (#5, #7).
- Settings/sync still have incomplete affordance/product-completeness gaps (#13–#16).

My honest product read:

**Today’s tree feels like “a much better 1.1 candidate” rather than “ship it, it’s polished.”**

If forced to label the current experience emotionally, I would call it:
- **strong progress,**
- **substantially improved,**
- **still a little too rough in Search and Player to feel serene.**

---

## 8) Highest-impact next 10 fixes, in priority order

## 1. Fully close the Search first-focus / first-keystroke hitch
Why first:
This is the fastest path to improving the product’s perceived quality. The first interaction with Search is a trust test.

Target:
- explicitly measure and remove the raw first-focus hitch,
- not just layout churn around it.

Related evidence:
- bug #18
- `SearchView.swift`
- `SearchViewModel.swift`
- `qa-artifacts/20260320-bug18-clear-slot-stability/`

## 2. Finish the broader Search smoothness pass
Why second:
Even after #18, bug #3 still remains the biggest overall UX drag.

Target:
- make Search feel calm and immediate under real use,
- not just in screenshot-driven regression passes.

Related evidence:
- bug #3
- multiple `20260320-bug3-*` folders

## 3. Redesign Search/Explore hierarchy so it feels premium, not just optimized
Why third:
The app needs a better emotional payoff after all the engineering work.

Target:
- richer idle Explore composition,
- stronger distinction between typed results, mood browse, and genre browse,
- less utility-chrome dominance,
- more premium browse hierarchy.

Related files:
- `SearchView.swift`
- `ExploreGenreGrid.swift`
- `MediaCardView.swift`

## 4. Finish player resize/aspect-ratio parity with the old behavior
Why fourth:
On Vision Pro, window geometry is core UX, not a side feature.

Target:
- predictable locked resizing,
- no awkward jumpiness,
- clear freeform vs locked behavior.

Related evidence:
- bug #5
- `PlayerView.swift`
- `PlayerAspectRatioPolicy.swift`
- `qa-artifacts/20260320-bug5-player-resize-inspection/`

## 5. Unpack the player’s overloaded top-right menu
Why fifth:
Stability is improved, but the information architecture is still weak.

Target:
- pull key actions into clearer, more discoverable controls,
- reduce the conceptual overload of the ellipsis menu,
- make presentation controls feel intentional.

Related file:
- `PlayerView.swift`

## 6. Fix audio/subtitle default selection and make those controls clearer
Why sixth:
Wrong default tracks make the player feel unreliable even when playback works.

Target:
- respect preferred languages,
- keep switching reliable,
- improve discoverability of subtitles/audio controls.

Related evidence:
- bug #7
- `PlayerView.swift`

## 7. Simplify the Library header and reduce action density
Why seventh:
Library currently works, but it feels more like list management than collection browsing.

Target:
- move lower-frequency actions into overflow,
- preserve the list/folder model,
- make the top of the screen feel less administrative.

Related file:
- `LibraryView.swift`

## 8. Improve sync trust messaging, not just sync correctness
Why eighth:
The Trakt refresh fix is good, but the UI still undersells what happened.

Target:
- richer sync result messaging,
- item counts / changed sections / partial-failure handling,
- clearer “what just happened” feedback.

Related files:
- `TraktSettingsView.swift`
- `AppState.swift`
- `qa-artifacts/20260320-bug12-trakt-sync-refresh-rerun/`

## 9. Clean up Settings affordance inconsistencies and provider UX
Why ninth:
Small setup inconsistencies still make the app feel unfinished.

Target:
- add Trakt Client ID paste button (#13),
- improve provider/model ergonomics,
- continue making Settings feel less like raw plumbing.

Related files:
- `TraktSettingsView.swift`
- `SettingsRootView.swift`
- `SettingsNavigationCatalog.swift`

## 10. Do one true release-candidate UX pass and update release framing
Why tenth:
The repo is moving fast, but the release story should catch up to reality.

Target:
- full current-tree screenshot/video pass,
- update `RELEASE_NOTES_v1.1_DRAFT.md` to match actual tracker state,
- make sure the final polish story is coherent.

Related files:
- `.committee/BUGS.md`
- `RELEASE_NOTES_v1.1_DRAFT.md`
- `qa-artifacts/20260319-followthrough-current/`

---

## Final judgment

VPStudio is **meaningfully better** and now has several surfaces that look like a real product, not just a prototype.

But the two surfaces that most determine perceived polish in this category are:
- **Search**
- **Player**

and both still have unresolved UX debt.

So my final answer is:

**This does not feel broken or amateur anymore. It does feel improved enough to justify a 1.1. But it still feels a little too rough to call it a truly polished 1.1 today.**

The good news is that the gap is not mysterious anymore. The next work is pretty clear:
- finish Search feel,
- finish Player geometry/clarity,
- reduce dense utility chrome,
- and do one final release-level UX sweep after those land.
