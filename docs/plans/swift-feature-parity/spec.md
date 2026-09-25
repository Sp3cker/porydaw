# Required behavior contracts

These are preservation requirements for the [roadmap](plan.md), not new Swift interface declarations. Implementations may change representation; user outcomes and file/audio laws may not silently change. [inventory.md](inventory.md) owns current status; [verification.md](verification.md) owns commands and evidence policy.

## Sample Studio — complete delivery contract

### Source and decode

- Preserve WAV, AIFF, MP3, FLAC, Ogg and SoundFont zone import. Detect container content rather than trusting suffixes; malformed/truncated/unsupported input is a refusal, not an empty successful sample.
- Keep decoded high-resolution source immutable; edited parameters derive previews/output without cumulative resampling or destructive source changes. Retain fractional source rates, pitch metadata, playable length and source-domain marker semantics: crop end exclusive, loop end inclusive.
- Preserve PCM widths/float behavior, mono conversion and the warning/left-channel choice for phase-cancelling stereo. Record that choice in provenance. Existing GBA-ready 8-bit mono WAV sources retain the no-op/default path, including untouched exact pitch metadata.
- SoundFont import includes searchable preset/instrument/zone selection, pitch/root/fine-correction conversion, loop-bound conversion, unsupported/ROM-zone refusals and linked-stereo warning behavior. Selecting a symbol already in the project is not a replacement for this workflow.

Sources: `src/audio/sampledata.h`, `sampleimport.cpp`, `sf2reader.cpp`; [historical formats](../../old/sample-editor/FORMATS.md); samplecheck decoder/soundfont ledgers.

### DSP and waveform editor

- Preserve crop, DC policy, resampling, normalization, loop crossfade, micro-fades, quantization/dither and metadata in the **existing render order**. Retune changes pitch metadata, not the audio's sample spacing. Keep exact pitch override only when the original contract permits it.
- Use the old DSP implementation/tests as the numerical oracle: loop-aware resampling and loop-ratio correction, alias/passband and gain limits, silent-input handling, deterministic signed-8 floor/clamp quantization and fixed-seed dither. Do not replace these with “sounds close” checks or pin the new algorithm's output as the expected result.
- Pitch detection is a hint/prefill with unpitched/low-confidence behavior; it must not silently overwrite deliberate pitch metadata. Preserve candidate loop cycling/refinement, first-enable loop population and seam amplitude/slope/correlation diagnostics, including “not meaningful” correlation without enough context.
- Waveform interaction includes crop and loop handles, anchored zoom/pan/fit, processed seam view, display gain, audition playhead and bounded marker relationships. Keep controls usable when the window shrinks; scrolling and splitter behavior are part of the surface.
- Preserve rate commit on preset/Return/focus-out rather than destructive reprocessing for every typed digit; loop toggle/crossfade, root/fine-tuning, normalize controls, pitch-apply hint, ROM cost/duration and warnings must remain available.
- Editing has a **dialog-local parameter undo history**: one drag/merged spin gesture per edit, undo/redo restores the rendered result. This is not a second song history: sample file commit remains write-through, and assignment to a voice belongs to the song/bank history.

Sources: `src/audio/sampledoc.cpp`, `sampledsp.cpp`, `sampledata.h`; [historical DSP contract](../../old/sample-editor/DSP.md); `src/ui/sampleeditordialog.cpp`, `waveformview.cpp`; samplecheck analysis/dsp/editor ledgers.

### Audition, commit and reopen

- Reuse the existing sample-audition owner. Preserve key choice, destination voice ADSR, live parameter/handle updates, one-shot repeat behavior and dialog-local Space audition of the rendered sample. The shipped strip is one play/stop control, not an original/final A/B selector. On cancel/close/project change, stop audition and release buffers only after the callback no longer consumes them.
- Final audition PCM, WAV metadata and the asset produced by the project's wav2agb pipeline must agree: sample bytes, frequency, play length and loop start/end. Preserve RIFF padding and `smpl`/`agbp`/`agbl` laws. Sample files are unsigned 8-bit WAV; song WAV export is a separate stereo 16-bit format.
- Probe the actual project build pipeline and registration anchor. Preserve actionable refusal for legacy AIF/aif2pcm or missing wav2agb/inc support; do not silently write unusable assets or install tools.
- Sanitize/prefill names and validate typed names against symbols plus existing WAV/BIN paths. A refused/cancelled create does not overwrite another sample. New commit writes the sample, registration and provenance with the old failure/write-order guarantees; existing-sample edit keeps its name and registration stable.
- A Tools import has no destination slot. A voice-initiated import commits the sample and then assigns it as a normal undoable bank edit, preserving the destination voice's applicable type/ADSR. Undoing assignment does not remove the newly registered sample. Existing sample editing refreshes catalog/audio without fabricating a new bank edit.
- Provenance includes source path/hash, SoundFont zone, channel choice and parameter state. Reopen uses unchanged hi-res source; unavailable/changed source falls back to committed WAV with the old warning/sidecar-invalidating policy. Do not confuse sample provenance with obsolete song-view sidecars.

