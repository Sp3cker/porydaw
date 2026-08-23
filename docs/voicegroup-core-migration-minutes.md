# Voicegroup Core Migration Minutes

## Purpose

Track decisions and open questions for moving Porydaw from Pory A's legacy C voicegroup loader to the loader backed by Rust `voicegroup-core`.

The authoritative implementation plan is
[`voicegroup-core-migration-plan.md`](voicegroup-core-migration-plan.md). These
minutes remain the historical decision record.

## Current state and reason for the migration

- Porydaw still builds Pory A's legacy standalone C voicegroup loader. That loader repeats project discovery, parsing, and symbol-map work that now belongs to Rust `voicegroup-core`.
- The dirty caching worktree contains a legacy-loader discovery cache, Porydaw checks for that cache, and a load benchmark. Focused checks pass, but that does not make the implementation suitable to keep.
- The legacy cache adds a large second execution path, process-wide mutable cache state, broad locking, timestamp-based invalidation, and repeated setup and cleanup. It deepens the implementation that we intend to remove and leaves two sources of truth.
- Preserve the cache test scenarios and benchmark results long enough to compare the replacement, but do not carry the old cache interface or implementation into the Rust-backed path.
- Rust `voicegroup-core` already covers reusable project indexing, voicegroup parsing, structural checks, symbol lookup, display names, diagnostics, sub-voicegroups, keysplits, and records for all ordinary voice types. Pory A's newer C loader uses those records to decode assets and create `LoadedVoiceGroup` runtime data.
- The migration is not a direct loader swap yet. Porydaw still needs focused interfaces for unsaved source text, project asset enumeration and selected-asset loading, structured diagnostics, long-lived context refresh, and Golden Sun synth definitions.

## Settled decisions

