# Task 94 brief — ruler and painted velocity detents across instrument families

# Context

Own the velocity drawer's immediate ruler click and deferred paint gesture for
square, programmable-wave and noise voices, with detents enabled, disabled and
unlocked at press. Task 95 later consumes the accepted velocity interaction
owner for captured-selection cancellation; it must preserve these commit laws.

Verified selection: **57 open rows (2 GAP + 55 PARTIAL)** in
`src/checks/velocity/proof.velocitydetentpainting.txt`, all behavioral:
A005, A006, A015, A016, A018, A022–A024, A026, A027, A029, A033–A035,
A039–A041, A054–A062, A064, A065, A067–A071, A075–A077, A081–A083,
A097–A105, A107, A108, A110, A112–A114, A118–A120.
The six native fixture-geometry PARTIALs A042, A044, A045, A085, A087, A088
are deliberately not selected.

Oracle: `fceecd88:src/checks/velocity/velocitydetentpainting.cpp`,
`rulerUnlockKeepsRawVelocity`, `lockedPaintUsesDetents`,
`unlockedPaintKeepsRawVelocities` and their instrument-family data rows.
Current owners: `VelocityInteraction` pointer/ruler handling,
`VelocityGestureState.detentUnlock`, `VelocityGesturePolicy.resolvedVelocity`,
`drawerVelocityProgramFlowChecks`, and `tst_ShellDrawerParity.qml`'s existing
mounted detent/early-unlock/late-unlock gestures. The current real wave fixture
is `mus_gym` slot 6 in the Swift program-flow checks; do not replace a wave
page journey with a policy-only calculation.

# Exact write set

- `src/swift/app/drawer/velocity/VelocityInteraction.swift` — conditional ruler/paint repair.
- `src/swift/app/drawer/velocity/VelocityTransactions.swift` — conditional frozen detent-policy repair.
- `src/checks/velocity/VelocityPaintDetentChecks.swift`
- `src/checks/velocity/VelocityPaintDetentUnlockedChecks.swift`
- `src/checks/editorqml/tst_ShellDrawerParity.qml`
- `src/checks/velocity/proof.velocitydetentpainting.txt` — selected 57 rows only.

No fixture content, voice catalog, bank loader, preference-store, QML page,
registration or other velocity ledger edits. Reuse the existing staged project
and runtime note/program builders; the shell's Route 101 fixture already
includes the project's instrument catalog.

# Prerequisites

Begin after accepted 84/86/87/89. Rebase reads of 89's
`VoiceListController.swift` and `DocumentSession.swift` bank/program binding,
84's `DocumentWorkspace.swift`, 86's `EditorSurface.qml` pointer-focus ingress
and 87's window shortcut contract. Preserve task 88's detent-drag behavior.
No file is shared with another Group A writer.

# Interface contract

- Preserve `VelocityGestureState` and pointer/ruler entry signatures, existing
  note-ID capture and `VelocityGesturePolicy.resolvedVelocity`. Do not add a
  second instrument-to-detent policy or use track identity as a voice family.
- Ruler raw-73 selection writes immediately on press for modifier-unlocked
  and disabled-detent cases, on each family. It publishes exactly one document
  event, dirty transition and undo increment. Both selected document notes
  and their timeline projections become 73; the unselected note stays exact.
  Release writes nothing further. The checkbox/state remains consistent with
  whether detents were disabled or temporarily unlocked, never silently toggled.
- Locked paint at raw 73 yields square 76, wave 64 and noise 76. Press away
  from nodes and move across two columns: until release, committed notes,
  timeline, undo position, document publications and dirty state do not change.
  Release commits the two selected results with one publication/dirty
  transition/undo increment, enables undo and clears preview state.
- Unlocked paint uses raw 37 and 91 for all three families. Unlock is captured
  at press and survives subsequent move events without that modifier. Preserve
  the same deferred-commit, unselected-note, exact-history and preview-clear
  laws as locked paint. A scalar policy result alone does not satisfy a
  document or timeline predicate.
- Each instrument-family data case executes the same distinct anchored
  clauses. Compare exact counts against the pre-gesture baseline, not just
  changed identity, dirty=true or canUndo=true as a proxy for all three laws.

# Implementation steps

1. Extend the two existing paint check files and real program-flow fixture
   with every square/wave/noise case. Observe actual page input, document
   publication, timeline notes and history at press, move and release.
2. Add missing independent message anchors for the selected fork clauses;
   retain all existing messages. Do not add assertions of incidental fixture
   dimensions or copy policy results into the expected document values.
3. Extend the mounted drawer parity journey to operate the actual detent
   control, ruler and plot, checking immediate versus deferred visible
   updates and press-latched unlock. Preserve existing late-unlock regressions.
4. Fix only demonstrated divergence in the two velocity owners. **RED may be
   absent if production already matches; then the check is the deliverable.**
   Update only the selected 57 rows with executed same-change evidence.

# Acceptance predicate

Controller-run after Group A settles. `runVelocityPageChecks` in
`swiftcore-projectsession` covers real program-flow/history/timeline laws;
`shell-drawer-parity` covers mounted controls and pointer gestures.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-drawer-parity --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Each invocation has a 175 s process alarm and ≤180 s verification ceiling,
with builds serialized by the lock. Require fresh
`build/proof-evidence/swiftcore-projectsession.json` and
`shell-drawer-parity.json`. Full shell runs all 26 lanes (~40 s warm), and
full verify (~10 s warm) is mandatory: fixture/program assumptions in other
lanes must not regress. No retirement is planned; the six unselected geometry
PARTIALs and other velocity surfaces remain untouched.

# Task-specific constraints

Use sprint-3 §10: no new C++; Swift 6.4 idioms; comments at most two lines;
base-font sizing; WCAG AA before pixel parity. Keep one keyboard authority;
no second dispatcher, synthetic forwarding, focus memory or bare-Space chrome
capture. No `Qt.callLater` coalescing or new idempotence guards. One literal
message anchor per fork clause, old messages verbatim, real fixtures, no
test-only seams. Preferences are CFPreferences/UserDefaults-backed: never
stage persisted state by plist bytes. No checked-in fixture edits; an approved
expansion must first name every exact-content consumer in the write set.
Workarounds need user approval. Parked areas, deferred menus and savecore
A016–A026 remain excluded.
