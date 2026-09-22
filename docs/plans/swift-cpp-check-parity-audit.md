# Swift/C++ check parity audit

Updated: 2026-09-21

This is the post-inventory audit integrated on `feature/swift-qml-grid` in
`682095474e862b90227de941d9a0a5b29ad5926c`. The local `.scratch/` directory is
review material and is not part of the commit.

## Runtime baseline

The committed production and registered-check tree builds and passes:

```text
deno task verify --verbose
build: ok (10.82s)
verify: 24/24 ok (16.91s)

deno task lsp:swift
index: 6/6 targets ok
```

The complete registered-suite pass is the behavioral baseline for subsequent
gap closure. It does not convert a `GAP`, `PARTIAL`, or native obligation into a
match by itself.

## Inventory snapshot

- 240 proof files cover 238 distinct original C++ sources.
- 185 originals still exist in the current tree; 53 are deleted and recovered
  from their pinned revisions.
- 15,651 canonical `A###` entries are present.
- 835 entries are `MATCHED` or `MATCHED-QML`.
- 9,482 entries are `GAP`.
- 2,038 entries are `PARTIAL`.
- 3,281 entries are `NATIVE` or `NATIVE-SETUP`.
- 15 entries use an explicit retired-representation/backend/role disposition.

The canonical inventory therefore records 11,520 unresolved Swift-parity sites
and 3,281 retained native obligations. Two older proof files are not included in
those counts because they still use `Original <line>` records instead of `A###`:

- `src/checks/automation/proof.automationmenus.txt`
- `src/checks/selectionkey/proof.localinputtier_text.txt`

Five other zero-`A###` proofs explicitly document that their original source
contains zero assertion sites.

## Final-ledger blockers

The header/path normalization pass repaired incomplete headers, the malformed
`eventviews/remap.cpp` reference, and ambiguous multi-counterpart header pairs.
All canonical Swift counterpart hashes now match the working tree.

The ledger is not yet a deletion gate for these reasons:

1. The two legacy proofs listed above need canonical `A###` inventories.
2. 256 `MATCHED` entries in 13 proofs name related Swift behavior without citing
   an `S###` predicate. They must be connected to exact Swift predicates before
   they can authorize C++ retirement. The SongDocument hardening pass cleared
   every such entry from `editcheck`; the track-header pass cleared its matching
   entries as well. The largest remaining clusters are automation domain, audio
   resonance/telemetry, and playback.
3. Of 220 current `src/checks/**/*.cpp` files, 185 have proofs. Most of the other
   35 are assertion-free harness/support sources. Two contain explicit failure
   sites and need either an inventory or a written exclusion rationale:
   `drawerpresentation/fixtures.cpp` (`qFatal`) and
   `selectionkey/corefixture.cpp` (`Q_ASSERT`).
4. Many proof evidence sections still say an integrated run is pending. Refresh
   them from the final committed layout and the 24/24 gate rather than treating
   this working-tree run as permanent evidence.

No C++ check should be deleted while any of these conditions applies to its
proof. `NATIVE` also means the native check remains unless an external
production-app journey proves the same observation.

## Gap queue

Work in vertical product slices and leave drawer-owned files alone while the
EditorDrawer proof-hardening pass is active. The structural refactor has not
started yet.

1. **Audio and playback.** The click-transport pass reduced audio to one partial
   site: the private-engine hard-cut negative control. Playback now has 3 gaps
   and 59 partial sites; its remaining gaps are raw-pointer lifetime observations.
   Continue reconciling exact Swift predicates while preserving native callback
   and reclamation obligations, then re-run `swiftcore`, audio, resonance,
   transport, click, and export harnesses.
2. **Core document editing and MIDI.** `editcheck` has 456 gaps and 519 partial
   sites; MIDI has 175 gaps and 138 partial sites. Close data-integrity,
   serialization, undo/redo, tick/range, and export behavior before UI parity.
3. **Project and voicegroup persistence.** Project checks have 268 gaps and 156
   partial sites; voicegroup and voicegroup-save have 768 gaps combined. These
   protect open/save identity and asset resolution.
4. **Track headers and selection routing.** Keep native input/focus observations
   native while porting model and command predicates. Do not turn a presenter
   assertion into evidence for pointer delivery or window shortcut priority.
5. **Drawer, automation, and velocity.** Finish the active proof-hardening pass,
   perform the queued EditorDrawer refactor, then rebase proof paths and close
   these as feature-sized slices. They currently contain the largest raw gap
   buckets and would cause avoidable merge conflicts if edited now.
6. **Native rendering and black-box journeys.** Preserve native checks for focus,
   pointer delivery, window routing, and raster output. Add a small external
   production-app suite for open, edit, save/export, relaunch, and critical
   QWidget/Quick keyboard transitions before retiring native coverage.

For each slice, the completion gate is: canonical proof metadata, exact `S###`
links for every match, passing focused harnesses, a passing full registered
suite, and no remaining `GAP`/`PARTIAL` entry unless an explicit product decision
retires that behavior.
