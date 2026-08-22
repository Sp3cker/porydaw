# SongDocument Refactoring Plans

[`sol-song-document.md`](sol-song-document.md) is the authoritative implementation plan. It resolves disagreements among the source reports, verifies their claims against the repository, and defines the final architecture, phases, invariants, and verification gates.

## Retained source reports

| Report | Contribution retained in the solution |
|---|---|
| [`designer.md`](designer.md) | The one-deep-`SongDocument` seam, domain language, internal ownership boundaries, target layout, and rejection of shallow public role objects. |
| [`reviewer.md`](reviewer.md) | The strongest behavioral-invariant catalogue: `EditOp` ordering, undo symmetry, NoteId lifecycle, overlap rules, remaps, publication order, tempo ownership, and verification coverage. |
| [`evidence-plan-architect.md`](evidence-plan-architect.md) | Phased execution, compile checkpoints, concrete acceptance evidence, and the check-harness gate model. |
| [`thermo-nuclear-reviewer.md`](thermo-nuclear-reviewer.md) | Structural-debt findings and the requirement that the split eventually delete duplication rather than only redistribute it. |

## Best two source reports

1. **`designer.md`** — best architecture and module-seam design.
2. **`reviewer.md`** — best correctness and regression-defense plan.

The evidence-plan report supplied valuable execution mechanics, and the thermo-nuclear report supplied valuable post-split simplification pressure. Neither was safe to execute verbatim; their useful parts are resolved in the authoritative plan.
