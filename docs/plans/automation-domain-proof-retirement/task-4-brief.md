# Task 4 — xcmd occurrences and opaque-epoch protection (A010-A028)

## Context

Second xcmd lane-CRUD slot: `xcmdOccurrencesAndOpaqueProtection`
(`xcmd.cpp:133-216`), 19 sites — point-occurrence CRUD interleavings and
the protection of unknown-selector ("opaque") XCMD epochs against lane
writes. Appends the opaque-epoch section inside
`drawerAutomationXcmdLaneEdits` created by Task 3 (producer contract:
`XcmdDomainFixture` from task-3-brief.md §Interface contract — reuse it;
do not redefine or widen it).

This slot carries one of the plan's two report-and-stop behavioral risks
(spec §5.3): opaque-epoch write rejection (A025/A028). A failing
predicate there is a production gap finding, never a check-side
workaround.

## Exact write set

- `src/checks/automation/domain/xcmd.swift` (append-only; the new
  section is appended inside `drawerAutomationXcmdLaneEdits` after the
  sweep section, plus any private helpers after the entry function)

## Prerequisites

Task 3 (its fixture and entry function). C1 has committed Task 3's
`xcmd.swift` state.

## Interface contract

No new public/internal entry points: the section runs inside
`drawerAutomationXcmdLaneEdits` under cppID
`"automation-domain/AutomationDomainTest::xcmdOccurrencesAndOpaqueProtection"`.
Private helpers (if any) stay file-private below the entry function.

Behavior — five phases, fixture values from spec §5.3 row 2 (all values
literal, no invention):

1. Occurrence CRUD: `setLane(volume, [(96,34),(192,35)])`; assert
   projection count 2 (A010); bytes at 96 `[(sel,0x08),(pay,34)]` (A011)
   and at 192 `[(sel,0x08),(pay,35)]` (A012); `deleteLanePoints` of the
   front point (identity from `lanePoints`); assert projection
   `["192:35"]` (A013), bytes at 96 empty (A014), bytes at 192 unchanged
   (A015); delete the remaining point; projection empty (A016) and
   `xcmdBytes()` empty (A017).
2. Inter-lane moves: re-add both; move front 96→384 v36
   (`moveLanePoints`, point identity from `lanePoints`); projection
   `["192:35","384:36"]` (A018); bytes at 192 (A019) and 384 (A020).
3. Mixed-lane per-tick isolation: `clearXcmd()`; volume `[(96,34)]`,
   length `[(96,17),(192,18)]`; move volume 96→160 v36; volume
   projection `["160:36"]` (A021); bytes at 96 = length pair only
   `[(sel,0x09),(pay,17)]` (A022); at 160 = volume pair (A023); at
   192 = length pair `[(sel,0x09),(pay,18)]` (A024).
4. Opaque-epoch rejection: `clearXcmd()`; `insertCc` selector `0x01` at
   tick 0, payload 1 at 1, payload 2 at 2; snapshot; write lane volume
   `[(1,30)]`; assert snapshot equality — bytes, revision, identity all
   unchanged (A025).
5. Malformed-epoch append + occupied-tick rejection: `undoToRoot()`;
   `insertCc` selector `0x01`@4, payload 1@5, payload 2@6, selector
   `0x03`@8, payload 99@9; snapshot; write volume `[(400,30)]`; assert
   `oneEdit` (A026) and full byte chain `[(sel,0x01),(pay,1),(pay,2),
   (sel,0x03),(pay,99),(sel,0x08),(pay,30)]` (A027); snapshot; write
   volume range exactly at tick 8 (`writeLane(track: 0, lane: volume,
   from: 8, through: 8, points: [LaneWrite(tick: 8, value: 30)])`);
   assert snapshot unchanged (A028).

## Implementation steps

1. Append the five phases in order inside the entry function after the
   Task 3 sweep section; snapshot equality assertions compare all three
   snapshot fields (bytes, revision, identity) per the
   `DrawerDomainCheckFixture.snapshot` idiom.
2. Byte-chain literals match spec §5.3 exactly; on failure of A025 or
   A028 stop and report the §5.3 opaque-epoch finding (which API accepted
   the write, resulting chain) — do not weaken the expectation.

## Acceptance predicate

- NAMED CHECKS (controller): `deno task verify --filter swiftcore --qt
  projectSession --verbose` PASS with cppId
  `automation-domain/AutomationDomainTest::
  xcmdOccurrencesAndOpaqueProtection` present in the PASS lines; then
  `deno task lsp:swift`. Implementer: `deno task proof show
  automation/domain/xcmd.cpp` still parses with `GAP 62`.
- Coverage: the run executes all 19 new predicates; PASS is the
  execution evidence Task 6's MATCHED mappings cite.

## Task-specific constraints

- Append-only (plan.md file-ownership policy); no edits to Task 3's
  canonical/sweep sections beyond appending after them.
- Point deletion/move must use identities returned by
  `document.lanePoints(track:lane:)`, never reconstructed values.
- No new fixture type: extend scenarios only through `XcmdDomainFixture`
  as contracted; if a needed capability is genuinely missing (e.g.
  channel access), add the smallest private helper in this file and name
  it in the task report.
