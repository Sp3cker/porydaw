# Task 221 brief — the export captures the live unsaved session and holds its bank for the whole render

# Context

This is draft P3-T3. The user rulings of 2026-09-29 bind it
(`repairs/p3-wav-export-draft.md`, "Open decisions", all RESOLVED):
- The export renders the live unsaved state: the edit-buffer document, the mounted
  bank including unsaved edits (`DocumentSession.bankLease`, the lease the live
  engine plays, `DocumentWorkspace.swift:194`/`:442`) and the applied settings.
  Nothing is read back from disk and nothing is saved.
- Capture is point-in-time. The app blocks input while the export runs (task 222),
  so the design needs no invalidation handling.
- The capture accessor `precondition`s
  `!bankPersistenceInFlight && !document.history.bankTransitionInFlight`. The same
  guard shape as `save()`/`close()` (`DocumentSession.swift:313`/`:474`), but
  hard.

Teardown safety (`spec.md:40`): the job holds the `NativeBankLease` (a `Sendable`
class, `ProjectService.swift:165-200`) for its whole lifetime, as `NativeAudio`
does (`NativeAudio.swift:19,33-36`).

Fork: `mainwindow.cpp:1300-1311` renders the retained selected lease against a
fresh timeline at the export rate, with `songSettingsFor(*tab)`
(`mainwindow.cpp:899-910`). Swift mirrors this in the private
`NativeAudio.settings(for:)` (`NativeAudio.swift:153-158`).

Consumes 220's `WavExport.render`, `WavExportOptions`, `WavExportTotals` and
`WavExportError`. Forward pointer: 222's presenter calls
`DocumentSession.wavExportCapture` and `NativeAudio.songSettings(for:)`, starts
`WavExportJob.run` and stops playback first. Stop-before-render ordering is 222's
predicate.

- Surface: the export's capture/job contract behind File → Export WAV.
- Spec ledger: none. `midiexport` rows closed in 220. Capture/lease/unsaved-state
  obligations come from `spec.md:40`, `inventory.md` AU01/AU02 and the
  verification.md WAV-export journey, not ledger rows.
- Verify lanes: `exportcheck-loop`, `exportcheck-tail`.

# Exact write set

Production:
- `src/swift/app/export/WavExportJob.swift` (new, module `PorydawApp`, new feature
  directory; 222 adds its presenter beside it).
- `src/swift/app/NativeAudio.swift`: replace the private `settings(for:)` with
  public `songSettings(for:)` and update its two callers (`bind(timeline:bank:config:)`,
  `updateSettings(config:)`).
- `src/swift/app/CMakeLists.txt`: add `export/WavExportJob.swift` to `PorydawApp`
  (**shared** with 220/222; serialize).

Checks:
- `src/checks/projectstore/ExportCaptureChecks.swift` (new).
- `src/checks/projectstore/ExportChecks.swift`: one call,
  `runExportCaptureChecks(report)`, at the end of `runExportChecks` (**shared**
  with 220; after its checkpoint).
- `src/checks/CMakeLists.txt`: add `projectstore/ExportCaptureChecks.swift` next to
  `projectstore/ExportChecks.swift` at `:289` (**hot shared** registration file).

Ledgers: none.

# Prerequisites

Task 220 accepted and checkpointed. This task consumes its interface and re-edits
`ExportChecks.swift` and `src/swift/app/CMakeLists.txt`.

# Interface contract

In `PorydawApp`, `WavExportJob.swift`:
- `extension AudioSettings { public func applyingSong(_ config: SongConfig) -> AudioSettings }`
  - Copies the engine fields (`pcmMixer`, `maxPcmChannels`, `pcmMixRate`,
    `analogFilter`).
  - Sets `songVolume = UInt8(clamping: config.masterVolume)` and
    `reverb = UInt8(clamping: config.reverb ?? 50)`: the existing
    `NativeAudio.swift:153-158` law, fork `mainwindow.cpp:899-910`.
- `NativeAudio.songSettings(for config: SongConfig) -> AudioSettings`: returns
  `engineSettings.applyingSong(config)`. Live playback behavior is unchanged.
- `public struct WavExportCapture: Sendable`
  - Stored fields: `state: SongState`, `lease: NativeBankLease`,
    `settings: AudioSettings`, `options: WavExportOptions`, `label: String`.
  - Immutable; its holder retains the lease.
- `extension DocumentSession { public func wavExportCapture(settings: AudioSettings, options: WavExportOptions) -> WavExportCapture }`
  - Precondition: `!bankPersistenceInFlight && !document.history.bankTransitionInFlight`.
  - Captures `document.state` (the edit buffer), the current `bankLease`, the given
    settings/options and `document.source.label`.
  - No mutation, publication, history entry or dirty change.
