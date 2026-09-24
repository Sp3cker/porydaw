---
name: proof-ledger-workflow
description: "Swift migration work is surface-first: build one user-visible Swift/QML surface, use its C++ proof ledger as the spec, and edit only that surface's rows in the same commit as the proving code and checks. No standalone ledger reconciliation."
scope: "tool:task, tool:edit(**/proof.*.txt), tool:write(**/proof.*.txt)"
---

Proof ledgers (`src/checks/**/proof.*.txt`) are acceptance specs for Swift
surfaces. They are not a work stream. Most open GAP rows describe features
that the Swift app does not have yet. Ledger edits cannot close those rows.
Only building the feature can close them.

## Unit of work: one user-visible surface

Pick a surface, not a ledger. Examples: Event List page, Songs dock,
timeline scrollbar, pitch bend popup, automation node drag. One task, one
branch, and one commit series close one surface.

1. **Read the spec.** Run
   `deno task proof sites --area <area> --status GAP` (also run it with
   `PARTIAL`). Sort each row into one of three buckets:
   - **Behavior**: an observable outcome that users or callers depend on.
     Port it as a Swift or QML check.
   - **Representation**: the row pins C++/Qt-widget internals, such as
     widget pointers, `QApplication::focusWidget`, or model indices of a
     retired class. Mark it `RETIRED-REPRESENTATION` with a one-line reason.
   - **Blocked**: the row depends on unfinished work, such as the
     ProjectSource boundary. Name the blocker in the task. Leave the row
     unchanged.
2. **Build the surface.** Write the Swift presenter/model, then the QML, then
   mount it in `ShellWindow.qml` or `EditorSurface.qml`. Reuse existing
   presenters (`EventListPresenter`, `SongListPresenter`,
   `VoiceListController`, and others). Adapt the original QML instead of
   duplicating it.
3. **Prove it.** Write the behavior checks in the same branch. Run the
   covering lane (`deno task verify --filter <lane>`, `verify:shell`,
   `verify:qml`, or `verify:qml-roll`), then run
   `deno task proof check --executed`.
4. **Update rows only in the same commit** as the code and checks that
   prove them. Use `deno task proof:edit` for each row. A row becomes
   `MATCHED` only when executed evidence supports it. A mapping that is
   only structurally equivalent stays `PARTIAL`.

## Allowed ledger-only changes

- A code change broke an anchor. Repair the anchor in the commit that broke
  it.
- Every row of a ledger is `MATCHED` or `RETIRED-*`. Delete that ledger and
  its C++ source together.

## Forbidden

- Waves of reconciliation, re-pinning, re-anchoring, or rewording across
  areas or across surfaces.
- Edits to rows outside the surface named by the current task.
- "Gap-closing" tasks with no surface. These are tasks whose deliverable is
  disposition counts.
- Porting representation rows as new checks. Re-pinning obsolete
  implementation assertions (charter V-1).
- Changing a disposition to `MATCHED` from a related passing test without
  executed evidence for that predicate.

## Dispatch

Every migration task brief names these four items:

- the surface
- the ledger areas that serve as its spec
- the verify lanes
- the blocked rows it leaves untouched

A brief that names only ledgers or disposition targets is invalid. Rewrite
it around the surface before you dispatch it.
