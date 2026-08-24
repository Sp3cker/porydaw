# Voicegroup Diagnostic Resilience Plan

Decouple project-wide voicegroup catalog diagnostics from individual program bank
and asset loading, so valid banks (e.g. `hanabi`) load even when unrelated project
voicegroup files have diagnostics.

---

## 1. Objective & success criteria

**Goal.** A project with both valid and degraded voicegroup files MUST load its
valid banks and assets normally. Project-wide diagnostics MUST be surfaced to the
UI without blocking individual bank or asset loads.

**Success criteria.**

1. `voicegroup-core` Rust `ProjectSnapshot::snapshot()` sets `succeeded = true`
   whenever the index was built (always), regardless of catalog diagnostics.
2. The Pory A C `VoicegroupProject` installs the generation (retains the index)
   whenever the index loaded, even when the snapshot contains diagnostics.
   `PROJECT_REFRESH_FAILED` is reserved for genuine fatal indexing failures
   (unreadable root, I/O error during discovery).
3. `voicegroup_project_load` (saved mode) and `voicegroup_project_load_asset`
   work against the retained index in the presence of unrelated diagnostics.
4. Per-bank and per-asset diagnostics still propagate correctly; a bank that
   itself has a blocking diagnostic still fails its own `voicegroup_project_load`
   with structured diagnostics.
5. Mixed-health project: `voicegroup_hanabi` (valid) loads and `voicegroup_broken`
   (references missing sample) surfaces its own diagnostic without blocking
   `voicegroup_hanabi`.
6. `deno task build:checks`, `deno task verify:voicegroup-vendor`, and
   `deno task verify` pass cleanly.
7. Upstream submodule `external/poryaaaa` sources remain clean: `cargo test -p
   voicegroup-core` and the C harness pass.

**Constraints.** No ABI surface change: no new/removed C functions, no struct
layout changes, no enum variant additions. The `succeeded` field remains a `bool`
in all three layers (Rust, C, C++). The semantic shift is the entire change.

---

## 2. Current-state findings

### 2.1 Rust `voicegroup-core` — `ProjectSnapshot::snapshot()`

**File.** `external/poryaaaa/packages/voicegroup-core/src/project_index/mod.rs`

```rust
// lines 252–263
pub fn snapshot(&self) -> ProjectSnapshot {
    let mut diagnostics = self.project_diagnostics.clone();
    let catalog = self.build_catalog(&mut diagnostics);
    ProjectSnapshot {
        succeeded: diagnostics.is_empty(),   // ← conflates catalog health with index availability
        catalog,
        diagnostics,
    }
}
```

`ProjectIndex::load()` (`discovery.rs:19–47`) returns `io::Result<ProjectIndex>`.
If it returns `Ok`, the index is fully built — all discovery steps completed.
`build_catalog` is infallible (returns `ProjectCatalog`, not `Result`). Catalog
diagnostics (unknown symbols, unsupported-layout warnings, keysplit cycles) are
**non-fatal**: the index is usable for valid banks.

However, `succeeded: diagnostics.is_empty()` conflates these two concepts. ANY
diagnostic — even from an unrelated file — flips `succeeded` to `false`.

**Evidence that diagnostics are non-fatal:**
- `discover_unsupported_layouts` (`discovery.rs:97–105`) records project-level
  diagnostics for `.s` files, `vg_` prefix, `_keysplit`/`_drumset` suffix, and
  deep-scan layouts. These are explicitly "unsupported but recorded" — the index
  is still functional.
- `build_catalog` (`catalog.rs:9–297`) iterates banks, appends per-bank
  diagnostics (unknown symbols, keysplit cycles). It never returns an error.
- `load_program_bank` (`loading.rs:45–113`) independently loads a specific bank
  against the index; it returns its own `ProgramBankLoadResult` with per-bank
  diagnostics.

**C ABI.** `c_api/project.rs:169–177` — `voicegroup_core_project_snapshot_result_succeeded`
returns `result.succeeded`. The doc comment says "completed without diagnostics",
which is the current (conflated) meaning.

### 2.2 Pory A C `VoicegroupProject` — `project_rebuild`

**File.** `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project.c`

