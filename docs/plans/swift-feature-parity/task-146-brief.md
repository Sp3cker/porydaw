# Task 146 brief — strict-mapping debt exception: message-anchor the four largest MATCHED ledgers

# Context

Parent scope and shared constraints: sprint-3 §16 (wave 139–146).
Explicitly user-requested mechanical exception to the
surface-first rule (`.omp/rules/proof-ledger-workflow.md` forbids standalone
reconciliation): `deno task proof check --strict-mappings` reports **485
errors**, every one of the form `MATCHED without a message-anchored
predicate` — the cited Swift predicates resolve, but their anchors are
`function`, so strict mode fails. This brief selects only the four largest
debt ledgers (**295 of 485**) and bounds the work to message-anchoring the
audited proven subset: rows whose clause an already-executing check in the
write set actually proves. Every other selected row stays debt and is
returned as an explicit exact retained list with reasons. No GAP/PARTIAL row
is touched, no disposition is upgraded, no predicate or evidence is invented,
no new check journey is added merely to attach an A ID.

Selected **295 MATCHED debt rows (0 GAP + 0 PARTIAL)** across four ledgers.
Per-ledger debt counts were measured with
`deno task proof check --strict-mappings` aggregated per ledger file
(88 / 78 / 70 / 59; next-largest `tst_nativewindowing` 39 is out of scope).
Citations below are assertion-start lines verified to align byte-for-byte
between each ledger's pinned Reference revision and fork oracle `fceecd88`
(sampled lines `L87/L110/L188/L358`, `L79/L103/L152/L280`,
`L97/L155/L225/L376/L461` all `ALIGN`; full line lists below are the
ledger-recorded headers). `swiftrollgated/clipboardchecks.cpp` is **absent**
at `fceecd88` (post-fork file), so its citations resolve only through ledger
pin `68209547`, never through the fork.

| Target A-ids | Citation |
|---|---|
| voicegroupsourceediting A003–A014 | `fceecd88:src/checks/voicegroup/voicegroupsourceediting.cpp:87,94,95,96,97,98,99,100,101,102,103,104` — `blankSlotCreateAndRestore` (12) |
| voicegroupsourceediting A015–A041 | `fceecd88:.../voicegroupsourceediting.cpp:110,112,114,122,131,132,133,134,135,136,137,138,139,140,141,142,145,146,147,148,149,150,151,154,155,156,157` — `sparseInsertionsSerializeAtBothEnds` (27) |
| voicegroupsourceediting A043–A085 | `fceecd88:.../voicegroupsourceediting.cpp:188,196,201,209,215,222,233,236,241,250,255,256,258,264,273,274,275,277,280,282,284,285,286,289,294,296,298,299,302,303,304,305,306,311,313,314,316,319,322,328,330,331,332` — `editedFamiliesPreviewSaveReloadAndCreate` (43) |
| voicegroupsourceediting A093–A098 | `fceecd88:.../voicegroupsourceediting.cpp:358,359,361,362,364,365` — `displayNamesAreStable` (6) |
| clipboardchecks A006–A010, A015, A016, A018–A022, A024, A025 | pin `68209547:src/checks/swiftrollgated/clipboardchecks.cpp:240,257,267,268,269,306,307,312,318,319,322,323,325,326` — `hostClipboardRoundTripAndReplacement` (14) |
| clipboardchecks A027–A059 | pin `68209547:.../clipboardchecks.cpp:333,335,337,339,341,342,344,345,346,347,349,351,353,364,365,370,372,378,379,380,381,385,403,404,406,407,417,418,419,420,436,437,440` — same journey (33) |
| clipboardchecks A061–A091 | pin `68209547:.../clipboardchecks.cpp:450,451,452,453,456,458,460,464,466,467,470,491,501,502,503,504,506,507,518,519,542,544,546,562,564,580,581,591,592,602,603` — same journey (31) |
| tst_voicegroupbank A002, A004–A013 | `fceecd88:src/checks/voicegroup/tst_voicegroupbank.cpp:79,83,86,87,88,89,90,92,93,94,95` — `init` (11) |
| tst_voicegroupbank A016, A018 | `fceecd88:.../tst_voicegroupbank.cpp:103,106` — `playableSongResolvesOnlyPlayableLabels` (2) |
| tst_voicegroupbank A019–A021, A023–A026 | `fceecd88:.../tst_voicegroupbank.cpp:111,114,115,119,121,122,123` — `bankLeaseIsReusedAcrossSharedVoicegroup` (7) |
| tst_voicegroupbank A027–A035 | `fceecd88:.../tst_voicegroupbank.cpp:152,156,157,158,159,160,161,162,163` — `appliedScalarEditReplacesBankAndPreservesOldLease` (9) |
| tst_voicegroupbank A036–A043 | `fceecd88:.../tst_voicegroupbank.cpp:171,185,186,187,189,190,191,197` — `staleBlankAndOutOfRangeEditsConflictWithoutMutation` (7) + `unknownIdentityIsHardError` (1) |
| tst_voicegroupbank A047, A051–A057 | `fceecd88:.../tst_voicegroupbank.cpp:213,226,227,230,231,232,233,234` — `previewFailureRollsBackCandidate` (8) |
| tst_voicegroupbank A058–A062, A065–A075 | `fceecd88:.../tst_voicegroupbank.cpp:240,241,248,250,251,254,255,256,262,264,265,266,267,268,272,273` — `blankMaterializationRevertAndSpentToken` (16) |
| tst_voicegroupbank A076, A078–A085 | `fceecd88:.../tst_voicegroupbank.cpp:280,287,288,289,290,291,292,294,295` — `saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty` (9) |
| windowtier_keyboard A001, A003–A009 | `fceecd88:src/checks/selectionkey/windowtier_keyboard.cpp:97,102,108,109,111,114,115,118` — `windowCopySoloExecutesExactlyOnce` (8) |
| windowtier_keyboard A015, A016, A019 | `fceecd88:.../windowtier_keyboard.cpp:155,158,164` — `chromeGripKeysStayLocal` (3) |
| windowtier_keyboard A025, A026, A028, A029, A032–A034, A036, A037, A039, A040, A043–A046, A049–A051, A054, A055, A058–A060, A069 | `fceecd88:.../windowtier_keyboard.cpp:225,229,242,243,248,249,250,252,253,258,259,274,275,276,281,286,288,290,294,295,299,300,301,313` — `parameterLabelActivationAndSharedCommands` (24) |
| windowtier_keyboard A079–A081, A085, A087–A091, A094–A101, A104 | `fceecd88:.../windowtier_keyboard.cpp:335,336,338,376,396,398,401,403,404,407,408,412,418,425,426,427,428,433` — `tapButtonKeysAndTransportCession` (18) |
| windowtier_keyboard A109–A112, A114, A115 | `fceecd88:.../windowtier_keyboard.cpp:461,468,473,484,496,499` — `chromeToggleRoutesNoteArrows` (6) |

