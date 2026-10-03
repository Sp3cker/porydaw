# Task 135 brief — startup tab recipes normalize once and reach the mounted tab order

# Context

Make the existing startup tab surface consume the already-implemented saved-recipe contract. ProjectIdentityChecks already has the original data matrix; add the real preference-to-shell consumer instead of a standalone ledger reconciliation.

Selected **17 open rows (17 GAP + 0 PARTIAL)** in `src/checks/project/proof.identity.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A020, A021, A022, A023, A024, A025, A026 | `src/checks/project/identity.cpp:146,147,150,151,152,153,155` — `savedRecipe_dedupOrderSelection` |
| A027, A028, A029, A030 | `src/checks/project/identity.cpp:162,164,168,170` — `savedRecipe_selectionFallbacks` |
| A031, A032, A033, A034, A035, A036 | `src/checks/project/identity.cpp:177,179,180,182,185,186` — `savedRecipe_legacySingleLabelAndEmpty` |

# Exact write set

- `src/swift/project/ProjectIdentity.swift`
- `src/swift/app/timeline/EditorViewStateCodec.swift`
- `src/checks/projectstore/ProjectIdentityChecks.swift`
- `src/checks/editorqml/tst_ShellTabs.qml`
- `src/checks/project/proof.identity.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 118 complete view-state producer and all 123–130 work. Task 138 preserves this startup contract; the ledger writer serializes this identity-ledger portion with task 136.

# Interface contract

Keep normalizeSavedRecipe(projectPath:labels:selected:) and WorkspaceTabRecipe as existing value boundaries. Reuse normalization in EditorViewStateCodec.loadTabs rather than maintaining divergent empty/dedup/fallback rules. Preserve project path; labels b, empty, a, b, c, a become b,a,c with a selected; missing/empty selection falls back to the first surviving label. Empty ordered labels plus selected solo produce one solo tab; fully empty recipe produces none. Mounted cases use the same equivalence classes with actual fixture labels and synchronized isolated preferences, then observe exact tab order and selected page after startup. Availability filtering remains a later projection: a deleted recipe song creates no phantom tab and successful restore must not rewrite its stored recipe.

# Implementation steps

1. Compare the two existing normalizers and consolidate only their shared saved-recipe semantics at the load boundary, keeping playable-song filtering in WorkspaceTabRecipe.normalized(available:).
2. Retain existing original data-matrix checks and add mounted duplicate/empty/missing-selection/legacy recipe journeys with exact expected order and selection.
3. Prove opening and closing the shell preserves unrelated preference keys and project files; map only the recipe rows.

# Acceptance predicate

The pure recipe matrix and the real startup shell agree on deduplication, ordering and selection, including legacy/empty input. projectidentitycheck runs savedRecipe; shell-tabs mounts production startup with isolated settings.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectidentitycheck --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs --verbose
```

# Task-specific constraints

Do not change startup request priority, auto-catalog scheduling, missing-project path policy, per-tab camera persistence or task-118 lane state. Identity A001–A019 and A037–A052 are not writable here. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
