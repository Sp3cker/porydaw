# Dynamic Velocity Detents — Upstream Port Plan

## Goal

Replace the fork's static PSG velocity-level tables with upstream's volume- and pan-aware hardware arithmetic. Feed each note's effective track volume and pan into `VelocityMap` so Square, Wave, and Noise detents reflect actual playback levels.

Source of truth: `upstream/main:src/core/velocitymodel.cpp` and `upstream/main:src/core/velocitymodel.h`, originally grounded at upstream commit `b428748`. The two files are byte-identical between `b428748` and the `upstream/main` tip (verified by empty `git diff`), so the pin stays valid. Port the arithmetic verbatim; adapt only includes and fork-specific call sites.

## Audit corrections carried by this revision

- **D-1** `VelocityMap::compatibleWith` compares voice, trackVolume, and trackPan. The fork's body compares voice only, so a multi-note selection spanning a CC 7/10 change shared one drifted detent table; `VelocityArea::currentContext` gates on this predicate, so with upstream semantics such a selection falls back to the continuous ruler.
- **D-2** `VelocityAxis::mode()` gates on `VelocityMap::hasDetents()`, not `levelCount() == 0`: a PSG channel the volume has squeezed to a single silent step keeps the plain velocity ruler instead of rendering a one-row intrinsic axis with nothing to detent.
- **D-3** Check expectations come from the public API of resolved maps. The arithmetic helpers (`cgbEnvelopeGoal`, `kWaveClassOfEnvelopeGoal`, `kDefaultVolX`) live in velocitymodel.cpp's anonymous namespace and are never called, exposed, or reimplemented by a harness.
- **D-4** Verification uses the real check-catalog names `velocity-model` and `velocity-page`. `velocitymodelcheck` and `rollcheckpsgvelocity` are file names, not catalog entries; no `--filter` matches them.
- **D-5** Every velocity-area resolve site captures the full `DrawerPageVoiceContext` inline and passes its volume and pan; none projects `.voice` off a temporary.
- **D-6** Upstream's `operator!=` is ported verbatim alongside the custom `operator==` (decision stated in Stage 1).

## Stage 1 — `velocity-model-core-and-axis`

Worktree `velocity-dynamic-detents`. Depends on nothing. Expected intermediate state: the tree does not compile until Stages 2–3 migrate every `resolve` call site; do not run `build:checks` here.

1. **`src/core/velocitymodel.h`**
   - Add:
     ```cpp
     constexpr int kM4aMaxVolume = 127;
     uint8_t m4aEffectiveTrackVolume(int volumeEvent, int masterVolume);
     ```
   - Change resolution to accept effective track state (trackVolume has no default, so every existing two-argument call breaks on purpose):
     ```cpp
     static VelocityMap resolve(const ToneData *tone, std::optional<uint8_t> key,
                                uint8_t trackVolume, int8_t trackPan = 0);
     ```
   - Add public queries (`isPsg` already exists):
     ```cpp
     bool isKeyless() const;
     bool hasDetents() const;
     uint8_t trackVolume() const { return m_trackVolume; }
     int8_t trackPan() const { return m_trackPan; }
     ```
   - Replace the defaulted `operator==` with upstream's custom one, which compares the resolved voice and also volume/pan for PSG voices.
   - **operator!= decision (D-6):** port upstream's `operator!=` verbatim (`return !(*this == other);`). C++20 would synthesize `!=` from the custom `==` via rewritten candidates, but the explicit declaration keeps this header textually identical to the source of truth — the port policy for this file — and makes the pair's symmetry visible at the declaration site. Relying on rewriting would be a silent divergence.
   - Replace the fork's voice-only `compatibleWith` body with upstream's (D-1): `isPsg()` on both maps, same voice, same `m_trackVolume`, same `m_trackPan`.
   - Add private constructor and level helper:
     ```cpp
     VelocityMap(VelocityVoice voice, uint8_t trackVolume, int8_t trackPan);
     std::size_t levelAt(int storedVelocity) const;
     ```
   - Replace the current single-argument private constructor.
   - Add members:
     ```cpp
     uint8_t m_trackVolume = uint8_t(kM4aMaxVolume);
     int8_t m_trackPan = 0;
     ```