# Exact write set

Check sources (anchor work only — add stable literal `message` expectations
to existing predicates, or split one compound function-anchored predicate
into one message-anchored predicate per A it proves; no behavior or
production change; no new files):

- `src/checks/projectstore/VoicegroupEditingChecks.swift` (voicegroupsourceediting predicates)
- `src/checks/projectstore/BankLeasesChecks.swift` (bank lease predicates)
- `src/checks/workspace/bank_edits.swift` (preview-failure / materialization / conflict predicates only)
- `src/checks/workspace/bank_saves.swift` (save round-trip predicates only)
- `src/checks/workspace/bank_sharing.swift` (sharing predicates only)
- `src/checks/workspace/session_save.swift`, `src/checks/workspace/session_io.swift` (only if a cited proving predicate hosted there needs its anchor; read-only otherwise)
- `src/checks/rollcheck/EditorGridCameraChecks.swift`
- `src/checks/editorqml/ShellQmlTests.swift`
- `src/checks/editorqml/GridInputClipProbe.swift`
- `src/checks/editorqml/tst_ShellClipboard.qml`
- `src/checks/editorqml/ShellClipboardSupport.qml` (predicate host of clipboard S054/S056/S062 — anchor strengthening only)
- `src/checks/selectionkey/localinputtier_text.swift`
- `src/checks/selectionkey/localinputtier_window.swift` (predicate host of the S120-class rows — anchor strengthening only)
- `src/checks/editorqml/tst_ShellWindow.qml`

Ledgers — separate ledger writer only, selected rows above (implementer never
edits proof files):

- `src/checks/voicegroup/proof.voicegroupsourceediting.txt`
- `src/checks/swiftrollgated/proof.clipboardchecks.txt`
- `src/checks/voicegroup/proof.tst_voicegroupbank.txt`
- `src/checks/selectionkey/proof.windowtier_keyboard.txt`

Stale references, not write targets: the ledgers' `Command:` lines naming
`projectstore-checks` and bare `swiftcore` predate the suite split, and the
clipboard ledger's `TimeChecks.swift` counterpart is absent from the tree
(proving time predicates now live under the projectSession suites). Nothing
outside the closed list above is writable.

# Prerequisites

Accepted/checkpointed 139–145 before reusing any of their check files; see sprint-3 §16's conflict matrix. Capture the full strict inventory immediately before this task. The planning baseline is 485; use the dispatch baseline if earlier accepted surfaces legitimately changed other debt.

# Interface contract

