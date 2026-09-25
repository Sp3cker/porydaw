# Parity acceptance and release gates

Companion to [plan.md](plan.md), [inventory.md](inventory.md) and [spec.md](spec.md). This is a verification design, not a report of passing application checks.

## What constitutes parity

For each inventory ID, require all four:

1. **Reachability:** the production app exposes the operation through its shipped menu, control, gesture or shortcut route. A presenter method alone does not count.
2. **Behavior:** observable results match the legacy contract, including cancellation, errors, enablement, selection/focus and history. Preserve outcomes, not QWidget internals.
3. **Persistence/audio:** reload written files with an independent consumer where applicable; compare audible output and timing through the production renderer. A test-local implementation is not the replacement.
4. **Evidence:** the covering Swift/QML predicates execute; native-window, audio-device, filesystem and deployment claims have their own relevant observations.

A feature can be present but under-proven. An unresolved proof row is not automatically a missing feature. Neither a green aggregate suite nor a ledger disposition percentage proves product parity.

Every new or rewritten MATCHED row must cite at least one predicate whose anchor is a `message` anchor; `Mapping:`/`Mapping/reason:`/`Swift:` lines citing only `function`/`deleted` anchors, or no citation at all, do not count. `deno task proof check --strict-mappings` lists and fails on the remaining debt; run it before claiming a ledger closed. `check` has no `--area`, so a ledger counts as closed when none of its sites appear in the strict list, not when the command exits 0.

## Existing commands and their limits

Commands below exist at the inspected revision. Reuse them in surface briefs; change a command only when its scope changes or the command proves stale/unavailable, recording the mismatch. The controller serializes builds and runtime lanes after parallel writers settle; writers may inspect source locally. No shared-tree build, formatter, or test runs mid-flight.

| Key | Exact command | What it covers / does not establish |
| --- | --- | --- |
| BRIDGE | `deno task verify:bridge` | Pinned-macro Swift/QML declaration guard with an empty baseline; also runs before every `verify*` lane. Its name-global observer matching and unresolved-target exclusions are not behavioral proof or complete signal-liveness analysis. |
| CORE | `deno task verify --filter swiftcore --verbose` | Registered Swift domain, presenter, project, audio and editing suites on macOS. Not automatically real-window interaction or every legacy assertion. |
| PROJECT | `deno task verify --filter projectstore --verbose` | Registered project-store entry points. Several manifest names alias the same Swift slot; count predicates, not entry names. |
| IDENTITY | `deno task verify --filter projectidentitycheck --verbose` | Project identity behavior. |
| BANK | `deno task verify --filter bankleases --verbose` | Bank lifetime and lease behavior; not every voice-editor workflow. |
| EXPORT | `deno task verify --filter exportcheck --verbose` | Current loop/tail registrations invoke `runExportChecks`. Its `renderExport` and RIFF writer live in the **check**, not a production export module. Replace that duplication as part of WAV export; current success would not establish File → Export WAV parity. |
| SHELL | `deno task verify:shell --verbose` | Production `ShellWindow` compositions, settings, tabs, songs, voices, transport, pitch bend, event list and visual lanes currently registered. Entries currently default to offscreen; not proof of native activation/file-dialog delivery. |
| DRAWER | `deno task verify:qml --verbose` | Editor drawer QML behavior registered in this lane. |
| ROLL | `deno task verify:qml-roll --verbose` | Swift roll QML input, camera, headers, scrollbar, plots, automation and playhead lanes. |
| ALL | `deno task verify --verbose` | Entire currently registered native runner; does not implicitly run the three separate QML lanes. |
| RENDER-BUILD | `deno task build:render` | Builds the development render CLI; building is not an audio comparison or a GUI export check. |
| PROOF | `deno task proof check` | Proof structure and source-anchor resolution only. |
| EXECUTED | `deno task proof check --executed` | Classifies predicate anchors against runner evidence and rejects certain unsupported matches. Inspect “not executed” and “unverifiable”; exit zero alone is not complete parity, and does not close GAP/PARTIAL rows. |
| STRICT-MAPPINGS | `deno task proof check --strict-mappings` | Fails on MATCHED sites citing no message-anchored predicate; plain `check` reports the same list as a warning. Required before treating a ledger as closed. |

Sources: `deno.json`, `tools/cli.ts`, `src/checks/checkcatalog.cpp`, `src/checks/editorqml/ShellQmlTests.swift`, `src/checks/projectstore/ExportChecks.swift`, `tools/proof_reader.ts`.

Use a registered shell entry for focused acceptance, for example:

```sh
deno task verify:shell --filter shell-songs --verbose
deno task verify:shell --filter shell-tabs --verbose
deno task verify:shell --filter shell-voicegroup --verbose
deno task verify:shell --filter shell-settings --verbose
deno task verify:shell --filter shell-transport --verbose
deno task verify:shell --filter shell-menus --verbose
deno task verify:shell --filter shell-pitch-bend --verbose
deno task verify:shell --filter shell-event-list --verbose
```

Do not copy stale legacy commands (`--samplecheck` or old `rollcheck`/`selectionkey` filters) into an acceptance claim without registration. New sample/onboarding/export shell lanes must be registered, stage their own fixtures, and demonstrate that their requested predicates actually ran.

