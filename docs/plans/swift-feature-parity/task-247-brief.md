# Task 247 brief — Provenance: sample sidecar, source hash, update-in-place, reopen resolution

# Context

Spec.md: "Provenance includes source path/hash, SoundFont zone, channel choice and parameter
state. Reopen uses unchanged hi-res source; unavailable/changed source falls back to committed
WAV with the old … sidecar-invalidating policy"; existing-sample edits keep name and
registration stable. Fork owners: `SampleRegistrar::{updateSample, sampleSidecarPath,
sourceHashHex, writeSampleSidecar, readSampleSidecar, removeSampleSidecar}`,
`Sidecar::ensureDir`, `ProjectIo::readSample`, and the decode half of
`WorkspaceUi::continueEditSampleFlow`.

Fork policy recorded (no invented warning): a sidecar whose source file is readable and whose
SHA-256 matches re-decodes the source (SF2 zone when `sf2Zone ≥ 0`, else `SampleImport` with
`leftOnly`) and restores the sidecar params; otherwise the committed 8-bit WAV is decoded
(gba-ready defaults) and the later commit removes the sidecar. The fork shows no extra
warning on fallback; the decoded WAV's own warnings stand.

Surface: sample provenance + committed-sample reopen (SA06).
Ledger spec: `src/checks/samplecheck/proof.integration.txt` A013–A059, A065–A071 → MATCHED
(scaffolding rows per the P4 rule).
Verify lane: `samplecheck`.
Blocked rows left untouched: A060–A064 (edit-mode editor; 249).

Oracles: `git show fceecd88:src/project/samplereg.cpp` (`updateSample`, sidecar functions and
JSON keys), `src/project/sidecar.cpp` (`dirPath`, `ensureGitignore`, `ensureDir`),
`src/project/projectio.cpp` 604–626 (`readSample`), `src/ui/workspaceui_samples.cpp`
`continueEditSampleFlow` (decode branch). Check oracle: `git show
fceecd88:src/checks/samplecheck/integration.cpp` (sidecarRoundtrip … sampleUpdateRefusals,
sidecarRemove).

# Exact write set

- `src/swift/sample/SampleSourceHash.swift` — NEW: pure-Swift SHA-256 (hex lowercase).
- `src/swift/sample/SampleSidecar.swift` — NEW: `SampleSidecar` + JSON codec.
- `src/swift/sample/SampleReopen.swift` — NEW: reopen resolution.
- `src/swift/sample/CMakeLists.txt` — add the three files.
- `src/swift/project/SampleRegistrar+Provenance.swift` — NEW: update, sidecar IO,
  `readCommitted`, `.porydaw` directory + `.gitignore` rule.
- `src/swift/project/CMakeLists.txt` — add the file.
- `src/checks/samplecheck/ProvenanceChecks.swift` — NEW `runProvenanceChecks`.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledger `proof.integration.txt` rows above.

# Prerequisites

246 (`SampleRegistrar.probe/validate`, `SampleRegistrationError`, fixtures), 244
(`SampleEditParams`, render, writer), 242 (`Sf2Reader.extractZone` for SF2 provenance).

# Interface contract

- `SampleSourceHash.sha256Hex(_ data: Data) -> String` — decision: pure Swift (CryptoKit is
  Apple-only and Linux is a target; no Qt hash is reachable without new C++). Verified by the
  FIPS 180-2 vectors ("abc", empty, 448-bit message) plus fork parity in A028.
- `public struct SampleSidecar: Sendable, Equatable { version = 1, sourcePath, sourceSha256,
  leftOnly, sf2Zone = -1, params: SampleEditParams }`; `func jsonData() -> Data`;
  `static func decode(_ data: Data) -> SampleSidecar?` — fork keys exactly: root `version`,
  `source{path, sha256, leftOnly, sf2Zone}`, `params{cropStart, cropEnd, loopOn, loopStart,
  loopEnd, baseKey, fineTuneCents, targetRate, normalizeMode, dcRemove, fadeIn, fadeOut,
  crossfadeOn, ditherOn, exactPitchOverride}` with the fork's numeric representation (int64
  fields and the pitch word written as JSON numbers) and read defaults/bounds
  (`normalizeMode`/`dcRemove` clamped into range, `fadeIn/fadeOut` default true, missing
  path/sha → nil, version ≠ 1 → nil). Reads fork-written sidecars.
- In `SampleRegistrar` (PorydawProject):
  - `static func update(projectRoot: String, name: String, wav: Data)
    throws(SampleRegistrationError)` — probe; symbol must be registered ("… is not registered
    in this project; use Import Sample to add new samples."); `<name>.wav` must exist
    ("<name>.wav does not exist in sound/direct_sound_samples - only samples with a .wav source
    can be updated."); rewrite the WAV atomically; the `.inc` is never touched.
  - `static func sidecarPath(projectRoot:name:) -> String` = `<root>/.porydaw/samples/<name>.json`.
  - `static func writeSidecar(projectRoot:name:_:) throws(SampleRegistrationError)` — creates
    `.porydaw/samples` and, when `<root>/.git` exists, appends `.porydaw/` to `.gitignore`
    unless an equivalent line exists (fork `ensureGitignore`, EOL/newline repair), then writes
    atomically.
  - `static func readSidecar(projectRoot:name:) -> SampleSidecar?`,
    `static func removeSidecar(projectRoot:name:)`.
  - `public struct CommittedSample: Sendable { name, wav: Data, wavPath, sidecar: SampleSidecar? }`;
    `static func readCommitted(projectRoot:name:) throws(SampleRegistrationError) ->
    CommittedSample` — fork `readSample` (probe refusal; missing WAV and unreadable/empty
    messages verbatim).
- `public enum SampleReopen` (PorydawSample):
  `public struct Result: Sendable { sample: ImportedSample, restoredParams: SampleEditParams?,
  fromSource: Bool, sidecar: SampleSidecar? }`;
  `static func resolve(wav: Data, wavPath: String, sidecar: SampleSidecar?)
  throws(SampleImportFailure) -> Result` — the recorded fork policy above; a failure to decode
  the committed WAV throws its decode message.

# Implementation steps

1. SHA-256, sidecar codec, reopen resolution (PorydawSample).
2. `SampleRegistrar+Provenance.swift`.
3. `ProvenanceChecks.swift`: SHA-256 vectors; sidecarRoundtrip (A013–A020), sidecarRerender
   (A021–A030: re-read hash equals, left-only re-import, re-render equals the committed
   bytes), sidecarTouchedSource (A031–A038: appended NULs → mismatch → fallback),
   sidecarFallback (A039–A045: no sidecar → committed WAV decodes gba-ready and re-renders
   byte-identically), sampleUpdate (A046–A053: WAV rewritten, `.inc` byte-identical),
   sampleUpdateRefusals (A054–A059), sidecarRemove (A065–A071); plus `.gitignore` legs (added
   once, CRLF kept, no `.git` → untouched) and a fork-format sidecar literal decoded.
4. Ledger edits.

# Acceptance predicate

Sidecars round-trip every provenance field in the fork JSON shape, an unchanged source
re-renders the committed bytes exactly, a touched or missing source falls back to the
committed WAV, updates rewrite only the WAV and refuse unregistered or `.bin`-only symbols,
and removal invalidates the sidecar.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

# Task-specific constraints

Sample provenance is not a song sidecar (spec.md PJ07): write nothing but
`.porydaw/samples/<name>.json` and the `.gitignore` rule. No ProjectStore state, no catalog
or loader refresh here (248).