- `voicegroup-core` is the source of truth for project discovery, voicegroup parsing, structural checks, and symbol-to-project-path indexing.
- Pory A's C loader remains responsible for sample decoding, runtime allocation, and `LoadedVoiceGroup` lifetime.
- Porydaw should call the Pory A C loader. It should not consume Rust types or build its own copy of the Rust project index.
- The cross-language seam is the C-compatible interface in `packages/voicegroup-core/include/voicegroup_core.h`; its Rust project-index implementation lives in `packages/voicegroup-core/src/project_index.rs`.
- Prefer one explicitly owned loader context per open project over a process-wide global cache.
- Do not keep the current Pory A legacy-loader cache commit or the Porydaw changes written for that old cache interface.
- Preserve the useful test ideas: project switching, stale source changes, nested discovery, and invalidation. Rework them as checks of the new `voicegroup-core` seam.
- Preserve the current benchmark only as temporary reference for an old-versus-new comparison; do not treat its present implementation as production code.
- Do not delete the dirty worktree changes until they have been safely preserved for reference.
- Unsaved voicegroup edits stay in memory. Do not write a temporary preview voicegroup file or add a general search-path override for this purpose.
- Add a focused `voicegroup-core` interface that loads unsaved voicegroup source text against an existing project index. Pory A's C loader then materializes the returned preview bank normally.
- Write voicegroup source to the real project file only when the user saves the project.
- The left-side voicegroup browser's project-wide sample picker must decode DirectSound samples, programmable waves, and keysplits on demand rather than loading the whole project at once.
- This on-demand decision does not change active-song playback: samples referenced by the active `LoadedVoiceGroup` remain preloaded before playback can use them.
- The separate Sample Studio loading path is not part of the project-wide sample-picker change.
- Do not add a separate metadata-only sample-reading path for the project-wide picker. When a sample row becomes current by mouse or keyboard, load the complete sample on demand, derive its metadata from that loaded sample, update the selected-row detail UI, and audition it.
- Remove the project-wide sample picker's per-row infinity loop badges. Show loop status only in the detail line for the current, loaded sample.
- Adopt `voicegroup-core` display names as the shared voice-slot naming rule. Expose those names to Porydaw through the C loader instead of preserving the legacy C loader's naming behavior.
- Own one Rust-backed project context per open decomp project and share it across that project's song tabs and voicegroup tools. Do not use a process-wide global snapshot cache.
- Watch the source files represented by the Rust project index, not the whole project tree recursively. A change marks the index stale; rebuild it before the next index lookup. Porydaw's own file additions mark the index stale directly.
- Porydaw's own saved voicegroup, sample, programmable-wave, and keysplit changes also mark the shared project index stale. Unsaved in-memory voicegroup previews do not.
- An external source change must not hot-swap the voicegroup currently used by playback. Refresh the index, but replace an active voicegroup only at a safe UI reload action. Never replace a voicegroup that has unsaved edits.
- Preserve the full structured `voicegroup-core` diagnostic list across the C loader seam. Do not reduce failures to one global error string.
- Porydaw must consume those diagnostics. Slot-specific problems should appear beside the affected voice in the voicegroup list; file, line, and message remain available for detailed presentation.
- A voice with a blocking diagnostic remains visible in the voicegroup list with its error marker and message, but its row and editor controls are disabled. Porydaw does not edit that invalid voice; the source must become valid before the row is enabled again.
- Treat diagnostics as errors only: either a voice is valid and loads, or it has an error and does not. Do not expose or describe a separate non-blocking diagnostic severity in Porydaw; remove the unused distinction from the migration interface.
- Materialization failures that have no Rust source range must still report the failed asset path and message.
- Voicegroup replacement is transactional using the session's existing active `LoadedVoiceGroup`: build a complete replacement first; on failure keep the active voicegroup; on success swap and free the old one. Do not add a history or backup cache.
- GUI voicegroup edits must validate the proposed in-memory source before Porydaw accepts them. Structured diagnostics also cover invalid projects, external edits, missing or corrupt assets, and unresolved typed symbols.
- Keep the voicegroup sample picker's search box, but remove its generated `Use "..."` row. The GUI may commit only symbols resolved by the Rust project index; newly imported samples become choices after successful registration and index refresh.
- Do not require Rust or Cargo for an ordinary Porydaw build. Pory A's own CI should build the Rust `voicegroup-core` native libraries for Porydaw's supported platforms.
- For the current development stage, check the supported-platform `voicegroup-core` static libraries into Porydaw and select the correct one in CMake. Defer GitHub Release publishing and automatic downloads until the dependency workflow needs to scale.
- Do not build or vendor the platform libraries until the new Rust and C loader interfaces are finished. Develop and test the interface on macOS first, then freeze one exact Pory A commit.
- After the interface commit is frozen, run a manually triggered Pory A GitHub Actions workflow that builds natively on Windows, Linux, macOS ARM64, and macOS x86-64. Download its temporary artifacts, commit those libraries into Porydaw with the matching header, source commit, and licenses, then run Porydaw's normal cross-platform CI against them.
- The temporary workflow artifacts may expire after Porydaw vendors them; a permanent GitHub Release pipeline is not required at this stage.
- Defer migrating Porydaw's C++ `VoicegroupSource` editing, source-preservation, rendering, and save logic into Rust. During this migration, keep that C++ model, render proposed unsaved edits in memory, and validate the rendered text through `voicegroup-core` before accepting the edit.
- Rust remains the source of truth for project indexing, loadability, and diagnostics in this phase. Replacing the C++ editing model is a separate later project.
- Preserve all existing Golden Sun DirectSound synth support during the migration. `voicegroup-core` must index the current synth symbols and descriptor data, and Pory A's C loader must materialize them with behavior that matches the legacy loader. Switching loaders must not break synth creation, loading, audition, or playback in Porydaw.
- This includes the existing custom/pulse, 25-percent/saw, and 50-percent/triangle synth forms and their accepted source names: `set_synth_custom`/`set_synth_pulse`, `set_synth_25`/`set_synth_saw`, and `set_synth_50`/`set_synth_triangle`.

## Frozen Pory A interface

The Wave 4 compatibility review freezes ABI version 1 and the following
`voicegroup_project.h` entry points:

```c
VoicegroupProject *voicegroup_project_open(const char *root, size_t root_len);
void voicegroup_project_refresh(VoicegroupProject *project, VoicegroupProjectResult *out);
void voicegroup_project_mark_stale(VoicegroupProject *project);
void voicegroup_project_result_free(VoicegroupProjectResult *result);
void voicegroup_project_free(VoicegroupProject *project);

VoicegroupLoadResult voicegroup_project_load(VoicegroupProject *project,
                                             const VoicegroupLoadRequest *request);
LoadedVoiceGroup *voicegroup_load_result_take(VoicegroupLoadResult *result);
void voicegroup_load_result_free(VoicegroupLoadResult *result);

VoicegroupAssetResult voicegroup_project_load_asset(VoicegroupProject *project,
                                                    VoicegroupAssetKind kind,
                                                    const char *symbol,
                                                    size_t symbol_len);
void voicegroup_asset_result_free(VoicegroupAssetResult *result);

VoicegroupSynthOverlay *voicegroup_synth_overlay_create(void);
void voicegroup_synth_overlay_add(VoicegroupSynthOverlay *overlay,
                                  const char *name,
                                  size_t name_len,
                                  uint8_t descriptor[6]);
void voicegroup_synth_overlay_free(VoicegroupSynthOverlay *overlay);
```

