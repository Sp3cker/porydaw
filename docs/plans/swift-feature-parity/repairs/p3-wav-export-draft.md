# P3 — WAV export: draft brief set

Status: **draft for scope-expansion decision.** plan.md authorizes contract/design work; implementation needs explicit go-ahead. P3's effective-bank snapshot contract (P3-T3) depends on the frozen P5/VG05 shared-bank policy — implement and verify bank coherence before accepting the complete journey. All other P3 work is independent.

Spec sources: `spec.md` export contract; `inventory.md` WAV rows; `verification.md` EXPORT row + WAV-export journey; `plan.md` P3 row. Oracle sources: `src/audio/wavexport.cpp`/`wavexport.h` (`wavExportTotals`, `exportWav`: duration law, 4GB guard, RIFF header, suppression pre-roll/flush, 4096-frame chunking, cancel/file cleanup), `src/mainwindow.cpp:1188-1328` (dialog: rate/loop/fade/tail controls, duration preview, dir memory, stopPlayback, progress, feedback) + `:313-315, :964` (File→Export WAV action/enablement). Anti-oracle: `src/checks/projectstore/ExportChecks.swift` — `renderExport`/`wavHeader` are check-local; verification.md requires replacing them with the production owner, not blessing them.

## Hard obligations (extracted)

- Capture the **unsaved** document + effective bank + song/engine settings; private renderer holds captured data/lease for its whole lifetime; source-session/job teardown must not invalidate a borrowed bank (spec.md:40).
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
| P3-T3 | Snapshot/lease capture + engine-settings contract: unsaved-document + effective-bank snapshot, teardown safety, stop-playback-before-render. **Sub-part blocked on frozen VG05 policy.** | P3-T2, VG05 policy |
| P3-T4 | Export dialog + File-menu mount + shell-export lane registration: rate/loop/fade-vs-tail controls, live m:ss duration, dir memory, suggested name, progress/cancel/error/empty/4GB feedback, File-menu enablement. Compare full registry set before mounting; never mount a dead action. | P3-T2, P3-T3 |
| P3-T5 | Acceptance + ledger re-map: independent WAV decode/duration/samples audit; suppression on/off duration equality; cancel-no-partial; fail-write cleanup; re-map `proof.tst_midiexport.txt` (23 MATCHED rows are check-local overclaims until they cite the production owner). | P3-T4 |

## Verification hooks

`deno task verify --filter exportcheck` (existing exportcheck-loop/-tail entries rerouted to the production owner); a new registered shell-export lane staged with its own fixtures; independent WAV inspection per the verification.md journey; `deno task proof check --executed`/`--strict-mappings` after ledger re-map.

## Open decisions for go-ahead

- Effective-bank snapshot policy (VG05 freeze is the named prerequisite).
- `proof.tst_midiexport.txt`: all 23 MATCHED rows re-derive from the production owner or drop to PARTIAL — no row stays MATCHED on check-local predicates.
- `wavexport.cpp` retirement belongs to P3-T5's commit once the replacement is proven.
