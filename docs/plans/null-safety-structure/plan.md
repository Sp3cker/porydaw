# Null-safety structure

Reshape project-owned nullable paths so the type or nearest guard carries the safety proof. Preserve behavior; do not suppress compiler diagnostics or add generic non-null wrappers.

## Global constraints

- Use language and Qt types directly: references for lifetime-required objects, `QPointer<T>` for QObject borrows that may disappear, and raw pointers only for immediately checked fallible lookups.
- Validate once and carry the resolved value. Do not pair a Boolean classification with a second lookup.
- Expected absence returns normally. Broken internal invariants fail explicitly; do not silently produce partial state.
- Preserve ownership, threading, QObject lifetime, public interfaces, and observable behavior unless a task explicitly names a signature change.
- Use the recorded `deno task` commands. Reassess only if scope changes or a command proves stale.
- No commit or push is authorized by this plan.

## Tasks

### 1. Resolve and carry XCMD descriptors — Direct

**Target:** `src/core/xcmd.cpp`, `src/core/songdocument_xcmd.cpp`.

**Change:**
- Make a resolved descriptor the single known-epoch proof inside private `SelectorBlock`; parsing resolves it once, and projection/traffic assessment consume it without repeating selector lookup.
- Make normalized point writes retain both the caller write and its resolved descriptor; rewrite matching and emission consume that pair without repeating lane lookup.
- In `SongDocument::moveLanePoints`, use one `descriptorForLane()` result for both XCMD classification and value bounds; remove the correlated Boolean-plus-second-lookup pattern.
- Preserve opaque/stray classification, duplicate-write ordering, clamping, byte-exact preservation, and all public `xcmd` interfaces. Add no fallback or warning suppression.

**Acceptance:**
```sh
deno task format --check src/core/xcmd.cpp src/core/songdocument_xcmd.cpp
deno task verify --filter xcmdcheck --filter automation-domain --verbose
```
`xcmdcheck` covers projection, known/opaque/stray epochs, canonical rewrites, raw reconciliation, and export canonicalization. `automation-domain` covers `SongDocument` XCMD lane editing, including move/clamp behavior.

### 2. Express required owner links as references — Direct

**Target:** `src/ui/songview.cpp`, `src/ui/songview/pianoroll.h`, `src/ui/songview/pianoroll.cpp`, `src/ui/songview/pianoroll_commands.cpp`, `src/ui/songview/pianoroll_geometry.cpp`, `src/ui/songview/pianoroll_gestures.cpp`, `src/ui/songview/pianoroll_gestures_active.cpp`, `src/ui/songview/pianoroll_interaction.cpp`, `src/ui/songview/quick/timelinequickview_pianoroll.cpp`.

**Change:** Change the required `SongView` constructor argument and stored owner link from pointer to reference. Preserve ownership and all piano-roll behavior; do not convert detachable QObject borrows in `TimelineQuickView`.

**Acceptance:**
```sh
deno task format --check src/ui/songview.cpp src/ui/songview/pianoroll.h src/ui/songview/pianoroll.cpp src/ui/songview/pianoroll_commands.cpp src/ui/songview/pianoroll_geometry.cpp src/ui/songview/pianoroll_gestures.cpp src/ui/songview/pianoroll_gestures_active.cpp src/ui/songview/pianoroll_interaction.cpp src/ui/songview/quick/timelinequickview_pianoroll.cpp
deno task verify --filter rollcheck --filter rollcheck-static --verbose
```

### 3. Snapshot nullable Qt borrows once — Direct

**Target:** `src/mainwindow.cpp`, `src/ui/songview/quick/timelinequickview.cpp`, `src/ui/songview/quick/timelinequickview_window.cpp`.

**Change:** At guarded `QPointer` use sites, take one local pointer snapshot, check it once, and use that snapshot for the non-reentrant operation. Retain `QPointer` storage and recheck after any call that can synchronously re-enter and destroy the object. Do not duplicate Qt context-object lifetime guards.

**Acceptance:**
```sh
deno task format --check src/mainwindow.cpp src/ui/songview/quick/timelinequickview.cpp src/ui/songview/quick/timelinequickview_window.cpp
deno task verify --filter selectionkey --filter timelinepancheck --filter mainwindowrouting --verbose
```

### 4. Guard internal lookup results at consumption — Direct

**Target:** `src/ui/editordrawer/nodelane/batchcommit.cpp`, `src/ui/songview/quick/timelinequickscene.cpp`.

**Change:** Resolve `tempoAtTick()` beside its use and reject missing source data there. Replace unchecked `rowFor()` dereferences with one private required-row helper that returns the row or fails explicitly when the model index invariant is broken; a release build must not silently continue with inconsistent rows.

**Acceptance:**
```sh
deno task format --check src/ui/editordrawer/nodelane/batchcommit.cpp src/ui/songview/quick/timelinequickscene.cpp
deno task verify --filter automation-domain --filter timelinepancheck --verbose
```

## Checkpoint

Tasks are independently reviewable. If persistence is later authorized, checkpoint accepted work after the requested task boundary; do not include unrelated working-tree files.