```c
// lines 29–121 (abbreviated)
static bool project_rebuild(VoicegroupProject* project, VoicegroupProjectResult* output) {
    // 1. Load index, build snapshot.
    status = voicegroup_core_project_index_load(project->root, &index);
    if (status == OK && index) status = voicegroup_core_project_index_snapshot(index, &snapshot);

    // 2. Fatal: index load / snapshot failed.
    if (status != OK || !snapshot) {
        // … set PROJECT_REFRESH_FAILED, return false.
    }

    // 3. Gate: only install generation when snapshot has NO diagnostics.
    if (voicegroup_core_project_snapshot_result_succeeded(snapshot)) {
        // Install generation, PROJECT_FRESH, return true.
    }

    // 4. Non-fatal-today: snapshot exists but has diagnostics.
    //    Free index, copy failure (catalog + diagnostics from retained generation),
    //    PROJECT_REFRESH_FAILED, return false.
    ProjectResultStorage* failure = project_storage_create();
    bool ok = failure && project_storage_copy_failure(failure, snapshot, project->generation);
    // … free snapshot, free index, set PROJECT_REFRESH_FAILED.
}
```

**Consequence.** When ANY voicegroup file has a diagnostic:
1. `succeeded` is `false` → step 3 gate is closed.
2. The new index is freed (`voicegroup_core_project_index_free`).
3. State becomes `PROJECT_REFRESH_FAILED`.
4. `ensure_generation` returns `false` → `voicegroup_project_load` (saved)
   returns `project.refresh_failed` → `loadVoicegroupFor` fails for ALL banks.
5. `voicegroup_project_load_asset` (line 318) short-circuits on `PROJECT_REFRESH_FAILED`.

**Retained generation.** The *previous* generation is kept in `project->generation`
(not freed), but inaccessible because the state machine blocks on `REFRESH_FAILED`.
The `project->failure` storage copies the snapshot's catalog + diagnostics (via
`project_storage_copy_failure`), so the UI can still display rows — but no bank
or asset can be loaded.

**Dead code after change.** `project_storage_copy_failure` (result.c:414–436) and
`project_storage_copy_catalog_parts` (result.c:409–412) are only called from the
non-fatal failure block (lines 99–100). After the fix, that block is removed and
both helpers become dead code.

### 2.3 Porydaw `VoicegroupProject` RAII

**File.** `src/project/voicegroupproject.cpp`

`VoicegroupProject::refresh()` (line 374–382) calls the C `voicegroup_project_refresh`,
copies the result view into `Snapshot`, and replaces filesystem watches when
`snapshot.succeeded` is true. The `snapshot.succeeded` field is a direct copy of
the C `VoicegroupProjectResult.succeeded` (line 99), which comes from the Rust
`ProjectSnapshot.succeeded`.

**No other `snapshot.succeeded` consumer in Porydaw blocks bank loading.**
`openVoicegroupSource` (`mainwindow.cpp:2713`) checks `!metadata` (catalog entry
presence), not `snapshot.succeeded`. `vgCatalog()` (`mainwindow.cpp:2523`) reads
`snapshot.catalog` without checking `succeeded`. `loadVoicegroupFor`
(`mainwindow.cpp:1401`) iterates candidates and calls `loadSaved`, which uses
`LoadResult::succeeded()` (per-bank), not the snapshot flag.

**One UI-level guard.** `reloadVoicegroup` (`mainwindow.cpp:2810–2821`) checks
`!snapshot.succeeded` and aborts the active-source reload with a project-level
error. Under the new semantics, this guard only fires on fatal index failure.

### 2.4 Tests asserting the current conflation

| Layer | Test | What it asserts |
|-------|------|-----------------|
| Rust | `project_index.rs:1089` `snapshot_keeps_invalid_bank_visible_and_returns_its_diagnostics` | `assert!(!snapshot.succeeded)` when a bank references an unknown symbol |
| Rust | `project_index.rs:1110` `assert_layout_diagnostic` helper | `assert!(!snapshot.succeeded)` for unsupported-layout discoveries |
| C harness | `voicegroup_project_harness.c:370–375` "invalid disk" block | `load_asset(DirectSoundWave)` returns `diagnostic_count > 0` when an unrelated bank references a missing sample |
| Porydaw | `contextcheck.cpp:196` corrupt-refresh test | `expect(!snapshot.succeeded, ...)` after writing a corrupt bank file |