- `public enum WavExportOutcome: Equatable, Sendable { case completed(totalFrames: UInt64), cancelled, failed(message: String) }`
- `public enum WavExportJob { @concurrent public static func run(_ capture: WavExportCapture, to path: String, progress: AsyncStream<Double>.Continuation?) async -> WavExportOutcome }`
  - Builds the timeline with
    `PlaybackTimeline.build(state: capture.state, sampleRate: Double(options.sampleRate))`.
    Mirrors the fork's fresh timeline at the export rate (`:1303`).
  - Calls `capture.lease.withVoices { WavExport.render(...) }` with progress
    `{ continuation?.yield($0); return !Task.isCancelled }`.
  - Maps the result: `.completed` → `.completed(totalFrames:)`,
    `.cancelled` → `.cancelled`, a `WavExportError` → `.failed(message:)`.
  - Always finishes the continuation.
  - Cancellation is cooperative: `Task.cancel()` on the job's task is observed at
    the next `progress` call.

# Implementation steps

1. `applyingSong` + `NativeAudio.songSettings(for:)`: move the existing law, then
   delete the private `settings(for:)`.
2. `WavExportCapture`, `DocumentSession.wavExportCapture` and the precondition:
   - Put it in the new file as an extension; `DocumentSession`'s flags are
     module-internal.
   - Do not edit `DocumentSession.swift`.
3. `WavExportJob.run`: use `@concurrent` as in the precedent
   `Task { @concurrent in try await ProjectRead.load(path:) }`
   (`ApplicationSession+ProjectOpening.swift:64`).
   - No GCD, no `Task.detached`, no locks.
   - The caller owns the continuation made with
     `AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))`.
4. `ExportCaptureChecks.swift`, `runExportCaptureChecks(_ report:)`.
   - Setup:
     - Open the staged root with `ProjectService` and a session with
       `DocumentSession.open(service:label:)`, for the entry's staged label.
     - Render at 44 100 Hz, loop count 1, fade/tail 1.0 s, suppression off.
     - Settings: `AudioSettings().applyingSong(document.state.config)`.
     - Drive the job with `runBlocking` into a temporary directory.
     - Decode PCM with a check-local `le16`, independent of the writer.
   - Message-anchored predicates, cppID `exportcheck/WavExportCapture::<case>`:
     1. `an export capture renders the unsaved note edit`:
        - Render capture A before an edit.
        - Add one note as `session_save.swift:411-414` does.
        - Render capture B. PCM A ≠ PCM B.
     2. `exporting leaves the document dirty, unsaved and out of history`. Across B's
        export these are unchanged: `document.isDirty` (true), `document.revision`,
        `document.history.undoCount` and the song's MIDI bytes on disk.
     3. `an export capture holds the mounted bank's unsaved lease`:
        - Pick the slot numbered by the first program change (status `0xC0…`) in
          `document.state.file`. Fail loudly if `bankSlots[slot].voice` is nil.
        - Edit its `release` through `applyBankEdit` (`session_save.swift:414-419`).
        - Capture C. `C.lease === session.bankLease`, and it differs from A's lease.
     4. `an export capture renders the mounted bank's unsaved edit`: PCM C ≠ PCM B.
     5. `exporting leaves the bank edit unsaved`: `bankDirty` stays true and the bank
        source bytes on disk are unchanged.
     6. `a capture outlives its closed session and service`:
        - Re-render C after `await session.close()` and `await service.close()`.
        - `.completed` with PCM byte-identical to C's first render.
     7. `a cancelled export job reports cancellation and leaves no file`:
        - `let task = Task { await WavExportJob.run(C, …) }; task.cancel()`.
        - Outcome `.cancelled`, and the path does not exist.
     8. `the export progress stream is monotonic and finishes at 1.0`: drain the
        stream of a completed run; strictly increasing values, the last is 1.0, and
        the stream terminates.
     9. `song settings keep engine fields and apply the song volume and default reverb`:
        - `applyingSong` on a non-default engine `AudioSettings` preserves all four
          engine fields.
        - Reverb nil → 50, reverb 30 → 30, `songVolume == masterVolume`.

# Acceptance predicate

For both staged songs, an export capture renders the live edit buffer and the
mounted bank's unsaved lease with song/engine settings:
- the document and bank stay unsaved and out of history;
- the captured lease keeps rendering after its session and service close;
- task cancellation leaves no file.

Implementer runs, under the build lock:
```sh
deno task build:checks
deno task checks --filter exportcheck-loop --verbose
deno task checks --filter exportcheck-tail --verbose
deno task proof check --executed
```

Coverage:
- Predicates 1–9 run on a loop song and a tail song.
- 220's rows must stay green; `--executed` confirms no anchor broke.

Gaps:
- The capture `precondition` is a deliberate crash and is not executed.
- Stop-before-render and the app-wide input block are 222's shell predicates.
- Whether a `release` edit is audible depends on the fixture. If predicate 4 cannot
  distinguish PCM on a staged song, stop and report; do not switch predicates.

# Task-specific constraints

- The capture copies values and a lease only. It never reads files and never calls
  `save()`.
- No `DocumentSession.swift` edit. The precondition stays hard (the ruling), not a
  graceful refusal.
- `NativeAudio` live behavior must not change. Its `bind`/`updateSettings` results
  are identical.
- Render determinism (predicate 6) assumes the engine is deterministic for identical
  inputs. A mismatch is a finding to report, not a tolerance to add.
