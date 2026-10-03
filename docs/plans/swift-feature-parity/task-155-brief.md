# Task 155 brief — repair Review146's numbered-literal defects and the themelayout S020 anchor

# Context

Review146 found committed checks stamping A-ids where they do not belong: an A-id on
predicates that prove a different clause, one A-id on several predicates, and A-ids on
setup guards. In-band `A0xx` prefixes are claims that a predicate proves that ledger
row's clause; §16 allows exactly one predicate per clause and no A-ids on setup guards.
Separately, `deno task proof check --executed` reports
`src/checks/themelayout/proof.tst_themelayout_color.txt S020: not executed` every run
because the anchored branch is unreachable, not because a predicate is missing.

S020 root cause (verified): `themeGridContrastChecks`
(`src/checks/themecolor/ThemeColorChecks.swift:361-372`) emits
`"\(tag): contrast 100 lightens away from the surface"` only in the
`baseLuminance > rollLuminance` arm. All three rows in `themePresetRows` take the
darkens arm, and `ShellAppearance.apply(to:mode:contrast:)`'s mode switch
(`src/swift/app/shell/ShellAppearance.swift:98-212`) produces no mode whose grid line is
lighter than its roll, so the white-endpoint branch of `gridColor` is unreachable
through the public API. The fork's own data rows never reached it either:
`gridContrast_data` at the pinned revision `97dc7fea` lists only vanilla,
dark-neutral-high and immaterial × contrast {0, 50, 100}. The ledger already classifies
A038 PARTIAL for exactly this reason. The defect is the anchor kind: a message anchor
that can never match is a standing false error, not missing coverage.

The voicegroupsourceediting S092–S161 "not executed" rows share the symptom but a
different cause (the `editingExpect`/`editingEqual` helpers prepend `"\(row): "` to the
emitted message). That file and `proof.voicegroupsourceediting.txt` are owned by a
parallel fix outside this plan: **do not touch
`src/checks/projectstore/VoicegroupEditingChecks.swift`,
`proof.voicegroupsourceediting.txt`, or their A001/A015 fixture predicates.**

Selected literal inventory (all current line numbers verified):

| File : line | Current literal prefix | Defect | Fix |
|---|---|---|---|
| `tst_ShellClipboardRoundTrip.qml:336,345,349,355,357,359,361` | `A017 ` ×7 | Prove malformed-MIME Paste refusal; clipboard A017 (68209547 pin, `clipboardchecks.cpp:308` `QCOMPARE(initialMime->text(), sentinelText)`) is the ED11 text-ownership GAP. No S-site anchors these literals | Drop prefix |
| `tst_ShellWindowLabelCommands.qml:50,52,53` | `A038 ` ×3 | A038's sites are S126–S131 in `localinputtier_window.swift`; these QML literals anchor nothing | Drop prefix |
| `tst_ShellWindowLabelCommands.qml:64,73` | `A061 ` ×2 | A061's sites are S153–S158 in `localinputtier_window.swift` | Drop prefix |
| `tst_ShellWindowLabelCommands.qml:74` | `A066 ` | A066 maps S195 (`ParameterKeys:278` Delete focus) | Drop prefix |
| `tst_ShellWindowParameterKeys.qml:247,308` | `A066 ` ×2 | Same row, Copy/Paste focus outcomes; S195 anchors :278 only | Drop prefix |
| `tst_ShellWindowFocus.qml:225,226` | `A113 ` ×2 | A113 maps S190, which anchors :228's note-identity literal; :225/:226 are the transport-routing and section-visibility clauses of other rows | Drop prefix |
| `tst_ShellWindowFocus.qml:173` | `A010 ` | Fork A010 (`windowtier_keyboard.cpp:122` at c17d966f) is ONE combined copy+solo+bytes clause; keep the A-id on :172 (Copy, S180) only | Drop prefix; re-point S181 |
| `tst_ShellWindowFocus.qml:192` | `A018 ` | Fork A018 (`:160`) is one combined clause; keep :191 (S185) | Drop prefix; re-point S186 |
| `tst_ShellWindowFocus.qml:156` | `A014 ` | Setup guard (focus owned before arrows) | Drop prefix; re-point S182 |
| `tst_ShellWindowFocus.qml:199` | `A108 ` | Setup guard | Drop prefix; re-point S189 |
| `tst_ShellWindowLabelCommands.qml:44` | `A031 ` | Setup guard | Drop prefix; re-point S206 |
| `tst_ShellWindowLabelCommands.qml:84` | `A077 ` | Setup guard | Drop prefix; re-point S192 |

