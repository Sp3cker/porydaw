---
name: ledger-delegation
description: "When Porydaw Swift checks change or proof files need bookkeeping, route proof correspondence to the DeepSeek ledger-agent before accepting or reviewing the task."
alwaysApply: true
agents: [main, task, sdd-implementer]
---

In Porydaw, after changes to Swift checks affecting `src/checks/**/proof.*.txt`, delegate the **proof-only** reconciliation to `ledger-agent` (`deepseek/deepseek-flash:max`). The check implementer finishes and freezes the check sources first; the ledger agent owns only the explicitly named proof files. Send it the changed Swift check paths, affected ledgers, applicable brief/spec, observed verification command/result, and a stable source snapshot. Do not ask it to guess missing assertions or re-run the suite.

`main` and a `task` agent acting as controller dispatch the ledger agent via `task` before the proof gate, task review, or C++ check retirement. A `task` agent without subagent-spawn access reports the needed handoff to its controller rather than silently doing repetitive proof edits. `sdd-implementer` does not spawn agents: when the controller explicitly assigns proof ownership to `ledger-agent`, implement the checks, report affected ledger paths/site identities and final Swift predicate locations, and mark proof work pending in the result; do not claim the whole brief DONE until the controller completes the proof gate. If a brief explicitly requires the implementer to edit proofs and the controller has not reassigned that ownership, follow the brief and ask the controller before deviating.

The controller verifies ledger output: `A###` to exact executing `S###` links, mappings/dispositions, predicate paths/lines/expressions, current Swift hashes, tallies, original provenance, and `deno task proof check` (structure only). Preserve unresolved `GAP`/`PARTIAL` rather than asserting parity. Serialize proof edits after check sources settle; assign a single ledger writer per file, never run both owners on the same proof concurrently. Review and verify the complete check+proof task before accepting it.
