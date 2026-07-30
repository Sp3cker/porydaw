# 40 — Final verification

**Owner:** coordinator  
**Candidate base:** `HOST_SHA` on `feature/psg-velocity-history-upstream`  
**Candidate identity:** record one exact integration SHA before dispatching a
reviewer or executing a candidate command.

## Purpose and non-inputs

Close one integrated candidate, once.  This packet makes no production change,
has no task worktree, and never manufactures a staged, transport, or synthetic
candidate.  `plans/editor-drawer/` is historical only.  The normative
specification remains authoritative; oracle `52fd478` is UX evidence only and
MUST NOT be merged, cherry-picked, or copied.

A candidate rejected during final review before four same-SHA approvals receives
no native matrix or manual smoke. Only after all four final reviewers approve
the same exact candidate SHA does the coordinator perform that candidate's one
native proof and one visible **UX-01...UX-11** smoke. A failure found during
that post-approval proof is recorded against the candidate that already
consumed its one proof, then follows repair routing to a replacement candidate.
Reviewers do not run a full matrix, and no agent duplicates either proof.

## Preserved pre-implementation baseline

Before packet 05 or any implementation task, the coordinator builds and runs
the upstream-only source at the fetched `UPSTREAM_SHA` against the pinned
`hearth-test` fixture revision.  Use an immutable canonical fixture copied or
reflinked into one isolated scratch project and isolated settings, then record
one baseline roll invocation:

```text
<upstream-build>/porydaw --rollcheck <baseline-scratch-project> mus_lovely <baseline-roll-screenshot>
```

Record `UPSTREAM_SHA`, fixture revision, build/configuration identity, platform
mode, isolated-settings identity, exact command, exit result, named cases, and
screenshot.  This immutable `UPSTREAM_SHA` record—not a later foundation,
product, host, oracle, or mutable-fixture result—is the sole baseline input for
attributing a later pre-existing roll failure.  It is captured before
implementation and is not rerun as part of a candidate proof.

## Entry condition and final review wave

Begin with the integrated `HOST_SHA` only after the coordinator has recorded:

- the foundation entry chain `10A → parallel 10B/11 → DOCUMENT_SHA → 10C →
  CONTRACT_SHA`, followed by normal reviewed merges for 12A/12B/13, 14A/14B,
  and `FOUNDATION_SHA`;
- normal reviewed product merges and `PRODUCT_SHA`;
- the three-agent packet-30 host merge, its one merged-mini-wave aggregate
  focused host proof (including **CORE-03** forwarding), and `HOST_SHA`; and
- packet-05 registration for activated individual new-module commands plus
  the named existing-harness commands below, with no duplicate aliases.

Confirm the candidate contains ordinary commits only.  Record its exact SHA as
`CANDIDATE_SHA`; every final report, command row, screenshot, and acceptance
ledger entry uses that same SHA.

Dispatch these four `reviewer` agents concurrently.  They inspect
`CANDIDATE_SHA`, the normative specification, and recorded focused evidence.
They do not edit code, create a fixture, commit, or execute the final native or
manual proof.

| Review domain | Required audit | Acceptance covered |
| --- | --- | --- |
| Drawer and persistence | Drawer overlay/layout, tab behavior and exact messages, focus, active-tab isolation, event-list blocking, sidecar decode/merge/unknown-field preservation, validation/fallback, cosmetic-only state, and save boundaries. | **DRW-01...DRW-05**, **UX-01**, **UX-02**, **UX-10**, relevant **LIFE-01** |
| Automation | Hosted automation context, row/lane state, menu and pointer behavior, remaps, gesture cancellation, one-Undo/no-op behavior, and drawing/cache invalidation ownership. | **AUT-01...AUT-03**, **CORE-01**, **LIFE-01**, **UX-03**, **UX-04** |
| Velocity and accessibility | Duplicate-note identity, shared selection, revision-checked batch mutation, continuous/intrinsic behavior, exact stored values, status chips, accessible descriptions, and no extra focus targets. | **CORE-02**, **CORE-03**, **VEL-01...VEL-04**, **A11Y-01**, **LIFE-01**, **UX-05...UX-08** |
| Rendering and ownership | `layout` provenance/derived geometry, host/page ownership, dynamic timeline bands, overlay-only steady playback, allowed invalidations, follow-scroll pause/resume, lifecycle completeness, and exclusions/unrelated churn. | **LAY-01**, **DRW-01**, **LIFE-01**, **PERF-01**, **UX-09**, **UX-11** |

Every report **starts** with exactly one decision line:
`APPROVED <CANDIDATE_SHA>` or `CHANGES_REQUESTED <CANDIDATE_SHA>`. Its
traceability body follows that line. An approval lists the normative IDs and
evidence examined. A changes-requested report lists the normative ID, precise
observable failure or source location, evidence examined, and proposed narrow
repair owner. An approval is valid only if all four reports name the identical
`CANDIDATE_SHA`. The coordinator rejects the candidate if any report is
missing, starts with another decision/SHA, or lacks its required traceability.