2. **`src/core/velocitymodel.cpp`**
   - Remove static `kPsgRepresentatives`, `kWaveRepresentatives`, and `kWaveRanges`.
   - Port upstream's:
     - `kWaveClassOfEnvelopeGoal`;
     - `kDefaultVolX`;
     - `cgbEnvelopeGoal` (the engine chain verbatim: `mid2agbEffectiveVelocity` rounding, `x = (volume * 64) >> 5`, `y = clamp(2*pan, -128, 127)`, `volMR`/`volML`, right/left capped at 255, `goal = (left + right) / 16`, hard-panned clamp to 15);
     - `m4aEffectiveTrackVolume`;
     - dynamic `levelAt` and `levelCount`;
     - binary-search `levelRange`;
     - `representative`;
     - `canonicalize`;
     - `moveLevels`;
     - `isKeyless`, `hasDetents`, the custom `operator==`, `operator!=`, and the volume/pan-aware `compatibleWith`.
   - Copy the hardware arithmetic verbatim. Do not restore or approximate the static tables when expectations change.

3. **`src/ui/editordrawer/velocityaxis.cpp`**
   - `VelocityAxis::mode()` becomes `return m_map.hasDetents() ? Mode::Intrinsic : Mode::Continuous;` (D-2). The constructor already calls `mode()` before `buildIntrinsicRows()`, so a single-step map skips intrinsic rows with no other axis change.

**Stage 1 acceptance:** the header declares upstream's full surface (resolve signature, queries, custom operator pair, `compatibleWith` over voice+volume+pan); the cpp arithmetic is byte-for-byte upstream modulo includes; `mode()` gates on `hasDetents()`.

## Stage 2 — `velocity-context-and-area-resolution`

Worktree `velocity-dynamic-detents`. Depends on Stage 1 (needs the new `resolve` signature and `compatibleWith` semantics).

4. **`src/ui/editordrawer/drawerpage.h`** — extend `DrawerPageVoiceContext`
   - Add after `endTick`:
     ```cpp
     uint8_t trackVolume = 127;
     int8_t trackPan = 0;
     ```

5. **`src/ui/songview/trackvoiceops.cpp`** — resolve effective CC state
   - Add an anonymous-namespace helper with the boundary-reference contract:
     ```cpp
     int ccValueAt(const SongViewModel &model, int track, uint8_t cc, int primed,
                   uint64_t tick, uint64_t &nextChangeTick);
     ```
   - Start with `primed`, find the lane via `SongViewModel::findLane(track, cc)`, and walk its tick-sorted `points`. Apply values at or before `tick`; lower `nextChangeTick` to the first point after `tick`.
   - `nextChangeTick` is intentionally a non-null `uint64_t &` out-parameter in `ccValueAt`, `trackVolumeAt`, and `trackPanAt`: every caller owns the live section boundary, and the reference keeps that contract null-safe while allowing direct `endTick` calls.
   - Add `SongView` helpers, declared near `voiceContext` in `src/ui/songview.h`:
     ```cpp
     uint8_t trackVolumeAt(int track, uint64_t tick,
                           uint64_t &nextChangeTick) const;
     int8_t trackPanAt(int track, uint64_t tick,
                       uint64_t &nextChangeTick) const;
     ```
   - Resolve volume from CC 7 and master volume:
     ```cpp
     return m4aEffectiveTrackVolume(
         ccValueAt(m_model, track, 7, kM4aMaxVolume, tick, nextChangeTick),
         m_document ? m_document->cfg().masterVolume : kM4aMaxVolume);
     ```
   - Resolve pan from CC 10:
     ```cpp
     return int8_t(std::clamp(
                       ccValueAt(m_model, track, 10, 64, tick, nextChangeTick),
                       0, 127) -
                   64);
     ```
   - In `voiceContext`, after finding the next voice-change tick, resolve volume and pan using the same `endTick` reference, so the section ends at the earliest of the three next changes. Return `{voice, program, endTick, volume, pan}`. The out-of-range-program branch returns `{nullptr, -1, endTick, volume, pan}`.

6. **`src/ui/editordrawer/velocityarea/velocityarea.h` and `.cpp`** — inline context capture (D-5)
   - `currentContext()`'s empty-selection branch captures the context by name instead of projecting `.voice` off the temporary:
     ```cpp
     const DrawerPageVoiceContext context = m_owner.voiceContext(tick);
     return VelocityMap::resolve(context.voice, std::nullopt,
                                 context.trackVolume, context.trackPan);
     ```
   - `contextForNote` passes its already-captured context's state: `resolve(context.voice, note.key, context.trackVolume, context.trackPan)`.
   - The incompatible-selection and null-voice fallbacks in `currentContext`, the axis reset, and the `m_axis` member initializer in the header resolve unresolved tones at `kM4aMaxVolume, 0`.
   - The multi-note compatibility gate now enforces D-1 semantics: every selected note must resolve to the same PSG voice under the same effective volume and pan, or the whole selection uses the continuous ruler.

