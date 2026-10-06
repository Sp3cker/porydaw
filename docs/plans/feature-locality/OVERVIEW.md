# Feature locality — investigator overview

Worktree `.worktrees/swift-token-plans`, branch `feature/swift-token-plans`, HEAD 88f7bea5.
Question: **is "one concept, one owner type" the best lever for agent reading cost, or one of several?**
Method: 12 read-set traces of realistic agent questions (files opened, lines needed, opened-file
totals, per-file cause attribution). Read-only; plans only. Companion evidence:
`local://feature-locality-evidence.md` (git co-change stats, hub files) + this plan set.

## 1. Verdict: one of several — and not the biggest

Concept ownership (cause **a**) explains **~15%** of measured excess reading. It is the strongest
*structural* lever (the only one that removes whole files from read sets), but two cheaper levers
beat it on cost-effectiveness, and the largest cause (**c**, ~50%) is only reachable through them:

| Rank | Lever | Cause | Share of measured excess | Questions fixed (effect) | Risk | Size | build_impact |
|---|---|---|---|---|---|---|---|
| 1 | **Area maps** (01) | g (+f, e discovery) | ~10% direct; converts whole-file reads to range reads | Q1–Q4, Q7–Q12 discovery phase (9/12). Q5 (map-covered) opened 629 vs Q2 (same shape, unmapped) 4,013 wc — 6.4× | trivial (docs) | small (~5 files) | **neutral** — docs only, no compile units touched |
| 2 | **Cohesion-first file rule** (AGENTS.md wording) | b | ~5% direct + unblocks (c) fixes the 600 ceiling now discourages | Q3, Q8, Q9, Q11 fragment near-misses (`+Close` 291 ln opened for 0 needed) | zero code; **adopted** (AGENTS.md `## Files and modules`) | tiny | **neutral** — wording; module-graph placement rules |
| 3 | **Concept owners** (02–04) | a (+buried c) | ~15–18% | Q1 (beat-math slice 674→~60 ln, addressability), Q2 (policy 3 files→1, −~160 opened), Q4 (−~640), Q7 (−~490) — all [INFERENCE] estimates | medium (core edits near pinned ports) | medium | **neutral** — new small compile units in cold files (PlaybackTimeline 6, TimeAxis 10, AudioRenderEngine 6 commits); no new modules/targets; fan-in edits rare |
| 4 | *(c) residual megafiles* | c | ~50% raw, ~half reachable via levers 1+3 | composers (DocumentWorkspace 518, ShellPresenter 535, EventListPresenter 598) stay multi-concept by nature | — | — | — (accepted; no action) |
| 5 | Checks map only (inside 01) | f | ~6% | Q12: CMake 643 ln read for 20 needed | trivial | tiny | **neutral** — map only |
| — | *Checks physical reorg* | f | (same) | — | **REJECTED**: rewiring runner lanes risks build/AOT churn for zero read win a map doesn't give | large | **increase risk** (new runner targets/AOT/link) |
| — | *Session surface reduction* | d | ~2% | — | **REJECTED**: ApplicationSession is the hottest file (88 commits); moving bridged members forces QtBridge regen + QML churn | large | **increase risk** (bridge codegen rebuild) |
| — | *Hop removal (standalone)* | e | ~14% raw | — | **REJECTED standalone**: QML routing rework on hot chrome; the actionable subset (Q2 mask hops) is inside 03 | large | **increase risk** |
| — | *WavExportJob move to app-audio* | a | — | — | **REJECTED**: capture types import PorydawDocument/PorydawProject; AppAudio links neither (app/CMakeLists.txt:275) — would reverse dependency | — | would **increase** (new cross-module edge) |

Build-time gate (user hard constraint, applies to every lever): no lever here adds a module, target,
QML import, or dependency edge. Lever 3 adds small files inside existing targets. The adopted
AGENTS.md placement rules (one-consumer code stays in its module; no new dependency edges;
narrow `internal`-first surfaces) keep every move inside this gate. `needs measurement`: none —
no accepted lever is rated increase; if execution wants confirmation, time
`deno task build:app` and one incremental edit in each touched target before/after 02–04.

## 2. Measured read sets (12 questions)

`opened` = full-file lines of files an agent realistically opens; `needed` = line ranges that
decide the answer. Row sums recomputed from range tables over wc-verified totals (scout
self-sums were off); totals: 89 file-opens, 4,019 needed, 30,211 opened — **87% excess**.
Line totals wc-verified except where marked. Attribution codes:
(a) concept split across modules/parallel types, (b) size-driven `Type+Aspect` fragments,
(c) multi-concept file read for a small slice, (d) QtBridge body-rule forwarders,
(e) pass-through hops, (f) runner-organized tests / CMake registry hubs, (g) naming / missing map,
(h) other.

