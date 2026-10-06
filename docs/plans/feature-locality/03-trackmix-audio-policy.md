# Plan 03 — Track-mix audio policy (lever: causes a+e; fixes Q2)

Route: **SDD-track** (audio-callback-adjacent policy move; atomicity and edge-triggered
all-notes-off must survive). Seat: `sdd-implementer`. Prerequisite: none.

## Verdict

Mute/solo policy is split across three modules today: sets in `DocumentSession` (document,
:135-143), set→bitmask conversion in `DocumentWorkspace` (app, :379-383), solo/mute combination
in `AudioRenderEngine`'s render callback (app-audio, :229-239), forwarded twice
(`NativeAudio.swift:132-133`, engine atomics :104-105). Q2 read 12 files / 4,013 opened (wc) to answer
"what does solo do to a muted track". The single-owner move: `AudioRenderEngine` — already the
playback-effect owner — becomes the only place that knows the mask encoding and the combination
rule; the boundary carries two `Set<Int>` values instead of two pre-encoded masks.

## Task 1 — `setMix(muted:soloed:)` as the one mix entry

**Context.** Producer: this contract. Consumers: `DocumentWorkspace` bind/observe paths,
`NativeAudio` facade, check `AudioControllerChecks`.

**Exact write set**
- `src/swift/app/audio/AudioRenderEngine.swift`
- `src/swift/app/NativeAudio.swift`
- `src/swift/app/DocumentWorkspace.swift`
- `src/checks/audio/AudioControllerChecks.swift`

**Interface contract**
- `AudioRenderEngine`: delete `public func setMuteMask(_:)` / `setSoloMask(_:)` (:104-105).
  Add `public func setMix(muted: Set<Int>, soloed: Set<Int>)` storing the same atomics
  (`mute`, `solo`, `.relaxed` ordering) after converting each set with a `private static func
  trackMask(_ tracks: Set<Int>) -> UInt32` moved verbatim from
  `DocumentWorkspace.swift:379-383` (0..<16 clamp, bit n = track n).
- `NativeAudio`: replace the two forwarders (:132-133) with one
  `public func setMix(muted: Set<Int>, soloed: Set<Int>) { device.renderer.setMix(muted: muted, soloed: soloed) }`.
- `DocumentWorkspace`: `:209-210` (bind) and `:457-458` (`.mixState`/trackRemap observer) each
  collapse their two calls into ONE `audio.setMix(muted: session.mutedTracks,
  soloed: session.soloedTracks)`; delete `trackMask`. One call per mix change is a small
  atomicity improvement (no mute-new/solo-old pair visible to a concurrent reader of the calls
  themselves); the underlying two relaxed atomic stores remain, so the pre-existing torn-read
  window between them is preserved, not introduced — narrower shape, same semantics.
- Checks: `AudioControllerChecks.swift` call sites :177,183,190,191,196,202,328 change from
  mask literals to set literals (`setMuteMask(1)` → `setMix(muted: [0], soloed: [])`,
  `setSoloMask(2)` → `setMix(muted: [], soloed: [1])`, etc.). Assertions unchanged.

**Preservation contract (behavior-identical)**
- `applyMute()` (:229-239) untouched: policy `(solo != 0 ? (muted | ~solo) : muted) & 0xFFFF`,
  edge-triggered `appliedMute` diff, `m4a_engine_all_notes_off` per newly-muted track.
- Render path (:250-303) untouched; `player.render(… muteMask: appliedMute)` unchanged; the
  `pd_player_render` C ABI and `Sequencer` consumption unchanged (still one effective `UInt32`).
- `DocumentSession` sets, `.mixState` emission (session-only, never dirty/history — :79-82),
  `TrackHeaders` toggle (:336-343), `TrackHeadersGeometry` projection all untouched.
- **QtBridge/QML surface: zero change.** No `@QtBridgeable` body edits; QML keeps calling
  `activateMute/activateSolo` on TrackHeaders.
- Conversion semantics identical: same clamp, same bit order → same masks for same sets.
- Atomicity note: `setMix` still performs two separate relaxed stores (`mute`, then `solo`); a
  render callback can observe the intermediate pair exactly as it can today between
  `setMuteMask` and `setSoloMask`. Preserved deliberately — a single packed atomic would change
  the storage layout for no measured need.

**Implementation steps**
1. Add `setMix` + private `trackMask` to `AudioRenderEngine`; keep atomics private.
2. Swap `NativeAudio` forwarders; delete old pair.
3. Update `DocumentWorkspace` bind + observer call sites; delete its `trackMask`.
4. Update the seven check call sites with set equivalents.
5. `deno task lsp:swift`; `grep path=src/swift pattern=setMuteMask|setSoloMask` → zero hits.

**Acceptance predicate (implementer-run)**
- `deno task build:checks`.
- `deno task checks --filter swiftcore-playback-controller` — the `audioController` suite owns
  the mute/solo assertions (`muteOnly`, `soloPrecedence`, drain/unmute cases at :176-205,:328).
- `deno task checks --filter swiftcore` — session/trackheaders slots ride the same lane; suite
  names for trackheaders/workspace slots are not individually verified (named gap) → full
  swiftcore filter, not narrower.
- `deno task format --check`.
- `checks:shell` not required: QML surface unchanged (reasoning recorded; run only if the
  implementer touches any bridged body despite the contract).

**Task-specific constraints**
- No new types across modules (no `TrackMixState` value type yet): sets are cheap values and the
  boundary already crosses app→app-audio once per mix change, not per frame. Revisit a value type
  only if a third producer appears.
- Build gate: net code motion inside two existing targets; zero new units/edges → build-neutral.
  Cold files (AudioRenderEngine: 6 commits; NativeAudio: 13; DocumentWorkspace: 40 — the hottest
  here, but the edit is two call-site lines).
- Comments ≤2 lines; per-frame paths allocation-free (set conversion happens on mix changes and
  bind only — never in `render`).

**Read-set effect (estimate, [INFERENCE])**: Q2 12→11 files / ~3,850 opened against the
wc-verified 4,013 baseline (`NativeAudio` no longer needed for mix semantics); the policy
question ("what does solo do") becomes 1 file (`AudioRenderEngine`) instead of 3; "where do
masks come from" answers at `setMix`.
