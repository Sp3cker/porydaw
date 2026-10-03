# Task 245 brief — Analysis: YIN pitch hint, loop-candidate search and refinement

# Context

Spec.md: pitch detection is a hint/prefill with unpitched/low-confidence behavior and must not
silently overwrite deliberate metadata; the editor keeps candidate loop cycling/refinement,
first-enable loop population and seam diagnostics. This task ports the fork's analysis
functions; the editor's use of them (adopt-pitch action, loop populate/cycle/refine) is 250.

Surface: `SampleDsp` analysis functions (SA03).
Ledger spec: `src/checks/samplecheck/proof.analysis.txt` A001–A015 → MATCHED
(pitchMatrix A001–A002, pitchNegativeCases A003–A004, loopAndCrossfade loop-suggestion
A005–A015).
Verify lane: `samplecheck`.
Blocked rows left untouched: A016–A021 (244) and the already-MATCHED audition rows A022–A035,
whose mapping lines lack message anchors (strict-mapping debt) — task 252 repairs them and
deletes the ledger. Do not delete `proof.analysis.txt` here.

Oracles: `git show fceecd88:src/audio/sampledsp.h` (`PitchResult`, `LoopCandidate`),
`sampledsp.cpp` 215–628 (`yinDifferenceFrac`, `floatSeamNcc`, `detectPitchYin` 250–407,
`suggestLoop` 409–598, `refineLoop` 600–628), `docs/old/sample-editor/DSP.md` §4, §6. Check
oracle: `git show fceecd88:src/checks/samplecheck/analysis.cpp` 60–183.

# Exact write set

- `src/swift/sample/SampleAnalysis.swift` — NEW: pitch + loop search.
- `src/swift/sample/CMakeLists.txt` — add the file.
- `src/checks/samplecheck/AnalysisChecks.swift` — NEW `runAnalysisChecks`.
- `src/checks/samplecheck/SampleChecks.swift` — one call line.
- `src/checks/CMakeLists.txt` — register the check file.
- `src/checks/samplecheck/proof.analysis.txt` — rows A001–A015 only.

# Prerequisites

243 (`SampleDsp.quantizeBuffer`, `seamMetrics`), 244 (serializes the analysis ledger writer;
no code dependency beyond 243).

# Interface contract

On `SampleDsp`:

- `public struct PitchResult: Sendable, Equatable { pitched, f0 (Hz), confidence }`.
- `static func detectPitchYin(_ x: [Float], rate: Double) -> PitchResult` — fork algorithm and
  thresholds; fewer than three analysis frames → unpitched; noise → unpitched.
- `public struct LoopCandidate: Sendable, Equatable { loopStart, loopEnd (final grid,
  inclusive), ncc, score, passedGates }`.
- `static func suggestLoop(_ x: [Float], rate: Double, period: Double, regionA: Int, regionB:
  Int) -> [LoopCandidate]` — fork ranking and gates (post-quantize seam amp ≤ 2 LSB, slope ≤ 3,
  NCC ≥ 0.95 for the top candidate on periodic material); window-starved input → empty.
- `static func refineLoop(_ x: [Float], period: Double, loopStart: inout Int, loopEnd: inout
  Int)` — never lowers the seam NCC.

# Implementation steps

1. Port the functions with the fork's constants and window sizes; no allocation inside the
   per-lag loops.
2. `AnalysisChecks.swift`: pitchMatrix (sine and saw at the fork's rates × keys within 5
   cents via `centsOff`), pitchNegativeCases (noise, too-short frame), loop suggestion
   (vibrato tone YIN within 20 cents of 440 Hz; gated top candidate seam/NCC/period-multiple
   bounds; noise top NCC < 0.5; amplitude-step tone still gated with no candidate spanning the
   step; refine never worsens NCC; starved buffer → no candidates). Fork literals only.
3. Ledger edits (A001–A015 → MATCHED).

# Acceptance predicate

Pitched sources report the fork's f0 within the fork tolerances, unpitched sources report no
pitch, and loop search/refinement meet every fork seam gate on the fork fixtures.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks --filter samplecheck --verbose
deno task proof check --executed --strict-mappings
```

# Task-specific constraints

The analysis never mutates parameters; it only returns hints/candidates (the editor decides in
250). Keep the pitch matrix within the lane's 175-second alarm — use the fork's frame
lengths, not longer signals.