---

## 3. Recommended design

### 3.1 Semantic definition of `succeeded`

**`succeeded` in `ProjectSnapshot` (Rust), `VoicegroupProjectResult` (C), and
`VoicegroupProject::Snapshot` (C++) means: "the project index was successfully
built and is available for loading banks and assets."**

It is `true` whenever `ProjectIndex::load()` succeeded (which is the only
precondition for `snapshot()`), regardless of catalog diagnostics. It is `false`
only when the index could not be built at all (I/O error, unreadable root).

**Rationale.** Catalog diagnostics are per-bank/per-asset metadata. They do not
impair the index's ability to resolve symbols, locate files, or load valid banks.
The "no diagnostics" signal is already available via `diagnostic_count == 0`.

### 3.2 Generation retention policy

When `project_rebuild` produces a snapshot (the index loaded), the C loader MUST
install the generation — keep the index handle, copy the snapshot's catalog and
diagnostics, and set `PROJECT_FRESH`. This is the same path that currently runs
only when `succeeded` is true; after the change, it runs unconditionally for any
non-null snapshot.

`PROJECT_REFRESH_FAILED` is only entered when the index could not be loaded
(`voicegroup_core_project_index_load` returns non-OK or snapshot is null). The
migration plan's §7 last-good-generation retention semantics for the fatal case
are unchanged.

**No new state is needed.** The existing three-state machine (`PROJECT_STALE`,
`PROJECT_FRESH`, `PROJECT_REFRESH_FAILED`) covers the new semantics:
- `FRESH` = index loaded (may have diagnostics).
- `REFRESH_FAILED` = index could not be loaded (fatal).
- `STALE` = watcher event or explicit `mark_stale`; re-armed for next rebuild.

### 3.3 Error handling & diagnostic propagation

| Layer | Signal | Meaning |
|-------|--------|---------|
| Rust `ProjectSnapshot` | `succeeded: true` | Index available |
| Rust `ProjectSnapshot` | `diagnostics: Vec<Diagnostic>` | Project-wide catalog diagnostics (non-fatal) |
| C `VoicegroupProjectResult` | `succeeded: true` | Generation installed, banks loadable |
| C `VoicegroupProjectResult` | `diagnostics: …` | Copied from Rust snapshot |
| C `VoicegroupLoadResult` | `succeeded: bool` | This specific bank materialized successfully |
| C `VoicegroupLoadResult` | `diagnostics: …` | Per-bank blocking diagnostics |
| C `VoicegroupAssetResult` | `diagnostics: …` | Per-asset decoding diagnostics |
| Porydaw `Snapshot` | `succeeded` | Same as C result |
| Porydaw `LoadResult::succeeded()` | Per-bank | Same as C load result |

**Project-wide diagnostics surface through `snapshot.diagnostics`**, which the UI
already copies into session diagnostics when the specific bank has no catalog
entry (`openVoicegroupSource:2723`) or on fatal refresh failure. The browser
(`updateVoicegroupBrowser`) already renders per-session diagnostics.

### 3.4 Argument for this approach

1. **Minimal ABI change.** No new/removed functions, no struct layout change.
   The `succeeded` field stays `bool` in all three layers. Only the meaning
   shifts.
2. **Cleans up dead code.** `project_storage_copy_failure` +
   `project_storage_copy_catalog_parts` and their declarations are removed.
3. **Fixes watcher behavior.** Currently, a diagnostic prevents `replaceWatches`
   from being called (since `snapshot.succeeded` is false), so fixing a broken
   file is not observed. After the change, watches are always installed when the
   index loads.
4. **Aligns with migration plan intent.** The migration plan §4 line 179–182
   says "unless a real partial catalog exists." The code must actually
   distinguish partial from catastrophic.

---

### Wave 0 — Reconnaissance (already performed; re-verifiable by `explorer` agents)

**Subagent type:** `explorer`.

The plan author has already traced the end-to-end flow (see §2). Before Wave 1
starts, dispatch **two `explorer` subagents** to re-confirm the seams against the
live tree, because the migration is actively moving files under
`external/poryaaaa`:

