# Task 114 brief — mouse hints follow the live pointer owner across tabs

# Context

Complete pointer-owned mouse hints through output-dial grabs, scrollbar release, track reorder, keyboard-only focus movement, tab hide and tab close. The user-visible hint belongs to the live hovered surface, not whichever editor most recently received focus. Preserve the existing MouseHints token ownership; do not expose its private token for tests.

Verified planning selection: **39 open rows (32 GAP + 7 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` — A118, A119, A120, A121, A122, A125, A126, A127, A128, A129, A130, A134, A135, A136, A137, A138, A139, A140, A141, A142, A143, A146, A147, A148, A149, A150, A151, A152, A153, A154, A155, A156, A157, A158, A159, A160, A162, A163, A164.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `b5815a6e23296a9cc48c85a201a2ce858b99aae9`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/MouseHints.swift`
- `src/ui/songview/quick/HoverHint.qml`
- `src/ui/songview/quick/TimelineScrollbar.qml`
- `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml`
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`
- `src/ui/shell/TransportOutputDial.qml`
- `src/ui/shell/TransportBar.qml`
- `src/checks/workspace/session_editor_semantics.swift`
- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 and Group A's checkpoint precede this task. Rebase tst_ShellTabs over 103 and EditorSurface over 105/109. Consume the actual completed tab-close lifecycle, not a substitute fake tab or manually cleared MouseHints token. Group B 112 owns roll gestures; this task owns only their QML hint binding.

# Interface contract

- Preserve `MouseHints.claim`, `clear` and `setWindowActive` token semantics. `HoverHint` freezes a profile during a grab and settles at the actual release position; visibility, reparenting, window deactivation and destruction invalidate a dead owner's claim. Keyboard focus is not a pointer-enter event. No public current-owner/debug token is added.
- Dial A118–A121: move onto the actual output dial, observe its nonempty profile, drag below value 50 while holding the same profile, and release over the output combo to clear the profile. Scrollbar A127–A129: hover/hold its empty profile, release over the roll, and observe the roll's nonempty profile. Use real scene-mapped coordinates, not direct claim/clear calls to fake crossing.
- Track header A136–A142: observe its specific/nonempty profile, begin the fork's primary-track 1 → 0 reorder, observe the reorder indicator, keep the header profile while held, commit one real revision change and observe the valid release-target profile. A138/A139/A141 may not be implied by hint text.
- With the pointer stationary over the roll, focus headers, move focus again and press Tab: A146–A153 require the same nonempty roll hint throughout. A148/A149 retain the actual focused-item changes; merely not moving the pointer is not evidence those keys worked.
- In the two-tab mounted shell, establish B's roll hint, switch to A and prove B cannot retain the visible claim; establish A's profile, close A, and prove its old owner cannot survive or clear a new B claim (A157–A159/A162–A164). Visible hint text and existing Swift token-isolation predicates jointly prove ownership; a dead source's private identity need not be exposed. A legitimately re-hovered surviving tab may reclaim its own hint.
- A122/A125/A126/A130/A134/A135/A143/A154/A155/A156/A160 are native fixture/session/thumb/window/item setup guards. Retire only those representations alongside the mounted consumer. Do not retire live source invalidation, release-target routing, focus independence or tab-close behavior.

# Implementation steps

1. Extend the registered mouseHintOwnershipChecks and scope checks in session_editor_semantics with the stale-owner/release/visibility transitions that support the mounted journeys; preserve private token encapsulation.
2. Extend tst_ShellTabs to drive the real dial, scrollbar, track header, stationary-pointer focus changes and two-tab hide/close transitions in one actual shell lane. Observe exact visible profiles and document/focus effects independently.
3. Repair only demonstrated MouseHints/HoverHint or control-binding divergence in the declared files. Preserve reorder/scroll/dial semantics; never call claim/clear in a mounted test to impersonate pointer ingress.
4. Map only the selected 39 lifecycle rows, including the bounded representation retirements. Keep the ledger and all unselected lifecycle/project-store rows unchanged.

# Acceptance predicate

SessionChecks registers the MouseHints ownership/scope checks in swiftcore-projectsession; shell-tabs mounts the actual window and tab lifecycle. Every grab/release/focus/tab clause executes and the selected 39 lifecycle rows close without a host/physical-cursor claim.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No application/tab lifecycle, document model, PianoGrid or command routing writes. If a lifecycle producer defect is discovered, the closed group contract must be revised before touching its owner; never paper it over by manual hint clearing in a test.
