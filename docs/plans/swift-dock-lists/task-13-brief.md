# Context

Reconcile the seven `voicegroupsave` assertion inventories and the historical visual browser inventory against the Swift/QML checks delivered by tasks 5–12. This task changes evidence records only; behavior and runnable predicates must already be complete. The assertion ledgers are source-oracle inventories and remain in the repository after task 17 retires native-only check sources.

Task 14 separately owns all seven `samplecheck/proof.*.txt` ledgers and the sample-specific `proof.dialogs.txt` sites. Task 15 owns viewcache parity; task 16 reconciles the viewcache proof ledger. Do not edit those files here. Task 17 retirement is blocked until tasks 13–16 parity/proof gates are green.

# Exact write set

- `src/checks/voicegroupsave/proof.editor.txt`
- `src/checks/voicegroupsave/proof.fixture.txt`
- `src/checks/voicegroupsave/proof.picker.txt`
- `src/checks/voicegroupsave/proof.presentation.txt`
- `src/checks/voicegroupsave/proof.savecore.txt`
- `src/checks/voicegroupsave/proof.switching.txt`
- `src/checks/voicegroupsave/proof.synth.txt`
- `src/checks/visual/proof.browsers.txt`

Do not edit `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt`, `src/checks/visual/proof.dialogs.txt`, any samplecheck ledger, source file, or frozen visual fixture. Preserve the historical source/context/provenance in every proof file.

# Prerequisites

Tasks 5–12 and their scoped SwiftCore, SwiftRollGated, and visual-swift predicates must be green. Task 9 supplies voicegroup creation; task 10 supplies sample actions/browser pins; tasks 11–12 supply sample processing/editor contracts used by the voicegroup picker checks. Task 14's sample-ledger work and tasks 15–16's viewcache work are separate from this task's edits; complete tasks 13–16 before task 17 retirement.

Previously executed headless SwiftCore predicates may support truthful
per-site partial mapping before this final gate; keep all unproved sites
`GAP`. Such mapping does not satisfy this task's prerequisites or allow
source retirement.

# Interface contract

- Update the existing `A###` records in place. Preserve every original source assertion expression, source path/line, branch/loop/fixture context, source hash, and surrounding sequence. Do not delete/reorder sites, regenerate them from counts, flatten branches, or replace the source oracle with a summary.
- Each site receives its own truthful `Disposition` and `Mapping/reason` naming the exact Swift check, SwiftRollGated/QML slot, or visual scenario that exercises that observation. Method ranges below are navigation aids only: they do not authorize a bulk “MATCHED” declaration. Never claim a method/file is matched unless each site has an actually executed counterpart; keep fixture setup and pixel comparisons distinct from presenter state checks.
- After task-owned check sources are frozen, replace each header's `Swift counterpart: none identified`/`Swift SHA-256: n/a` with the exact supporting Swift, SwiftRollGated, or visual-check source and its SHA-256. When one ledger spans multiple sources, record the primary and each `Additional Swift counterpart` with its own `Swift SHA-256` in the parser-supported multi-source format. Preserve `Original SHA-256` and reference-revision fields unchanged until task 17 retires only wholly proved ledgers.
- Add exact runnable predicate names to each mapping:

  | Proof inventory | Site range → required Swift/QML check identity |
  |---|---|
  | `proof.editor.txt` | A001–A010 `releaseEditorUsesBankUndoPipeline`; A011–A024 `blankTemplateMaterializesUndoably`; A025–A026 SwiftRollGated slot `dockMinimumWidthIsFamilyInvariant`; A027–A032 SwiftRollGated slot `adsrFieldSpaceTogglesTransport` |
  | `proof.fixture.txt` | A001 `isolatedFixtureSettingsAreResolved`; A002 `copiedFixtureProjectOpens`; A003 `fixtureAudioEnginePlayPauseRoundTrips`; A004 `fixtureSongTimelineIsOpenAndReady`. Each is a separate SwiftRollGated native-fixture setup assertion; retain `NATIVE` because these are environment/setup observations, not product parity claims. |
  | `proof.picker.txt` | A001–A027 `samplePickerAuditionsAndCommits`; A028–A032 `samplePickerKeysplitAuditions`; A033–A047 `samplePickerWaveModeAuditionsAndCommits` |
  | `proof.presentation.txt` | A001–A011 `revealsTrackProgramsAndUsedMarks`; A012–A031 `quickHeaderPressSurvivesVoicegroupRebuild`; A032–A037 `newVoicegroupCreatesAndAssignsUndoably`; A038–A080 `typeColumnMapsEveryFamily` |
  | `proof.savecore.txt` | A001–A015 `failedRebindRetainsBinding`; A016–A026 `catalogOutageRetainsLastValid`; A027–A031 `releaseEditDirtiesOnlyBank`; A032–A045 `undoShortcutRestoresWithoutWrite`; A046–A052 `unifiedSavePersistsSongAndBank`; A053–A067 `queuedSaveSnapshotPreservesNewerEdit`; A068–A076 `undoSaveRoundTripsBankBytes`; A077–A081 `cleanSaveEmitsNoReceipt` |
  | `proof.switching.txt` | A001–A007 `switchCarriesUnsavedBankEdit`; A008–A016 `selectorSwitchUsesUndoableCfgEdit`; A017–A029 `valueCommandSurvivesSourceReplacement`; A030–A046 `blankTokenRebasesAcrossSourceReplacement` |
  | `proof.synth.txt` | A001–A042 `synthDefinitionsStayMemoryOnlyUntilSave` |
