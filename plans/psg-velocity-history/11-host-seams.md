# 11 — Neutral host seams

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/host-seams`  
**Worktree:** `11-host-seams`  
**Base:** `NOTE_ID_SHA`, after 10A's approved ordinary merge.

`git-operations-runner` creates/verifies the `11-host-seams` worktree and `task/psg-velocity/host-seams` branch from the exact `NOTE_ID_SHA` milestone and initializes/verifies submodules before the `task` agent begins.

Packet 11 runs in parallel with 10B from `NOTE_ID_SHA`; 10C starts later from
`DOCUMENT_SHA`. The task agent writes implementation, focused seam coverage,
and one commit, but does **not** build, test, format, lint, or validate. The
coordinator owns that evidence and the reviewer/merge handoff.

## Exclusive paths

This task creates and owns only these five neutral value/seam files:

1. `src/ui/editorviewstate.h`
2. `src/ui/editorviewstate.cpp`
3. `src/ui/editorpage.h`
4. `src/ui/editorpagehost.h` (contains `EditorPageContext`)
5. `src/editorviewstatecheck.cpp`

No other path is owned by packet 11. In particular it must not edit or claim concrete
ownership of `SongView`, `TimelineSurface`, `PlayheadOverlay`, `AutomationPage`,
`MainWindow`, `CMakeLists.txt`, or `src/main.cpp`. `TimelineSurface` already exists
upstream and is only consumed by the later host integration; this packet neither
creates nor changes it.

## Contract

Define a neutral page-host contract with these boundaries:

- `EditorViewState` is typed, persistent **cosmetic** state only. It carries no
  live selection, timeline, voice, or document state.
- `editorpagehost.h` declares `EditorPageContext` beside `EditorPageHost`, so
  the host/context seam has one header and no orphan context file.
  `EditorPageContext` carries runtime selection, timeline, voice, document,
  and callback state to pages; it is the explicit non-persistent context
  boundary.
- `EditorPageContext::drawerContextTick(double)` is the sole static `uint64_t`
  helper through the `editorpagehost.h` seam for drawer/context callers. It
  returns the `uint64_t` tick `floor(max(0, t) + 0.5)`; no page, drawer, or
  later packet may duplicate the rounding rule.
- `EditorPage` is a neutral page interface. `EditorPageHost` owns attachment,
  detachment, and lifetime coordination without choosing product page behavior.
- Replacing a song/document or selected track must not leave a page context
  with a stale document pointer, grab, hover, or preview.

The seam must preserve the existing single source of truth for selection,
selected track, scrolling, time zoom, cursor, playhead, grid/snap, voice
context, focus, and automation. It must not transfer those runtime values into
`EditorViewState` merely to make them persistent.

## Non-goals

- Do not implement a drawer, tabs, persistence codec, page routing, MIDI mutation,
  Undo, remap policy, automation gestures, or velocity behavior.
- Do not alter painting, event-update regions, playhead rendering, focus behavior, or
  any existing product UI. Packet 30C later owns rendering/playhead work; 30A later
  owns the SongView adapter/lifecycle; 30B later owns MainWindow routing/persistence.
- Do not introduce a host-specific selection model or a second document/voice
  authority.

## Focused evidence and handoff

`editorviewstatecheck.cpp` is a self-contained, runnable focused harness for
persistent-cosmetic versus runtime-context separation, attachment/detachment,
and safe context replacement. It also covers `drawerContextTick` at negative,
integral, half, and fractional inputs, including clamping below zero and
rounding halves upward. After the commit, the coordinator runs the packet-05
registered self-contained `porydaw --check-host-seams` command once
against this head. It runs independently alongside 10B's existing
`porydaw --editcheck <scratch-project>` command; 10C has its separate,
post-`DOCUMENT_SHA` projection command. It does not run a repository-wide
geometry scan.

A `reviewer` agent inspects the committed range against `NOTE_ID_SHA`,
specifically checking the five-file boundary, that `EditorPageContext` and the
sole static `uint64_t EditorPageContext::drawerContextTick(double)` rounding
helper are contained in `editorpagehost.h`, its focused check coverage, and
that no concrete UI class was claimed. The approved head merges normally into
`feature/psg-velocity-history-upstream`; no cherry-pick, staged-tree
transport, or early `FOUNDATION_SHA` is permitted. `CONTRACT_SHA` is recorded
only after the later 10C merge is also approved and integrated.