### Cross-module closure

The four reports collectively, not merely per-module, must establish that:

- every **LIFE-01** event—page hide/switch, drawer hide/close, selected-track,
  song, document, or voice replacement, every mutation including Undo/Redo and
  reload, mouse-grab loss, deactivation, and Escape—reaches the active page;
  page-owned termination restores staged document/selection snapshots without
  MIDI/Undo change, clears preview/hover/grab/cursor, and retains applied
  pan/resize;
- **CORE-03** reaches the concrete host: 30A forwards the exact revision and
  `NoteId` batch; no-op leaves revision/MIDI/Undo/selection unchanged; stale
  input has no partial mutation; and successful values Undo exactly;
- for **PERF-01**, dynamic bands reach `PlayheadOverlay`; 120 warmed-up
  playhead-only updates advance to the requested final tick without automation
  or velocity content builds, while edit, selection, zoom, theme, resize,
  document, and voice changes reach the affected invalidation route; and
  follow-scroll pauses only for the drawer gesture and resumes on commit or
  cancellation; and
- the cross-owner **UX** paths cover drawer/persistence, active-tab shortcuts,
  event-list blocking, focus/announcements, automation and velocity
  interaction, intrinsic restoration, playback, and both base-font scales'
  geometry/hit testing.

## Candidate-based repair and mandatory restart

Route every finding to its narrow owner; do not repair it on the integration
branch:

| Finding source | Repair owner |
| --- | --- |
| packet-05 CMake registration, command dispatch, or generated dispatch header | `check-registration` (05) |
| `NoteId` declaration or identity transport through SMF/`TimelineEvent` | `note-identity` (10A) |
| `SongDocument` ID minting, complete `TrackRemap` publication, revision, or atomic batch mutation | `document-contracts` (10B) |
| `ViewNote` `NoteId` projection or duplicate-note projection characterization | `note-projection` (10C) |
| shared layout resolver values or clean-process base-font contract | `layout-resolver` (12A) |
| geometry-gate source audit, self-test, or fixtures | `layout-gate` (12B) |
| neutral seam contract only | `host-seams` |
| pure PSG canonicalization or axis model | `velocity-model` |
| shared SongView opaque selection, SongView-owned track remap state, or `SongView::ViewState` snapshot capture/apply DTO | `shared-host-state` (14A) |
| raw event-list SMF-chunk anchoring | `event-list-remap` (14B) |
| drawer shell | `drawer` |
| automation page/area | `automation` |
| velocity page/area | `velocity` |
| sidecar codec | `sidecar` |
| SongView module adaptation/lifecycle or `hostcheck` | `host-songview` (30A) |
| MainWindow shortcut, focus, or persistence routing | `host-mainwindow` (30B) |
| TimelineSurface/playhead dynamic-band rendering | `host-rendering` (30C) |

For every rejected `CANDIDATE_SHA`, `git-operations-runner` creates and verifies
the fresh repair branch and worktree
`repair/psg-velocity/<owner>/<candidate-short>` **from that rejected candidate
SHA**, including submodule initialization and verification (not from the owner's
historical task base or a prior repair). The assigned `task` implementation
agent commits implementation code and focused tests in that prepared worktree
without creating, resetting, or rebasing worktrees, and does not run validation.
The coordinator runs only the affected focused command(s) or direct-file
check(s), each once, obtains a focused review that names the repair commit SHA,
and normally merges it to create a replacement integration candidate. Record
the replacement SHA, then
rerun **all four** final reviewers in parallel against that one replacement SHA.
No repair reuses a stale base; no partial rereview is sufficient. Only after
all four approve that replacement SHA does it receive its one full final proof,
including aggregate host integration, and one visible smoke; that proof is not
inherited from the rejected candidate. Repeat this cycle for every finding,
including one discovered after a previous candidate proof.

## One coordinator-owned proof per approved candidate

