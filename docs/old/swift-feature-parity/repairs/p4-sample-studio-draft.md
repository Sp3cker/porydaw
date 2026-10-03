# P4 — Sample Studio: draft brief set

Status: **draft for scope-expansion decision.** plan.md authorizes contract/design work; implementation needs explicit go-ahead. P4's bank-assignment/commit-visibility contract depends on the frozen P5/VG05 shared-bank policy — bank coherence is implemented and verified before the complete journey is accepted. Decode/DSP/audition/commit mechanics are independent of it.

Spec sources: `spec.md` sample contract; `inventory.md` SA01–SA06 rows; `verification.md` Sample-Studio journey; `plan.md` P4 row. Oracle sources: `src/audio/sampleimport.cpp/.h`, `sf2reader.cpp/.h`, `sampledoc.cpp/.h`, `sampledsp.cpp/.h`, `samplewav.cpp/.h`, `src/ui/sampleeditordialog.*`, `src/ui/waveformview.cpp`, `src/ui/workspaceui_samples.cpp`, `docs/old/sample-editor/{FORMATS,DSP}.md`. Deleted-but-pinned check oracles: `src/checks/samplecheck/*.cpp` at `a7fcaa3` (decoder at `5af4355`, dsp at `1f9f8a5`). Ledgers (spec): `src/checks/samplecheck/proof.{decoder,soundfont,dsp,analysis,editor,project,integration}.txt` — ≈408 GAP total, 0 PARTIAL; the 14 analysis MATCHED rows cover the audition primitive only.

Existing Swift seams: `AudioSampleAudition` (4-slot engine-true publish/ack), `SamplePicker.qml` + `ProjectStore+Picker.swift` (symbol picker — picker, not editor), `VoiceListController.swift:153-155` nil `onNewSampleRequested`/`onEditSampleRequested` (the P4 mount seam, invoked :554-558).

## Hard obligations (extracted)

- **SA01 launch:** Tools/Import Sample + New/Edit-beside-voice routes; source-selection + reopen workflows; wire the nil callbacks into real destinations (Tools import = no slot; voice import = destination slot).
- **SA02 decode:** WAV/AIFF/MP3/FLAC/Ogg content-sniffed; SoundFont preset/instrument/zone search + pitch/root/fine + loop-bound conversion + ROM-zone/unsupported refusals + linked-stereo warning; malformed/truncated refusal; hi-res source immutable; fractional rates; PCM width/float laws; mono left-channel + phase-cancel warning recorded in provenance; GBA-ready 8-bit mono WAV no-op path.
- **SA03 DSP/editor:** crop, DC policy, resample, normalize, loop crossfade, micro-fades, quantize/dither in the existing render order; retune = pitch metadata only; old DSP tests are the numerical oracle; pitch-detect = hint only; loop candidate cycling/refinement + seam metrics; crop+loop handles, anchored zoom/pan/fit, seam view, display gain, audition playhead, bounded markers; rate-commit discipline; ROM cost/duration + warnings; dialog-local parameter undo — commit stays write-through, assignment stays song/bank history.
- **SA04 audition:** reuse `AudioSampleAudition`; key choice, destination-voice ADSR, live param/handle updates, one-shot repeat, dialog-local Space, single play/stop strip; stop + release-after-callback on cancel/close/project-change.
- **SA05 commit:** unsigned-8-bit WAV + registration into wav2agb projects only; real pipeline/anchor probe; actionable refusal for legacy AIF/aif2pcm or missing wav2agb/inc; sanitized/prefilled names validated vs symbols + WAV/BIN paths; refused/cancelled create overwrites nothing; new commit = sample+registration+provenance; voice-initiated commit then assigns as normal undoable bank edit (undo assignment ≠ remove sample); existing-sample edit refreshes catalog/audio with no fabricated bank edit.
- **SA06 provenance:** sidecar = source path/hash + SF zone + channel choice + param state; reopen uses unchanged hi-res source; changed/missing → committed-WAV fallback with old warning/sidecar-invalidation; asset bytes/freq/play-length/loop ≡ final audition PCM ≡ wav2agb output incl. RIFF padding + smpl/agbp/agbl laws.

## Task decomposition (dependency edges in brackets)

| Task | Scope | Depends on |
|---|---|---|
| P4-T1 | Sample decode owner: content-sniffed containers, refusal taxonomy, stereo policy, GBA-ready no-op; decoder-ledger slice. | — |
| P4-T2 | SoundFont zone import: preset/instrument/zone search, pitch/loop conversion, ROM/unsupported refusals, linked-stereo warning; soundfont-ledger slice. | — |
| P4-T3 | DSP kernel: render-ordered crop/DC/resample/normalize/crossfade/micro-fade/quantize-dither + retune-metadata-only + fixed-seed determinism vs old oracle; dsp-ledger slice. | P4-T1 |
| P4-T4 | Editor dialog + analysis: pitch-hint, loop suggest/cycle/refine + seam metrics, waveform handles/zoom/seam/gain/playhead, rate-commit, ROM cost/warnings, dialog-local undo; analysis+editor DSP-UI slice. | P4-T1, P4-T3 |
| P4-T5 | Engine-true audition strip on `AudioSampleAudition` + teardown lifetime; preview-bytes ≡ commit-bytes invariant. | P4-T3, P4-T4 |
| P4-T6 | Commit/registration + voice assignment: 8-bit WAV write, pipeline probe, AIF/wav2agb refusals, name sanitize/validate, write-order/failure guarantees; assign-vs-edit-refresh split (**visibility sub-part blocked on VG05**); project-ledger slice. | P4-T1, P4-T5, VG05 policy |
| P4-T7 | Provenance/reopen + ROM-pipeline agreement: sidecar, hash check, unchanged-source reopen, changed/missing fallback, asset≡audition≡wav2agb byte agreement; integration-ledger slice. | P4-T1, P4-T6 |
| P4-T8 | Surface mount + lanes + ledger closeout: wire nil New/Edit callbacks + Tools route, destination-slot plumbing, new samplecheck runner lane + shell/editor lane, all seven ledgers re-mapped, Sample-Studio journey. | P4-T2, P4-T4, P4-T6 |

## Verification hooks

New registered samplecheck runner lane (none exists today — no checkcatalog/cli.ts registration; must stage own fixtures and prove predicates ran); a shell/editor lane mounting the production surface; `deno task verify --filter swiftcore` for domain predicates; ledger re-map under the same-commit rule; ROM asset comparison per the verification.md journey.

## Open decisions for go-ahead

- Bank assignment/commit visibility policy (VG05 freeze is the named prerequisite).
- NATIVE-row classification in editor (50), soundfont (12), dsp (6), integration (3) ledgers — per-row surviving-behavior vs retired-representation at brief time.
- `VoiceListController` + `ApplicationSession` are P5-shared files; P4-T8's mount must coordinate with the P5 sample-return path consumer.
