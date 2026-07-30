# 05 — Conditional build and check registration

**Agent:** `task`  
**Branch:** `task/psg-velocity/check-registration`  
**Worktree:** `05-check-registration`  
**Base:** the coordinator-recorded `UPSTREAM_SHA` from fetched `upstream/main`.

`git-operations-runner` prepares and verifies worktree `05-check-registration` and branch `task/psg-velocity/check-registration` from `UPSTREAM_SHA` and initializes/verifies submodules. The `task` agent enters the prepared worktree to author implementation and commit changes.
## Exclusive ownership

This prerequisite owns exactly these paths:

1. `CMakeLists.txt`
2. `src/main.cpp`
3. `src/editorcheckdispatch.h.in` (new)

`CMakeLists.txt` configures that template into the build directory and makes it
available to `porydaw`; no generated header is checked into `src/`. No later
packet may edit registration or dispatch. A module owner must make its complete
production/check set compile and run through the appropriate manifest route on
its branch; it must not defer registration or harness extension to host
integration.

## Deliver

Create one explicit CMake manifest with two deliberately different routes:

1. A **conditional group** has a genuinely new, packet-owned sentinel source
   below. Its predicate tests that sentinel and every member of its exact
   production/check set with `EXISTS`. When complete, CMake adds each source
   that is not already an upstream target source exactly once, defines the
   listed `PORYDAW_HAS_...` macro for the generated dispatch, and exposes only
   that group's command. No wildcard discovery, fallback command, deferred
   source addition, or partial enablement is permitted.
2. An **existing-harness task** has no CMake predicate, macro, or new dispatch
   command. Its files already exist and are already compiled on
   `UPSTREAM_SHA`; its owner extends that named harness and the coordinator
   runs its existing command. Existence of those paths is never evidence that
   the task completed.

`editorcheckdispatch.h.in` is the single typed declaration and availability
surface for conditional commands. It declares a dispatch function that
recognizes every conditional-manifest command spelling. A recognized spelling
returns a deterministic exit result: under its generated macro the function
declares/runs the corresponding runner with argument validation; without that
macro it has no enabled conditional runner and returns a deterministic nonzero
`unavailable` result. `main.cpp` only routes a recognized conditional-manifest
command to that function; non-manifest arguments retain normal startup and it
does not duplicate feature declarations, guards, or parsing. With no sentinel
present, CMake still configures the header and every conditional-manifest
spelling is unavailable without launching the GUI, while the upstream-only
executable and its existing command surface compile unchanged.

### Conditional executable groups

The **Runner declaration (authoritative)** column is the sole declaration
contract for independent module owners and for `editorcheckdispatch.h.in`.
Every `QString` parameter is `const QString &`; `screenshotPath` is optional
only where it has `= QString()` at the declaration. Definitions do not repeat
that default.