**Stage 2 acceptance:** `DrawerPageVoiceContext` carries trackVolume/trackPan; `voiceContext`'s `endTick` is the earliest of the next voice change and the next CC 7/10 change; every `velocityarea.{h,cpp}` resolve site compiles against the new signature and passes captured context state; the `context != m_axis.map()` rebuild path now also fires on volume/pan changes under the custom equality.

## Stage 3 — `velocity-paint-and-harnesses`

Worktree `velocity-dynamic-detents`. Depends on Stage 2.

7. **`src/ui/editordrawer/velocityarea/velocityarea_paint.cpp`**
   - The per-section loop already captures `DrawerPageVoiceContext`; pass `context.trackVolume, context.trackPan` to its `resolve` so painted detent bands follow each section's effective state.

8. **`src/checks/velocitymodelcheck.cpp`** (D-3)
   - Update every two-argument `resolve` call to pass `kM4aMaxVolume` (plus an explicit pan where the scenario needs one).
   - Keep the pinned full-state tables (`squareNoiseRepresentatives`, `waveRepresentatives`): full volume 127 with pan 0 reproduces them exactly.
   - Derive every volume/pan expectation through public queries on maps resolved at the fixture state: `levelCount()` falls as volume drops; `levelRange()` runs stay contiguous and ordered; centered and `-32` panned Square and Wave pairs have distinct `levelRange()` results; `hasDetents()` is false at the single-step squeeze and `VelocityAxis::mode()` picks `Continuous` there; `compatibleWith` is false across any volume or pan difference; `canonicalize`/`moveLevels` clamp at the endpoints. `m4aEffectiveTrackVolume` (public) may build fixture states; the file-local envelope chain is never referenced or duplicated.

9. **`src/checks/rollcheckpsgvelocity.cpp`** (D-3)
   - Update every `resolve` call to the fixture's captured volume/pan.
   - Derive representative and graduation expectations by resolving each fixture's map (voice, key, effective volume, pan) and querying it — never by re-deriving the envelope chain inside the harness.

10. **Verification** (D-4) — the catalog entries are `velocity-model` (`runVelocityModelCheck`) and `velocity-page` (`runVelocityPageCheck`, hosted in rollcheckpsgvelocity.cpp):
    - `deno task build:checks`
    - `deno task verify --filter velocity-model --verbose`
    - `deno task verify --filter velocity-page --verbose`
    - Open a Square or Wave velocity lane. Change track volume and pan, then confirm detent rows shift and lower effective volume produces fewer reachable levels.
    - Confirm a CC 7, CC 10, or voice change after the inspected tick limits the returned context section at the earliest next change.
    - Select notes on both sides of a volume change: the lane must show the continuous ruler, not detents from one note's state.

**Stage 3 acceptance:** both filter runs pass; the paint loop's detent bands track per-section volume/pan; harness expectations are all public-API derived.

## Stage 4 — thermo review

Worktree `velocity-dynamic-detents`. Depends on Stage 3.

Run the thermo-nuclear code-quality review (read-only) over the working-tree diff of Stages 1–3 after both filter runs pass. Fold accepted findings back into the same file set — no new files, no reformatting — and re-run the two filters before merge.

## Critical files

- `src/core/velocitymodel.{h,cpp}` — authoritative dynamic detent arithmetic.
- `src/ui/editordrawer/velocityaxis.cpp` — `hasDetents()` mode gate.
- `src/ui/editordrawer/drawerpage.h` — volume/pan in the resolved voice context.
- `src/ui/songview.h` and `src/ui/songview/trackvoiceops.cpp` — CC 7/10 and master-volume resolution.
- `src/ui/editordrawer/velocityarea/velocityarea*.cpp` and `.h` — map consumers with inline context capture.
- `src/checks/velocitymodelcheck.cpp` and `src/checks/rollcheckpsgvelocity.cpp` — behavioral contracts.

## Re-baselining rule

The dynamic model intentionally changes numeric tables. When an existing assertion disagrees, resolve a `VelocityMap` at the fixture's effective state (voice, key, volume, pan) and read the expectation off its public queries — `levelCount`, `levelRange`, `representative`, `levelOf`. Full volume 127 with pan 0 reproduces the old table shapes; do not reinstate static tables to satisfy stale expectations, and never call velocitymodel.cpp's internal helpers from a harness.
