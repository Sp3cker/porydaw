# Task 104 brief — automation lead-in, step curves and pencil commit raster

# Context

Own the mounted automation curve from empty lane through first point, tick-zero promotion, half-open selection and pencil commit/restore. Consume 100's accepted selection/capture contract; this task supplies the remaining pixel and timeline/history conjuncts, not a new renderer.

Verified selection: **45 open rows (35 GAP + 10 PARTIAL)**, all remaining open rows in:

- `src/checks/automation/proof.automationpainting.txt` — 32 (30 GAP + 2 PARTIAL): A002, A007, A008, A011, A013, A016–A018, A021, A023, A026, A027, A031, A032, A035–A038, A044–A048, A053–A061.
- `src/checks/automation/proof.automationpencil.txt` — 13 (5 GAP + 8 PARTIAL): A003–A005, A017, A026, A043, A049, A050, A053, A057, A058, A068, A069.

Both matching C++ paths are pinned at `c17d966fbf56b1cccb2c1112b7eef84bec1dc7ac`; use that exact assertion extraction with fork `fceecd88`. Selected painting clauses are in ledger :22–568; pencil clauses :32–66, :113–120, :154–168, :233–240, :263–325, :359–375. Both originals are already deleted in `31ea635`.

# Exact write set

- `src/swift/app/drawer/automation/AutomationInteraction.swift` — conditional pencil completion repair.
- `src/swift/app/drawer/automation/AutomationDrawingTransactions.swift` — conditional pencil tail/commit repair.
- `src/swift/app/drawer/automation/AutomationContentPublication.swift` — conditional lead-in/step/node/selection paint repair.
- `src/swift/app/drawer/automation/AutomationOverlayPublication.swift` — conditional preview publication repair.
- `src/ui/songview/quick/drawer/AutomationPage.qml` — conditional curve/node paint repair.
- `src/checks/automation/presentation/painting.swift`
- `src/checks/automation/domain/gesturePencil.swift`
- `src/checks/automation/automationselection.swift`
- `src/checks/editorqml/tst_EditorDrawer.qml`
- `src/checks/automation/proof.automationpainting.txt` — selected rows; delete after closure.
- `src/checks/automation/proof.automationpencil.txt` — selected rows; delete after closure.

No `AutomationPage.swift`, popup/prompt owner, registration, fixture, palette redesign, shell or unrelated ledger changes. Task 106 owns prompt ingress separately in Group B.

# Prerequisites

Start after all 91–98 and the accepted Group A checkpoint. Rebase interaction/publication/QML/editor checks over 96 then 100, and `automationselection.swift` over 92 then 100. Preserve 92's precise Tempo/raw-event laws, 96's hover topology and 100's captured selection. The Group B prompt owner must not change these files.

# Interface contract

- Preserve `publishContent`, `appendCurve`, `nodeHandles` (`AutomationContentPublication.swift:107–132,229–304`), `publishPreview` (`AutomationOverlayPublication.swift:87 onward`) and existing pointer signatures. Published rectangles are not themselves proof of painted pixels.
- An empty Tempo lane has no default curve or tick-zero node. A first nonzero Tempo point paints the held default lead-in at 120 BPM but no synthetic origin marker; its actual written marker uses lane ink. Once a real tick-zero point exists, its marker paints and the pre-zero lead-in does not. Real CC step segments and written-node markers paint the same lane ink. Sample meaningful line/marker positions derived from the mounted font/DPR/camera.
- A selected node paints its highlight ring and selection edge/reticle. A half-open range includes its first node, excludes the endpoint and later node; extending the endpoint includes the second node and still excludes the third. Require independent positive/negative pixel clauses, never native layer revision values.
- An empty-controller pencil stroke projects its last value through the timeline within one unit. A stroke over existing Pan restores the baseline at the end-cell boundary in the timeline. Single clicks on ordinary CC, Tempo and Bend each advance revision and undo index exactly once; unchanged unrelated lanes, one undo and original bytes remain protected. Existing `drawerAutomationPencilStrokeModifiers` (`gesturePencil.swift:139–320`) and `drawerAutomationTempoBendClickRestore` (`automationselection.swift:483–535`) are the owners.
- Retire painting A002/A011/A021/A035/A036/A044/A053 (native lane/body prerequisites), A013/A023/A031/A032/A045/A046/A054/A058 (native mesh revision counters); pencil A003–A005/A053 (native input/body prerequisites), A026 (native transient revision). Exactly **20 representation rows** retire beside **25 executed behavior rows**; none of the ink/ring/reticle/timeline/history results may retire.

# Implementation steps

1. Extend `drawerAutomationPresentationPaintingModel` (`presentation/painting.swift:141–405`) and the existing pencil/click functions with missing timeline and exact history clauses. Keep document-derived expected values independent from the rendered model.
2. Extend the real production editor lane's pencil preview journey (`tst_EditorDrawer.qml:7770–7817`) and existing image-sampling helpers to cover every lead-in, marker, step and half-open ring law. Capture the actual curve/node/selection items (`AutomationPage.qml:338–423`), not an imitation component.
3. Fix only demonstrated selected-law divergence in the existing drawing/publication owner. RED may be absent; a new consumer-visible check then supplies the missing proof. No extra cache, coalescer or observation property.
4. Update selected mappings from executed evidence and retire only the specified prerequisites/counters. Delete both closed ledgers in this same surface change; original C++ sources are already absent.

# Acceptance predicate

`runAutomationPageChecks` registers painting/pencil/click checks (`AutomationPageChecks.swift:337,369–370,391`); `EditorQmlTests.swift:18–23` registers the production drawer lane. Swift proves committed timeline/history and editor QML proves actual raster before/after pointer input.

Controller-run on the settled group under sprint-3 §11 verification policy:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Require fresh `swiftcore-projectsession.json` and `editorqml-drawer.json` under `build/proof-evidence`. Full shell and full verify are mandatory, in addition to the mounted journey; each invoked process has a 175 s alarm and a 180 s ceiling after serialized lock acquisition.

# Task-specific constraints

Read sprint-3 §10 “Wave constraints and verification” and §11 “Inherited constraints and verification” as mandatory parts of this brief. They cover unique literal anchors, fixture-consumer boundaries, CFPreferences staging, honest absent RED, Swift 6.4/no new C++, two-line comments, base-font geometry, WCAG AA, keyboard priority, no `Qt.callLater`/idempotence guards/test seams, and approval before workarounds. All §11 exclusions remain unchanged.
Preserve 100’s selection rings and 96’s hover ink. Offscreen raster does not certify physical-monitor DPR or native host rendering.