1. **Rust seam explorer** — confirm `ProjectSnapshot::snapshot()` (mod.rs:252),
   `build_catalog` (project_index/catalog.rs), and
   `voicegroup_core_project_snapshot_result_succeeded` (c_api/project.rs:169) have
   not changed since this plan was written; return current line numbers and the
   list of `snapshot.succeeded` test assertions.
2. **C loader seam explorer** — confirm `project_rebuild` (voicegroup_project.c),
   `ensure_generation`, `voicegroup_project_load`, `voicegroup_project_load_asset`
   (voicegroup_project_asset.c), and `project_storage_copy_failure`
   (voicegroup_project_result.c) still match §2.2; return current line numbers
   and any new callers of `project_storage_copy_failure`.

Each explorer returns file:line evidence; they do NOT edit. If either report
diverges from §2, the implementer must reconcile before editing.

---

## 4. Wave-by-wave implementation plan

### Wave 1 — Rust `voicegroup-core` semantic change

**Subagent type:** `task` (multi-file edit with precise test updates).
**Reviewer gate:** `reviewer` after implementation.

**Mechanical flips:** the two `assert!(!snapshot.succeeded)` → `assert!(snapshot.succeeded)`
flips in `tests/project_index.rs` (lines 1089, 1110) are `sonic`-grade, single-token
edits that can be dispatched to a `sonic` subagent while the `task` agent owns the
source change and the new mixed-health test.

**Files.**

| File | Change |
|------|--------|
| `external/poryaaaa/packages/voicegroup-core/src/project_index/mod.rs:255–263` | `snapshot()`: set `succeeded: true` unconditionally. Update doc comment on `snapshot()` (lines 252–254) to say "Callers may install a runtime bank even when `diagnostics` is non-empty." |
| `external/poryaaaa/packages/voicegroup-core/src/catalog.rs:520–524` | Update `ProjectSnapshot.succeeded` field doc: "Whether the project index was successfully built. Always `true` when a snapshot exists; does not reflect catalog diagnostics." |
| `external/poryaaaa/packages/voicegroup-core/src/c_api/project.rs:169–177` | Update `voicegroup_core_project_snapshot_result_succeeded` doc: "Returns whether the project index was successfully built (always true when the snapshot handle is valid); does not reflect catalog diagnostics." |
| `external/poryaaaa/packages/voicegroup-core/tests/project_index.rs` | **(a)** `snapshot_keeps_invalid_bank_visible_and_returns_its_diagnostics` (line 1089): flip `assert!(!snapshot.succeeded)` → `assert!(snapshot.succeeded)`. Rename test to `snapshot_succeeds_with_diagnostics_and_keeps_invalid_bank_visible`. **(b)** `assert_layout_diagnostic` helper (line 1110): flip `assert!(!snapshot.succeeded)` → `assert!(snapshot.succeeded)`. **(c) Add mixed-health test**: `snapshot_succeeds_in_mixed_health_project_and_valid_bank_loads`. Create a project with two banks — `voicegroup_healthy` (valid) and `voicegroup_broken` (references missing sample). Assert `snapshot.succeeded`, `snapshot.diagnostics` non-empty, `catalog.entries` contains both banks, `load_program_bank("voicegroup_healthy")` returns `ProgramBankLoadResult { bank: Some(…), diagnostics: [] }`, `load_program_bank("voicegroup_broken")` returns `bank: None` or `diagnostics` non-empty. |
| `external/poryaaaa/packages/voicegroup-core/tests/c_api.rs` (optional) | Add a "diagnostics present but snapshot succeeded" C ABI test via the `c_api.rs` test infrastructure (which already uses `voicegroup_core_project_snapshot_result_succeeded` at line 114 for a clean project). |

**Acceptance.** `cargo test -p voicegroup-core` passes with all new assertions.

**Reviewer checks.** Confirm no other Rust code reads `snapshot.succeeded` (search
`src/` and `tests/` for `succeeded`). Confirm `build_catalog` remains infallible.

---

### Wave 2 — C loader `VoicegroupProject` decoupling

**Subagent type:** `task` (multi-file C edit).  
**Reviewer gate:** `reviewer` after implementation.

