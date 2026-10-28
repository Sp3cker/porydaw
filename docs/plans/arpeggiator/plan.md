# Track arpeggiator

## Global Constraints

Build the production Swift/QML track arpeggiator with Master/Transpose left; Rate/Trigger, Mode, Octave, Insert columns; Shuffle/Gate/Steps right; 32 pads in two rows of 16. Selector rows have small active toggles on the left and separate plain labels on the right, not full-width label buttons. Add Accent beside Master, a compact source/loop header, solo Audition and Copy Notes footer. No MIDI-note preview strip or backing row model. Use Porydaw theme pairs and font-derived geometry. Do not include external product names, links, logos, or image assets in committed content.

The tool is bound to its contextual track, feeds from that track's sounding MIDI notes across the song loop, auditions generated notes solo, and copies one complete loop into Porydaw's existing clipboard. No selection prerequisite, input routing selector, source mutation, Apply/replace, saved live effect, or generic preview framework. Closing, tab deactivation, document/bank changes stop audition. Preserve source document, history, normal timeline and bank ownership.

Controller owns shared-tree builds/checks/formatting and source registration outside Core; workers perform read-only local inspection and do not run those commands. Reuse recorded commands; report concrete command mismatches rather than narrowing coverage. Existing proof ledgers and asserted Swift predicates stay unchanged; controller registers new behavior checks. Commit and push this task's changes after verification, per user authorization. Baseline HEAD: 05c10a2242cb5e35c78d39443cd5dd6b17acadbf. Existing untracked docs/ideas/memacc-flow-ableton-wayfinding.md, profiler/, prototypes/ remain untouched and excluded from the commit by explicit user choice.

## Tasks

1. Core generation — SDD-track, pure musical behavior; task-1-brief.md.
2. Isolated audio pattern audition — SDD-track, realtime ownership; task-2-brief.md.
3. Plugin-shaped QML controls — SDD-track, visual/keyboard interactions; task-3-brief.md.
4. Presenter, contextual menu, registration and complete workflow — controller integration, cohesive multi-file exception; task-4-brief.md.

Tasks 1–3 have disjoint write sets and fixed interfaces below, and run concurrently. Integration consumes their interfaces, not implementation details. A single final settled-tree build/check/review covers the complete surface; no intermediate commits.

## Shared specification

### Generator interface

PorydawCore exports `ArpeggiatorMode: Int, CaseIterable, Sendable` cases `up=0, down, upDown, manual, poly, custom`; `ArpeggiatorInsert: Int, Sendable` cases `off=0, lowest, highest`; `ArpeggiatorSettings: Equatable, Sendable` with public default init and mutable fields `mode`, `insert`, `rateNumerator: Int=1`, `rateDenominator: Int=16`, `octaves: Int=1`, `transpose: Int=0`, `masterVelocity: Int=100`, `accentAmount: Int=25`, `shuffle: Int=0`, `gate: Int=80` (101=Tie), `steps: Int=16`, `enabledSteps: UInt32=UInt32.max`, `accentSteps: UInt32=0`, `restartOnNoteOn: Bool=true`, `customPattern: String="1234----"`, `seed: UInt64=1`.

Control bounds: transpose -12...12, masterVelocity 0...100 percent, accentAmount -100...100 percent, shuffle 0...99 percent, gate 10...101, steps 1...32, octaves 1...4.