Current CLI help explicitly rejects `--no-build`; all supported verify commands build incrementally. The Swift/QML check targets are currently Apple-gated as well as the `swiftcore` registrations. A Linux application build cannot establish these lanes passed; P9 must make the applicable lanes executable before platform acceptance.

Swift asynchronous commands in mounted QML checks require the existing `waitForNative` helper, which services the native RunLoop. Qt-only `wait`/`tryVerify` does not service Swift main-actor tasks; it can report unchanged state after a valid Undo request. Wait for the real state transition with the native helper rather than retrying input or weakening assertions.

## Surface proof procedure

Read both unresolved categories before defining a surface brief:

```sh
deno task proof sites --area samplecheck --status GAP
deno task proof sites --area samplecheck --status PARTIAL
```

Substitute the exact area named in the inventory, and page with `--offset` until exhausted. Record each relevant behavior, representation-only row, and real prerequisite. Keep unrelated/blocked rows unchanged. Include source/check evidence beyond ledgers: untested shipped behavior remains required.

After feature code and check sources settle, the controller delegates only the named proof files to `ledger-agent`, supplying the stable sources, brief and observed verification. Validate exact A→S correspondence against executing predicates. Keep GAP/PARTIAL when evidence is incomplete; do not restore obsolete line-number/hash/tally blocks or close a row from a merely related check.

The user authorizes retiring a completed proof file together with its obsolete C++ check once the replacement Swift/QML behavior has been exercised and reviewed. The ledger agent may delete its explicitly assigned completed proof file instead of maintaining a fully closed ledger; the code owner removes obsolete C++ sources and all build/runner registrations. Include the deleted oracle and replacement checks in the task review so the correspondence remains auditable in Git. Retain any file that still specifies unresolved required behavior or native observations the replacement cannot establish. Retirement belongs to the validated surface's commit, not a standalone bookkeeping sweep.

## Required end-to-end journeys

Each journey runs on isolated project copies through the production application. Check filesystem diffs against the explicitly permitted write set. Preserve fixtures for observable regressions; do not add source-text/wiring or mock-echo tests.

| Journey | Required observations |
| --- | --- |
| Existing composition | Open project/song → edit notes and automation → raw-event edit → undo/redo → save → close/relaunch. Preserve unknown MIDI/meta/SysEx, flags, same-tick order and unrelated project bytes; compare generated mid2agb output for no-edit round trips. |
| New composition | New Song → choose/create bank → choose player/config → create/register → draw/play/save → reopen. Include partial registration and actionable retry; validate regioned/expansion and monolithic/per-file project layouts where supported. |
| External MIDI | Menu → file picker → analysis/options → accept or cancel → save/register/reopen. Cover format 0, division conversion, duplicate setters, metadata, over-budget tracks, malformed input and filename collisions. No source overwrite on cancel/refusal. |
| Shared instruments | Two tabs share a bank → edit voice during playback → switch bank/song → undo/redo → save/relaunch. Exercise typed synths, keysplits/drumsets/waves, opaque read-only types, pending definitions, external-change refusal and failed saves. |
| Sample Studio | Import each supported source/zone → crop/loop/tune/resample/normalize → audition rendered sample and live edits → commit → assign voice → save → reopen edit from provenance → build asset. Compare the final audition PCM to the asset actually consumed by the ROM pipeline, including loop metadata. Include cancellation, changed/missing source and unsupported project refusal. |
| WAV export | Unsaved note + bank edits → choose rate/loops/fade/tail and path → stop live playback → render privately → inspect independent WAV decode, duration and samples. Toggle suppression and engine settings; cancel early/mid-render and fail a write. No partial successful output, unintended song save or dropped final/tail frames. |
| Window lifecycle | Open menus/popups, edit numeric/text controls and press transport/editor shortcuts; switch tabs/project, hide surface, deactivate window, lose pointer grab and close during gestures/audition/jobs. Prove the distinct cancellation causes and no stuck notes or late callbacks. |
| Settings/layout | Change theme/font/scale/display/follow preferences → resize docks/window and reopen. Test actual text contrast, focus, keyboard access and persisted state with both empty and loaded app; destructive prompts must remain readable. |
| Distribution | Install packaged app on a clean host → open/edit/play/save/export/sample import → relaunch. Verify Qt/QML plugins, Swift runtime, fonts/SVGs, audio backend, paths with spaces/non-ASCII and platform clipboard/shortcut conventions. |

## Release exit

- Every required inventory row has production reachability and observed behavior evidence; no silent scope deletion. Representation retirement is not product retirement.
- Run ALL, SHELL, DRAWER and ROLL on the settled integration tree, then PROOF and EXECUTED. Review the results, not just process exit codes. Do not reuse stale evidence across unrelated revisions.
- Preserve native tests where the new lane cannot observe the original behavior. A deliberate feature removal requires a user decision, not a proof-tool label.
- Match platform claims to actual toolchain, runtime and packaged-app evidence. `INSTALL.md` reports Linux ARM64 validation; Windows is pending. macOS checks are not Windows/Linux certification, and `__APPLE__`-guarded registrations must not permit a misleading empty platform pass.
- Update manuals, release notes and platform instructions with the completed surface. Remove obsolete production callers and temporary verification scaffolding in the same cutover.