| Q | Question | Files | Needed | Opened | Dominant causes (evidence) |
|---|---|---:|---:|---:|---|
| 1 | 6/8 ruler beats | 12 | 810 | 3,390 | (c) PlaybackTimeline 674 for 5 needed (:145-149), RulerMenuPresenter 446/61, GridGeometry 525/124; (e) SceneSync/GridScene/EditorRulerBand forwards ~620; (f) CMake 325; (a) meter split core/document + `PlaybackTimeSignature`/`TimeSigPoint` parallel types; (d) prompt state on session |
| 2 | mute/solo | 12 | 516 | 4,013 | (c) TrackHeaders 640/106, Sequencer 561/59, DocumentSession 459/118; (a)+(e) sets→mask→policy across DocumentSession:135-143 → DocumentWorkspace:379-383 → NativeAudio:131-133 → AudioRenderEngine:242-250; (f) CMake 267 |
| 3 | WAV export | 15 | ~1,100 | 4,812 | (c) PlaybackTimeline 674/36, ApplicationSession 579/15, ShellPresenter 488/10; (a) settings composed in NativeAudio:179-181 + AudioRenderEngine:180-187 + WavExportPresenter:131-132 + WavExport:160-162; (e) entry routing ~630; (f) CMake 274; (b) session fragments |
| 4 | tempo point → timing + display | 9 | 556 | 3,445 | (c) SongDocument 565/22, PlaybackTimeline 674/139, Sequencer 551/81, AutomationLaneProjection 411/13, EventListProjection 266/26; (g) negative finding (tempo does NOT move grid) costs TimeAxis+GridGeometry extra ~480; (a) BPM rounding duplicated ×3 |
| 5 | velocity lane edit | **2** | 28 | **629** | (c) VelocityInteraction 532/35 — best-in-class because `drawer/README.md` maps the area |
| 6 | roll drag threshold | 2 | 33 | 1,253 | (c) PianoGrid+Gestures 830/26 (post plan-02 merge), PianoGrid 423/7 |
| 7 | event-list BPM cell | 6 | 236 | 2,432 | (c) EventListPresenter 598/22, SongDocument 565/55; (e) QML cell/page/presenter ~640; (a) one edit contract split EventListModel:215-254 + EventListEditing:37,:71-82 |
| 8 | save flow | 8 | 115 | 1,764 | (c) ShellPresenter 535/10, DocumentSession 459/25, ProjectService+Bank 276/27; (b) must know `+Commands` is the save aspect; (e) ProjectStore 34/3 |
| 9 | shell command + shortcut | 5 | 123 | 1,960 | (c) ShellPresenter 535/43, ShellContent 315/14, ApplicationSession 579/3; (e) TransportBarPresenter 290/4 hop; (a) KeybindingRegistry 241/46 separate from dispatch switch ShellPresenter:155-206; (d) session `play()`→`playImpl()` :528-530 |
| 10 | note-overlap rule + scale snap | 4 | 202 | 1,568 | (c) PianoGrid+Gestures 830/32, NoteEditing 463/99; NoteCollision 77/77 — plan-03 kernel working as designed |
| 11 | open song / tab policy | 11 | 210 | 3,624 | (c) DocumentWorkspace 518/32, SongTabsController 460/26, DocumentSession 459/15, SongListPresenter 455/35; (b) `+Close` 291 opened for 0 needed, `+ProjectOpening` near-miss; (e) SongDockController 231/6; (g) policy hides in +Tabs:132-144 |
| 12 | add velocity regression check | 3 | 90 | 1,320 | (f) checks CMake 643/20; (b) suite split `tst_velocityediting` 409 + `VelocityPageChecks` 268; (g) runner-named dirs, no checks map |

Cause rollup (overlapping primary-attribution estimates; shares sum >100% by construction, ±10%):
**(c) ≈13,600 (52%) · (a) ≈3,900 (15%) · (e) ≈3,600 (14%) · (g) ≈2,600 (10%) · (f) ≈1,500 (6%) ·
(b) ≈1,300 (5%) · (d) ≈600 (2%)**.

Q5-vs-Q2 is the controlled comparison for maps: both are "edit a UI-lane concept" questions; the
drawer area has a README map, headers/audio does not — 629 vs 4,013 opened lines. The map is
necessary for that gap but not sufficient (Q2 is also cross-module) — [INFERENCE].

## 3. File-size rule assessment (AGENTS.md:75-78)

Current: *"Target 200–400 lines per file; review cohesion above 600. One concept per file
(`src/swift/app/drawer/` is the model). No 80-line fragments either."*
Note: `.omp/rules/keep-files-small.md` already encodes this cohesion-first policy for agents
("Never move or split code solely to satisfy a line-count target"; "A cohesive file may exceed
600L"). The adopted section aligns AGENTS.md with the rule the repo already enforces; it adds the
fragment ban and module-graph placement rules the .omp rule leaves implicit.

Measured:
- Size-driven splits (b) explain **~5%** of excess (Q3 session fragments, Q11 `+Close`,
  Q12 suite split, Q8 fragment targeting).
- Over-large multi-concept files (c) explain **~51%** — the rule's *numeric* halves (200–400
  target, 600 review, no-80-fragments) neither caused most of the excess nor fix it; the
  *"one concept per file"* half is the load-bearing clause.
