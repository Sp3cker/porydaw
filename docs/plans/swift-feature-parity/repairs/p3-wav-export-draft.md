# P3 — WAV export: draft brief set

Status: **draft for scope-expansion decision.** plan.md authorizes contract/design work; implementation needs explicit go-ahead. Snapshot source and export invariance are ruled (2026-09-29): the render sees the live unsaved session and the app blocks input for its duration. The remaining VG05 dependency is narrow — a coherent read of the effective mounted bank at accept — so T3 waits only on that exposure contract. All other P3 work is independent.

Spec sources: `spec.md` export contract; `inventory.md` WAV rows; `verification.md` EXPORT row + WAV-export journey; `plan.md` P3 row. Oracle sources: `src/audio/wavexport.cpp`/`wavexport.h` (`wavExportTotals`, `exportWav`: duration law, 4GB guard, RIFF header, suppression pre-roll/flush, 4096-frame chunking, cancel/file cleanup), `src/mainwindow.cpp:1188-1328` (dialog: rate/loop/fade/tail controls, duration preview, dir memory, stopPlayback, progress, feedback) + `:313-315, :964` (File→Export WAV action/enablement). Anti-oracle: `src/checks/projectstore/ExportChecks.swift` — `renderExport`/`wavHeader` are check-local; verification.md requires replacing them with the production owner, not blessing them.

## Hard obligations (extracted)

- Capture the **live unsaved session state** — user ruling 2026-09-29: the export renders what the app currently sounds like, not what's on disk. That means the *edit-buffer* document (all in-flight edits, nothing re-read from the project file), the *effective* bank as currently mounted (including an unsaved bank selection/lease), and the engine/song settings as currently applied. The renderer holds the captured data/lease for its whole lifetime (spec.md:40).
- Export is **modal to the whole application** — user ruling 2026-09-29: between accept and completion/cancel, no user input is accepted; the application state is invariant for the render's duration. There is no mid-export bank switch, tab change, or edit to invalidate the snapshot. The only cancellation path is the export's own Cancel control. Source-session/job teardown (e.g. the app closing) still must not invalidate the borrowed bank mid-render.
- Options: 32000/44100/48000 Hz (48k default); looping mode loops 1–99 (default 2), fade 0–60 s (default 5); non-loop tail 0–60 s (default 3). Live m:ss duration preview; loop-vs-tail control swap; remember output dir (`lastWavExportDir`, default MIDI dir); suggested name = song label + `.wav`.
- Duration law: `fadeStart = loopStart + loopCount*(loopEnd-loopStart)`; `total = fadeStart + round(fade*rate)`; non-loop `total = length + round(tail*rate)`; linear fade gain `1→(pos-fadeStart)/fadeLength`; zero-fade/tail and terminal-frame semantics per `wavexport.cpp:45-57,174-178`.
- Propagate song volume/reverb + engine `maxPcmChannels`/`pcmMixer`/`pcmMixRate`/`analogFilter`. Suppression: `ResonanceSuppressor` pre-roll `kLatency` frames + final zero flush, duration unchanged.
- Stop live playback after accept, before render. Progress 0–1000 + Cancel; success/cancel/error feedback; empty-render and 4GB (`dataSize+36 > UINT32_MAX`) refusals; incomplete output removed on cancel/failure/flush-fail; no song save, no document/history mutation.
- Streamed 4096-frame chunks; **one Swift production owner used by app AND checks**; retire unreachable `wavexport.cpp` only after the replacement passes.

## Task decomposition (dependency edges in brackets)

| Task | Scope | Depends on |
|---|---|---|
| P3-T1 | Export totals + RIFF writer as production owner: rates, loop/fade/tail math, zero cases, 4GB guard. Replaces check-local `wavHeader`/fixture totals. | — |
| P3-T2 | Streamed offline renderer: chunked `AudioRenderEngine` render + linear fade + suppression pre-roll/flush + bounded buffers + monotonic progress/cancel. `ExportChecks.swift` rewritten to call it (no private renderer). | P3-T1 |
| P3-T3 | Snapshot/lease capture + engine-settings contract: unsaved-document + effective-bank pin at accept (point-in-time; input blocked so no invalidation design), teardown safety, stop-playback-before-render. Depends only on VG05's effective-bank exposure, not its full policy. | P3-T2, VG05 exposure |
| P3-T4 | Export dialog + File-menu mount + shell-export lane registration: rate/loop/fade-vs-tail controls, live m:ss duration, dir memory, suggested name, progress/cancel/error/empty/4GB feedback, File-menu enablement. Compare full registry set before mounting; never mount a dead action. | P3-T2, P3-T3 |
| P3-T5 | Acceptance + ledger re-map: independent WAV decode/duration/samples audit; suppression on/off duration equality; cancel-no-partial; fail-write cleanup; re-map `proof.tst_midiexport.txt` (23 MATCHED rows are check-local overclaims until they cite the production owner). | P3-T4 |

## Verification hooks

`deno task verify --filter exportcheck` (existing exportcheck-loop/-tail entries rerouted to the production owner); a new registered shell-export lane staged with its own fixtures; independent WAV inspection per the verification.md journey; `deno task proof check --executed`/`--strict-mappings` after ledger re-map.

## Open decisions for go-ahead

- Effective-bank snapshot policy (VG05 freeze is the named prerequisite).
- RESOLVED 2026-09-29 — export invariance: the application blocks all user input during the render, so the captured snapshot cannot be invalidated by user action; there is no mid-export bank-switch case to design for. Cancel is the only exit.
- RESOLVED 2026-09-29 — snapshot source: the export uses the application's live unsaved state (edit-buffer document + effective mounted bank + applied settings). No disk round-trip, no implicit save.
- Effective-bank lease mechanics narrowed by the invariance ruling: because input is blocked for the render, T3 needs only a point-in-time pin of the effective bank at accept — no invalidation/copy-on-switch design. The remaining VG05 dependency is only *how the effective bank is exposed for capture* (read the mounted lease coherently), not snapshot-vs-switch policy.
- `proof.tst_midiexport.txt`: all 23 MATCHED rows re-derive from the production owner or drop to PARTIAL — no row stays MATCHED on check-local predicates.
- `wavexport.cpp` retirement belongs to P3-T5's commit once the replacement is proven.
