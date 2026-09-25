# Context
Repair R06 on the existing voice editor. Queued edits currently retain only a slot index across suspension, while one controller is rebound between tabs. Read plan.md Global constraints and spec.md.

# Exact write set
- src/swift/app/voicelist/VoiceEditorController.swift
- src/swift/app/voicelist/VoiceListController.swift
- src/checks/voicelist/voicelist_session.swift
- src/checks/editorqml/tst_ShellVoicegroup.qml

# Prerequisites
None. Do not edit DocumentSession, ApplicationSession or ProjectService; other owners handle those.

# Interface contract
Every delayed scalar/type/synth/sample editor mutation belongs to the session and bank identity at request time. A later rebind must never redirect it to another document with the same slot. Reuse existing session identity/lease semantics; no second bank authority. Preserve ordinary queued edits on the same bank and error publication. Preserve public QML entrypoints.

# Implementation steps
1. Trace all queued editor operations and current owner binding lifetime.
2. Capture stable origin session/bank identity and validate it after suspension before obtaining draft or applying edit. Cancel obsolete requests rather than writing to a newly selected document.
3. Cover scalar, type/symbol and synth paths consistently; preserve pending-task ownership and legitimate same-origin ordering.
4. Add deterministic two-session same-slot regression using existing fixture/check seams, and an actual mounted route where feasible. No sleeps, mock echo or test-only production getter.
5. Return final proof predicate identities and ledgers for later proof-only handoff; do not edit proofs.

# Acceptance predicate
An edit queued on tab A cannot alter tab B after rebind, while same-session ordered edits and undo still work: controller runs `deno task verify --filter swiftcore --verbose` and `deno task verify:shell --filter shell-voicegroup --verbose`.

# Task-specific constraints
SHARED_TREE. Skip builds/tests/lint/formatters; controller verifies. No comments, commits, scratch reports, new UI or fallback behavior.
