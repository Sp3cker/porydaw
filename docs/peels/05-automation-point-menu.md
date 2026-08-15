# Peel 05 — Automation point context menu (Set Value / Delete) + precise hit-testing

Read `docs/peels/GROUND-RULES.md` first. Target: main's `AutomationArea` in
`src/ui/songview.cpp`. Source: branch `automationarea.cpp:243-334` (menu),
`automationrows.cpp:309-368` (hit test), `src/ui/contextmenu.{h,cpp}` (menu class);
harness `src/rollcheckautomation.cpp:838-1011`.

## The feature

1. **Right-click on a point opens a menu instead of instantly deleting.** Today
   main's right-release-in-place on a point deletes it with no confirmation
   (`songview.cpp` `rightClickInPlace`). Port the branch's two-action menu:
   - **Set Value…** — type-in with per-row semantics: Tempo 1..999 labeled "BPM:",
     bend −8192..8191, CC 10/24 (pan/tune-like) presented as centered −64..63;
     commits an in-place value change. Reuse/merge with main's existing
     double-click `editValue` dialog so there is ONE value-prompt implementation.
   - **Delete** — deletes the point.
   Right-click on empty lane space keeps main's current behavior (time-selection
   menu inside a selection, clear-selection outside). Voice-row right-click
   marker delete on main MUST keep working (the branch regressed it — don't).
2. **Live retargeting.** While the menu is open, right-clicking another node
   re-aims the menu at that node (highlight moves, menu re-pops, first menu never
   "dismiss-then-reopen"); the targeted node stays highlighted while the menu is
   open (branch `setContextPointHighlight` + `highlightLocked`). Main's note
   context menu in the roll already does exactly this via `NoteContextMenu` —
   which brings in:
3. **Extract `ui::ContextMenu`.** Branch extracted main's `NoteMenuStyle` +
   `NoteContextMenu` (`songview.cpp:~436-520` on main) verbatim into
   `src/ui/contextmenu.{h,cpp}` and reused it for the point menu. Do the same
   extraction, with two corrections to the branch's version:
   - KEEP main's `rect().contains()` guard (only clicks OUTSIDE the popup run the
     retarget handler) — the branch silently dropped it; restore it.
   - DO port the branch's added `mouseReleaseEvent` override that swallows the
     release paired with a handled retarget press (a genuine fix main lacks).
   Rebase main's roll `NoteContextMenu` onto the extracted class (behavior
   identical — verify with the existing rollcheck note-menu probes).
4. **2-D nearest-wins hit test for points.** Replace/augment main's x-only 9px
   `nearestPoint` for right-click targeting with the branch's circular-radius 2-D
   test so same-tick duplicate points resolve by the cursor's y, not "last wins"
   (branch `automationrows.cpp:309-368`; harness :838-941). Keep main's grabPoint
   (±7 both axes) for left-drag as-is.

## Design note

This changes right-click-on-point from instant-delete to menu. That is a
deliberate UX upgrade (delete stays one click away inside the menu, and Peel 04's
Delete key covers fast deletion). Call it out prominently in the summary so the
user can veto during manual test.

## Tests

- New rollcheck section: right-click a point → menu appears (find by objectName),
  Delete removes exactly that point (same-tick duplicates: the one under y);
  Set Value commits the typed value (drive the dialog like samplecheck/rollcheck
  drive dialogs); retarget: open on point A, right-click point B → menu still
  open, Delete removes only B (adapt harness :944-1011); voice-marker right-click
  delete still works; roll note-menu probes still green after the extraction.
- Negative-test each probe; SF 1/1.5/2; full ASAN sweep + ctest; SPEC.md + CHANGELOG.

## Status (2026-08-12)

DONE on branch `peel/05-automation-point-menu` (feature `d553901` + review fixes
`031bf17`), off main `e8fad4f`. Swept (full ASAN run_checks + ctest + rollcheck
SF 1/1.5/2), unmerged — user review owed. Deviations from this brief, all
flagged in the session summary: menu label is "Set value…" (house sentence
case, not the branch's "Set Value"); Set value HEALS shadowed same-tick
duplicates (moveLanePoints' documented rule, branch-identical — the 2-D y-pick
decides which point seeds the dialog, Delete alone is duplicate-precise); the
aim ring shares the node dots' pxPerBeat >= 24 gate; retargets onto
selection-covered points decline (precedence consistency, found in review).