| Group | New sentinel | Exact complete production/check set | Definition | Runner declaration (authoritative) | Focused command signature |
| --- | --- | --- | --- | --- | --- |
| 10A identity transport | `src/noteidcheck.cpp` | `src/core/noteid.h`, `src/core/smf.h`, `src/core/miditimeline.h`, `src/core/miditimeline.cpp`, `src/noteidcheck.cpp` | `PORYDAW_HAS_NOTE_ID_CHECK` | `int runNoteIdentityCheck(const QString &scratchProject);` | `porydaw --check-note-identity <scratch-project>` |
| 11 neutral seams | `src/editorviewstatecheck.cpp` | `src/ui/editorviewstate.h`, `src/ui/editorviewstate.cpp`, `src/ui/editorpage.h`, `src/ui/editorpagehost.h`, `src/editorviewstatecheck.cpp` | `PORYDAW_HAS_HOST_SEAMS_CHECK` | `int runHostSeamsCheck();` | `porydaw --check-host-seams` |
| 13 model and axis | `src/psgvelocitymodelcheck.cpp` | `src/core/psgvelocitymodel.h`, `src/core/psgvelocitymodel.cpp`, `src/ui/velocityaxis.h`, `src/ui/velocityaxis.cpp`, `src/psgvelocitymodelcheck.cpp` | `PORYDAW_HAS_VELOCITY_MODEL_CHECK` | `int runPsgVelocityModelCheck();` | `porydaw --check-velocity-model` |
| 20 drawer | `src/rollcheckdrawer.cpp` | `src/ui/editordrawer.h`, `src/ui/editordrawer.cpp`, `src/rollcheckdrawer.cpp` | `PORYDAW_HAS_DRAWER_CHECK` | `int runEditorDrawerCheck(const QString &screenshotPath = QString());` | `porydaw --check-editor-drawer [screenshot]` |
| 21 automation | `src/ui/automationpage.cpp` | `src/ui/automationpage.h`, `src/ui/automationpage.cpp`, `src/ui/automationarea.h`, `src/ui/automationarea.cpp`, `src/rollcheckautomation.cpp` | `PORYDAW_HAS_AUTOMATION_CHECK` | `int runAutomationCheck(const QString &scratchProject, const QString &songLabel, const QString &screenshotPath = QString());` | `porydaw --check-automation <scratch-project> <song-label> [screenshot]` |
| 22 velocity page | `src/ui/velocitypage.cpp` | `src/ui/velocitypage.h`, `src/ui/velocitypage.cpp`, `src/ui/velocityarea.h`, `src/ui/velocityarea.cpp`, `src/rollcheckpsgvelocity.cpp` | `PORYDAW_HAS_VELOCITY_PAGE_CHECK` | `int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel, const QString &screenshotPath = QString());` | `porydaw --check-velocity-page <scratch-project> <song-label> [screenshot]` |
| 23 sidecar | `src/viewsidecarcheck.cpp` | `src/ui/viewsidecar.h`, `src/ui/viewsidecar.cpp`, `src/viewsidecarcheck.cpp` | `PORYDAW_HAS_SIDECAR_CHECK` | `int runViewSidecarCheck(const QString &scratchProject, const QString &songLabel);` | `porydaw --check-sidecar <scratch-project> <song-label>` |
| 30A SongView adapter | `src/hostcheck.cpp` | `src/ui/songview.h`, `src/ui/songview.cpp`, `src/hostcheck.cpp` | `PORYDAW_HAS_HOST_ADAPTER_CHECK` | `int runHostAdapterCheck(const QString &scratchProject, const QString &songLabel);` | `porydaw --check-host-adapter <scratch-project> <song-label>` |
| 30B MainWindow routing | `src/mainwindowroutingcheck.cpp` | `src/mainwindow.h`, `src/mainwindow.cpp`, `src/tabcheck.cpp`, `src/sessioncheck.cpp`, `src/mainwindowroutingcheck.cpp` | `PORYDAW_HAS_MAINWINDOW_ROUTING_CHECK` | `int runMainWindowRoutingCheck(const QString &scratchProject, const QString &songA, const QString &songB);` | `porydaw --check-mainwindow-routing <scratch-project> <song-a> <song-b>` |
| 30C bands and playhead | `src/renderingplayheadcheck.cpp` | `src/ui/timelinesurface.h`, `src/ui/timelinesurface.cpp`, `src/ui/playheadoverlay.h`, `src/ui/playheadoverlay.cpp`, `src/renderingplayheadcheck.cpp` | `PORYDAW_HAS_RENDERING_PLAYHEAD_CHECK` | `int runRenderingPlayheadCheck(const QString &scratchProject, const QString &songLabel, const QString &screenshotPath = QString());` | `porydaw --check-rendering-playhead <scratch-project> <song-label> [screenshot]` |

The aggregate host route is a fourth conditional registration, not a substitute
for an individual one. Its runner is owned by 30B in
`src/mainwindowroutingcheck.cpp` and is exactly
`int runHostIntegrationCheck(const QString &scratchProject, const QString &songA, const QString &songB, const QString &screenshotPath = QString());`.
It defines `PORYDAW_HAS_HOST_INTEGRATION_CHECK` and exposes
`porydaw --check-host-integration <scratch-project> <song-a> <song-b>
[screenshot]` only when the three genuinely new sentinels
`src/hostcheck.cpp`, `src/mainwindowroutingcheck.cpp`, and
`src/renderingplayheadcheck.cpp` all exist, together with all three complete
sets above. `editorcheckdispatch.h.in` declares and dispatches that runner only
when `PORYDAW_HAS_HOST_ADAPTER_CHECK`,
`PORYDAW_HAS_MAINWINDOW_ROUTING_CHECK`, and
`PORYDAW_HAS_RENDERING_PLAYHEAD_CHECK` are all defined. It is one real
integrated runner, not sequential aliases to the three individual checks, and
runs only on the merged packet-30 candidate.

