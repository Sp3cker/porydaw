# Task 115 brief — automation pointer ownership survives focus, rebuild and lane transitions

# Context

Finish the existing automation pointer lifecycle as one surface: real hover, held grabs, stale-release cancellation and node/range edits. This consumes 111’s settled presentation and supplies task 119’s stable input producer; it adds no insertion gesture.

Verified planning selection: **93 open rows (64 GAP + 29 PARTIAL)**. This is the in-flight §13 census, not a completion claim.

- `src/checks/automation/hover/proof.tst_automationhover.txt` — A002, A003, A006, A007, A014, A015, A016, A020, A022, A024, A030, A032, A034, A035, A045, A050, A054, A056, A059, A060, A061, A062, A074, A075, A076, A077, A078, A080, A081, A082, A084, A085, A086, A087, A088, A089, A097, A098, A099, A104, A107, A108, A113, A121, A123, A126, A127, A128, A130, A133, A141, A142, A143.
- `src/checks/automation/proof.automationnodedrag.txt` — A026, A027, A028, A029, A030, A031, A032, A033, A034, A055, A056, A057, A067.
- `src/checks/automationgesturecheck/proof.contract.txt` — A001, A023, A062, A063, A064, A065, A066, A067.
- `src/checks/automationgesturecheck/proof.crosslane.txt` — A001, A002, A011.
- `src/checks/automationgesturecheck/proof.hover.txt` — A002, A013, A015, A030.
- `src/checks/automationgesturecheck/proof.parity.txt` — A001, A002, A006, A007, A008, A009, A010, A011, A012, A015, A016, A019.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`, `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`, `7430fb426d466be20dd3a5e816cb2081c0e9135f`, `7430fb426d466be20dd3a5e816cb2081c0e9135f`, `7430fb426d466be20dd3a5e816cb2081c0e9135f`, `7430fb426d466be20dd3a5e816cb2081c0e9135f`. Read selected expressions with `deno task proof sites` / `show`; deleted C++ check paths are references, never write targets.

# Exact write set

- `src/swift/app/drawer/automation/AutomationInteraction.swift`
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift`
- `src/ui/songview/quick/drawer/AutomationPage.qml`
- `src/checks/automation/automationcanvasediting.swift`
- `src/checks/automation/domain/gestureSweep.swift`
- `src/checks/automation/domain/gestureNodeDrag.swift`
- `src/checks/automation/domain/gestureNodeDragPhantom.swift`
- `src/checks/automation/domain/gesturePointRange.swift`
- `src/checks/editorqml/tst_ShellDrawerParity.qml`
- `src/checks/automation/hover/proof.tst_automationhover.txt`
- `src/checks/automation/proof.automationnodedrag.txt`
- `src/checks/automationgesturecheck/proof.contract.txt`
- `src/checks/automationgesturecheck/proof.crosslane.txt`
- `src/checks/automationgesturecheck/proof.hover.txt`
- `src/checks/automationgesturecheck/proof.parity.txt`

Closed list: production writes are limited to the interface below. The implementer owns code/check files; the separate ledger writer alone owns the listed proof files after evidence settles, in the same surface change.

# Prerequisites

111, 112, 114 and the 113 Volume clipboard follow-up must be accepted first. Preserve 104/107 insertion and 108/112 velocity work. Group A 118 alone owns AutomationPage.swift, DocumentSession and ApplicationSession; this task may consume their existing interfaces but not its new state interface.

# Interface contract

- Preserve AutomationInteraction pointerPress/pointerMove/pointerRelease/pointerLeave and its frozen transaction. Ordinary focus loss cancels the edit but retains the held pointer grab until release; window deactivation cancels and releases it. Prove both with actual mounted focus/window transitions and a subsequent successful fresh gesture, not calls to a fake host or inspection of native grabber pointers.
- For hover A099/A104 deliver the existing pencil shortcut through ShellWindow and observe both toggles. A108/A121/A123/A126/A127 must show the plot hint, menu-owned suppression during the open menu, and the exact restored sweep text on close. Actual pointer movement enters/leaves the plot and gutter; no claim/clear calls stand in for delivery. A054/A056 and gesture-hover A030 retain both leave transitions.
- Complete contract/crosslane/parity snapshots with independently captured serialized full-song bytes, revision, history index/count and exact points. The Tempo unchanged-value move lands at tick 192 with its original microseconds, not a BPM roundtrip; same-tick CC values remain [10, 20] in order. The selected-range move yields points [(0,80),(144,100),(240,64),(384,110)] and interval [144,336). Sweep, Shift ramp, pencil and right-button band each prove their own release and exactly-one-edit result. Retain all existing per-lane table rows; a Tempo result cannot supply CC evidence.
- For row/geometry rebuilds use the existing production refresh/parameter/session change ingress while held, then deliver the stale release. There is no write, history change or surviving band preview; the next press/move/release works. Keep typed parameter identities stable. Numeric LaneHandle indexing/body lookups are obsolete representations, not permission to add an index API.
- Node-drag A026–A034 observes Arrow cursor and the held-value curve before/after phantom movement: both spans exceed twice the independently resolved hit radius, vertical change exceeds half one physical pixel, and its sign follows the pointer. A055–A057/A067 observes transient visible during drag then absent after cancellation, with no lingering selected-lane band. Hover A133/A141/A142/A143 uses the actual hit/dip location and the independent expected midpoint, never a self-comparison.
- Only native fixture pointers, LaneHandle arithmetic, capture-helper success, shortcut-registry plumbing and obsolete layer revision counters may retire: hover A002/A003/A007/A014/A024/A030/A034/A035/A045/A050/A059–A062/A075–A078/A080–A082/A085–A089/A097/A098/A107/A113/A128/A130; contract A062/A064/A065/A067; crosslane A002; hover-contract A002. Retain behavioral grab/cancel/visibility clauses in mixed rows. A006/A015/A016/A020/A022/A032/A084 require the replacement grab lifecycle before their native-object component retires.

# Implementation steps

1. Extend the existing registered domain cases at held/release/cancel boundaries, reusing their fixture and expected tables rather than duplicating neighboring passing checks.
2. Extend shell-drawer-parity with real focus/deactivation, shortcut, menu and pointer journeys; preserve the existing actual ShellWindow dispatcher.
3. Repair only demonstrated transaction/hover publication or QML delivery defects in the declared owners; keep 118’s new state ownership separate.
4. Give the separate ledger writer the executed conjuncts and bounded representation decisions for the six selected ledgers. Delete a ledger only after its whole inventory, including any pre-existing native obligations, is closed.

# Acceptance predicate

The registered automation domain/canvas checks and mounted shell-drawer-parity journey execute every selected transaction and ownership clause, including successful recovery after stale release. Task 119 can depend on those producers without changing key authority.

The implementer runs these exact covering lanes under §13’s build-lock policy; the controller runs the settled-group full gates:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-drawer-parity --verbose
```

# Task-specific constraints

No AutomationPage.swift, application/session, registration or fixture-content writes. The 93-row exception is one verification surface spanning existing hover/gesture ledgers, not permission for unrelated automation cleanup.

Read sprint-3 §13 “Evidence and execution contract” as part of this brief: real input; independent expectations; no setup-only assertions; exact raster colors/positions and executed DPR2 where claimed; no shell dispatcher in editorqml; verbatim existing and unique complete new messages; all exact-content fixture consumers updated; copied-fixture isolation for shared bank leases; implementer-owned locked lanes; separate ledger writer.
