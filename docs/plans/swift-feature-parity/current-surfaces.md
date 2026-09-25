# Current-surface parity execution

User direction, 2026-09-24: prioritize missing details in current surfaces over adding absent legacy features. Do not create new QML for old features: reuse the adapted surface or recover/copy original QML and adapt it to Swift. UI scope is bounded by C++ checks/proofs, not speculative manual features. User authorizes desktop verification and independent judgment while away.

This is a historical batch record, not a second active plan. [plan.md](plan.md) is authoritative for current scope and every pending, active, complete or blocked obligation. Sample Studio, WAV export, onboarding and other absent surfaces remain required but blocked by the existing-surface scope restriction.

## Baseline and ownership

Execution baseline: `1096534c7d3e97c17a785625a93a215459c39d6e`. Menu/transport/drawer/About and roll display-mode work landed after the planning snapshot; preserve it. Existing .omp changes are unrelated and must not be overwritten. The separately authored menu handoff was later consolidated, with user authorization, into [shell migration history](../../old/swift-migration-shell.md).

Three disjoint implementation lanes:

1. Existing shell commands: ShellPresenter, ShellWindow, existing ShellMenus/PitchBend QML checks. Restore only still-missing semantic command routes supported by original proofs. No new dialog/surface.
2. Ghost rendering: PianoGrid, GridScene, existing note_rendering/keyboard Swift checks. Restore other-track ghost projection and scoped time-selection highlights without ghost editability; preserve newly integrated display modes.
3. Ruler details: RulerMenuPresenter, ApplicationSession, existing EditorSurface QML, ruler_loop_menu/timemenu checks. Recover modifier scope, exact chip ticks and seek semantics from original assertions/QML. No new controls.

Each implementer must report exact affected proof files/A sites and executing predicate locations. They do not edit proofs or run shared gates. The controller runs settled-tree Swift and QML suites, exercises the production desktop, freezes checks, then delegates proof-only edits to ledger-agent. Match only exact executed behavior; keep unrelated GAP/PARTIAL/native obligations unchanged. Review the complete code/check/proof changes before acceptance.

Commands: `deno task verify --filter swiftcore --verbose`, `deno task verify:shell --filter shell-menus --verbose`, `deno task verify:shell --filter shell-pitch-bend --verbose`, `deno task verify:qml-roll --verbose`, then `deno task proof check` and executed-evidence inspection. Read registrations before accepting filters; run broader affected lanes for final integration.

## Completed current-surface batch

- Shell: restored G pitch bend, Set Velocity, Loop from Selection and event-move routes through existing commands. Mounted checks exercise the actual shortcut/popup, menu effects and exact two-step loop-marker Undo behavior.
- Roll: other-track ghost notes render without becoming editable or auditionable. Track-scoped time selections highlight covered primary/ghost notes without adding them to explicit note selection. Lane-only ranges do not highlight notes. Projection reserves its cached total note count.
- Ruler: modifier scope is captured at press; tap, cancellation, half-open containment and exact chip ticks retain their distinct behavior. Paused seeking updates the shared playhead immediately; stopped seeking changes only the edit cursor. Origin-bound callbacks prevent retained background tabs from seeking the selected song.
- Existing QML files were adapted. No new production QML surface, sample editor, export dialog or onboarding UI was introduced.

Historical verification for that batch, before the later branch assessment and integration repairs:

| Command | Observed result |
| --- | --- |
| `deno task verify --filter swiftcore --verbose` | PASS; registered Swift core suite, 16.53s. |
| `deno task verify:qml-roll --verbose` | PASS; Swift roll window lane, 22.82s. |
| `deno task verify:shell --filter shell-menus --filter shell-pitch-bend --filter shell-grid-input --filter shell-grid-menu --filter shell-transport --verbose` | Menu, pitch-bend, grid-input and grid-menu lanes passed. The new background-ruler test initially exposed a missing explicit QML invokable argument; that check call was corrected. |
| `deno task verify:shell --filter shell-transport --verbose` | PASS after the argument correction; all transport cases including paused/stopped seek and background-tab isolation, 3.99s. |
| `deno task build:checks` | PASS; final application and checks linked, 1.34s. |
| `deno task proof check` | PASS; 188 files, 13,789 original sites, 9,458 resolved anchors including 28 historical anchors. |
| `deno task proof check --executed` | PASS; 8,830 executed, 13 not executed, 615 unverifiable across the existing evidence corpus. The 13 not-executed anchors are outside the changed ledgers; aggregate success is not complete product parity. |

Native macOS observations: G opened the existing note-automation popup on a selected note without dirtying the document; modified ruler sweeps highlighted covered ghosts and plain sweeps excluded them; a paused ruler seek moved the red playhead and clock to the white cursor. These desktop observations supplement, rather than replace, executing check predicates.

Proof-only reconciliation followed frozen checks. `selectionkey/proof.localinputtier_pitchbend.txt` A004 and `rollcheck/proof.keyboard.txt` A054 are now MATCHED. Other strengthened rows retain PARTIAL where native delivery, exact trigger counts or framebuffer pixels remain unproved. No legacy checks were retired. All three task reviews approved the final changes after correcting ruler callback ownership and splitting its multi-purpose check.

Tooling limits: QML LSP was unavailable. `deno task lsp:swift` completed but indexed 0/0 targets; this is not evidence of a refreshed Swift reference index. Compiler and runtime gates above provide the recorded validation.