### Existing-harness and direct-file commands

These are documented in the manifest so their owners have exact, runnable
evidence, but packet 05 does not conditionally register them. Existing
10B/10C/14A/14B paths cannot prove task completion by passing `EXISTS`; the
30B/30C groups likewise require their listed new sentinels, not their
already-present production/harness paths.

| Task | Existing harness or direct file | Focused command signature |
| --- | --- | --- |
| 10B document mutation | `src/editcheck.cpp` | `porydaw --editcheck <scratch-project>` |
| 10C view projection | `src/rollcheck.cpp` | `porydaw --rollcheck <scratch-project> <song-label> [screenshot]` |
| 12A resolver | `src/ui/theme/themechecks_main.cpp` and `src/ui/theme/themecheck.cpp` | `QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks --editor-layout-check --base-font-px 12`; `QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks --editor-layout-check --base-font-px 16` |
| 12B geometry gate | new direct files `tools/check_editor_layout_geometry.py`, `tools/check_editor_layout_geometry_test.py`, `tools/check_editor_layout_geometry_fixtures.py` | `python3 tools/check_editor_layout_geometry.py --self-test` |
| 14A shared host state | `src/rollcheck.cpp` | `porydaw --rollcheck <scratch-project> <song-label> [screenshot]` |
| 14B event-list remap | `src/eventviewcheck.cpp` | `porydaw --eventviewcheck <scratch-project> <song-label> [screenshot]` |

The 12B command is directly runnable from its new script and therefore has no
application dispatch macro. It is not a reason to register a CMake source
predicate for an already-existing executable.

## Non-goals and boundaries

- Do not add feature behavior, edit a feature source, rename an existing
  command, or change normal startup behavior.
- Do not add a source audit, run a geometry repository scan, or make
  registration a substitute for a module's focused checks.
- Do not make a missing conditional group silently pass. Its new command is
  unavailable until its complete set and new sentinel are present.
- Do not cherry-pick, transport a staged tree, or fold future sources into this
  branch.

## Required evidence and handoff

`git-operations-runner` prepares and verifies the worktree, branch, ref base, and submodules from `UPSTREAM_SHA`. The `task` agent enters the prepared worktree, implements the registration, and makes one commit, but does **not**
build, test, format, lint, or validate. The coordinator alone runs one focused
infrastructure proof from that committed packet-05 head. Its source set is
otherwise the `UPSTREAM_SHA` source set: only packet 05's owned registration
and dispatch changes are present, and no later module sentinel or group is
present. Configure and build that committed head with testing enabled;
`UPSTREAM_SHA` remains the comparison base only and is not rebuilt for this
proof. Explicitly exercise the generated `editorcheckdispatch.h` no-sentinel
fallback: record that it was configured with no conditional availability macro,
then invoke
`<packet-05-build>/porydaw --check-host-integration <scratch-project> <song-a> <song-b>`
and confirm that the recognized manifest spelling returns the deterministic
nonzero `unavailable` result with no enabled aggregate runner and without
launching the GUI. Confirm that all existing command signatures above are
unchanged, that no conditional command is enabled while its new
sentinel/complete set is absent, and that non-manifest arguments preserve
normal startup. Record the exact commands/results with the committed packet-05
SHA.

A `reviewer` agent reviews that committed range against `UPSTREAM_SHA`,
including every new-sentinel predicate, generated-header fallback, and
unchanged upstream path. After approval, merge the branch normally into
`feature/psg-velocity-history-upstream`; no cherry-pick or staged-tree
transport. Record the resulting integration commit as `INFRA_SHA`. Every
foundation implementation branch starts from `INFRA_SHA` or from the named
descendant in its packet.
