# Independent voicegroup editing

Base and checkpoint: `78bb76e20f18958757ee3fda90d10726442560bf`.
Specification: [spec.md](spec.md).

## Global Constraints

- Work only in `/Users/spencer/dev/cProjects/porydaw/.worktrees/voicegroup-separation`; use absolute file-tool paths and explicit shell cwd. Main checkout stays at the pushed UI checkpoint.
- Swift owns all behavior. Preserve current native storage, section-scoped conflict checks, immutable playback leases, QtBridge ownership and global keyboard shortcut priority. No new module, dispatcher, cache, compatibility shim, polling, fallback, or parallel bank owner.
- Clean cutover: voice edits, kit edits, dirty state, undo/redo, save and lifetime belong to one shared voicegroup session; song assignment remains song history. Preserve unrelated editing, playback, export, backups and creation semantics.
- Reuse named verification commands below. Both writers perform read-only local structural inspection but defer all shared builds, tests, lint and formatting to the controller until sources settle. Report unavailable LSP evidence honestly. No proof ledgers exist in this checkout; do not invent any.
- Session-owned UI notifications must use the existing publication path and QtBridge. Dirty/history/save state must agree; failed or stale operations cannot mark newer changes saved or publish partial histories.
- No commits by implementers. Controller checkpoints the coherent complete refactor only after checks and review; every commit is pushed.

## Tasks

1. **Backend ownership cutover** — SDD-track, `sdd-implementer`; [task-1-brief.md](task-1-brief.md). Exception to three-file default: one end-to-end ownership change spans canonical bank publication, existing history, persistence and the checks that enforce them.
2. **App/QML ownership cutover** — SDD-track, `sdd-implementer`; [task-2-brief.md](task-2-brief.md). Exception to three-file default: one user-visible command/save/close contract spans its existing presenters, QML surfaces and tests. Consumes task 1's public interface only; disjoint writes permit overlap. Controller owns integration rulings.

## Verification and milestone

After both writers freeze, controller runs `uv run --no-sync dev format`, `uv run --no-sync dev build:checks`, `uv run --no-sync dev lsp:swift`, `uv run --no-sync dev checks --filter swiftcore-bankhistory --filter swiftcore-projectsession --filter swiftcore-documenthistory --filter swiftcore-noteedits`, and `uv run --no-sync dev checks:shell --filter shell-voicegroup --filter shell-tabs --filter shell-undo-history --filter shellwindow-shortcuts --filter shellwindow-focus --filter shellwindow-parameter-keys --filter shell-text-contrast --pool=1`, plus `uv run --no-sync dev checks:bridge`, `uv run --no-sync dev checks:qml-aot`, and `uv run --no-sync dev format --check`. Confirm selected harness names from runner output; replace a stale filter rather than counting an empty selection as coverage. Reconcile all regression failures introduced by the cutover; preserve and report unrelated baseline warnings.

Inspect an isolated rendered production surface and exercise voice editing, independent undo/save and last-song close. Use existing QML fixture instrumentation for temporary captures, then remove it. No foreground automation against the user's project.

Expanded integration coverage: `uv run --no-sync dev checks --filter swiftcore-bankhistory --filter swiftcore-projectsession --filter swiftcore-documenthistory --filter swiftcore-noteedits --filter bankleases --filter exportcheck --filter projectstore-bank --filter projectstore-editing --filter projectstore-savebank --pool=1` covers the additional lease/export/storage migrations. `uv run --no-sync dev checks:shell --filter shell-menus --filter shell-split-studio --pool=1` covers menu routing and new-kit saves. `uv run --no-sync dev checks:shell --filter shell-edit-in-studio --filter shell-sample-studio-voice --filter shell-sample-studio-refusal --pool=1` covers stable existing-kit/sample edit origins and refusal behavior.

Audit-driven consumer coverage also runs `--filter shell-export --filter shell-import-commit` in the shell lane (three export harnesses plus import commit). Build each producer serially after Swift lane-source edits, then use `uv run --no-sync dev checks:run build/debug/shell_qml_tests` with the same filters for parallel prebuilt runs; concurrent implicit lane builds race shared outputs.

The R1 audit repair also runs `--filter swiftcore-playback-controller`: real PCM/CGB preview output after bank restoration with no song timeline, stopped/nonadvancing transport, independent-reference timbre, and release-to-silence. This is renderer-boundary evidence, not an end-to-end NativeAudio/device-output claim.

Task-scoped spec/quality review precedes acceptance. Final whole-branch audit is by user-named `m1` (Claude Opus 5.5), explicitly seeking a more graceful design, simpler ownership and removable machinery as well as correctness. Apply actionable findings, reverify affected paths, and obtain fix review. One final coherent checkpoint/push; no per-task bookkeeping commits unless file ownership transfer requires one.
