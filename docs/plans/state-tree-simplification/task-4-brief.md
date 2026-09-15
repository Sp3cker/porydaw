# Task 4 — One automation command-target epoch

## 1. Context

Task 1 makes document identity constant; task 2 centralizes row identities.
Replace repeated automation popup identity/revision/row revalidation with the
epoch defined in [spec.md](spec.md). Cancellation is not sufficient: a handler
can already have consumed its pending target when a Qt signal or focus return
synchronously changes the selected track. Preserve command targets and QObject
lifetime checks, and validate after reentrancy rather than before it.

## 2. Exact write set

- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_pointmenu.cpp`
- `src/ui/editordrawer/automationcanvas_menu.cpp`
- `src/ui/editordrawer/automationcanvas_deleteprompt.cpp`
- `src/ui/editordrawer/automationcanvas_taptempo.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea.h`
- `src/ui/editordrawer/voicechangearea/voicechangemenu.cpp`
- `src/checks/automation/tst_automationediting.h`
- `src/checks/automation/automationpointmenus.cpp`

## 3. Prerequisites

Task 1: permanent document identity and reference access.
Task 2: model publication keeps the node stack's row identities unchanged on
selection-only refresh; row remapping remains in `rebuildRows()`.
Task 3 precedes this task by shared-file schedule, not a consumed validity API.

## 4. Interface contract

```cpp
struct AutomationTargetEpoch {
    uint64_t documentRevision = 0;
    uint64_t rowGeneration = 0;
    friend bool operator==(const AutomationTargetEpoch &, const AutomationTargetEpoch &) = default;
};
AutomationTargetEpoch AutomationCanvas::targetEpoch() const noexcept;
```

The result is `{ m_page.document().revision(), m_rowGeneration }`.
Increment `m_rowGeneration` at the start of `rebuildRows()`, before any
cancellation or outward notification. Layout-only adapter reconstruction over
unchanged row identities does not increment it; no adapter pointer survives a
reentrant call. Document mutation already advances revision synchronously.

`PendingMenu`, `PendingNodeMenu`, `PendingCcDeletePrompt`, `PendingValuePrompt`
and the tap-tempo anchor replace their revision/document identity fields with
an epoch. Keep lane handle, row identity, point/anchor, track and prompt copy.
`PendingValuePrompt` currently has a revision but no document QPointer: do not
invent a uniform old structure. Voice menus keep revision/track validation and
lose only their document identity field/comparisons.

Validation order is semantic, not a literal last-line constraint:
consume pending → establish lifetime guard → existing reentrant operations →
check lifetime → validate epoch → resolve current adapter/value → mutate.
Check lifetime after each reentrant operation before touching members again.
Read-only preparation after validation is allowed; another outward call before
mutation requires revalidation. Initial hit/miss and slot existence checks stay.
Equal epoch replaces only post-capture row identity and point-presence proofs.
Keep expected-document-revision commit-helper contracts unchanged.

Preserve actual per-handler timing:
- Node/lane menu actions return focus before final validation as today.
- CC delete acceptance emits `ccDeletePromptChanged` and closes its owned form
  before validation; focus return remains after mutation.
- Value acceptance emits `valuePromptChanged` after consuming pending state,
  validates afterward and normally returns focus after mutation. Install its
  lifetime guard before the signal; do not move focus to the front.
- Tap tempo has no focus return. Preserve its idle timer, draft/reset and
  committed signal order. Validate the captured epoch before the write.
- Open paths can reenter through grab release, popup open/cancel or presentation
  signals. Protect lifetime across those operations and reject an epoch changed
  during opening before leaving a usable pending command.

After mutation, document notifications can destroy the canvas or rebuild adapters.
Do not use old slot/lane pointers afterward; guard remaining member accesses.

## 5. Implementation steps

1. Add the epoch/accessor/generation; migrate the four pending structures and
   tap anchor. Preserve targets and reset an abandoned tap epoch with its draft.
2. Migrate open and dispatch paths to the above order. Replace repeated
   document identity/revision/row checks with epoch equality after reentrancy;
   resolve adapters only afterward. Keep initial target validation, point
   insertion duplicate checks and document commit revision checks. Record the
   invariant once at the epoch definition, removing comments for deleted chains.
3. Remove voice pending document identity storage/checks; retain revision,
   track, owner-lifetime and input-host conditions and all focus timing.
4. Add the consumed-value-prompt regression below to the existing point-menu
   suite. It exercises a real signal during acceptance, not a direct epoch-unit
   assertion or a cancelled-menu no-op.

## 6. Acceptance predicate

A pending command cannot edit a different lane or stale point after document
mutation, row remap or reentrant invalidation. Normal menu/prompt/tap actions,
undo behavior and focus return are unchanged. No drawer pending command stores
`QPointer<SongDocument>`; non-pending document-revision caches and gesture commit
checks are not removed by a blanket grep rule.

New regression: open Set Value for a CC point on track A. Connect a one-shot
`valuePromptChanged` handler that, when the prompt becomes absent during
acceptance, switches to track B without editing the document. Accept a value
that would change the point. Verify the handler actually switched tracks, both
tracks' serialized points remain unchanged, and the document revision/undo
position remain unchanged. At signal delivery pending state has already been
consumed by `acceptNodeValuePrompt`; ordinary cancellation cannot make this
scenario pass on its own. Add the slot declaration in the existing header and
the scenario in `automationpointmenus.cpp` using its shown Quick fixture.

Existing `pointMenuStaleDocumentCannotDeleteTarget` and CC delete confirmation
scenarios exercise invalidation before dispatch, not this consumed-command
edge; keep both forms of coverage. A throwaway focus-return variant may observe
a track switch during a menu handler, but it must prove that the callback fired
inside dispatch, not during the earlier menu close.

Named checks (native desktop for shown Quick interaction cases):

```sh
deno task verify --filter automation-editing --verbose      # menus, prompts, tap tempo and new consumed-prompt scenario
deno task verify --filter editor-drawer --verbose           # voice menu/picker and drawer lifecycle
deno task verify --filter automation-hover --verbose        # gesture/hover cancellation remains intact
deno task verify --filter automation-presentation --verbose # generation rebuild still publishes presentation
```

## 7. Task-specific constraints

- Reuse existing dispatch/popup ownership paths; no event bus or pending.valid()
  abstraction. Keep the comparison visible at the mutation seam.
- `rebuildRows` is the generation owner; layout-only rebuilding is not a row
  remap. A newly discovered identity-changing path is an explicit contract
  correction, not permission to silently omit its invalidation.
- No blanket demand that each handler already contains a self guard or returns
  focus first: the value and delete prompt bodies do not have that shape today.

### Controller verification

```sh
deno task verify
deno task build:app
```

Native smoke (desktop, `skill://capture-macos-app-window`): launch the built app,
open a route and show the automation drawer. Select a time range over a lane
with written events, then an empty lane; verify the populated-selection label
and event count. Exercise a normal node value edit and undo. Open a node menu,
change document state elsewhere and confirm the menu is retired without a late
mutation; do not require clicking a menu that cancellation correctly destroyed.
Switch tabs and back and observe the drawer remains coherent. Capture screenshots
for the stable visual states; screenshots alone do not prove absence of a
transient blank frame. Use the consumed-prompt regression for stale-dispatch proof.
