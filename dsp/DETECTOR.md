# Resonance Suppressor — Detector & Gain-Computer Implementation Plan

Status: **plan v7** — implemented under review (see §17).
Scope: stereo bus effect, real-time, deterministic; fixed latency while enabled and
zero latency while disabled.
References: none external; all constants are grounded in black-box
measurements of a commercial dynamic resonance suppressor ("the reference
plugin" below), 2026-08-15, 48 kHz.

---

## 1. Goal

Automatically reduce *steady narrowband (resonant) content* — ringing, whistles,
feedback, tonal hum, room modes — while leaving broadband/transient program
material untouched. Behavior is **per-bin and level-gated**: each FFT bin is
attenuated only when its level exceeds the silence baseline by a
knob-controlled margin (the Guard), up to a depth-controlled amount, with
slow attack/release (§9). Depth is shaped across frequency by the knot curve
of §6; guard and timing are global. When the effect is disabled, the audio
path must be bit-exact pass-through.

## 2. Non-goals

- No adaptive notch synthesis (no zero placement, no comb filtering).
- No noise-*gate* semantics (no removal of silence/pads).
- No multiband EQ presets; the response is data-derived, not static.
- No lookahead beyond the processing frame; no latency hidden inside "off".

## 3. Architecture (top-down)

While enabled, each stereo input frame is windowed and transformed. A single
stereo-linked detector computes a per-bin excess metric from the two spectra
(§7); the knot curve of §6 supplies a per-bin depth envelope; per-bin target
gains are smoothed in the dB domain (§9) into one real-valued mask. That mask
is multiplied into both original complex spectra and the result is
inverse-transformed through weighted overlap-add. The detector never replaces
the spectra; it only supplies their shared mask.

The mask is purely per-bin: no cross-bin smoothing. A sink is therefore as
narrow as one FFT bin — at N=2048 a bin is 21.5 Hz @44.1k / 23.4 Hz @48k,
comparable to the reference plugin's measured sink locality of ±10–15 Hz at N=4096.

## 4. Frame and latency

- Sample rate: **fs = the live engine rate** (the device's native rate as
  resolved at `AudioEngine::init`, typically 44100 or 48000). A code-path
  audit (2026-08-15) found no 32768 Hz grid in the live path: miniaudio is
  configured with `sampleRate = 0` (device native) and `m4a_engine_init`
  receives that rate, so the mix sum already runs at the device rate. All
  rate-dependent constants are computed from `fs` at init.
- FFT size N = 2048; hop H = 1024 (50% overlap, 23.2/21.3 ms @44.1/48k);
  square-root periodic Hann analysis and synthesis windows.
- Frequency bin: `Δf = fs / N` = **21.5/23.4 Hz** @44.1/48k (N/2 = 1024
  bins to Nyquist).
- **Enabled latency: N−1 = 2047 samples** (≈ **46.4/42.7 ms** @44.1/48k),
  constant regardless of active bands. There is no wet/dry mix in v1.

- **Disabled latency: 0 samples.** Disabled audio copies input to output
  directly and does not enter the frame processor.
- **Enable/disable is a hard switch.** On enable, the pipeline primes from
  silence: the first ≈N−1 output samples are silent and gains attack up from
  0 dB per §9. On disable, the delayed tail in the pipeline is discarded and
  the 0-latency bit-exact path resumes immediately (an audible jump is
  accepted; temporary loss of audio on activation is accepted).
- Internal processing in `double`; I/O float32.

Requirement: while disabled, output == input **bit-exact** (same float bits).
The enabled FFT path has a numerical reconstruction tolerance (≤ −120 dB RMS
relative to input with mask = 1, §14); it is not bit-exact.

## 5. Analysis stage

Per frame, per channel:

```
x_windowed = x * sqrt_hann_periodic(N)
X[k] = FFT(x_windowed)                  // k = 0..N/2 (real FFT)
```

The window is `w[n] = sqrt(0.5 - 0.5*cos(2*pi*n/N))`. Analysis and synthesis
both use `w`. At `H=N/2`, the overlapping products sum to one:
`w[n]^2 + w[n+H]^2 = 1`. The forward transform is unscaled and the inverse
transform includes `1/N`; adapt only that scale if the chosen FFT backend uses a
different convention. The implementation must preallocate its FFT plan and scratch
buffers during initialization. A mask of 1 must reconstruct the delayed input within
the numerical tolerance in §14, not bit-for-bit.

## 6. Knot curve (depth envelope)

12 knots on an ascending log-frequency axis (indices b = 0..11):

| b | default knot freq (Hz) | depth value |
|---|------------------------|-------------|
| 0 | 63   | 0.0 |
| 1 | 125  | 0.0 |
| 2 | 250  | 0.0 |
| 3 | 400  | 0.0 |
| 4 | 630  | 0.0 |
| 5 | 1000 | 10.0 |
| 6 | 1600 | 10.0 |
| 7 | 2500 | 10.0 |
| 8 | 4000 | 10.0 |
| 9 | 6300 | 10.0 |
| 10| 10000| 10.0 |
| 11| 16000| 10.0 |

**Shipping default (Option B, decided 2026-08-16):** knots 7–10
(2500 Hz – 10 kHz) active, knots 0–6 and 11 inactive. The low bands never
participate, so bass/kick/fundamentals are untouched; only ringing/whistles
in the presence zone are pulled down. The full 1–16 kHz curve proved too
aggressive in listening (2026-08-16): with per-bin gating it dims all
steady high-band program material, so the default band is narrowed to the
whistle range and the global depth lowered (below).

Each knot has: `freq[b]` (strictly ascending, 20 Hz..min(20 kHz, Nyquist)),
`depthDb[b]` (0..10 dB), and `active[b]` (bool). Frequencies at or above Nyquist
are inactive at that sample rate. (The reference plugin's shipping default curve is 12
arbitrary "auto" positions, mostly ≥ 790 Hz — our grid is a deliberate
simplification.) Parameter editing is outside the v1 DSP landing; the check
harness supplies explicit values. The only v1 product control is
enable/disable, using the shipping defaults above.
A **global depth** `g_depthDb` (0..10 dB, default **3**) scales the
per-knot envelope:
```
effDb[b] = active[b] ? g_depthDb * depthDb[b] / 10 : 0
```
With the shipping default (g_depthDb = 3, active knots at 10.0): effDb = 3
on the active bands → steady plateau ≈ kDepth·3 = **≈ −7.5 dB** over
2.5–10 kHz for a full-strength resonance; very resonant bins (≥ 20 dB
excess) get ×1.25 → **−9.4 dB**, small ones follow the §7 ramp (gentler
default, 2026-08-16).

A **tilt** knob (in dB/octave, range ±3) rotates the knot depths about the
1 kHz reference:

```
effDb[b] += tilt * (log2(freq[b]/1000))
effDb[b] = clamp(effDb[b], 0, 10)
```

Interpolation: for any frequency f, the knot curve is **piecewise linear in
(log f, dB)**; outside the knot span, hold the outermost knot value.
Sampled at every bin center, this yields the per-bin depth envelope
`depthEnv[k]` (dB) consumed by §8 — the only band-shaped quantity in the
design; guard and timing stay global (§7, §9).
This gives the curve the “shoulder” behavior we validated in prototype
measurements: deep-but-smooth midregion, gentle roll-off outside.

## 7. Detector — spectral contrast (the Guard law)

For each FFT bin, linked stereo power is

```
P[k] = (|XL[k]|^2 + |XR[k]|^2) / 2
```

and the per-bin level is `L[k] = 10*log10(P[k] + 1e-24)` dB. Detection is
entirely per-bin. DC and Nyquist never contribute to the detector.

The baseline is the **fixed silence threshold** `SilenceDb = −120 dBFS`;
there is no adaptive floor. Measured reference behaviour: a steady tone is
suppressed at a constant plateau for the full 90 s probe (< 0.01 dB drift,
two factory presets), and a −63 dBFS tone engages on first appearance.
Any upward floor pursuit would lighten the suppression as the floor caught
up; none is observed, so the baseline never rises. A bin at or below
`SilenceDb` is silent and its target gain is 0 dB.

The detector is therefore **stateless**; all memory lives in the §9 gain
smoothers.

**Excess** (the gate metric) is a *spectral contrast*, not an absolute
threshold (changed 2026-08-16 — a pure absolute gate engages every tonal
bin of a full mix and reads as "suppressing everything"):

```
ref[k]  = max(mean(L[k±3..k±6]), SilenceDb)   // neighbours at 3..6 bins
excess[k] = L[k] − (ref[k] + Gdb)
```

The reference is the **mean** of the four bins 3–6 positions away on each
side. The Hann peak spread of a tone covers ±2 bins, so the tone's own
energy is excluded; a **median** was measured to under-estimate a noise
floor by ~1.6 dB (half the bins of broadband program engage every hop —
measured 1.4 dB of accumulated dimming), so the mean is used. The floor at
`SilenceDb` makes an isolated tone behave exactly like the old absolute
law: a silent neighbourhood reads −120 dBFS and the tone engages on level
alone.

If `excess[k] ≤ 0` → no suppression in this bin (not a local peak). This is
the Guard knob (0–12 dB, **default 6.0 dB**; raised from 3.0 when the law
became contrast-relative, 2026-08-16): the margin a bin must exceed above
its spectral neighbourhood to engage. Protection of program material comes
from the contrast law itself, plus the depth-curve shape and the slow
timing law.

The response is **progressive** (user decision 2026-08-16 — "dampen very
resonant resonances a bit more but dampen small resonances less"): nothing
below the 6 dB knee, then a smoothstep to the **1.25× ceiling** at 20 dB
excess:

```
excessLaw[k] = 1.25 * smoothstep((excess[k] - 6 dB) / 14 dB)   // 6..20 dB
excessLaw[k] = 0        for excess ≤ 6 dB
excessLaw[k] = 1.25     for excess ≥ 20 dB
```

A resonance 26 dB or more above its local floor gets the full 1.25× depth
(default plateau **−9.4 dB**), a modest one (12 dB above the floor) gets
about a quarter of full depth, and broadband program (noise, drums, full
mixes) sits below the knee and passes with < 0.3 dB measured dimming.
Isolated tones reach the ceiling (their contrast is capped near 36 dB by
their own Hann skirt, which also excludes them from their reference
neighbourhood, so the measured excess is level-independent).

Example: with `L[k]=-40 dBFS`, silent neighbourhood, `Gdb=6 dB`:
`excess=74 dB`, `excessLaw = 1.25`, and the target gain is
`−kDepth·depthEnv[k]·1.25`.

## 8. Depth law (per bin, static shape)

```
targetGb[k] = −kDepth · depthEnv[k] · excessLaw(excess[k])
```

`kDepth = 2.5` is the plateau/depth ratio. The reference plugin's steady-state plateau
measures **1.9–3.8× the active knot's depth value** (three factory presets:
8.0 → −18.7 dB, 6.3 → −19.4 dB, 5.0 → −18.9 dB; shape/retilt-dependent) —
we fix 2.5, so a knot depth of 10 dB saturates at −25 dB.

`excessLaw(e)` is a soft knee so deep resonances saturate at the depth
instead of over-cancelling. The response curve is the §7 progressive law:

```
excessLaw(e) = e ≤ 6 dB        ? 0
             : 6 < e < 20 dB   ? 1.25 · smoothstep((e − 6 dB) / 14 dB)
             : e ≥ 20 dB       ? 1.25
```

Result: 0 dB when the bin sits at or below the guard, growing
progressively to the full `kDepth·depthEnv[k]` at 20 dB excess, and to
`1.25 · kDepth · depthEnv[k]` for very resonant bins (user decision
2026-08-16 — see §7).

## 9. Smoothing & per-frame step limit (Timing law)

All smoothing is applied **in the dB (gain) domain**, per bin, as a per-hop
one-pole. The exponential-in-dB shape is what the reference plugin's attack traces show
(our measured attack fits are log-linear in dB over 0.7–3 s), so this is the
same curve class, discretized per hop with `dt = H/fs` (23.2/21.3 ms
@44.1/48k):

```
if targetGb < curGb:   τ = τAttack   (engage)
else:                  τ = τRelease  (recover)
alpha = 1 − exp(−dt/τ)
step  = (targetGb − curGb) · alpha
curGb += clamp(step, −cap, +cap)
```

- `τ_attack  = MainTiming`        (default 500 ms; one-pole t63 = τA)
- `τ_release = MainTiming · 4`    (default 2.0 s at timing 500 ms; ours —
  the reference plugin's release was only measured as <1 s partial rebound + memory)

The reference plugin's measured attack is t63 ≈ 0.7–3.3× its Timing knob (0.05–0.87 s
across T=94–500 ms), never T/8-fast — hence τA = T here.

**Frame-step cap:** per bin, per hop, the change of `curGb` must not exceed
`ΔGmax = 1 dB per 10 ms` (100 dB/s) = **100·H/fs dB/hop** (2.32/2.13 dB/hop
@44.1/48k). The
one-pole step is computed first, then clamped (`clamp` above). This bounds
“pumping” and keeps gain motion inaudible. At short timings the cap dominates
the attack (τA = 94 ms and a 25 dB plateau give t63 ≈ 158 ms ≈ 1.7·T),
reproducing the reference plugin's slower-than-τ onset at small Timing values.

## 10. Mask synthesis

Per frame:

1. Per-bin: `M[k] = curGb[k]` (dB) directly — no band reconciliation and
   **no cross-bin smoothing**. The reference plugin's measured locality is bin-scale
   (±10–15 Hz at N=4096/48k); smoothing would smear the sink over
   neighbouring bins. A Hann-windowed tone still spans ±2 bins, so the
   effective sink follows the window naturally.
2. Bins 0 and N/2 are masked to 1 (0 dB) always — DC and Nyquist untouched.
3. Convert: `m[k] = 10^(M[k]/20)`.

## 11. Synthesis & windows

```
X'[k] = X[k] · m[k]
x' = IFFT(X')  (complex→real; real part)
out = x' · hann(N) · (2/N normalize)   // COLA: Hann·Hann sum=1 at 50% overlap
```

COLA property: with 50% overlap, `Σ_k w²(n−kH) = 1`, so the synthesis
window is the same Hann and no extra gain is needed; verify numerically at
init.

Bypass: `m[k] ≡ 1` → output equals delayed input exactly (check bit-exact
unit test).

## 12. Latency compensation & dry path

- The engine keeps a `mLatency = N−1` internal ring; the audible output = the
  *processed* path but the *dry* path is delayed by the same amount so that a
  `mix` parameter (later) can blend sample-aligned.
- **No latency reporting.** The audible 2047-sample delay is accepted
  silently: the playhead derives its position from m4a tick position, so no
  visual indicator of the latency exists or is needed.
- Stereo: both channels share the same mask computed from the linked per-bin
  power of §7 (stable image; M/S variant noted for future).

## 13. Integration point (porydaw)

- Insert: `AudioEngine::process()` — right after the mix sum, before the
  master/output gain multiply, at the live engine rate (§4). Both channels.
  The render loop is chunked; the suppressor accumulates its 1024-sample
  hop across chunks. **Live-audio path only** — `wavexport.cpp` renders
  through a private M4AEngine and is deliberately NOT touched in v1
  (exported WAVs do not carry the effect).
- Enable: atomic bool `mResonanceSuppression` (default off), read by the
  engine each frame; when off, skip analysis+synthesis entirely (bit-exact
  path, no CPU).
- UI/harness: a checkable action on the transport bar; persisted under
  QSettings `"dsp/resonanceSuppression"`; and a `--resonancecheck` CLI
  harness following the pattern of the existing `*check.cpp` checks
  (render fixed probes, assert passive bypass + mask-depth invariants).
  The `ResonanceParams` struct is fully wired as **test entry points**
  (harness flags / debug inputs): gDb, guardDb, timingMs, tilt, curve[12].
  The product action uses the shipping defaults of §6/§9/§15.

## 14. Verification plan (deterministic, no external tools)

| case | probe | expected |
|------|-------|----------|
| bypass | any noise burst | output == input bit-exact |
| passthrough | mask forced to 1 | reconstruction error ≤ −120 dB RMS relative to input |
| below threshold | 1 kHz @ −118 dBFS, guard 6 | excess < 0 → change ≤ 0.1 dB |
| above guard | 1 kHz @ −30 dBFS from silence, knot@1k depth 10, global depth 3, guard 6, ≥2 s dwell | plateau ≈ −9.4 ± 1 dB |
| saturation | same probe at −10 dBFS | same −9.4 dB plateau, never < −10.5 |
| level independence | 1 kHz staircase −63..−3 dBFS, 1.5 s dwell, global depth 8 | plateau ≈ −25 dB, drift ≈ 0 (reference: < 3 dB) |
| sustained hold | 1 kHz @ −15 dBFS, 60 s | gain plateau constant to < 0.1 dB after attack (measured on the gain state — a signal-level probe is smeared by the tone's own unmasked Hann skirt; reference: 90 s, < 0.01) |
| attack | gate on 1 kHz, timing 500 ms | t63 ≈ 0.5 s ± 50% (reference: 0.62 s) |
| release | gate off 1 kHz | gains recover ≥90% within 4·τR (measured on the gain state — §9; a signal-level re-gate probe is smeared by the STFT hop lookahead) |
| step cap | gate on 1 kHz | per-bin |Δg| ≤ 100·H/fs dB/hop (2.13 dB/hop @48k), measured hop-exact on the gain state |
| two-tone engagement | 1 kHz @ −15 + 12 kHz witness @ −40 (spectrally separated), steady 20 s, global depth 8 | both components at ≈ −25 ± 1 dB (reference: both −19.5; level-independent, per-component) |
| bypass | full scale sine, enabled→disabled | disabled == original exactly |
| low band exemption | 300 Hz @ −15 dBFS, steady | change ≤ 0.1 dB (knots 0-4 inactive) |
| program protection | white noise @ −15 dBFS RMS, 5 s, global depth 8 | broadband RMS within 0.5 dB (blanket detector would dim ~13 dB; mean-vs-median regression measured 1.4 dB) |
| resonance in program | same noise + 3 kHz tone @ −15 dBFS | tone engages ≥ 10 dB; broadband RMS within 3.5 dB (up to ~3.1 dB is the legitimate removal of the tone's own energy) |
| small resonance in program | same noise + 3 kHz tone @ −25 dBFS | tone engages gently (1.5–8.5 dB, far below the −25 full plateau); broadband RMS within 1.5 dB |
| device rate 44.1 kHz | 1 kHz @ −15 dBFS, fs = 44100 | plateau ≈ −25 ± 1 dB; per-hop cap 2.32 dB (100·H/44100) |
| DC/Nyquist guard | 0.5 DC + Nyquist sine + 23.5 kHz @ −15 dBFS, full curve | gain stays 0 on bins 0 and N/2; bin 1003 engages (checked on the gain state — the Goertzel at exactly Nyquist is degenerate) |

## 15. OPEN/decided notes

- [x] FFT size 2048 at the live engine rate (latency 2047 ≈ 46/43 ms
  @48/44.1k) — chosen vs other sizes: the only hard constraint is the
  latency budget. Per-bin masks at 23.4/21.5 Hz @48/44.1k give sink widths
  comparable to the reference plugin's measured ±10–15 Hz at N=4096.
- [x] DC/Nyquist guard: bins 0 and N/2 left untouched (mask=1) always.
- [x] Depth scale: plateau = `kDepth·depth` with `kDepth = 2.5`, grounded in
  reference-plugin plateau/knot ratios (1.9–3.8, shape/retilt-dependent).
- [x] Guard default 6.0 dB — raised from the reference's 3.0 when the gate
  became contrast-relative (2026-08-16); with the mean reference this keeps
  broadband program under 0.3 dB of dimming (median measured 1.4 dB).
- [x] Spectral contrast detector (user decision 2026-08-16 — "it's
  suppressing everything"): excess = L[k] − (mean(L[k±3..k±6]) + guard),
  floored at −120 dBFS. Isolated tones behave as before (level
  independence preserved); broadband program is exempt; a narrow tone in a
  mix still engages.
- [x] Gentler shipping default (user decision 2026-08-16): knots 7–10
  (2.5–10 kHz) active, g_depthDb 3 → plateau −7.5 dB; the full 1–16 kHz
  @ depth 8 curve dims the whole high band.
- [x] Progressive response (user decision 2026-08-16 — "dampen very
  resonant resonances a bit more but dampen small resonances less"):
  smoothstep knee 6 dB → 1.25× ceiling at 20 dB excess (ceiling lowered
  from 24 when measurements showed isolated tones' contrast is capped near
  36 dB by their own Hann skirt, and the flat ceiling kills the skirt-phase
  ripple a mid-ramp law picks up).
- [x] fs = the live engine rate (device native; no 32768 Hz grid exists in
  the live path — code-path audit 2026-08-15, user approved live-rate) —
  the suppressor initializes from `m_sampleRate` at device init.
- [x] Hard enable/disable switch: prime from silence on enable (first
  ≈2047 samples silent, gains attack up), discard the delayed tail on
  disable; audible jump and temporary audio loss accepted — user decision
  2026-08-15.
- [x] Live-audio path only; `wavexport.cpp` untouched in v1 (exported WAVs
  carry no effect) — user decision 2026-08-15.
- [x] `ResonanceParams` wired as test entry points (harness flags/debug
  inputs).
- [x] Shipping curve — **Option A** (user decision 2026-08-15): knots
  1000–16000 Hz active at 10.0, knots 63–630 Hz inactive; g_depthDb = 8 →
  effDb 8 → plateau ≈ −20 dB (mirrors the reference: its default bands ≥ 790 Hz
  at ≈8, plateau −18.7 dB). tilt = 0, guardDb = 3.0, timingMs = 500 are
  the product defaults behind the enable/disable action.
- [x] No latency reporting: playhead position comes from m4a tick position,
  so the 2047-sample delay has no visual indicator — user decision
  2026-08-15.
- [x] Reconstruction tolerance: ≤ −120 dB RMS relative to input with
  mask = 1 (double-internal FFT round trip is far below this; the bound is
  generous to absorb window/overlap float32 I/O noise).
- [x] Smoothing law: per-hop one-pole in dB with `alpha = 1 − exp(−dt/τ)`,
  cap applied to the one-pole step (3.125 dB/hop); exponential-in-dB form
  matches the reference plugin's measured attack fits (log-linear over
  0.7–3 s).
- [x] Attack/release: τA = MainTiming, τR = 4·MainTiming (ratio 1:4); the
  1 dB/10 ms cap dominates at short timings, reproducing the reference plugin's
  t63 ≈ 0.7–3.3·T onset.
- [x] Fixed threshold, no adaptive floor — user decision 2026-08-15 after the
  90 s hold measurement (plateau drift < 0.01 dB, both presets). Consequence:
  guard and the §8 knee bind only below ≈ −93 dBFS; the detector is
  stateless. Rejected alternatives: post-suppression floor (keeps the guard
  meaningful, behaviourally near-identical); spectral-neighbourhood excess
  (old witness deltas re-read as relative to the sunk baseline — two-tone
  probes show no bystander exemption).
- [ ] The “depth” knob scales the envelope; per-knot depths share one global
  depth — modeled on “band template” style, our own choice to keep the UI 1
  knob for depth.

## 16. File/landing plan (dsp/)

- `src/audio/resonance_suppressor.h/.cpp` — the DSP core (single file each),
  no dependencies outside <cmath>, <cstdint>, <vector>.
- Unit test `src/resonancecheck.cpp` (existing harness convention).
- The engine owns the instance; parameter struct shared via
  `ResonanceParams { gDb, guardDb, timingMs, tilt, curve[12] }`.

## 17. Revision history

- v0 draft: architecture + laws as specified above. No external references
  by design.
- v2 (2026-08-15): validated against black-box measurements of the
  reference plugin. Detector moved from band-level to per-bin; dropped
  cross-bin mask smoothing; depth re-scaled ×2.5 (measured plateau/knot
  1.9–3.8); τA = Timing (measured t63 ≈ 0.7–3.3·T); guard default 3.0 dB;
  floor init −120 dBFS; DC/Nyquist mask=1 decided.
- v3 (2026-08-15): 90 s sustained-tone measurement (two presets: −19.43 dB
  at t=8 s and t=89 s; −18.67 dB; drift < 0.01 dB) falsified the upward
  floor pursuit → detector reduced to a fixed −120 dBFS threshold, stateless.
  Steady two-tone probes: quiet witnesses at 700–1100 Hz all sink to the
  same plateau as a −15 dBFS 1 kHz tone (level-independent, per-component).
- v4 (2026-08-15): integration decisions — fs fixed at 32768 (engine grid;
  device upsampling downstream); latency 2047 ≈ 62.5 ms; bin 16 Hz; hop
  31.25 ms; cap 3.125 dB/hop. Hard enable/disable switch (prime from
  silence, discard tail on disable). Live-audio path only (wavexport
  untouched). ResonanceParams wired as test entry points. No latency
  reporting (playhead from m4a ticks). Smoothing pinned as per-hop one-pole
  in dB (reference-plugin attack fits are log-linear); cap applied to the one-pole
  step. Reconstruction tolerance ≤ −120 dB RMS (mask = 1).
- v4.1 (2026-08-15): shipping curve decided — Option A: active knots
  1000–16000 Hz at 10.0, lower five inactive, g_depthDb = 8, tilt 0
  (plateau ≈ −20 dB; mirrors the reference's ≥ 790 Hz @ ≈8 default).
- v5 (2026-08-15): rate correction — the plan's fixed 32768 Hz grid was
  falsified by a code-path audit (miniaudio `sampleRate = 0` native device,
  `m4a_engine_init(deviceRate)`, no interposer upsampler; samplecheck's
  32768 was an arbitrary offline test constant). The suppressor runs at the
  live engine rate (typically 44100/48000): Δf ≈ 21.5/23.4 Hz, latency
  2047 ≈ 46.4/42.7 ms, hop 23.2/21.3 ms, cap 2.32/2.13 dB/hop. All laws are
  rate-parameterized at init. Implementation: `resonance_suppressor.{h,cpp}`
  + `--resonancecheck` harness (plan v5 = v4.1 + this correction).
- v6 (2026-08-16): listening feedback ("it's suppressing everything") →
  detector law changed from an absolute per-bin gate to **spectral
  contrast**: `excess[k] = L[k] − (mean(L[k±3..k±6]) + guard)`, reference
  floored at −120 dBFS so isolated tones behave exactly as before (level
  independence preserved, all original checks pass unchanged). Mean
  estimator over median (median under-estimates a noise floor ~1.6 dB →
  measured 1.4 dB broadband dimming; mean → 0.24 dB). Guard default raised
  3.0 → 6.0 dB (now contrast-relative). Shipping default gentled: knots
  7–10 (2.5–10 kHz) active, g_depthDb 8 → 3 → plateau −7.5 dB. New checks:
  low-band exemption, program protection (≤ 1 dB on noise), resonance in
  program (tone ≥ 10 dB, program ≤ 3.5 dB); two-tone witness moved to
  3 kHz (spectrally separated). Harness: 18 cases.

- v7 (2026-08-16): user feedback ("dampen very resonant resonances a bit
  more but dampen small resonances less") → **progressive response**: the
  flat 1.0 law became a smoothstep from a 6 dB knee to a **1.25× ceiling**
  at 20 dB excess — below the knee nothing engages; a modest resonance gets
  a fraction of full depth; a strong one gets 1.25× (−9.4 dB default
  plateau). Measurements drove the ceiling: an isolated tone's contrast is
  capped near 36 dB by its own Hann skirt, and a law riding mid-ramp picks
  up the 3-hop window-phase ripple (±0.2 dB plateau wobble); the flat
  ceiling kills it. The sustained-hold check moved to the gain state (a
  signal-level probe is smeared by the tone's unmasked skirt). New check:
  small resonance in program (engages gently, far below the ceiling).
  cleanly). Harness: 20 cases.
  Independent review pass (2026-08-16) added: peak-convention calibration
  (π²/N²; a bin-centred full-scale sine reads 0 dBFS), Nyquist-knot
  deactivation (knots ≥ fs/2 forced inactive), hop-exact gain-state step
  cap check, 44.1 kHz device-rate case, DC/Nyquist guard case, tighter
  program bounds (0.5 dB pure program). Harness: 24 cases.