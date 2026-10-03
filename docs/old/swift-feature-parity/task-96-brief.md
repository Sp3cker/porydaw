# Task 96 brief — mounted automation hover topology and hint recovery

# Context

Own the automation drawer's passive/active hover presentation: insertion guide,
held-value ghost, node ring, value text, cursor/focus, accessibility description
and mouse-hint ownership across pencil mode, menus and cancellation. Consume
92's accepted gesture contract without changing its mixed-range edit behavior.

Verified selection: **36 open rows (17 GAP + 19 PARTIAL)**:

- `src/checks/automationgesturecheck/proof.hover.txt`: 17 — A003, A005–A008,
  A011, A012, A014, A017, A023–A030.
- `src/checks/automation/hover/proof.tst_automationhover.txt`: 17 — A011,
  A037, A041, A052, A064, A068, A099, A104, A108–A112, A121, A123, A126,
  A127.
- `src/checks/automationgesturecheck/proof.parity.txt`: A018, A019.

Use hover/parity's pinned `7430fb426d466be20dd3a5e816cb2081c0e9135f`
`src/checks/automationgesturecheck/hover.cpp` and `parity.cpp` (the split files
are absent at `fceecd88`), plus the legacy hover ledger's pinned
`src/checks/automation/hover/tst_automationhover.cpp`. Current seams are
`drawerAutomationHoverModel`, the menu-hint checks,
`drawerAutomationNodeDragAndPhantomOutcomes`, `AutomationLifecycle.applyHover`,
`AutomationOverlayPublication`, and `AutomationPage.qml`'s real plot/ring/label
items. `tst_EditorDrawer.qml` already has
`test_productionAutomationHoverThroughInput`,
`test_automationHintsRetainGrabOrigin` and ghost-curve raster journeys.

# Exact write set

- `src/swift/app/drawer/automation/AutomationInteraction.swift` — conditional hover/phantom/cancel repair.
- `src/swift/app/drawer/automation/AutomationLifecycle.swift` — conditional hover publication repair.
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift` — conditional guide/ring/text repair.
- `src/ui/songview/quick/drawer/AutomationPage.qml` — conditional mounted hover/hint repair.
- `src/checks/automation/automationcanvashover.swift`
- `src/checks/automation/domain/gestureNodeDragPhantom.swift`
- `src/checks/editorqml/tst_EditorDrawer.qml`
- `src/checks/automationgesturecheck/proof.hover.txt` — selected 17 rows only.
- `src/checks/automation/hover/proof.tst_automationhover.txt` — selected 17 rows only.
- `src/checks/automationgesturecheck/proof.parity.txt` — A018/A019 only.

No ShellWindow, router, selection-command, palette, fixture-content or
registration changes. In particular, `tst_ShellWindow.qml` belongs to 95
and `tst_ShellGridInput.qml` belongs to 97 in Group B.

# Prerequisites

Start after the accepted Group A checkpoint; rebase `AutomationInteraction.swift`
over 92 and preserve 85's node-drag behavior. Rebase reads of 84's
`DocumentWorkspace.swift` page binding, 86's `EditorSurface.qml` press-focus,
87's ShellWindow keyboard priorities and 89's `DocumentSession.swift`.
All 84/86/87/89 must already have landed; none runs concurrently with this task.

# Interface contract

- Keep existing page pointer, hover, cancel and hint-publication APIs. A real
  pointer move shows the guide at the expected root-content x within one
  device pixel; inter-node hover paints the held-value filled ghost, insertion
  line and value label. Existing-node hover shows ring/value text and suppresses
  the insertion ghost. Cover both ordinary CC and Tempo lanes.
- The actual mounted input has a meaningful accessibility description. A
  handled press gives that input real focus; leave restores the neutral cursor
  and clears dirty hover items. Window-deactivation cancellation ends the live
  gesture; subsequent move visibly restores passive hover.
- Repeated hover at the same coordinate preserves the existing retained hover
  state/build count. Use the existing observable count/model, not a new probe
  or a new idempotence/coalescing guard. Lane transition and leave clear all
  guide/ghost/ring/text state, not just one visibility flag.
- Held-B pencil mode activates and releases correctly. Plot hints are owned by
  the actual plot and are meaningful; phantom/node/sweep/pencil modes publish
  distinct operational hints. An open menu owns hints, retains them through
  its interaction, and returns ownership/text to the prior sweep on dismissal.
  Test ownership/transitions, not incidental literal UI wording.
- An origin phantom hover keeps the arrow cursor. Pressing and moving it
  publishes a changed visible preview curve at each required stage. Do not
  mistake the deleted native layer's revision counter for a new bridge API.
- Hover A007 alone is RETIRED-REPRESENTATION: the deleted native render-layer
  revision integer, with sibling A005/A006/A008 proving fresh mounted output.
  The remaining 35 rows are behavioral. A019 still requires actual original /
  moved curve publication and raster change; its native revision bookkeeping
  is not grounds to retire the curve outcome.

# Implementation steps

1. Extend existing Swift hover/menu/phantom checks with separate literal
   anchors for each selected state/ownership/curve clause. Preserve old
   messages and the existing real automation fixture constructors.
2. Extend the existing production-phase `tst_EditorDrawer.qml` journeys with
   real pointer, B press/release, menu and cancellation input. Sample visible
   ghost/ring/curve output as well as item state; keep container-phase checks
   isolated and do not insert a fake page or fake hint owner.
3. Repair only demonstrated divergence at the named owners. **RED may be
   absent if production already matches; then the check is the deliverable.**
   Preserve 92's transaction behavior and existing cancellation ownership.
4. Update the 36 selected rows from fresh same-change evidence, including the
   single tightly scoped native revision retirement. Host grab/release counters
   A013/A015 and other unselected native rows remain untouched.

# Acceptance predicate

Controller-run after Group B settles. `swiftcore-projectsession` proves page
state/ownership; `verify:qml` runs the real production editor-drawer phase and
must record the added mounted functions in `editorqml-drawer.json`.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

All processes are ≤180 s, with a 175 s alarm after acquiring the serialized
build lock. Full shell (all 26 lanes, ~40 s warm) and full verify (~10 s warm)
are mandatory even though the task's mounted owner is the editor lane.
Require fresh evidence under `build/proof-evidence`; offscreen window
cancellation is not physical macOS host-ownership proof.

# Task-specific constraints

Incorporate sprint-3 §10: no new C++; Swift 6.4; comments ≤2 lines; base-font
sizing; WCAG AA beats pixel parity. One keyboard authority, no second
dispatcher, synthetic forwarding, focus memory or bare-Space chrome capture.
No `Qt.callLater` coalescing or new idempotence guards. One message anchor
per fork clause, existing messages verbatim, real fixtures and no test-only
seams. Preferences setup uses CFPreferences/UserDefaults, never plist bytes.
No fixture-content changes; any approved expansion must enumerate every
exact-content consumer first. Workarounds need user approval. Parked areas,
deferred menus and savecore A016–A026 remain excluded.