After four approvals of one `CANDIDATE_SHA`, configure/build that exact
candidate once and execute the following native rows once. This applies equally
to an original candidate and to an approved repaired replacement candidate.
The packet-05 manifest is authoritative: run every activated **individual**
conditional new-module command, the aggregate host command below, and each
named existing-harness command below. The
[packet-05 Runner declaration column](05-check-registration.md#conditional-executable-groups)
is the authoritative exact `int run...` signature contract for every
conditional row, including `const QString &` inputs and declaration-only
`screenshotPath = QString()` defaults. The aggregate runner is exactly
`int runHostIntegrationCheck(const QString &scratchProject, const QString &songA, const QString &songB, const QString &screenshotPath = QString());`
in 30B's `src/mainwindowroutingcheck.cpp`; it is declared/dispatched only with
all three host macros and is a real integrated runner, not sequential aliases.
Every conditional-manifest spelling remains recognized when its availability
macro is absent: it has no enabled conditional runner and returns deterministic
nonzero `unavailable` without launching the GUI; non-manifest arguments retain
normal startup. Never invent an alias or run one harness through two command
rows. Run
`<porydaw> --check-host-integration <scratch-project> <song-a> <song-b> [screenshot]`
exactly once from this candidate build as part of this final proof; the earlier
packet-30 mini-wave proof does not substitute for it. Each row records
`CANDIDATE_SHA`, build/configuration identity, platform mode, fixture revision
where relevant, isolated-settings identity, exact command, exit result, and
its required evidence.

| Native row | Required evidence |
| --- | --- |
| Every activated packet-05 individual conditional new-module command | Record manifest group, new sentinel check source, compile definition, exact command, result, and owning packet. The velocity module result contains exactly the twelve named PSG-velocity cases and fails for a false, missing, duplicated, or non-twelve result. Existing-harness coverage belongs only to its named row below. |
| `<porydaw> --check-host-integration <scratch-project> <song-a> <song-b> [screenshot]` | Aggregate same-`CANDIDATE_SHA` host proof, including its screenshot when supplied and named cases. |
| `<porydaw> --editcheck <scratch-project>` | Named cases. |
| `<porydaw> --rollcheck <scratch-project> mus_lovely <roll-screenshot>` | Screenshot and comparison only to the preserved `UPSTREAM_SHA` baseline for a claimed pre-existing failure. |
| `<porydaw> --eventviewcheck <scratch-project> mus_lovely <event-screenshot>` | Screenshot and named cases. |
| `<porydaw> --keymapcheck` | Key-binding result. |
| `<porydaw> --sessioncheck <scratch-project> mus_lovely` | State round-trip result. |
| `<porydaw> --tabcheck <scratch-project> mus_lovely <second-valid-song>` | Recorded second valid song and result. |
| `QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks --editor-layout-check --base-font-px 12` | Audit-scale resolver result. |
| `QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks --editor-layout-check --base-font-px 16` | Alternate-scale resolver result. |
| `python3 tools/check_editor_layout_geometry.py` | One integrated-candidate repository-wide default source-audit result. Do not run this scan in product or host waves. |
| `git diff --check <UPSTREAM_SHA>..<CANDIDATE_SHA>` | Clean final feature-diff result. |
| `ctest --test-dir <build> -N` | Configured-runner applicability: record `BUILD_TESTING`, discovered tests, and runner identity. |
| `ctest --test-dir <build> --output-on-failure` | Run when the configured runner has applicable tests; record its result. If no tests are configured, record the `BUILD_TESTING`/discovery evidence as a genuine non-applicable result, not an unrecorded skip. |

A skipped applicable command fails final proof unless the coordinator records a
normative specification exception.  Use the pinned fixture revision and an
immutable canonical fixture read-only.  Immediately before every mutating
command, create one isolated scratch copy/reflink, use it for that command
only, remove it on either outcome, and keep at most one scratch fixture at a
time.  Do not retain raw project trees as evidence.  Record the second valid
song and use the required song/voice matrix covering tempo, voice, controller,
DirectSound, Square, Noise, Wave, and key-split notes.

### One visible smoke on the same candidate

After the native rows, visibly exercise **UX-01...UX-11** exactly once on the
same `CANDIDATE_SHA` and representative fixture: drawer open/switch/resize/
close/restore; focus and event-list shortcut blocking; automation lane and
gesture operations; roll/velocity selection, edit, cancellation, and Undo;
intrinsic Square/Noise/Wave behavior; mixer-independent graduations; playback
with each page open; no-MIDI sidecar restoration; and second-scale layout/hit
testing.  Record acceptance ID, song/voice case, operator action, observed
result, and a screenshot whenever it is visual evidence.  For **UX-09**, the
native counter evidence is mandatory alongside the visible playback observation.

## Final acceptance

At the same `CANDIDATE_SHA`, produce an acceptance ledger mapping every
**LAY-01**, **CORE-01...CORE-03**, **DRW-01...DRW-05**,
**AUT-01...AUT-03**, **VEL-01...VEL-04**, **A11Y-01**, **LIFE-01**,
**PERF-01**, and **UX-01...UX-11** to a focused record, same-SHA reviewer
approval, native row, or manual observation.  Audit exclusions on that same
SHA: oracle assets/research scripts or resource entries, temporary mixed
harnesses, Visual Studio ignore churn, forced Fusion setup, removed unrelated
checks/spec coverage, event-list/follow-playhead/keymap regressions, broad
colour-cache/benchmark work, whole-file formatting, and unrelated voice-editor
sizing.  Do not add a cleanup/formatting/gate commit merely to make the audit
pass.

Acceptance is complete only when the same exact SHA has four valid approvals,
the one native proof, the one visible smoke, fixture-safe records, a clean
diff/configured-runner result, the acceptance ledger, and the exclusion audit.