- The ceiling **blocks** (c) fixes: the executed plan-02 merge left `PianoGrid+Gestures.swift`
  at 830 lines — exactly the consolidation Q6 needs — sitting above the review line.
- Splits are not inherently harmful: velocity's 9-file lane reads at 629 opened *with a map*;
  `ApplicationSession+8` reads badly *without* one and because fragments are aspects, not concepts.

**Adopted (user-approved):** AGENTS.md `## Files and modules` replaces the old section. It keeps
cohesion-first sizing and the fragment fold-back rule, requires the area map update in the same
change, and adds module-graph placement (lowest common importer for shared concepts, one-consumer
code stays put, no new dependency edges, `internal` by default, new modules only to cut a
dependency on `PorydawApp`).

## 4. Plan files and execution order

1. `01-area-maps.md` — lever 1 (+ checks map, + drawer README label fix). Direct route. First:
   instant payoff, zero risk, and later levers' read-set wins are only observable with maps in place.
2. AGENTS.md `## Files and modules` — **done** (user-approved; see §3).
3. `02-meter-ownership.md` — lever 3a: core `Meter` owner; Q1/Q4 read sets shrink.
4. `03-trackmix-audio-policy.md` — lever 3b: effective-mask policy owner in `AudioRenderEngine`; Q2.
5. `04-small-concept-owners.md` — lever 3c: event-list cell-edit policy; tempo BPM display rounding; Q7/Q4.
6. `05-feature-dotted-quarter-beats.md` — **FEATURE, not a refactor**: compound-meter ruler display.
   Only on explicit user approval; sequenced after 02 which gives it an owner to live in.

Milestones: commit after 01 (docs); checkpoint 02+03 together (structural, disjoint write sets);
04 anytime after 03; 05 last. Verification policy once, here: implementers reuse the recorded
`deno task` commands per brief; `deno task build:checks` precedes the first check run after any
CMake source-list edit; `deno task format --check` on changed files; `deno task checks:bridge`
after any file that touches a `@QtBridgeable` class body (none planned in 01–04).
Maps stay honest by review, not CI: any change touching a mapped file re-resolves that map's
citations for the touched rows (01 acceptance item 4).

## 5. Rejected options (with reasons)

- **Drawer-lane kernel, NoteEditing emitter merge, ThemeColorTables rewrite** — settled earlier
  (docs/plans/swift-token-cost/); not reopened.
- **Checks physical reorg by feature** — build risk (runner lanes/AOT), zero measured read win
  beyond the map; Q12's cost is the registry *read*, which the map removes.
- **ApplicationSession surface reduction** (move prompt/presenter bridged members out) — hottest
  file (88 commits), QtBridge regen, QML churn; measured share ~2%; the session map (01) captures
  most of the discovery win without code.
- **WavExportJob → app-audio** — dependency direction (AppAudio links Core/Playback only,
  app/CMakeLists.txt:275); rejected in the Q3 trace itself.
- **Wholesale splitting of composer megafiles** (ShellPresenter, DocumentWorkspace,
  EventListPresenter) — they are genuine multi-concept composers; splitting produces aspect
  fragments (b) without a concept boundary; maps + range reads are the correct cure.
- **Tempo structural consolidation** — Q4's spread is projections of one canonical owner
  (`SongDocument.state.tempo` + `PlaybackTimeline` conversion), unlike C++'s four-way split;
  the measured excess is (c)/(g). Map (01) + BPM-display dedup (04) cover it.

## 6. Assumptions / open items

- Read-set traces approximate a competent agent doing directed discovery (LSP/grep with `path`);
  lazier agents make maps look better, stricter ones slightly worse — [INFERENCE] on absolute shares,
  ordering is robust.
- Post-change read sets quoted in briefs are estimates against the same 12 questions, not
  re-measured — [INFERENCE].
- **Open user decision — song-settings resolver (Q3's largest (a)-slice)**: composition is split
  across `NativeAudio.songSettings` (:179-181), `AudioRenderEngine.applySettings` (:180-187),
  `WavExportPresenter` (:131-132), `WavExport` (:160-162). Option A: 04 task 3 making
  `NativeAudio.songSettings` the single resolver. Option B: accept the split with a stated reason.
  Not decided here; pointer recorded in 04.
- Q10's scale-snap request is a feature, not a locality lever; recorded in 01's roll map as the
  pointer pair (`PianoGrid+Gestures.swift:407-420` pitch construction + `MusicalScale.swift:35-69`),
  not planned here.
- Scout line totals were wc-verified by the controller where cited without `[INFERENCE]`;
  `EventListPresenter` 598, `TrackHeaderRows.qml` 334 conflicts resolved in favor of wc.