Each anchored row keeps its proving function, file and journey; the change is
one stable independent literal per clause
(`report.expect... message: "<complete unique literal>"` in Swift,
equivalent unique literal verify in QML) with that S entry re-anchored from
`Anchor: function` to `Anchor: message "<same literal>"` (`#n` occurrence
suffix where the literal repeats). The literal names the clause outcome
independently of the code under test (exact bytes, counts, tokens, labels —
never the item's own color/text or a self-comparison). **One A per
predicate**: where one function-anchored predicate currently carries several
debt rows, split it so each A cites its own message-anchored predicate;
conversely never duplicate an already-proven journey into a second check
merely to attach an A ID. Existing passing literals are preserved, never
reworded. A selected row whose clause no executing check in the write set
proves — uncovered clause, representation-only clause, or predicate host
outside the write set — is recorded in the retained list with its reason and
its debt line stays.

# Implementation steps

1. For each selected A row, read its original expression
   (`deno task proof show <ledger> <A###>`) and its cited S anchor
   (`show <ledger> <S###>`); audit it into the proven subset or the retained
   list. Historic ledger `Result: PASS` lines are context only — execution of
   each newly anchored predicate must be confirmed by fresh
   `deno task proof check --executed` evidence, never assumed from an old
   PASS.
2. For the proven subset, add the stable literal to the already-executing
   check (splitting compound predicates so each A gets its own predicate) and
   re-anchor via the separate ledger writer.
3. Record the exact retained inventory: every selected ID not anchored,
   with reason per row.
4. Re-run the narrow lanes below, then the strict inventory compare.

# Acceptance predicate

After the change, the proven subset of the 295 selected rows cites
executed message-anchored predicates (one A per predicate), and the retained
list names every other selected ID with a reason. The four-ledger strict
output must equal exactly the retained inventory — debt reduced by the
audited proven subset, nothing hidden. The remaining ~190 strict-debt lines
in other ledgers are untouched.
Debt must decrease in each of the four selected ledgers; an empty proven
subset or a retained list without clause-level evidence is not completion.

`deno task proof check` accepts no `--area`/positional scoping (verified:
`tools/proof_reader.ts` `options()`/`main()` invalid-args gate), so focus is
by output inventory, compared as files — never a `grep ...; test $?`
pipeline, which passes vacuously if the command fails. Under sprint-3 §16
execution ownership, run the live narrow owners (verified against
`src/checks/checkcatalog.cpp`, suite ids in
`src/checks/support/corecheck/core_check.h`, and dispatch in
`CoreCheckSupport.swift` — not the stale ledger `Command:` lines):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectstore-editing --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter bankleases --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-clipboard --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
```

Lane-to-predicate registration (inspected): `projectstore-editing` runs
`voicegroupEditing` → suite 20 → `runVoicegroupEditingSuite` (the
`projectstore-checks` ledger line runs suite 22, which is editing + savecore
— broader, not accepted as the narrow lane); `bankleases` and `vgbankcheck`
both dispatch `bankLeases` → suite 31 → `runBankLeasesSuite`;
`swiftcore-bankhistory` runs suite 11 → `runBankHistorySuite` (workspace
bank_* proving checks); `swiftcore-projectsession` runs suite 10 →
`runProjectSessionSuite` (windowtier `windowTierKeyboardOutcomes` /
`coreEditingKeyboardOutcomes` via `drawerOriginalNumericPromptTransaction`,
plus `runEditorGridCameraChecks`); `shell-clipboard` / `shellwindow` are
registered in `src/checks/editorqml/ShellQmlEntries.swift`.

Then run the proof commands without a pipeline so their complete output and
exit status are retained:

```sh
deno task proof check --executed
deno task proof check --strict-mappings
```

The strict command is expected to exit 1 while out-of-scope debt remains;
that exit is not a pass. Compare its complete `(ledger path, A-id)` error
inventory with that dispatch baseline: the removed pairs must be
exactly the audited proven subset, the selected remaining pairs exactly
the retained list, and every out-of-scope pair unchanged. Require the final
error tally to equal `dispatchBaseline.count - provenSubset.count`; any tool/runtime failure
or additional error is a failed acceptance, not retained mapping debt.
`proof check --executed` must exit 0. The
unfiltered strict run still reports the ~190 out-of-scope debt lines plus
the retained inventory — that remainder is the bounded-exception evidence,
not a failure of this task.

# Task-specific constraints

One-off user-requested exception to the proof-ledger-workflow ban on
standalone reconciliation, bounded to the 295 named MATCHED rows. It sets no
precedent: no further ledger may be added without explicit user approval, and
no brief may cite this task to justify re-pinning, rewording, disposition
upgrades, or whole-ledger closure. No production (`src/swift/`, `src/ui/`)
change; no new check files, runner entries, or manifest edits. No GAP/PARTIAL
upgrade anywhere. No fake predicates, no evidence inferred from related
checks, no incidental wording/forwarding re-pinning, no duplicated journeys
to attach IDs. Excluded throughout: physical audio output, ImageIO decoding,
P3 WAV export, P4 sample studio, savecore A016–A026, transport A009/A010/A013.
