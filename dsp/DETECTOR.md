# Resonance Suppressor — Detector & Gain-Computer Implementation Plan

Status: **plan v1** — for review before implementation.
Scope: stereo bus effect, real-time, deterministic, fixed latency.
References: none. This document is self-contained; all constants are ours.

---

## 1. Goal

Automatically reduce *steady narrowband (resonant) content* — ringing, whistles,
feedback, tonal hum, room modes — while leaving broadband/transient program
material untouched. Behavior is **per-band, level-gated, slowly adaptive**:
a band is attenuated only when its level exceeds a locally-estimated floor by a
knob-controlled margin, and only up to a depth-controlled amount. When the
effect is disabled, the audio path must be bit-exact pass-through.

## 2. Non-goals

- No adaptive notch synthesis (no zero placement, no comb filtering).
- No noise-*gate* semantics (no removal of silence/pads).
- No multiband EQ presets; the response is data-derived, not static.
- No lookahead beyond the processing frame; no latency hidden inside "off".

## 3. Architecture (top-down)

```
        ┌─────────────┐      ┌──────────────┐      ┌─────────────┐
 input  │ frame delay │─────▶│ analysis     │─────▶│   detector  │
 ──────▶│  (latency   │      │  FFT 2048    │      │  (floor +   │
        │   compens.) │      │  hann/50%    │      │  gate +     │
        └─────────────┘      └──────────────┘      │  depth)     │
                                                    └──────┬──────┘
        ┌─────────────┐      ┌──────────────┐              │ gains dB
 output ◀──│ overlap-add │◀─────│  IFFT 2048  │◀─────────────┘
        │  + window   │      │  apply mask │      ┌──────────────┐
        └─────────────┘      └──────────────┘      │  smoothing   │
                                                    │  + frame lim │
                                                    └──────────────┘
```

The signal path is a classic 50%-overlap Hann FFT (analysis→per-bin gain→
synthesis). The detector runs in the same frame domain but only on **band
levels** (12 knots), never per-bin; the resulting band gains are interpolated
to a smooth per-bin mask.

## 4. Frame and latency

- Sample rates: all supported (`fs` ∈ {44100, 48000, 88200, 96000}).
- FFT size N = 2048; hop H = 1024 (50% overlap); Hann window.
- Frequency bin: `Δf = fs / N` (≈21.5 Hz @44.1k, ≈23.4 Hz @48k).
- **Latency: N−1 = 2047 samples** (≈46.4 ms @44.1k, ≈42.6 ms @48k) — constant
  regardless of active bands; delivered as a pure delay on the dry path so
  wet/dry summing stays sample-aligned (`mLatency` in the engine).
- Internal processing in `double`; I/O float32.

Requirement: when bypassed, output == input **bit-exact** (same float bits).

## 5. Analysis stage

Per frame, per channel (or per mid/side if linked later):

```
x_windowed = x * hann(N)                // COLA-normalized window
X[k] = FFT(x_windowed)                  // k = 0..N/2 (real FFT)
L[k] = 20*log10(|X[k]| + 1e-12)         // dB magnitude per bin
```

Window: symmetric Hann,N; normalization is done at synthesis so that a flat
mask reconstructs input exactly (see §10).

## 6. Band knot model

12 knots, **log-frequency scale** from 20 Hz to 20 kHz (indices b = 0..11):

| b | default knot freq (Hz) | depth value |
|---|------------------------|-------------|
| 0 | 63   | 0.0 |
| 1 | 125  | 0.0 |
| 2 | 250  | 0.0 |
| 3 | 400  | 0.0 |
| 4 | 630  | 0.0 |
| 5 | 1000 | 0.0 |
| 6 | 1600 | 0.0 |
| 7 | 2500 | 0.0 |
| 8 | 4000 | 0.0 |
| 9 | 6300 | 0.0 |
| 10| 10000| 0.0 |
| 11| 16000| 0.0 |

Each knot has: `freq[b]` (free), `depthDb[b]` (0..10 dB), `active[b]` (bool).
A **global depth** `g_depthDb` (0..10 dB) scales the per-knot envelope:

```
effDb[b] = active[b] ? g_depthDb * depthDb[b] / 10 : 0
```

A **tilt** knob (in dB/octave, range ±3) rotates the knot depths about the
1 kHz reference:

```
effDb[b] += tilt * (log2(freq[b]/1000))
effDb[b] = clamp(effDb[b], 0, 10)
```

Interpolation: for any frequency f, the knot curve is **piecewise linear in
(log f, dB)**; outside the knot span, hold the outermost knot value.
This gives the curve the “shoulder” behavior we validated in prototype
measurements: deep-but-smooth midregion, gentle roll-off outside.

## 6. Detector — floor tracking (the Guard law)

Per knot band, the band level is

```
Lb[b] = mean over bins k of L[k],  where log2(f_k/freq[b]) within ±1/12 octave
```

The floor `F[b]` is a **slow minimum-tracking estimate** per band:

```
F[b] = max(F[b], Lb[b])                   // instant ceiling: never below signal
if Lb[b] > F[b]:                           // signal rises → floor catches up slowly
    F[b] += (Lb[b] - F[b]) * a_floor;      // a_floor: 0.1/sample-pair (≈ slow pursuit)
else:
    F[b] *= a_floor_release;               // hold floor during silence (≈30 s release)
```

- `a_floor` ≈ exp(−1/(fs·τ_floor)), τ_floor ≈ 4 s (soft).
- `a_floor_release` ≈ exp(−1/(fs·30)) (very slow upward crawl).

**Excess** (the gate metric):