**Files.**

| File | Change |
|------|--------|
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project.c:29–121` | `project_rebuild()`: **(a)** Remove the `if (voicegroup_core_project_snapshot_result_succeeded(snapshot))` gate at line 70. The install-generation block (lines 72–93) runs unconditionally when `snapshot` is non-null. **(b)** Delete the dead non-fatal failure block (lines 99–121). **(c)** Replace the `!ok` fallthrough (after `project_storage_dispose(storage); free(generation);` at lines 95–96) with a minimal OOM/copy-failure path: `add_simple_diagnostic` with code `"project.out_of_memory"` for the output, free snapshot + index, `PROJECT_REFRESH_FAILED`, `project_failure_copy` for output. **(d)** Add a comment above the install block: "Index is available; install the generation even when the catalog reports diagnostics." |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project_internal.h:94–96` | Remove declarations of `project_storage_copy_failure` and `project_storage_copy_catalog_parts` (private helper, no external callers). |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project_result.c:409–436` | Remove `project_storage_copy_catalog_parts` (lines 409–412) and `project_storage_copy_failure` (lines 414–436). |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project_harness.c:370–405` | Rewrite the "invalid disk" block to test decoupled behavior: **(a)** Write `invalidDisk` (references `MissingSample`), `mark_stale`. **(b)** `load_asset(DirectSound, "DirectSoundWave")` → `CHECK(diagnostic_count == 0 && payload_len == 3)` (unrelated valid asset loads). **(c)** Refresh → `CHECK(snapshot.succeeded && snapshot.diagnostic_count > 0)` (project has diagnostics but index is available). **(d)** `voicegroup_project_load` a bank that references `MissingSample` → `CHECK(!load.succeeded && load.diagnostic_count > 0)`. **(e)** Restore valid `voiceGroups`, `mark_stale`, `load_asset` → valid again. **(f)** Second write of `invalidDisk`, `mark_stale`, `load_asset` → valid asset still loads (confirming the cache is cleared and the new valid index is used). **(g)** `refresh` → `CHECK(recovered.succeeded && recovered.diagnostic_count == 0)` after restoring valid file. |

**Acceptance.** The C harness binary passes under ASan (build with
`PORYAAAA_BUILD_VOICEGROUP_PROJECT_HARNESS=ON`). State machine: stale →
rebuild-with-diagnostics → fresh (generation installed); mark_stale →
rebuild-valid → fresh (diagnostics cleared).

**Reviewer checks.** Verify `project_storage_copy_failure` and
`project_storage_copy_catalog_parts` have no other callers (they are only
referenced in `voicegroup_project.c:100` and `voicegroup_project_result.c:422`).
Verify the OOM fallback doesn't leak the index or snapshot. Verify
`ensure_generation` and `voicegroup_project_load`/`voicegroup_project_load_asset`
early-return logic is unchanged and now correctly only fires on fatal failure.

---

### Wave 3 — Porydaw integration & tests
**Subagent type:** `task` (C++ test update + verification).
**Reviewer gate:** `reviewer` after implementation.

**Mechanical flip:** the `expect(!snapshot.succeeded, …)` → `expect(snapshot.succeeded, …)`
flip in `contextcheck.cpp:196` is a `sonic`-grade edit; the `task` agent owns the
mixed-health sub-test and the caller audit.

**Files.**

| File | Change |
|------|--------|
| `src/checks/contextcheck.cpp:191–198` | **(a)** Flip `expect(!snapshot.succeeded, …)` → `expect(snapshot.succeeded, "corrupt refresh still loads the index and reports diagnostics")`. **(b)** Keep `expect(!snapshot.diagnostics.isEmpty(), …)`. **(c)** Add a new sub-test after the corrupt-refresh block: write a second valid bank file (`voice_group secondary\n\tvoice_directsound 60, 0, DirectSoundWave, 255, 0, 255, 0\n`) in a separate file, register it in the include table, then after corrupting primary bank, assert `loadSaved("secondary")` succeeds, proving mixed-health loading. |
| `src/mainwindow.cpp` | **(a) Verify no change needed.** The `reloadVoicegroup` guard at line 2812 naturally only fires on fatal `!snapshot.succeeded` (which is now rare). The per-source `loadSource` diagnostics handle the per-bank error path. **(b) Optionally add a comment** at line 2812: "Fatal index failure only; non-fatal diagnostics are surfaced per-bank below." |
| `src/project/voicegroupproject.cpp` | **(a) Verify no change needed.** `refresh()` at line 379 now always replaces watches when the index loads (desirable fix). **(b) Optionally update the `Snapshot::succeeded` doc** in the header to match the new semantics. |

