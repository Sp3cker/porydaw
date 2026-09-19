# Swift ownership cutover — executable plan (authorized slice)

Execution plan for the user-authorized slice only (2026-09-19): M0 baseline +
probe, one production-Swift organization task, and the corrected M1/M2 gate
design. Not authorized by this plan: new legacy-client facade, expanded C ABI
vocabulary, production header retirement, document-authority cutover, disabled
editing features, replacement window/input dispatcher.

Design: [design.md](design.md). Governing: charter
(../../swift-backend-charter.md — normative) and the
[QtBridge integration contract](../../qtbridge-integration-contract.md)
(baseline + evidence ledger).

## Global Constraints

- Charter `swift-backend-charter.md` applies whole: prime directive (no
  workarounds without approval), Swift implementation policy, INV-1/2/3,
  S-1..S-5, V-1..V-3, interop taxonomy, retirement table.
- The integration contract's evidence ledger is the only place bridge
  guarantees are recorded; a probe row is `Verified`/`Unsupported` only with
  executed commands and observed results. Capability proof is not production
  header parity and never retires a production surface.
- Behavior-preserving only: user-visible behavior of retained surfaces does
  not change in the organization task. Deletions must have zero-caller
  evidence or named covering-check migration.
- Checks are registered under `src/checks/` and run via
  `deno task verify --filter <name> --verbose`; implementers never build,
  format, or run shared checks (controller gates on the settled batch).
- Quality gate: thermo-nuclear review per design.md §"Mandatory thermo-nuclear
  quality gates" (referenced, not duplicated, here).
- C ABI frozen: no new or widened `sg*` symbols; existing names unchanged.

## Tasks

1. **m0-probe** — [task-m0-probe-brief.md](task-m0-probe-brief.md): build the
   `swiftqtml` harness proving the contract's observable model-update rows
   through real QML delegates; controller records ledger outcomes.
2. **swift-org** — [task-swift-org-brief.md](task-swift-org-brief.md): bounded
   production-Swift rehome + obsolete-code retirement with zero-caller
   evidence.