Sources: `src/audio/samplewav.cpp`; `src/ui/workspaceui_samples.cpp`; historical `SampleRegistrar`/`SampleSidecar` in samplecheck project/integration ledgers; current `AudioSampleAudition.swift` and `ProjectStore+Picker.swift`.

## WAV export — one production implementation

- Export captures the active unsaved document, effective voice bank and song/engine settings. The private renderer uses the captured data/lease for its whole lifetime, never saved-on-disk MIDI as a substitute. Source-session/job teardown cannot invalidate a borrowed bank.
- Preserve user options: 32,000/44,100/48,000 Hz (48,000 default); looping songs use 1–99 loops (2 default), fade 0–60 seconds (5 default); nonlooping songs use tail 0–60 seconds (3 default). Show live duration and appropriate loop-vs-tail controls, remember output directory and use the song label as the suggested name.
- Loop duration: `fadeStart = loopStart + loopCount * (loopEnd - loopStart)`; total frames add fade rounded to the export sample rate. Nonloop total adds rounded tail to song length. Preserve linear fade law, zero fade/tail behavior and terminal-frame semantics.
- Propagate song volume/reverb plus engine PCM limit/mixer/mix-rate/analog-filter settings. Suppression output must compensate the existing fixed processing latency by pre-roll and final zero flush without adding initial silence or dropping the tail. Expected duration does not change when suppression toggles.
- Stop live playback after options/path acceptance and before render, as the original UI does. Preserve cancellation at both dialogs and during render, progress, success/cancel/error feedback, empty-render and RIFF 4GB refusals, and removal of incomplete output. No forced song save or mutation of document/history.
- Stream output with bounded buffers; do not retain the whole song's PCM. Use one Swift production owner for app and checks. Replace `ExportChecks.swift`'s private renderer/header implementation instead of blessing it as production parity. The old unreachable C++ export owner retires only after its complete replacement passes.

Sources: `src/mainwindow.cpp:1188-1328`, `src/audio/wavexport.cpp`, `src/checks/midi/proof.tst_midiexport.txt`. Current test limitation: `src/checks/projectstore/ExportChecks.swift`.

## Onboarding and project writes

- Reuse the existing MIDI codec/import analyzer, registration writers and store. New/import wizard preserves source file, chosen label/constant/player/config, optional new bank and format/timing/duplicate-setter decisions. Keep track/polyphony/unsupported-control warnings and remembered file-picker directory. Do not add a window-drop/package importer under the parity label.
- Creating a bank is a real file/include operation followed by undoable song assignment; honor per-file/monolithic layout capabilities, naming/collisions and copy/template choices. It must be ready before New Song offers it.
- Registration writes only the required song lines in the table/constants/linker/charmap/debug lists, preserving unrelated bytes, line endings and numeric-ID contracts. Cover free slots, partial registrations, alias/value region markers, expansion debug-list shape and idempotent retry.
- Preserve partial-success semantics: a registration failure may leave a usable but unregistered song with a retry badge; do not turn that into silent success or delete the user's new composition. Freeze the original create/write order before implementing a transaction abstraction.
- Song deletion retains fallback ID 0 refusal, dirty-open-song refusal, trash destination/collision handling, table holes/tail trimming, and conservative optional unused-bank deletion. Do not introduce permanent asset cleanup into this command.
- Ordered save and stale-save identity, external-change detection, pending synth materialization and bank-switch history remain invariants for every new flow. Test real unwritable/conflicting files, not only mocked completion callbacks.

Sources: `src/ui/workspaceui_samples.cpp:31-90`; historical NewSongWizard and project/check oracles; `src/swift/project/SongRegistration*.swift`, `MidiCfg.swift`, `SongsMk.swift`, `VoicegroupSave.swift`; onboardcheck and voicegroupsave ledgers.

## Existing editors, settings and lifecycle

The inventory's ED/SH/PJ rows are preservation requirements, not permission to redesign working editors. Important cross-surface invariants:

- Menus, context menus and keys invoke the same semantic operation and share enablement; checks must press the advertised key/click the control at least once, not exclusively call the presenter.
- Ghost-track context is visible but not a second editing target; time-range coverage and selected-track scope must match the legacy behavior. Ruler modifier sweep, exact loop/signature chip hits and out-of-selection cursor/seek behavior must survive.
- Distinguish toolbar Play's resume from Space's start-at-edit-cursor behavior. Persist app preferences through the canonical settings owner, not a second shadow preference store.
- Preserve per-tab in-memory camera/selection/scale, global drawer/lane settings and workspace tab recipe. Do not create project song-sidecar writes solely because older SPEC text mentions them; actual legacy save/close nonmutation checks govern. Sample provenance is a different contract above.
- Two tabs sharing a bank must not show/play stale snapshots after another tab edits/saves/undoes it. Freeze the legacy shared-bank/history policy before selecting an invalidation/adoption mechanism.
- Preserve all distinct focus/ungrab/hide/deactivation cancel paths, popup/text/IME arbitration, callback teardown and native clipboard semantics. A pointer or Qt index identity may retire; the outcome it protected may not.