- SwiftCore identities use `cppID` `vgsavecheck/VoicegroupSaveTest::<method>` for each listed method; SwiftRollGated mappings name the exact slot and carry the original source-method identity. Task 9 reserves `vgsavecheck/VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably` for full file creation/catalog/assignment/undo-redo behavior; the intent-only `newVoicegroupIntentReachesOwner` is not a counterpart for that proof method.

- `src/checks/visual/proof.browsers.txt` remains the old visual-source oracle. Map every site to the matching task-owned Swift/QML fixture or visual predicate, preserving its original site identity. `VisualBrowsersTest::initTestCase` A001–A007 map separately to the exact setup predicates in both visual slots `voicegroupBrowserVanilla` and `voicegroupBrowserDark`: A001 `browserProjectOpensFromFixtureRoot`, A002 `browserSongNameIsValid`, A003 `browserSongIsPlayable`, A004 `browserBankLoads`, A005 `browserLoadedSongLoads`, A006 `browserSongViewRigCreates`, and A007 `browserCatalogSamplesAndUsedVoicesPopulate`. `VisualBrowsersTest::browserBaseline` A008 maps theme application and A009 maps both full 420x680 `voicegroupbrowser/vanilla` and `voicegroupbrowser/darkneutralhigh` captures, preserving every frozen region name/bound including `vgNewSampleButton`, `vgEditSampleButton`, `editor.sample.new`, and `editor.sample.edit`. `VisualBrowsersTest::editorVariants` A010 maps theme application in `voicegroupBrowserEditorVariants`; A011 maps the `editor-square1` and `editor-readonly` rows to their exact variant/theme baselines. `VisualBrowsersTest::samplePickerPopup` A012 maps theme application in task 8's `samplePickerVanilla`/`samplePickerDark` visual slots; A013 popup opening, A014 lookup of `vgSamplePickerList`, A015 visibility, A016 the 340-pixel minimum width and 420-pixel maximum height, and A017 close-after-hide each map to task 8's SwiftRollGated slot `samplePickerPopupLifecycle`; A018 maps both `samplepicker/vanilla` and `samplepicker/darkneutralhigh` screenshots with the `vgSamplePickerList` region to the named visual slots. Preserve the original `kThemeVariants`/editor-variant data rows, theme input, and popup geometry assertion at each site.
- Keep all original site IDs and provenance even when the C++ check source is later deleted. A current `GAP` may become `MATCHED` only with its named Swift/QML predicate and observed run. A screenshot site is not covered by a model predicate; use the exact visual scenario and frozen baseline. A setup site is not evidence for product behavior.
- In `proof.savecore.txt`, A068 asserts that the release spin box exists; leave this UI site for the real QML editor, not a headless substitute. For A069–A076, the existing `bankSaveRoundTrip` SwiftCore check restores bank bytes but does not reproduce the original interleaved song-note undo and two-resource dirty/clean sequence. Add executable observations of that sequence before mapping its unproved sites; do not count a shared `cppID` as equivalence. A077–A081 additionally require an initially clean document and selected bank followed by a no-op save with no new save receipt; bank byte round-trip does not prove that condition.
- Task 8 and task 10 own the picker and browser visual runtime checks. Consume their already-green `visual-swift-12`/`visual-swift-16` receipts, including task 10's `voicegroupBrowserVanilla`/`voicegroupBrowserDark` setup assertions; do not rerun visual checks here. Then run only `deno task proof check` as the structure-only gate after all runnable checks are green. It validates ledger syntax and site provenance, not behavior.

# Implementation steps

1. Compare each of the seven voicegroupsave ledgers to the exact task 5–12 check implementation and actual invocation name; identify the matching predicate before changing its record.
2. Reconcile each `A###` independently using its original expression and branch/fixture context. Map the four fixture sites to four Swift harness checks and each data-driven browser row to its distinct baseline ID.
3. Reconcile all visual browser A-sites while retaining the source-oracle record and immutable screenshot baseline IDs. Leave editor dialog sample pins to task 14.
4. Preserve all source hashes/context and complete a per-site audit: 332 voicegroupsave assertions plus every existing visual-browser assertion still has one record and a runnable named counterpart or its truthful native setup status.
5. Run only `deno task proof check` for this documentation change; do not use it as evidence that any behavior check ran.

# Acceptance predicate

- All 332 voicegroupsave sites are individually mapped to their named Swift/QML check identity, except the four justified native fixture-precondition sites: A001 `isolatedFixtureSettingsAreResolved`, A002 `copiedFixtureProjectOpens`, A003 `fixtureAudioEnginePlayPauseRoundTrips`, and A004 `fixtureSongTimelineIsOpenAndReady` each name a live SwiftRollGated setup assertion and remain clearly classified as setup.
- Every assertion site in `src/checks/visual/proof.browsers.txt` has a precise mapping to the appropriate task-owned Swift/QML fixture, popup behavior, or frozen visual scenario; no native site is dropped or represented by a count-only claim.
- Original assertion text, file/line, source-context, branch/row constraints, original source hashes, and frozen baseline references remain intact. `proof.browsers.txt` and all seven ledgers remain present as historical source oracles.
- `deno task proof check` passes structurally. Feature evidence comes only from the named task 5–12 runnable receipts, including task 8's picker and task 10's browser/sample-editor visual runs; proof parsing is not behavioral evidence.

# Task-specific constraints

- No source, test, visual baseline, or samplecheck-ledger edits. If a named predicate is absent or its behavior does not match the original expression, leave that site as an explicit GAP and stop the relevant retirement gate; do not invent a mapping or dilute the assertion. Report the missing predicate by exact ledger/site and owning task.
- Do not mark all sites in a method/file `MATCHED` from one related check. Preserve a separate updated disposition and reason at every original assertion site.
- Keep Task 14's sample ledgers and `proof.dialogs.txt` sample editor A010–A015 out of this write set; the source inventories are disjoint.