`ArpeggiatorResult` exposes `notes: [NewNote]` (absolute ticks, caller's track), `droppedPitchCount: Int`. `Arpeggiator.generate(notes: [Note], track: Int, start: Tick, end: Tick, ticksPerBeat: UInt32, playbackSettings: PlaybackSettings, settings: ArpeggiatorSettings) throws -> ArpeggiatorResult` is pure and deterministic. Errors describe invalid settings/range, unsupported timing combinations and output too large. No document mutations.

Result also exposes parallel `stepTicks: [Tick]`/`stepIndices: [Int]`, plus effective `quantumTicks: Tick`, `quantumClocks: Int`, `stepClocks: Int`, `shuffleClocks: Int`, `gateClocks: [Int]` (parallel to emitted notes). `Arpeggiator.supportsTiming(ticksPerBeat: UInt32, playbackSettings: PlaybackSettings, settings: ArpeggiatorSettings)->Bool` validates settings/timing without enumerating the loop; use this for option availability, never generate and discard a whole pattern per option.

At each clock tick, available notes satisfy source start <= tick < source end; unterminated notes sustain to loop end. Include notes beginning before loop. Deduplicate pitches, most-recent active input wins. Up/Down use expanded pitch ordering, UpDown excludes repeated endpoints, Manual uses note-on chronology with deterministic onIndex tie-break, Poly emits all expanded pitches. Octaves expand upward in octave blocks before transpose; out-of-range output pitches are omitted and counted. Custom is <=8 characters of 1–9/R/-, numbered low-to-high expanded pitches; '-' is unused padding (ignored), missing numbered chord members produce a rest; R selects a member with deterministic seeded randomness. Source note velocity is scaled by master then accent multiplier on marked pads; round nearest, zero means silence, positive clamp 1–127.

Timing is hardware-clock-first: 24 clocks/quarter, or 48 with playbackSettings.extendedClocks. The document must also store each generated boundary exactly. Use the common absolute lattice: g=gcd(ticksPerBeat,clocksPerBeat), quantumTicks=ticksPerBeat/g, quantumClocks=clocksPerBeat/g. This handles high-PPQ MIDI and documents whose PPQ is coarser than Extended Clocks without pretending finer resolution. Loop bounds must lie on this lattice; otherwise explain the mismatch rather than silently moving markers. Quantize source retrigger onsets to this lattice for generated timing only, without changing the source.

Source retriggers round up to the first shared clock boundary at or after their source onset, never to an earlier boundary that still sees the old chord. A boundary at loop end does not create another segment inside the loop.

Whole-note rate: 4*clocksPerBeat*rateNumerator/rateDenominator hardware clocks. UI values 4/1,2/1,1/1,1/2,1/3,1/4,1/6,1/8,1/12,1/16,1/24,1/32,1/48 are enabled only if their durations are exact positive multiples of both quantumClocks and quantumTicks after conversion. Never approximate an unsupported rate or collapse duplicate onsets. Shuffle delays odd steps by a whole-quantum offset nearest the requested percentage, bounded so every actual slot retains one quantum (two with Insert). Surface the effective offset in clocks; percentage changes may resolve to the same rhythm. Derive onsets from integer clock indices, not accumulated floating times.

The More menu also exposes the reference documentation's dotted eighth rate as `1/8 dotted` (whole-note ratio 3/16, eighteen normal GBA clocks). Append it without changing the existing quick-choice or default indices.

Loop is [start,end), all notes end <= end. Pad off advances time and note-order cursor. At pattern wrap reset pad cursor; with restartOnNoteOn=false also reset note cursor. With restartOnNoteOn=true, a source note-on group restarts clock/pad/note order at its clock-aligned onset (simultaneous source notes one group); note-off alone doesn't reset. Insert splits each enabled step slot in two clock-resolved subslots: lowest/highest expanded chord member first, chosen arp note(s) second. An odd number of quanta splits floor(N/2) then ceil(N/2), explicitly 1+2 clocks for a 3-clock slot at normal PPQ. Each subslot requires at least one quantum; unsupported combinations are disabled/explained, not collapsed. Accent applies to both.

Gate 10–100% resolves to the nearest positive duration representable in both the shared lattice and the project's existing mid2agbEffectiveDuration policy, respecting playbackSettings.exactGate. Choose duration fixed points so playback/export does not quantize the generated duration a second time; constrain non-tie gates to their slot. Show effective gate clocks. Gate 101 ties each emitted group to next sounding group or loop end with the same duration-policy constraints; do not promise an unrepresentable exact tie. Trim same-pitch previous output at its next onset using a supported non-overlapping gate and deduplicate simultaneous same-pitch events, so audition and clipboard contain no ambiguous overlaps. Refuse >65,536 generated notes, explaining the limit; don't hang or silently truncate.

These edge rules are explicit Porydaw interpretations where reference documentation is incomplete, not claims of bit-for-bit vendor parity. Preserve every named control.

### Audio interface

`NativeAudio.startPatternAudition(_ timeline: PlaybackTimeline)` and `stopPatternAudition()`; `patternAuditionPositionSamples: UInt64` getter. Start/replace/stop happen with rendering quiesced; render uses existing preview engine with a separately owned sequencer and immutable timeline, allocation/lock-free. Audition overrides audible normal song output, pauses normal transport without altering the document timeline, loops sample-accurately, and leaves normal song playback paused when stopped. Reuse borrowed voicegroup while bank lease remains held. Unload/bank/config changes stop pattern audition safely. No main-actor timers scheduling MIDI.

### Presenter/QML interface

Swift-owned registered `ArpeggiatorPresenter` with `isOpen: Bool`, `sourceLabel: String`, `loopLabel: String`, `status: String`, `canCopy: Bool`, `isAuditioning: Bool`, `baseFontPx: Double`, `currentStep: Int` (-1 stopped), `promptStyle: PromptStyle`, `colors: GridPalette`, `bodyFont: QmlFont`, and public Int fields `masterVelocity`, `transpose`, `accentAmount`, `rateIndex` (default index9=1/16), `mode`, `octaves`, `insert`, `shuffle`, `gate`, `steps`; Bool `restartOnNoteOn`; String `customPattern`; `[String] rateLabels`. No visual-note-preview model, row type, or related exposed fields.

Methods `setParameter(name: String, value: Int)`, `setCustomPattern(value: String)`, `setRestartOnNoteOn(enabled: Bool)`, `toggleStep(index: Int, accent: Bool)`, `stepEnabled(index: Int)->Bool`, `stepAccented(index: Int)->Bool`, `stepRevision: Int` observable counter for pad bindings, `reshuffle()`, `toggleAudition()`, `copyNotes()`, `close()`. `configure(fontPx: Double)` updates font-derived geometry/style. QML uses explicit slots, not property writes, for settings changes.

Timing-facing presenter additions: `timingLabel: String` explains effective step/shuffle/gate clock resolution and normal/extended mode; `rateAvailable(index: Int)->Bool` and `insertAvailable(value: Int)->Bool` let QML disable unsupported options rather than approximate them. Bind all such queries to observable `stepRevision` so changed rate/Insert/clock state invalidates them.

Presenter opens `open(track: Int)`, reads all source track notes, loop bounds and immutable source state; no loop -> visible explanation with audition/copy disabled. Source selection changes don't reroute. One generated snapshot supplies the isolated audition timeline and clipboard. Construct PorydawClip directly with span=end-start and loop-relative note times, empty lanes/tempo, current PPQ. Never use copyNotes (it strips leading silence). Copy doesn't close or mutate song. Empty output disables Copy. Invalid custom text retains draft and explains error without auditioning stale output. All settings persist only in workspace lifetime; no project format changes.

## Verification

Use `--release` for build/runtime lanes to exercise the checkout-local Qt 6.11.2 kit; the Debug cache retains Homebrew Qt 6.12.

Controller: `uv run --no-sync dev build:checks --release`; `uv run --no-sync dev checks --release --filter swiftcore-noteedits` (new arpeggiator checks run inside the existing Swift note suite without adding native C++ harnesses); `uv run --no-sync dev checks:shell --release --filter shell-arpeggiator`; `uv run --no-sync dev checks:shell --release --filter shell-text-contrast`; `uv run --no-sync dev checks:bridge`; `uv run --no-sync dev checks:qml-aot --release`; `uv run --no-sync dev format --check`; `uv run --no-sync dev lsp:swift`. Add focused new behavioral checks, no source-text/wiring tests. Exercise actual shell tool, edit controls/pads, audition/stop, copy/paste and unchanged source/history, and capture visible production surface. If registration filters differ, inspect registration then correct commands here. Review full scoped change including new files before handoff.
