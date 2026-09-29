# Task 246 brief — Sample registration: pipeline probe, naming, write-through register, loader/engine agreement

# Context

Spec.md: sample files are unsigned 8-bit WAV registered only into wav2agb projects; probe the
actual build pipeline and registration anchor; actionable refusal for legacy AIF/aif2pcm or
missing wav2agb/inc; sanitize/prefill names and validate against symbols plus existing
WAV/BIN/AIF paths; a refused create overwrites nothing; the asset the pipeline consumes equals
the render. The fork owner is `SampleRegistrar` (`src/project/samplereg.cpp`). This task ports
its probe/validate/register half into the Swift project store; update/sidecar/remove are 247,
the transactional commit + loader-context rebuild is 248.

Surface: `SampleRegistrar` (PorydawProject) — the write-through registration (SA05).
Ledger spec and rows:
- `src/checks/samplecheck/proof.project.txt` (all 63): behavior rows → MATCHED; projectInspect
  A025–A039 → RETIRED-REPRESENTATION ("fork check-only inspector `inspectSampleWav`, no
  production caller at fceecd88; the registered WAV's loader-derived fields are proven by
  A047–A050 through `voicegroup_load`"); harness rows per the P4 scaffolding rule. Ledger
  deleted in this commit when no open row remains.
- `proof.dsp.txt` A035–A051 (parityCases, profiles A–F): A037, A038, A045 → MATCHED;
  A039–A043 → MATCHED via the check-local RIFF reader (fields read from the written bytes, not
  a production inspector); A046–A051 NATIVE → MATCHED (loaded `WaveData` equals the render);
  A035/A036/A044 per the scaffolding rule. Ledger deleted when zero open rows remain.
- `proof.integration.txt` A001–A012 (engineLoop) → MATCHED (A001/A002/A006 per the
  scaffolding rule).
Verify lane: `samplecheck`.
Blocked rows left untouched: integration A013–A071 (247/249).

Oracles: `git show fceecd88:src/project/samplereg.{h,cpp}` (`SampleFormatProbe`,
`makeFilePaths`, `hasPatternRule`, `probeSampleFormat`, `validateSampleName`,
`registerSample`); `fceecd88:src/project/voicegroupsource.cpp` `directSoundSymbols`. Check
oracles: `git show fceecd88:src/checks/samplecheck/project.cpp` (`createWav2AgbProject` 28,
methods projectProbe … projectCrlf), `dsp.cpp` 364–430, `integration.cpp` 40–125.

# Exact write set

- `src/swift/project/SampleRegistrar.swift` — NEW.
- `src/swift/project/CMakeLists.txt` — add the file; `target_link_libraries(PorydawProject
  PUBLIC PorydawCore PorydawSample)`.
- `src/checks/samplecheck/SampleFixtures.swift` — add `writeWav2AgbProject(root:)` (fork
  `createWav2AgbProject`: `Makefile` `include audio_rules.mk`, `audio_rules.mk` wav2agb
  pattern rule, `sound/direct_sound_data.inc` seed, placeholder `.bin`, orphan `.wav`) and
  `writeAif2PcmProject(root:)`.
- `src/checks/samplecheck/RegistrationChecks.swift` — NEW `runRegistrationChecks`.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- Ledgers above.

# Prerequisites

244 (`SampleDocument`, `SampleWavWriter`, `ParityProfile`, RIFF reader), 240 (`SampleNames`).

# Interface contract

`public enum SampleRegistrar` (file IO through `ProjectFileStore`; no ProjectStore state):

- `public struct Probe: Sendable, Equatable { enum Pipeline { wav2agb, legacyAif, unknown };
  pipeline, incPath, samplesDir, refusal: String; var ok: Bool }`.
- `static func probe(projectRoot: String) -> Probe` — fork `probeSampleFormat`: missing
  `sound/direct_sound_data.inc` → the "cannot find sound/direct_sound_data.inc …" refusal;
  a make file (root `Makefile`/`makefile`/`*.mk`) with a `%.bin: …%.wav` pattern rule whose
  tab-indented recipe mentions `wav2agb` → `wav2agb`; the `aif` + `aif2pcm` rule →
  `legacyAif` with the "this project predates wav2agb …" refusal; otherwise the "cannot find a
  wav2agb build rule …" refusal. Refusal texts verbatim.
- `static func validate(projectRoot: String, name: String, existingSymbols: [String]) ->
  String?` — nil when valid; else the fork message (empty; grammar `^[a-z0-9_]+$`; symbol
  `DirectSoundWaveData_<name>` exists; `<name>.wav|.bin|.aif` exists in
  `sound/direct_sound_samples/`).
- `static func register(projectRoot: String, name: String, wav: Data)
  throws(SampleRegistrationError)` — probe; validate against a fresh
  `VoicegroupSource.directSoundSymbols(projectRoot)` scan (never a cached catalog); mkpath the
  samples dir; write `<name>.wav` atomically FIRST; then append to the `.inc` the block
  `<blank line if needed>` + `<align indent>.align 2` + `DirectSoundWaveData_<name>::` +
  `<incbin indent>.incbin "sound/direct_sound_samples/<name>.bin"` using the file's own EOL
  (`\r\n` if present) and the indents of its existing `.align`/`.incbin` lines, written
  atomically. A refusal before the WAV write writes nothing; an `.inc` write failure leaves
  the orphan WAV (fork: harmless) and reports "cannot write <path>.". Error strings verbatim.

- `public struct SampleRegistrationError: Error, Equatable, Sendable { public let message:
  String }` — declared in this file; 247 and 248 reuse it.

# Implementation steps

1. `SampleRegistrar.swift` (probe helpers private; regex via Swift `Regex`).
2. Fixtures + `RegistrationChecks.swift`: projectProbe (A001–A011), projectSanitizeValidate
   (A012–A024, sanitize through `SampleNames.sanitize`), projectRegister (A040–A051: WAV
   bytes equal, exact `.inc` bytes, `directSoundSymbols` contains new + existing, a written
   `voicegroup_samplecheck.inc` resolves through `voicegroup_load`, tone fields and WaveData
   freq/loopStart/size/status/data, voice name), projectDuplicate (A052–A057), projectCrlf
   (A058–A063); dsp parityCases profiles A–F (A035–A051) incl. the loaded-WaveData ≡ render
   rows; integration engineLoop (A001–A012) binding the loaded bank's `ToneData` into
   `AudioRenderEngine` (the `AudioControllerCheckFixture` pattern) and asserting the fork's
   ≥ 4 loop wraps and wrap-step bound.
3. Ledger edits; delete `proof.project.txt` and `proof.dsp.txt` if they have zero open rows
   (dsp: every row after 243/244/246).

# Acceptance predicate

wav2agb projects probe OK, aif2pcm/rule-less/inc-less projects refuse with the fork messages,
names sanitize/validate like the fork, registration writes WAV then a byte-exact `.inc` block
(CRLF preserved), duplicates refuse without touching the `.inc`, and the native loader and
engine play back exactly the rendered bytes/loop.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

Gap: the real wav2agb binary is not in the repo; agreement with its output is the optional
corpus run of 244. The loader (`load_wav_from_path`) is the engine's own consumer.

# Task-specific constraints

No ProjectStore/ProjectService state or catalog refresh here (248). No `inspectSampleWav`
port. Registration never installs tools or rewrites make files.