The module owns its project snapshot, last failure, retained generation, and
generation-local decoded-asset cache. Each result owns a separate arena copy of
every returned string, array, sample payload, synth descriptor, and typed
keysplit result. `voicegroup_load_result_take` is the only ownership transfer:
after it returns a bank, the caller owns that bank and must use
`voicegroup_free`. A result free is repeat-safe after the result is zeroed.
The per-bank materializer uses an unbounded cache keyed by absolute sample path,
matching legacy semantics; it has no fixed 128-entry limit. Repeated slots in
one bank graph decode once. A successful project generation separately owns its
picker cache, which is cleared in full when the project becomes stale.

Diagnostics have no public severity. They carry a scope, source path, asset
path, optional slot, and a 1-based start-inclusive/end-exclusive source range.
Materialization-only failures have no invented range. The project state machine
is entirely inside Pory A; the C++ shell only refreshes or marks it stale.
`VoicegroupLoaderConfig` and its broad `voicegroupPaths` search override are
declared unsupported and absent from the frozen API. Unsaved synth definitions
use the typed transient overlay instead; no replacement filesystem override is
accepted or silently ignored.

### Frozen native artifacts

Source commit:
`342159a24c4566b31c7117ba447561150060a720`.
Workflow run:
`https://github.com/Sp3cker/poryaaaa-monorepo/actions/runs/32667981322`.
All four jobs passed with Rust 1.98.0, ABI 2, generated-header SHA-256
`eae66d353cb1bd97b8e23ce4de0330347cf85e37fb3b49601056f812ca3e7b29`,
and compatibility for both single- and double-colon GAS labels.

Wave 8 exposed two omissions in the first frozen snapshot: per-family typical
ADSR and the project's defined `set_synth_*` macro aliases were present in Rust
or the legacy editor but absent from the bulk C result. The final freeze adds
both as deterministic arena-owned arrays, watches `asm/macros`, bumps the ABI,
and derives the packaged manifest ABI from the generated header.

| Target | Runner / architecture | Archive SHA-256 |
|---|---|---|
| `aarch64-apple-darwin` | `macos-15` / ARM64 | `19e49e8244c64391cdb09e5cb9b5a2c01e7cee768a8913ac3019db5855691a45` |
| `x86_64-apple-darwin` | `macos-15-intel` / X64 | `a5b2636aa5000dc19cadda7eb7709e3f191b7ee8d369241720d90d0fd3b87799` |
| `x86_64-unknown-linux-gnu` | Ubuntu 20.04 container / X64 | `73279980b487be2bbaa95064911f9c4565aea9890e53efc0fbb1ac2e2cb40a40` |
| `x86_64-pc-windows-msvc` | `windows-2025` / X64 | `10154202069e24e4bae164a0b075d3682eba6848f2292d8a1fc2eca9e2903319` |

## Rejected approaches

- Do not expand or ship the legacy C loader's project-discovery cache. The shared project index belongs in `voicegroup-core`.
- Do not make Porydaw and Pory A build separate project indexes or pass Rust collections into C++.
- Do not write unsaved voicegroup previews to temporary files or preserve a broad extra-search-path override for that purpose.
- Do not eagerly decode every project sample for the left-side sample picker.
- Do not add an asynchronous loader, a metadata-only header path, or extra row-level metadata machinery for the first on-demand picker version.
- Do not allow the sample search field to commit a symbol that the project index cannot resolve.
- Do not hot-swap the active playback voicegroup when a watched source changes.
- Do not introduce warning-level diagnostics in Porydaw. A voice either loads or has an error.
- Do not require ordinary Porydaw contributors to install Rust or Cargo during this development stage.
- Do not move Porydaw's source-preserving C++ voicegroup editor into Rust as part of this migration.

## Compatibility audit

Review one capability at a time before changing Porydaw's build or loader path.

Known topics to review:

1. In-memory unsaved voicegroup previews. **Settled:** add a source-text preview interface; do not preserve the temporary-file override.
2. Project-wide sample-picker loading. **Settled:** expose the catalog from `voicegroup-core`, then materialize selected samples, programmable waves, and keysplits on demand instead of preserving the old batch load.
3. Voice display-name compatibility. **Settled:** use the Rust core's display names and adapt the C loader field consumed by Porydaw.
4. Long-lived project-index ownership, refresh, and invalidation. **Settled:** one shared context per open project; watched indexed source files plus Porydaw writes mark it stale; rebuild before the next lookup; do not recursively watch the project tree.
5. Error reporting and diagnostics. **Settled:** return the full structured error list; show slot errors beside invalid voices; retain file, range, asset path, and message for detail; reject invalid GUI edits; and keep the active voicegroup when replacement fails.
6. Build and cross-platform linkage of the Rust static library. **Settled for now:** ordinary Porydaw contributors do not need Rust or Cargo; finish and freeze the interface first; use one manual native-platform Pory A workflow to produce temporary artifacts; vendor them in Porydaw and select one in CMake. Defer Pory A releases and automatic downloads.
7. Ownership and freeing. **Settled:** `MainWindow` owns one project handle; each `SongSession` owns its loaded bank; result arenas and the generation-local picker cache are module-owned; the audio engine only borrows the active bank and is unbound before replacement or destruction.
8. Voicegroup source editing. **Settled for this migration:** retain Porydaw's C++ editor/source writer and validate its in-memory output through Rust; defer moving edit and save operations into `voicegroup-core`.
9. Golden Sun DirectSound synth compatibility. **Settled:** preserve every synth form supported by Porydaw and the legacy loader; add their symbols and descriptor data to `voicegroup-core`, then materialize them identically through the C loader.

