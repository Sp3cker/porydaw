# Task 167 brief — physical B-key mode switch retains a held stroke at its snapped cell

# Context

The mounted ownership journey proves that switching tool mode mid-stroke retains and
commits the pencil/node-drag gesture, but only via a direct mode change with a loosely
bounded endpoint: the landed predicates accept the committed value "at ticks 166–168"
where the fork required the exact `endCell.tickBegin`, and none delivers the physical
B key while the stroke is held — the fork's actual user path. Fifteen PARTIAL rows in
`src/checks/automation/proof.automationownership.txt` (A045, A047–A049, A051, A052,
A055, A057–A062, A103, A104) carry exactly these residues.

Surface: pressing B (pencil mode) on the mounted drawer while a pencil stroke or node
drag is held — the stroke survives and commits at the snapped cell.
Ledger spec: the rows above; fork `AutomationEditingTest::
pencilModeChangeRetainsPencilGesture` at pinned revision `c17d966f`
(`src/checks/automation/automationownership.cpp:186-202` and the sibling functions
cited by the selected rows): the B-key mode switch retains the captured stroke, the
committed endpoint sits at the original `endCell.tickBegin`, the pointer mapping is
probed before release, and history/bytes invariants hold.
Verify lanes: `deno task verify:qml --filter editorqml-drawer --verbose` plus the
service family lane `deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: automation hover's native pointer-token identity tails;
raster pixel rows.

# Exact write set

- `src/checks/automation/automationcanvasediting.swift` — exact-cell endpoint requirements and pre-release pointer-mapping probes.
- `src/checks/editorqml/tst_EditorDrawer.qml` — physical B-key delivery during held strokes/drags.
- `src/checks/automation/proof.automationownership.txt` — the 15 selected rows only.

# Prerequisites

None. Disjoint from every sibling (162 landed in `painting_raster.swift`, untouched
here). Read sprint-3 §19.

# Interface contract

Consume the drawer's existing key handling: deliver the real B key to the mounted
surface while the gesture is held (the same input path a user's keypress takes).
The committed endpoint must equal the independently computed snapped cell's
`tickBegin` literal — if the production surface accepts a non-snapped endpoint, that
is a divergence to repair on the interaction/presenter seam (conditional repair:
`src/swift/app/drawer/automation/` interaction file), not a loosened predicate.
Pre-release pointer-mapping probes observe the model's projected node before commit.

# Implementation steps

1. Add the mounted B-key-during-held-stroke journeys (pencil stroke and node drag).
2. Tighten the service predicates to the exact snapped-cell endpoints and add the
   pre-release pointer-mapping probes.
3. Repair the production snapping seam only if a journey exposes a real divergence.
4. Close the 15 rows in the same commit. Compact form for closed rows: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Pressing B mid-gesture retains and commits the stroke at the exact snapped cell
through real key input, with the fork's history/bytes invariants.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --filter editorqml-drawer --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

No synthesized shortcut forwarding — the B key goes through the surface's real key
path. No raster/pixel obligations. Sibling files (`tst_ShellWindow.qml`,
`tst_ShellEventList.qml`, `remap.swift`) stay untouched.
