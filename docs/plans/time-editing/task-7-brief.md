# Task 7: Document verified time editing

## Context

Tasks 4/6 supply exercised window and menu contracts. These existing user documents are the final consumers; no further production interface is introduced.

## Exact write set

- `docsrc/manual/piano-roll.md`
- `docsrc/manual/shortcuts.md`
- `CHANGELOG.md`

## Prerequisites

Task 4: window routing evidence. Task 6: menu safety evidence. Integration gate in plan.md passed.

## Interface contract

Update the existing time-editing section in `piano-roll.md`, binding descriptions in `shortcuts.md` and Unreleased Added/Changed sections in `CHANGELOG.md` as the user-facing owners of the accepted [behavior and interfaces](plan.md#behavior-and-interfaces). Keep the distinction between clearing contents and removing duration there, not in a parallel guide.

## Implementation steps

1. Update piano-roll.md time editing to explain selection scope/anchor, no-selection Insert prompting, rejected active scope, selection-only Delete and both context-menu paths.
2. Update shortcuts.md for selection-aware Insert and default-unbound Delete Time using the existing platform key naming convention; ordinary Delete/Cut remain contents-only.
3. Add concise Added/Changed Unreleased entries using the existing changelog structure; preserve unrelated entries.
4. Compare claims with accepted source behavior and recorded runtime evidence; inspect Markdown and resolve local link targets.

## Acceptance predicate

The three documents match verified behavior, labels and bindings without promising a deletion prompt or destructive default shortcut. Named checks: source/evidence comparison and Markdown inspection; local-link resolution: `python3 -c 'from pathlib import Path; import re; files = [Path(p) for p in ("docsrc/manual/piano-roll.md", "docsrc/manual/shortcuts.md", "CHANGELOG.md")]; missing = [(str(p), u) for p in files for u in re.findall(r"\]\(([^)]+)\)", p.read_text()) if not re.match(r"[a-zA-Z]+:|#|/", u) and not (p.parent / u.split("#")[0]).exists()]; assert not missing, missing'`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: the familiar Insert shortcut now edits immediately when a selection exists; describe that change explicitly rather than implying it always prompts. No application build for documentation-only validation; link validation supplements, not replaces, semantic inspection.