**Acceptance.** `deno task build:checks` compiles. Then:
```
deno task verify --filter contextcheck
```
Mixed-health test passes: a corrupt primary bank does not prevent loading a
valid secondary bank. Structured diagnostics are present in the snapshot.

Also run `deno task verify --filter vgcheck` and `--filter vgsavecheck` to
confirm no edit/save/reload regressions.

**Reviewer checks.** Verify no other Porydaw code reads `snapshot.succeeded` and
assumes it means "no diagnostics." The grep from §2.3 shows only `reloadVoicegroup`
(line 2812) and `contextcheck.cpp:196` — both are addressed. `exportcheck.cpp:72`,
`selftest.cpp:33`, `onboardcheck.cpp:135`, `vgsavecheck.cpp:72`, `tabcheck.cpp:623–629`,
`vgcheck.cpp:200,243` all use `snapshot.succeeded` as a "can I proceed?" guard,
which becomes more permissive (correctly) under the new semantics.

---

### Wave 4 — Re-vendor & full verification

**Subagent type:** `task` + `reviewer` (build + verify).  
**No parallel agents** — this wave is a serial gate.

**Steps.**

1. **Rebuild the vendored Rust staticlib.** Run the native-static-libs workflow
   (as documented in the migration plan §14/§17) to produce an updated
   `libvoicegroup_core.a` for the host target (`aarch64-apple-darwin` on this
   workstation). The header `voicegroup_core.h` is NOT regenerated unless cbindgen
   picked up the changed doc comments — verify byte-identical or regenerate.
2. **Update manifest fingerprints.** Update `lib_sha256` in:
   - `third_party/voicegroup-core/lib/aarch64-apple-darwin/manifest.json`
   - `third_party/voicegroup-core/manifest.json` (targets array, aarch64 entry)
   If the header changed, also update `header_sha256` in both files.
3. **Run verification gates:**
   ```bash
   deno task verify:voicegroup-vendor
   deno task build:checks
   deno task verify
   ```
4. **Reviewer:** final sign-off. Confirm all four waves produce a clean diff and
   all acceptance criteria are met.

**Manual verification.** Launch Porydaw against a real decomp project with a
mixed-health voicegroup layout (e.g., temporarily corrupt one voicegroup file
while keeping `hanabi` valid). Verify:
- The voicegroup browser shows the project's catalog rows.
- `hanabi` loads and plays.
- The corrupted bank shows per-row error markers.
- Fixing the corrupted file and refreshing recovers it.

---

## 5. Testing & verification

### 5.1 Automated tests

| Scope | Command | What it covers |
|-------|---------|----------------|
| Rust unit tests | `cargo test -p voicegroup-core` (from `external/poryaaaa/packages/voicegroup-core/`) | `snapshot.succeeded` semantics, mixed-health `load_program_bank`, C ABI round-trip |
| C harness | `voicegroup_project_harness` (CMake, ASan) | State machine, generation retention, mixed-health `load_asset`/`load`, per-bank diagnostics |
| Porydaw contextcheck | `deno task verify --filter contextcheck` | RAII lifecycle, corrupt-refresh → succeeded + diagnostics, mixed-health `loadSaved` |
| Porydaw vgcheck | `deno task verify --filter vgcheck` | Voicegroup editing, save, reload, per-bank diagnostics |
| Porydaw vgsavecheck | `deno task verify --filter vgsavecheck` | Disabled-row rendering, edit/save/undo with diagnostics |
| Vendor integrity | `deno task verify:voicegroup-vendor` | Header + lib sha256, ABI version, manifest consistency |
| Full suite | `deno task verify` | All Porydaw harnesses + Rust + C |

### 5.2 Mixed-health regression cases

