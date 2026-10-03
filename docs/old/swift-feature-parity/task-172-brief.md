# Task 172 brief — repeated hover/leave transitions leave the document byte-identical

# Context

The scrolled-phantom journey proves no-mutation during the held drag and after lane
cancellation, but not at the repeated hover/leave transitions the fork pinned: after a
second pointer leave the complete document state — snapshot, serialized bytes and
history — must be exactly the pre-hover values. The existing
`drawerAutomationRasterScrolledPhantom` function already captures all three before
the gesture; the missing predicates are two transitions on the same journey.

Surface: automation plot hover/leave on the drawer's scrolled phantom (model-level
no-mutation guarantee).
Ledger spec: `src/checks/automation/raster/proof.interaction.txt` A013 and A021
(PARTIAL), fork `src/checks/automation/raster/interaction.cpp:364` (complete snapshot
equality after repeated hover/leave) and `:388` (same after the double pointer leave)
at the pinned revision `c17d966f`.
Verify lane: `deno task verify --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: the pixel-probe rows A012/A025/A032/A033/A037/A044 (no
Swift framebuffer readback) and 167's in-flight `automationcanvasediting.swift`.

# Exact write set

- `src/checks/automation/presentation/painting_raster.swift` — `drawerAutomationRasterScrolledPhantom` only: the two transition predicates using the already-captured baseline.
- `src/checks/automation/raster/proof.interaction.txt` — A013 and A021 only.

# Prerequisites

Task 162's landed predicates in this file are consumed unchanged. Disjoint from 167
(`automationcanvasediting.swift`, `tst_ShellGridInputKeyboard.qml`) and 168. Read
sprint-3 §20.

# Interface contract

After the journey's existing repeated-leave and after the double-leave clear, assert
snapshot equality, serialized-bytes equality and unchanged history index against the
pre-hover captures (already taken by the function). No new fixtures, no production
change expected; repair only if a transition actually mutates state (that would be a
real defect).

# Implementation steps

1. Add the two transition predicates beside the existing no-mutation assertions.
2. Close A013 and A021 in the same commit. Compact form for closed rows: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Repeated hover/leave transitions on the scrolled phantom leave snapshot, bytes and
history untouched, with executed evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No pixel/framebuffer obligations, no `automationcanvasediting.swift` edits, no new
files. The pixel GAP rows keep their no-readback reasons.
