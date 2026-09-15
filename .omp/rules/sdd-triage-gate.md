---
name: sdd-triage-gate
description: "Route implementation work before dispatch: Direct for small reversible tasks, SDD-track via sdd-execution-loop for multi-step, risky, or uncertain work."
scope: "tool:task"
---

Before dispatching implementation work with the task tool, run triage. Two
paths; pick one. Decidable without subagents.

## Size the dispatch (both paths)

Every implementation task item lists files touched, numbered steps, and one
acceptance predicate. Defaults: 3 files, 5 steps, 1 acceptance. They bound
dispatch and review effort, never design: they never justify splitting
cohesive work. If the pieces share one behavior change and one verification
surface, keep them in one task however many files it closes over — name the
over-cap exception in the dispatch.
Over the defaults, split BEFORE sending — only at real seams:
1. Cut at interface boundaries; a boundary invented to satisfy the file
   count is not a seam.
2. Give each piece its interfaces and acceptance.
3. Write earlier pieces' outputs as interfaces in later pieces.
Never one big call to save rounds — huge jobs stall, split jobs flow.
Mechanical same-shape edits (same one-line fix across N files) are exempt
from the file count: one dispatch with a per-file list.
An implementer returning BLOCKED/NEEDS_CONTEXT on size means split and
re-dispatch, never push through.


## SDD-track (invoke `sdd-execution-loop`) if ANY is true

1. Multi-file / multi-step with an interface between steps
2. Irreversible / destructive / out-of-worktree side effect
3. Architectural choice with more than one valid approach
4. Spans more than one commit or needs mid-flight verification
5. Uncertain requirements or needs cross-task context

## Else Direct

Inline `# Target / # Change / # Acceptance` in the task item, light
permissive `outputSchema` (`status`, `summary`). No brief file, no reviewer,
no BASE — one round-trip dispatch carries all the context it needs.

Risk overrides size: small but security-sensitive → SDD-track. Explicit user
direction wins over the heuristic ("just do it" → Direct, "follow the plan"
→ SDD-track).