1. **Two banks, one broken.** Project has `voicegroup_healthy` (valid) and
   `voicegroup_broken` (references unknown sample). `snapshot.succeeded == true`,
   `snapshot.diagnostics` non-empty (one entry for broken bank). `loadSaved("voicegroup_healthy")`
   → `LoadResult::succeeded() == true`, bank materialized. `loadSaved("voicegroup_broken")`
   → `succeeded() == false`, diagnostics propagated.
2. **Unsupported layout + valid bank.** `discover_unsupported_layouts` records
   a diagnostic for e.g. a `.s` file. `snapshot.succeeded == true`. Valid bank
   loads normally.
3. **Watcher recovery.** Modified file introduces a diagnostic → watcher fires →
   `mark_stale` → `load` triggers rebuild → generation installed with diagnostics
   → valid banks load. File is fixed → watcher fires → `mark_stale` → rebuild →
   diagnostics cleared, `succeeded` still true.
4. **Fatal failure.** Unreadable root → `voicegroup_core_project_index_load`
   returns `LoadFailed` → `PROJECT_REFRESH_FAILED` → `ensure_generation` returns
   false → `load` returns `project.refresh_failed` with cached failure diagnostics
   (last-good generation retained per migration plan §7).

---

## 6. Risks, compatibility, and migration

### 6.1 Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Porydaw caller assumes `succeeded == false` means "no catalog" and skips UI rendering | Low — only `reloadVoicegroup` and `contextcheck` use it; both are addressed | Waves 3–4 verify all callers |
| `project_storage_copy_failure` removal breaks something | Very low — only one call site, now dead | Reviewer gate in Wave 2 |
| Vendored artifact rebuild produces different symbols (unrelated to change) | Low — Rust/Cargo is deterministic for the same source | `verify:voicegroup-vendor` catches mismatch |
| C loader's OOM fallback leaks resources | Low — mirrors existing fatal path pattern | Wave 2 reviewer + ASan run |

### 6.2 Compatibility

- **ABI:** No change. `succeeded` remains `bool` in all structs. No new/removed
  functions, no enum variant changes. The generated header is byte-identical
  (unless a doc comment flows through cbindgen).
- **Porydaw save format:** Unchanged. The voicegroup project file format is
  independent of the loader's diagnostic semantics.
- **Legacy loader:** The `voicegroup_loader` (old code path) is unaffected by
  this change — it operates on the `voicegroup_core` ABI but is already being
  superseded by the migration.

### 6.3 Migration path

This plan is a corrective refinement to the ongoing `voicegroup-core-migration`
(see `docs/voicegroup-core-migration-plan.md`). It resolves the gap between the
migration plan's stated intent ("unless a real partial catalog exists", §4) and
the current code's conflation of catalog health with index availability.

The change is self-contained within the migration's already-modified files. No
new files are created. No existing callers outside the migration scope need
updating.

---

## 7. Alternatives considered

### Alt A — Repurpose `succeeded` (RECOMMENDED)

Redefine `succeeded` = "index available." Minimal ABI surface change. The
"no diagnostics" signal is already available via `diagnostic_count == 0`.

### Alt B — Add a new `index_available` field

Keep `succeeded` = "no diagnostics" and add a separate `index_available: bool`
(or rename `succeeded` to `diagnostics_free` and add `index_available`).

**Rejected.** Larger ABI surface change: new field in `ProjectSnapshot` (Rust),
new accessor in C ABI, new field in `VoicegroupProjectResult` (C), new field in
`Snapshot` (C++). Every consumer of `succeeded` must be audited and potentially
updated. The benefit is marginal: the "no diagnostics" signal is fully
substitutable by `diagnostic_count == 0`.

### Alt C — C-only fix (keep Rust `succeeded` semantics)

Keep `succeeded = diagnostics.is_empty()` in Rust. Change only the C loader to
install the generation regardless of `succeeded`. The C `VoicegroupProjectResult.succeeded`
would still be false when diagnostics exist (copied from Rust), but bank loading
would work.

**Rejected.** Creates inconsistency: `snapshot.succeeded == false` but banks load
fine. Porydaw's `reloadVoicegroup` guard would still abort on non-fatal
diagnostics unless ALSO changed to ignore `succeeded`. The assignment explicitly
asks for a "precise semantic definition for `snapshot.succeeded`," which this
alternative does not provide.

