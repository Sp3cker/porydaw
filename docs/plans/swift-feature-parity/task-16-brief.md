# Context

R20: the proof validator must reject meaningless MATCHED mappings. Today
`deno task proof check` (`tools/proof_reader.ts` `check` command) verifies only
that cited S-predicates exist and their `Anchor:` resolves. It never requires a
MATCHED site to cite any predicate: 611 MATCHED sites across the corpus carry
no `Mapping:` line at all (a bare header + `Disposition: MATCHED`), and a
further ~250 compact MATCHED sites cite only `Anchor: function` or `deleted`
predicates — anchors that prove a function exists, not that it asserts the
site's contract. The plan requires meaningful MATCHED mappings with **no bulk
ledger rewrite**: the existing 4,786 MATCHED sites cannot all be forced to a
new bar in this task.

# Exact write set

- `tools/proof_reader.ts` — the `check` command's site-mapping validation
- `deno.json` — proof task permission flags only if the new code needs them
- `docs/plans/swift-feature-parity/verification.md` — document the new rule

Controller owns nothing else. No ledger `proof.*.txt` edits: this task must not
touch any ledger row. Excluded on purpose: `tools/proof_editor.ts` and
`tools/proof_compact.ts` behavior stays as-is; their output must still pass the
strengthened check.

# Interface contract

- Add `deno task proof check --strict-mappings` (invoked as
  `tools/proof_reader.ts check --strict-mappings`), which fails on any MATCHED
  site that (a) has no `Mapping:`/`Mapping/reason:`/`Swift:` line citing at
  least one `S###` predicate id defined in the same ledger, or (b) cites only
  predicates whose `Anchor:` is `function` or `deleted`. PARTIAL/GAP/
  RETIRED-*/NATIVE-* rows are not judged.
- Default `deno task proof check` (and `--executed`) keep today's behavior
  plus a non-fatal warning line naming how many sites would fail the strict
  rule, so existing ledgers stay valid while the debt is visible:
  `… strict-mapping debt: N site(s)`.
- The strict failure message lists each offending `path site-id` and exits
  nonzero, matching the existing `proof check error(s)` style.
- `verification.md` gains the rule in its proof-acceptance section: *every new
  or rewritten MATCHED row must cite at least one predicate whose anchor is a
  `message` (or equivalent non-function/deleted) anchor; run
  `deno task proof check --strict-mappings` before claiming a ledger closed.*
- No change to anchor resolution, `--executed` classification, `list`,
  `show`, `sites`, or `search` output beyond the added warning/failure.

# Implementation steps

1. Extend `check` in `proof_reader.ts`: after the existing anchor-resolution
   pass, compute per-site "meaningful mapping" per the contract using the
   already-parsed `Site`/`Predicate` structures (`mappingIds(site)` exists;
   predicate anchor kinds are available via `predicate.anchor?.kind`).
2. Print the debt count under default `check`; under `--strict-mappings`
   escalate the same list to a thrown error naming each site.
3. Record the rule in `verification.md` where the ledger acceptance policy
   lives (near "An unresolved proof row is not automatically a missing
   feature").
4. Sanity-run both modes from the controller's commands below; report the
   current debt number in the task report (expected ~861).

# Acceptance predicate

- `deno task proof check` — exit 0, prints the debt warning count.
- `deno task proof check --executed` — unchanged classification output plus
  the warning.
- `deno task proof check --strict-mappings` — exit 1 today, naming sites
  (e.g. `mainwindowrouting/proof.tst_mainwindowrouting_native.txt A002`).
- No ledger file modified; `git status src/checks` clean.
- `deno task build:checks` / a spot verify lane unchanged.

Controller-run named checks after the writer freezes:
- `deno task proof check`
- `deno task proof check --strict-mappings` (expected failure listing sites)
- `deno task verify --filter projectstore --verbose` (toolchain smoke)

# Task-specific constraints

No ledger edits, no retro-failing default `check`, no new disposition labels,
no second validator binary, no bulk rewrite of existing rows. Keep the reader
single-pass and read-only; reuse `mappingIds`, parsed anchors and the existing
error-aggregation style. `git` is not available to the reader under current
task permissions — do not shell out; strict mode compares structure, not
history.