Ledger rows to re-point in this commit (`src/checks/selectionkey/proof.windowtier_keyboard.txt`,
dispositions unchanged): S181 → `message "F24 never activates window Solo"`;
S186 → `message "grip arrows never activate window Solo"`;
S182 → `message "automation resize grip owns active focus before arrows"`;
S189 → `message "automation toggle owns active focus before arrows"`;
S206 → `message "the Volume label owns active focus before commands"`;
S192 → `message "label owns focus before routed arrows"`.
No S-site anchors any other de-prefixed literal (verified by ledger grep); A010/A018's
`Mapping:` lists keep citing S179–S181 / S185–S186 because those predicates still prove
the clause jointly.

# Exact write set

- `src/checks/editorqml/tst_ShellClipboardRoundTrip.qml` — the seven message literals only.
- `src/checks/editorqml/tst_ShellWindowLabelCommands.qml` — six message literals only.
- `src/checks/editorqml/tst_ShellWindowParameterKeys.qml` — two message literals only.
- `src/checks/editorqml/tst_ShellWindowFocus.qml` — six message literals only.
- `src/checks/selectionkey/proof.windowtier_keyboard.txt` — S181, S186, S182, S189, S206, S192 anchors only.
- `src/checks/themelayout/proof.tst_themelayout_color.txt` — S020 anchor and its annotation; A038's mapping-reason line numbers only.

# Prerequisites

None. Disjoint from Task 152 (in flight) and from the parallel voicegroupsourceediting
executed-anchor fix. Read sprint-3 §18 for shared constraints.

# Interface contract

No production interface changes. QML predicate semantics, key sequences and observed
state stay byte-identical except the message strings; every re-pointed S-anchor literal
must equal its new message text exactly so `deno task proof check` resolves it.
S020 changes from `Anchor: message "\(tag): contrast 100 lightens away from the surface"`
to `Anchor: function`, keeping its annotation (refreshed to the current
`ThemeColorChecks.swift:368-372` lines) documenting that no shipped preset reaches the
lightens arm. A038 stays PARTIAL with its existing reason; only its stale
`:576-578` citation refreshes to `:368-372`.

# Implementation steps

1. Remove the twelve dangling/duplicate `A0xx ` prefixes listed above; touch nothing
   else in those statements.
2. Re-point the six windowtier S-anchors to the de-prefixed literals in the same commit.
3. Re-anchor S020 to `Anchor: function` and refresh the two stale ThemeColorChecks line
   citations (S020 annotation and A038 mapping reason).
4. Do not renumber, merge or split any predicate; do not add new assertions.

# Acceptance predicate

Every message literal that carries an in-band A-id proves that ledger row's clause, each
A-id sits on exactly one predicate per clause family, setup guards carry none, and
`proof check --executed` no longer lists themelayout S020. The four edited lanes still
pass with their renamed messages.

Named checks under §18 ownership (macOS native Qt desktop required):

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-clipboard-round-trip --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-focus --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-label-commands --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-parameter-keys --verbose
deno task proof check
deno task proof check --executed
```

The two proof commands cover anchor resolution (no `literal not found`/ambiguity) and
the S020 line's disappearance. The voicegroupsourceediting `not executed` lines remain
until the parallel fix lands; they are this brief's expected residual, not a failure.

# Task-specific constraints

Six files are one bounded hygiene surface named by Review146; no behavior predicate is
added, removed or weakened. `--executed` verdicts for `.qml` headers depend only on the
test function having run, so the re-points cannot change execution evidence. Do not
touch `VoicegroupEditingChecks.swift`, `proof.voicegroupsourceediting.txt`, any other
ledger, or any production file.
