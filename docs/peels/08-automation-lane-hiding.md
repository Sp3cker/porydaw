# Peel 08 — Hide/unhide automation lanes + lane-menu improvements

Read `docs/peels/GROUND-RULES.md` first. Target: main's `AutomationArea` lane
menus + `ViewSidecar` persistence. Source: branch `automationarea.cpp:993-1125`,
view-state in `src/ui/editorviewstate.h` (do NOT port that type — see below).

## The feature

1. **Hide lane.** The lane gutter menu gains "Hide lane": the row disappears from
   the lanes area but its data stays untouched (branch `automationarea.cpp:1043`,
   `:1120-1125`; announces the hide).
2. **Unhide via the add-lane menu.** The "+ Add lane" menu grows a "Hidden lanes"
   section listing `Show: <name> (hidden)` entries that restore the row (branch
   `:1001-1013`, `:1018-1024`). Add-lane candidates exclude hidden rows.
3. **Persistence.** Hidden-lane set persists in the `.porydaw` sidecar next to
   `laneHeights`/`laneRanges`. Main's view state uses string keys
   (`QHash<QString,int>`, `laneKey(track,cc)` = "cc:T:C") — express hidden lanes
   the same way (a string list/set), NOT the branch's typed `EditorAutomationRowId`
   `EditorViewState` (drawer architecture; porting it would churn the sidecar
   codec for no user value). Extend `SongView::ViewState` + `ViewSidecar`
   read/write + the sessioncheck/viewsidecar round-trip coverage. Sidecar rule:
   old files without the key load fine (default: nothing hidden); new files opened
   by old builds must not break (additive JSON key — verify the codec tolerates it).
4. **Small menu improvements** (each trivial, take them along):
   - Add-lane strip opens on right-click as well as left (branch `:453-456`).
   - Gutter lane menu also works for empty/cosmetic CC lanes (main requires a live
     `AutoLane`, so an added-but-empty lane has no menu — branch `:463-467`).
     Keep main's left-or-right button access, don't copy the branch's right-only.

## Interaction rules to get right

- Hiding the last visible lane must leave a sane area (tempo row is always
  present; decide whether Tempo/Voice rows are hideable — the branch allows
  hiding CC lanes; recommend: CC lanes only, matching the branch).
- A hidden lane whose track is deleted/moved: the string keys are (track, cc)
  scoped — reuse whatever main's `laneHeights` does on track moves (they keep
  stale keys harmlessly); mirror that and say so.
- The time selection over a hidden lane's identity: hidden lanes drop out of
  `rebuildRows`, so the band can no longer include them — acceptable; note it.

## Explicitly exclude

- Branch's area-local automation clipboard (`m_clipboard`) — regression vs main's
  shared `SongView::Clip`; skip entirely.
- Typed `EditorViewState`, `publishViewState` round-trip — drawer architecture.

## Tests

- rollcheck: hide a CC lane → row gone, data intact (doc lanePoints unchanged),
  undo stack untouched (view-only op); add-lane menu lists it under Hidden and
  restores it; hidden lane skipped by add-lane candidates; right-click opens the
  add-lane strip menu; empty-lane gutter menu opens.
- sessioncheck/sidecar: hidden set round-trips through save/reopen; legacy sidecar
  without the key loads clean.
- Negative-test each probe; ASAN sweep + ctest; SPEC.md + CHANGELOG.