```
excess[b] = Lb[b] − (F[b] + Gdb)            // dB above floor+guard
```

If `excess[b] ≤ 0` → no suppression in this band (below guard). This is the
Guard knob (0–12 dB, default 6): how far above the local floor a resonance
must climb before it is touched.

## 9. Depth law (per band, static)

```
targetGb[b] = −effDb[b] · excessLaw(excess[b])
```

`excessLaw(e)` is a soft knee so deep resonances saturate at the depth
instead of over-cancelling:

```
excessLaw(e) = e ≤ 0        ? 0
             : e < KneeDb   ? 0.5·(e/KneeDb)·(e/KneeDb)      // quadratic onset
             : 1 − 0.5·(1 − (e−KneeDb)/(MaxExcess−KneeDb))²  // saturating tail
             : 1
with KneeDb = 3, MaxExcess = 24 dB.
```

Result: 0 dB when the band sits near the floor, growing to the full knot depth
when the band is clearly isolated, hard-capped at `depthDb[b]`.

## 10. Smoothing & per-frame step limit (Timing law)

All smoothing is applied **in the dB (gain) domain**, per band:

```
if targetGb < curGb:   τ = τAttack   (engage)
else:                  τ = τRelease  (recover)
per-sample: dG = (target − cur) · (1 − exp(−1/(τ·fs)))
```

- `τ_attack  = MainTiming / 8`   (default 62.5 ms at timing 500 ms)
- `τ_release = MainTiming · 4`    (default 2.0 s at timing 500 ms)

**Frame-step cap:** per band, per hop (1024 samples), the change of `curGb`
must not exceed `ΔGmax = 1 dB per 10 ms of audio` (i.e. ≤ 0.1·1024/fs·1 dB/10ms
≈ 0.2 dB/hop @48k). This bounds “pumping” and keeps gain motion inaudible.
Implemented by clamping the one-pole increment when `|Δ| > cap`.

## 11. Mask synthesis

Per frame:

1. Reconcile band gains → per-bin gains via the knot interpolation of §6
   (dB, linear-in-log-freq).
2. **Frequency-domain smoothing**: ≤3-bin moving average of the mask (≈ 1/3
   octave) to avoid per-bin “comb” artifacts.
3. Optionally flatten near 0 Hz / Nyquist (first/last 16 bins → neighbor
   value) to keep DC and Nyquist untouched (bit-invisible at DC).
4. Output mask `M[k]` (dB), converted `m[k] = 10^(M[k]/20)`.

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

## 7. Latency compensation & dry path

- The engine keeps a `mLatency = N−1` internal ring; the audible output = the
  *processed* path but the *dry* path is delayed by the same amount so that a
  `mix` parameter (later) can blend sample-aligned.
- Stereo: both channels share the same mask computed from `(L+R)/2` (linked
  = stable image; M/S variant noted for future).

## 11. Integration point (porydaw)

- Insert: `AudioEngine::process()` — right after the mix sum, before the
  master/output gain multiply. Both channels.
- Enable: atomic bool `mResonanceSuppression` (default off), read by the
  engine each frame; when off, skip analysis+synthesis entirely (bit-exact
  path, no CPU).
- UI/harness: a checkable action on the transport bar; persisted under
  QSettings `"dsp/resonanceSuppression"`; and a `--resonancecheck` CLI
  harness following the pattern of the existing `*check.cpp` checks
  (render fixed probes, assert passive bypass + mask-depth invariants).

## 12. Verification plan (deterministic, no external tools)

| case | probe | expected |
|------|-------|----------|
| bypass | any noise burst | output == input bit-exact |
| below guard | 1 kHz @ −60 dBFS | no change > 0.1 dB |
| above guard | 1 kHz @ −30, depth 3 dB | steady mask ≈ −3 ± 0.25 dB |
| saturation | same at −10 dBFS | ~ −3 dB (capped), < −3.5 never |
| attack | gate on 1 kHz | 63% of depth within 0.7·τA ± guard |
| release | gate off 1 kHz | recovers ≥90% within 4·τR estimate |
| step cap | impulse/stepy source | per-band |Δg| ≤ 1 dB/10 ms |
| spectral skirt | burst 1 k + quiet 1.045 k witness | bystander offset ≤ 6 dB extra |
| stereo | same mono both ch | identical outs |
| bypass | full scale sine, enabled→disabled | disabled == original exactly |

## 5. OPEN/decided notes

- [x] FFT size 2048 (latency 2047 ≈ 46 ms) — chosen vs other sizes: the only
  hard constraint is the latency budget; this is the smallest power-of-two
  that gives enough per-knot resolution (≥ 12 active knots / ≥ 1/3-oct).
- [ ] DC/Nyquist guard: bins 0 and N/2 left untouched (mask=1) always.
- [ ] The “depth” knob scales the envelope; per-knot depths share one global
  depth — modeled on “band template” style, our own choice to keep the UI 1
  knob for depth.
- [ ] Attack/release: MainTiming tracks the *release* feel (4×) and the attack
  is a fraction (1/8); ratio 32:1 keeps pumping inaudible on Program.

## 12. File/landing plan (dsp/)

- `src/audio/resonance_suppressor.h/.cpp` — the DSP core (single file each),
  no dependencies outside <cmath>, <cstdint>, <vector>.
- Unit test `src/resonancecheck.cpp` (existing harness convention).
- The engine owns the instance; parameter struct shared via
  `ResonanceParams { gDb, guardDb, timingMs, tilt, curve[12] }`.

## Revision history

- v0 draft: architecture + laws as specified above. No external references
  by design.