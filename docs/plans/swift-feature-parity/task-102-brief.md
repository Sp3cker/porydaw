# Task 102 brief — authoritative track/time selection through keyboard edits

# Context

Own the selected track/time/note scope as it moves through document replacement, structural track remap, ruler selection and normalized keyboard editing. The visible surface is the mounted roll; do not widen this into the unported cosmetic-track-remap or raw conductor-promotion features.

Verified selection: **44 open rows (26 GAP + 18 PARTIAL)**:

- `src/checks/clipboard/proof.selectioncheck_tracks.txt` — all 24 (16 GAP + eight PARTIAL): A047, A074, A080–A085, A088–A094, A096–A100, A102–A105.
- `src/checks/rollcheck/proof.keyboard.txt` — 20 (ten GAP + ten PARTIAL): A004, A006, A019–A021, A024, A026, A028, A029, A039, A053, A066, A091, A092, A095, A098, A100, A101, A104, A105.

Use fork `fceecd88` and each ledger's pinned matching original: selection tracks `996c6446f2cbfaa5b88ed721df4fa831129bd7bc`, keyboard `a1244957bb05a59d62b8912e053d49b2a6f3d771`. Keyboard A077–A080 (timeline-unused-track refused Insert Time) stay open: do not claim that a disabled command in an unrelated state proves the missing invalid-scope journey. The selection ledger closes; keyboard does not.

# Exact write set

- `src/swift/app/DocumentSession+Internals.swift` — conditional selected-row remap/publication repair.
- `src/swift/app/DocumentSession+Selection.swift` — conditional authoritative selection repair.
- `src/swift/app/roll/NoteCommands.swift` — conditional key resize/nudge repair.
- `src/swift/app/roll/PianoGrid.swift` — conditional existing roll command ingress repair.
- `src/swift/app/roll/GridScene+Notes.swift` — conditional selected ring publication repair.
- `src/checks/editcheck/SelectionChecks.swift`
- `src/checks/rollcheck/keyboard.swift`
- `src/checks/rollcheck/note_commands.swift`
- `src/checks/rollcheck/ruler_loop_menu.swift`
- `src/checks/editorqml/tst_ShellGridInput.qml`
- `src/checks/clipboard/proof.selectioncheck_tracks.txt` — delete after full closure.
- `src/checks/rollcheck/proof.keyboard.txt` — selected 20 rows only.

No ShellWindow, key-arbiter, automation producer/QML, velocity, fixture-content or core raw-edit writes. The selection original C++ was already deleted; do not recreate it. Do not add CMake/registration changes or conditional owners outside this closed set.

# Prerequisites

All 91–98 must land first. Rebase `PianoGrid.swift`, `GridScene+Notes.swift` and `tst_ShellGridInput.qml` over 93/96/97, and `note_commands.swift` over 97; preserve exact fractional camera/raster, hover and pointer-gesture laws. Task 99 is the sole Group A owner of window-shortcut routing. Task 100 owns automation gesture ingress: consume its current public selection behavior without editing its owners. Group B 105 may reuse the roll producer files only after Group A's checkpoint.

# Interface contract

- Preserve `DocumentSession.handleDocumentChange` and its selection-before-document publication ordering (`DocumentSession+Internals.swift:107–195`), including stable surviving NoteIDs, mute/solo masks and clearing a range whose primary owner was deleted. Compare actual `SelectionTransition.previousTrackTime` and `trackTime` from the existing observer, not a parallel remap implementation (:71–78).
- Exercise true empty-used-track Tempo coverage, replacing a document with a prior active selection, a remap to primary 4/scope {2,4} retaining the selected note, duplicate lane collapse to {(2,7),(4,8)} with Tempo retained, primary/scope fallback to zero, and dropping every selected lane. Retain the exact 20–30 range and both previous/current transition payloads where the original asserts them. Use production structural edits and real selection APIs, not an exposed test-only arbitrary-map entrypoint.
- Retire selection A083/A090/A096/A103 only as the deleted native `SelectionChange` flag bitmask. Its semantic before/after values remain behavioral obligations. All other selected selection clauses are behavior; `nil` time selection means no lanes, not a need to resurrect a vector-returning API.
- After Up then Shift+Down, real Right advances one snap cell. The ruler's modified sweep yields exactly the original range and complete expected track set; covered ghost and primary notes are actually visible and render their selection-ring pixels at DPR2. Aggregate provider color alone does not prove paint.
- A second time-range Duplicate creates the exact next span, note at the new span's start, cursor at its end and history index +2. Shift+Right on two distinct durations merges into index/count +1; each Shift+Left preserves both note identities and positions while uniformly shortening to the one-tick floor. A further press at the floor changes neither bytes, revision, index nor count. Active time selection blocks Shift+Left/Right with every original document/selection/cursor/history member unchanged.
- The transpose/sweep/resize slot unwinds to its post-seed bytes before the outer fixture restores pre-seed state; do not substitute those boundaries. Retire keyboard A019/A020/A021/A024/A091 as native fixture lookup/setup guards, never by adding setup-only passing assertions. Total planned representation retirements: nine; behavior rows: 35.

# Implementation steps

1. Extend `runClipboardSelectionChecks` and its existing unified/transition helpers (`SelectionChecks.swift:5–35,38–103,167–285`) for the exact remap/replacement/empty-track boundary and observer payloads. Reuse actual SongDocument/DocumentSession construction and existing scoped restoration.
2. Extend `withKeyboardSeed`, transpose and resize checks (`keyboard.swift:31–140,248–318`), the existing ruler checks and `checkKeyboardDuplicatePrefersTimeSelection` (`note_commands.swift:183–218`) with the missing exact conjuncts. Existing post-seed predicates may already make RED absent; preserve them instead of duplicating the same scenario.
3. Extend the actual shell-grid-input keyboard/ruler flows (`tst_ShellGridInput.qml:167–218,791`), using real pointer/key delivery, mapped rendered note geometry and settled captures. Add the selected command/ring assertions to consumer-visible journeys, not a test-only dispatcher or state-setting QML property.
4. Repair a demonstrated selected divergence only in the declared producers; keep task-97's gesture/history ownership intact. Update selected proof rows with fresh execution and delete only the fully closed selection ledger.

# Acceptance predicate

`SessionChecks.swift:68,90` registers keyboard and clipboard selection checks; `ShellQmlTests.swift:62–63` registers shell-grid-input. Domain checks prove exact bytes, history and observer payloads; the mounted lane proves actual normalized key/ruler delivery and painted rings.

On the settled task/group tree the controller runs every command below, serialized. Implementers do not run them while siblings edit. Apply §11 checkpoint/review policy and deduplicate full sweeps at the accepted group boundary, not omit them.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

All commands must finish within 180 seconds after lock acquisition (the wrapper alarms at 175). Fresh execution must classify selected behavioral anchors in `swiftcore-projectsession.json` and `shell-grid-input.json`; execute every data row, DPR/palette variant and mounted interaction used to close a row. Full shell and full verify pass, selected rows have no GAP/PARTIAL/NATIVE residue, and executed proof validation resolves all retained anchors. Preserve existing literal messages and add unique complete literals, never interpolated phase anchors. Capture before/after structure, real-surface smoke, source/evidence pins and the task review gate; never invent RED or execution.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
Do not absorb `rollcheck/proof.remap.txt`, endpoint-stack lane selection, corrupt-MIME routing, or unused-track Insert Time merely to close another ledger. No new arbitrary remap seam or public history counter is authorized.