---

## 8. Assumptions & unresolved questions

### Assumptions

1. `ProjectIndex::load()` is the only fatal boundary. If `discovery::load` returns
   `Ok`, the index is fully functional for bank loading. Confirmed by code review:
   all `?` propagation in `discovery.rs` is I/O only; `build_catalog` is infallible.
2. The `voicegroup_core.h` header is generated by `cbindgen` from the Rust source.
   If the changed doc comments flow into the header, the header sha changes and
   the manifest must be updated. The `verify:voicegroup-vendor` task will catch
   this.
3. The native-static-libs workflow (migration plan §14) is functional and can
   rebuild the vendored `.a` from the modified submodule sources.
4. The `PROJECT_REFRESH_FAILED` state is only entered for fatal index failures
   after the change. The migration plan's §7 "last-good generation retained"
   semantics for the fatal case are still correct.

### Unresolved

1. **Should `project_rebuild` merge the retained generation's catalog into the
   fatal failure result?** Currently the fatal path only adds a single
   `project.index_load_failed` diagnostic. The migration plan §9 says "the
   retained snapshot when one exists" should be available. This is a separate
   concern (fatal-failure catalog preservation), out of scope for diagnostic
   resilience. Tracked by migration plan Wave 9.
2. **Cross-platform vendored artifact rebuild.** The plan describes the workflow
   for the workstation target (`aarch64-apple-darwin`). The CI-native-static-libs
   workflow must rebuild all four targets. This is part of the migration's
   freeze-and-vendor sequence (Waves 5–6 in the migration plan); the plan
   author should coordinate with the migration's artifact owner.

---

## Appendix A — File inventory

| File | Wave | Action |
|------|------|--------|
| `external/poryaaaa/packages/voicegroup-core/src/project_index/mod.rs` | 1 | Edit `snapshot()` |
| `external/poryaaaa/packages/voicegroup-core/src/catalog.rs` | 1 | Update field doc |
| `external/poryaaaa/packages/voicegroup-core/src/c_api/project.rs` | 1 | Update function doc |
| `external/poryaaaa/packages/voicegroup-core/tests/project_index.rs` | 1 | Flip assertions, add mixed-health test |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project.c` | 2 | Remove gate, delete dead block, add OOM path |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project_internal.h` | 2 | Remove two declarations |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project_result.c` | 2 | Remove two dead functions |
| `external/poryaaaa/packages/poryaaaa/plugin/voicegroup/voicegroup_project_harness.c` | 2 | Rewrite invalid-disk test block |
| `src/checks/contextcheck.cpp` | 3 | Flip assertion, add mixed-health sub-test |
| `src/mainwindow.cpp` | 3 | Verify + optional comment |
| `src/project/voicegroupproject.cpp` | 3 | Verify + optional doc update |
| `third_party/voicegroup-core/lib/aarch64-apple-darwin/libvoicegroup_core.a` | 4 | Rebuild |
| `third_party/voicegroup-core/lib/aarch64-apple-darwin/manifest.json` | 4 | Update `lib_sha256` |
| `third_party/voicegroup-core/manifest.json` | 4 | Update `lib_sha256` (targets) |

## Appendix B — Subagent type summary

| Wave | Primary agent(s) | Reviewer gate | What each does |
|------|------------------|---------------|----------------|
| 0 | `explorer` | — | Re-confirm Rust + C seams against live tree (read-only, file:line evidence) |
| 1 | `task` + `sonic` | `reviewer` | Rust source change + mixed-health test (`task`); two mechanical `assert!(!succeeded)` flips (`sonic`); reviewer confirms no other `succeeded` consumers |
| 2 | `task` | `reviewer` | C loader edit + harness rewrite; reviewer confirms state machine + OOM safety |
| 3 | `task` + `sonic` | `reviewer` | C++ mixed-health sub-test + caller audit (`task`); one mechanical `expect(!succeeded)` flip (`sonic`); reviewer confirms no regressions |
| 4 | `task` + `reviewer` | (same) | Rebuild vendored artifact, run full verification suite |