## Planned order

1. Finish the compatibility audit before changing Porydaw's loader or build path.
2. Add and test the missing `voicegroup-core` interfaces and Golden Sun synth indexing in Pory A.
3. Adapt Pory A's newer C loader to expose the data, diagnostics, and lifetime operations Porydaw needs.
4. Test the interface on macOS and freeze one exact Pory A source commit and matching C header.
5. Produce the native static libraries for all supported platforms and vendor them in Porydaw with their source commit and licenses.
6. Switch Porydaw to the new loader through small C++ lifetime wrappers, then implement the agreed picker, refresh, diagnostic, and in-memory preview behavior.
7. Rework the preserved cache test ideas against the new project-context interface and compare the replacement with the old benchmark.
8. Remove the legacy loader cache experiment and its tied Porydaw wiring only after the Rust-backed path passes the compatibility checks.

## Wave 13 benchmark ratification

- Fixture tree: `229e9bb81cef6ce33d9f6761316f2eb0a2b91139`, identical
  to Wave 0. Host: Apple M4 Pro (`arm64`), Darwin 25.5.0, Release build, warm
  filesystem cache, 20 sequential timed repetitions per workflow.
- Cold saved bank: 1.864 / 2.065 / 2.102 / 2.501 ms
  (min / median / mean / max), new handle with no generation; open, first
  refresh, and saved load timed. This exceeds the 1.11 ms threshold.
- Warm saved bank: 0.503 / 0.522 / 0.539 / 0.644 ms, steady-state Fresh after
  an untimed warmup. This exceeds the 0.45 ms threshold.
- Preview materialization: 0.490 / 0.510 / 0.512 / 0.583 ms, steady-state
  Fresh with full-file `VG_LOAD_SOURCE`. This passes the 0.615 ms threshold.
- First picker row: 0.024 / 0.029 / 0.030 / 0.039 ms, Fresh after an untimed
  refresh with an empty asset cache. This passes the 0.21 ms threshold.
- The reviewer attributes the cold delta to once-per-project-open indexing:
  the new path builds the project catalog, dependency and watch paths, and
  structured diagnostics, then amortizes that generation across the session.
  The 0.24 ms warm delta is accepted for the structured result/ownership
  contract and the decision not to retain a process-global cache. These costs
  are user-initiated, not per-frame work.
- Measurement notes: cold output is labelled Fresh only after its first
  refresh; it is not a steady-state sample. The legacy harness includes result
  teardown inside its timing window while the new harness stops immediately
  before RAII teardown; this microsecond-scale asymmetry cannot change any
  decision. Legacy preview includes the temporary shadow-file write that the
  new in-memory source path intentionally removes.
- Full Porydaw verification passed 56/56, including runtime ABI pairing and the
  project-switch, stale-source, nested-discovery, and invalidation/re-arm
  scenarios.
- **Ratification decision: APPROVE LEGACY REMOVAL.** The reviewer explicitly
  approves cold up to the recorded 2.102 ms mean and warm up to the recorded
  0.539 ms mean for this cutover; preview and picker pass their numerical gates
  outright.

## Open questions

- None for the frozen integration contract. Wave 4 closed ownership,
  diagnostics, layout, overflow, deduplication, decode parity, and lifetimes;
  Wave 6 proved the vendored header/archive checksum, target, architecture, ABI,
  and compile-link rejection gates.

## Immediate cache experiment

- Before deciding whether to execute the Rust migration or add persistent SQLite voicegroup tables, change only the project-wide sample picker to load assets on demand through the existing legacy C loader.
- Opening the picker must list symbols without decoding the whole catalog. When a row becomes current through explicit mouse or keyboard interaction, request only that DirectSound sample, programmable wave, or keysplit and retain its returned `LoadedSampleSet` in memory for the current project.
- Clear the in-memory picker asset cache when the project catalog is invalidated or the project closes. Do not add SQLite tables, Rust interfaces, asynchronous loading, or audio-thread decoding in this experiment.
- This does not change active-song loading. A song's `LoadedVoiceGroup` must still contain every asset it references before playback begins.
- Measure the result before deciding whether repeated legacy-loader discovery needs a persistent SQLite cache or whether the Rust migration remains worthwhile.
