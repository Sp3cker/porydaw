# T21 — Remove the remaining per-song embedding focus signal

## Context

Final gate B cleanup of the per-song embedding seam: `embeddingFocusRequested`
was the bridge a per-song host used to ask the outer shell for focus; with one
WorkspaceQuickHost, explicit outer entry (task15's `focusEditor`/`focusTabs`,
task16's `focusSongEditor`, task18's registry actions) replaces it entirely.
Consumed by task20's focus checks and task22's deletion of the task9 adapter in
this same atomic cutover. Consumes tasks 15, 17, 18 interfaces.

## Exact write set

- `src/ui/songview/quick/timelinequickview.h`
- `src/ui/songview/quick/timelinequickview.cpp`

## Prerequisites

Interfaces from tasks 15 (host entry), 17 (window-free session), and 18
(Registry commands).

## Interface contract

Per spec S3/S4:

- Delete the `embeddingFocusRequested` signal declaration, all its emissions,
  and its comments — final removal, no replacement signal.
- Preserve the semantic focus APIs `focusBand`/`focusEventListInput` with their
  existing names and parameters, but revise their contract: when
  `isInputEligible()` is false or the target input is absent, return false
  WITHOUT calling requestActivate/forceActiveFocus; a true return means an
  actual eligible focus request was made. This suppresses inactive/unready
  programmatic calls (e.g. background reload calling setEventListVisible)
  without any queued repair.
- No alias, no replacement per-page host signal, no timer, no QObject window
  owner.

## Implementation steps

1. Remove the signal declaration from timelinequickview.h and replace its stale
   scrollbar comment referring to SongTab::InputGate with the S4 eligibility
   seam.
2. In timelinequickview.cpp: remove every emission site and the comments
   describing the bridge; do not preserve the old "false only when missing"
   comment — the new false-on-ineligible contract replaces it.
3. Gate `focusBand`/`focusEventListInput` on `isInputEligible()` plus input
   presence as specified above, preserving names, parameters, and the
   true-means-requested return contract.
4. Confirm no remaining references to the signal inside the write set;
   references outside it require controller amendment of the affected brief,
   never silent expansion.

## Acceptance predicate

Explicit focus actions and native page focus still work after the bridge is
removed. NAMED CHECKS:
`deno task verify --filter mainwindow-routing --filter selectionkey`
(controller-run at gate B).

## Task-specific constraints

- Deletion only within the two listed files; the task9 SongTabQuickHost adapter
  is deleted by task22 in this same gate — do not add a transitional fallback.
- No new focus dispatcher, focus history, or activation policy anywhere.

## Controller verification

[Gate B](plan.md#verification-and-checkpoint-semantics).
