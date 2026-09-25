# Context

R21: platform coverage must be explicit and an empty-lane success must be a
failure. Today every Swift lane (`swiftcore`, `projectstore-*`, etc.) is
registered inside `#ifdef __APPLE__` in `src/checks/checkcatalog.cpp`. On a
Linux/Windows build those lanes vanish from `porydaw_checks --manifest`
entirely: `deno task verify` then runs the shrunken set and reports PASS —
`run_checks.ts` never knows the lanes exist on other platforms. A "clean"
non-Apple verify is therefore a misleading empty pass (verification.md:93
calls this out; plan row R21).

# Exact write set

- `src/checks/checkcatalog.h` — `CheckDefinition` gains a platform field
- `src/checks/checkregistry.cpp` — manifest emits the field
- `src/checks/checkcatalog.cpp` — platform declarations on the Apple-gated
  entries (and any entries already host-restricted)
- `tools/run_checks.ts` — manifest parsing, platform accounting, empty-pass
  refusal
- `tools/checks_options.ts` / `tools/checks_reporter.ts` — only if the summary
  surface needs it
- `INSTALL.md` — state which lanes each supported platform currently runs

Controller owns nothing else. No proof ledger edits. Do not un-gate the Swift
lanes or otherwise change which code compiles; the `#ifdef __APPLE__` handler
implementations stay.

# Interface contract

- `CheckDefinition` gains `PlatformMask platforms` (or equivalent enum set;
  `All` default) — a source-level declaration, so catalog readers see the
  intent without reading JSON.
- `manifestEntry` emits `"platforms": ["macos"]`-style data; entries without
  the field remain valid (absent = all platforms) so third-party manifests or
  older fixtures don't break the parser.
- The catalog registers the Swift lanes **unconditionally**: the
  `result.push_back` calls leave `#ifdef __APPLE__`, each entry declares
  `platforms = {macos}`, and the `Handler` is `nullptr` (or an unavailable
  stub) on non-Apple builds — the `swiftCore`/`swiftBank`/`swiftExport`
  function definitions keep their `#ifdef`. A non-Apple manifest still
  *lists* every lane with its platform set; running one off-platform is a
  runner refusal, not a catalog absence.
- `run_checks.ts` classifies each manifest entry as `runnable` or
  `platform-skipped` (host `Deno.build.os` ∉ `platforms`). Platform-skipped
  entries are excluded from the pool but reported in the summary line, e.g.
  `verify: 12/31 ok, 8 skipped, 11 platform-skipped`.
- **Empty-lane refusal:** if a `verify` selection resolves to zero runnable
  entries (whether by filter, platform skip, or empty manifest) the runner
  exits nonzero with an explicit message — `run_checks: N check(s) registered
  but none runnable on this platform` or the existing no-match error — never
  `PASS`. This applies to the bare `deno task verify` default and to filters.
- A lane whose harness runs but reports zero tests is out of scope (Qt Test
  already fails those); this task covers manifest/selection emptiness only.

# Implementation steps

1. Add the field and the manifest key; move the `result.push_back` calls for
   the `#ifdef __APPLE__` entries outside the guard with `platforms = {macos}`
   (the `swiftCore`/`swiftBank`/`swiftExport` function definitions stay gated;
   `Handler` is `nullptr` off-Apple).
2. Parse `platforms` in `run_checks.ts`'s `CheckManifestEntry`; partition
   runnable vs platform-skipped before filtering; extend the summary and the
   "no harness matches" paths so an all-platform-skipped selection exits 2
   with the new message instead of passing.
3. Update `INSTALL.md`'s platform note to reflect that non-Apple manifests now
   list but skip the Swift lanes.

# Acceptance predicate

- `porydaw_checks --manifest` output contains `platforms` on the Swift lanes
  (macOS host: still runnable).
- `deno task verify` on macOS: summary line reports `platform-skipped 0` (or
  omits the term); unchanged PASS.
- Simulated: `--filter` selecting a lane declared macOS-only while pretending
  a foreign host — exercised by a unit-style check or by a manifest fixture —
  must exit nonzero. If no host simulation exists, the implementer adds the
  minimal seam (e.g. `PORYDAW_CHECK_HOST` env override) and proves it.
- `deno task verify --filter doesnotexist` still exits 2 (existing behavior
  preserved).

Controller-run named checks after the writer freezes:
- `deno task build:checks` and inspect `--manifest` JSON
- `deno task verify --filter projectstore --verbose` (lanes still run on macOS)
- `deno task verify --filter nonexistent-lane` (must exit 2)
- env-override simulation of a non-Apple host proving empty-lane refusal

# Task-specific constraints

No un-gating of Swift compilation (the harness still can't link Swift lanes
off Apple today — that's P9 work); no changes to check bodies; no new harness;
no visual-baseline or `--all` behavior changes; preserve exit codes 0/1/2
semantics (2 = selection/setup error, 1 = check failure); keep the runner's
quiet/verbose reporter contract. The platform field is a declaration of where
the lane is *expected* to run, not a discovery mechanism.
