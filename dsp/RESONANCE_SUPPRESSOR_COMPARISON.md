# Resonance suppressors: porydaw and commercial references

**Scope.** This comparison uses the porydaw detector specification and implementation, plus first-party vendor manuals/product pages only. Vendor documentation describes behavior and controls; it usually does **not** disclose the proprietary filter-bank or masking implementation. “Not documented” means that no claim is made here.

## The musician's short answer

- **porydaw** is a deliberately narrow, one-click live-bus suppressor. With the shipping defaults it looks for a spectral bin that stands out from nearby bins, works mainly from **2.5–10 kHz**, and applies the same slow, linked stereo cut to both channels. It is a good fit for persistent whistles, feedback, and harsh ringing when a conservative automatic action is wanted. It is not a replacement for a full plug-in editor: the product exposes enable/disable only, with no wet/dry, frequency nodes, sidechain, phase mode, or output limiter.
- **soothe2** is the broadest “find and shape resonances” reference here: depth, sharpness, selectivity, editable sensitivity bands, stereo linking/M/S, sidechain, quality, and wet/dry controls. It is the closest functional category match, but its exact detection/filter topology is not public.
- **DSEQ3** is the most explicit engineering-style dynamic spectral EQ: threshold, selectivity, attack/release, slope, pre-filters, custom threshold curves, gain-reduction limits, selectable L/R or M/S routing, and linear/natural phase modes. It is the clearest choice when the musician wants to set the detection rule rather than accept a fixed one.
- **Smooth Operator Pro** uses compressor-style spectral peak reduction with Peak/RMS detection, detail/isolation, editable nodes, per-node overrides, and L/R or M/S imaging. It is flexible for surgical work and sidechain spectral ducking; its exact latency and transform details are not published.
- **Gullfoss** is the least like a conventional resonance notch tool. It uses a vendor-described auditory-perception/masking model and can both cut dominant material and recover dominated material while preserving perceived loudness/dynamics. Standard/Master are about 20 ms; Live is about 2 ms. It is better understood as perceptual unmasking/tonal balancing than as porydaw-style “only cut a local peak.”

## Porydaw: verified behavior

The following is taken from [`dsp/DETECTOR.md`](DETECTOR.md) and [`src/audio/resonance_suppressor.h`](../src/audio/resonance_suppressor.h) / [`resonance_suppressor.cpp`](../src/audio/resonance_suppressor.cpp), not inferred from the commercial products.

| Dimension | Implemented behavior | Practical consequence |
|---|---|---|
| Detection | A 2048-point FFT is run per channel. The detector averages linked L/R bin power, compares each bin with the mean of bins 3–6 positions away on either side, and adds the 6 dB Guard. The reference is floored at −120 dBFS; there is no adaptive floor. Bins below the contrast knee do not engage. | Broadband material is protected by contrast rather than by an absolute “all tonal bins are bad” gate; an isolated, steady peak can still engage. |
| Spectral control | 2048-point FFT half-spectrum (1025 bins including DC and Nyquist; 1023 interior bins available to the detector); at the live 44.1/48 kHz device rates, bin spacing is about 21.5/23.4 Hz. There is no cross-bin mask smoothing. A log-frequency knot envelope is the only band shape; shipping active knots cover 2.5–10 kHz. Global depth defaults to 3 dB, with a 2.5× depth scale; a strong resonance reaches about −9.4 dB at the shipping plateau. DC and Nyquist are untouched. | Cuts are intentionally local at FFT-bin scale, not broad dynamic-EQ bands. Low bass and fundamentals are outside the shipping curve. |
| Timing and latency | Hop = 1024 samples (about 23.2/21.3 ms at 44.1/48 kHz). Attack time defaults to 150 ms; release is 4× attack (600 ms). Gain motion is capped at 100 dB/s. Enabled latency is 2047 samples (about 46.4/42.7 ms); disabled latency is zero. | It favors stable, non-pumping suppression over instant transient clamping. |
| Stereo/channel | One linked detector mask is applied to both original complex spectra. There is no L/R-vs-M/S mode or channel-link control. | A resonance in one channel can drive the same frequency cut in the other channel. |
| Phase/modes | The source uses a real FFT, symmetric square-root Hann analysis/synthesis, and weighted overlap-add. No selectable phase mode is exposed or documented. | The implementation has one fixed spectral path; do not describe it as a selectable linear/minimum/natural-phase product. |
| User controls | The product action is a persisted checkable **Suppress Resonances** enable/disable action. `ResonanceParams` (global depth, Guard, timing, knot depth/active flags) are wired as harness/test entry points, not product UI controls. There is no wet/dry mix, sidechain, node editor, quality mode, delta monitor, or output gain control in this landing. | A musician gets a simple switch, not the tuning surface offered by the commercial references. |
| Program protection and transitions | Contrast gating, the 2.5–10 kHz default curve, progressive 6–20 dB knee, slow attack/release, and a 1.25× law ceiling limit routine program reduction. There is no limiter or explicit peak-protection stage. Enabling live playback resets/prime-fills the pipeline (initial output silence); disabling discards the delayed tail and returns immediately to bit-exact pass-through. When enabled, WAV export applies the same processing with its fixed latency compensated. | It is conservative by design. Live enable/disable remains a hard transition with unreported playback delay, while offline exports preserve their original duration and alignment. |

## Commercial comparison

### oeksound soothe2

**Documented behavior.** The [official manual](https://oeksound.com/manuals/soothe2/) calls soothe2 a dynamic resonance suppressor that analyzes the incoming signal and applies automatic reduction. It documents **Soft** mode as less level-dependent, more transparent, and better at preserving transients; **Hard** mode is more level-dependent and more aggressive. **Depth** controls processing amount/sensitivity and can produce up to 60 dB notches at extreme settings. **Sharpness** makes cuts deeper and narrower; **Selectivity** acts as a prominence threshold, with higher values cutting only the most prominent resonances.

**Resolution and targeting.** Oversample calculates the reduction filter at higher frequency resolution. Resolution changes the resonance-detection refresh and filter-update rate; Eco roughly halves CPU, while High/Ultra can help transient-rich material. The graph provides a low-cut, high-cut, and four general-purpose sensitivity bands. Per-band frequency, sensitivity, Q, curve type, and balance are exposed. The manual describes that curve as inverse-EQ/sidechain weighting: boosted regions receive more sensitivity and cut regions less. No FFT size, bin width, or filter topology is published in the manual.

**Timing, channels, and phase/latency.** Attack and release are user controls; their displayed values are reference constants, actual response is frequency-dependent, and higher frequencies respond relatively faster. Higher release can reduce artifacts because rapidly moving filters may create audible phase distortion. Stereo mode is L/R or M/S; at 100% link channels are summed for analysis and receive the same processing, while 0% is dual mono. Balance can bias processing globally and per band. An external sidechain can supply the detection signal. The manual does not publish a fixed latency number; it says main and sidechain inputs must be synchronized and the DAW handles delay compensation. No linear/minimum-phase switch is documented.

**User protection.** Mix, wet-only trim, delta audition, band listen, and soft bypass are documented. Soft bypass continues computing, so it is not a CPU-saving bypass. There is no output limiter or hard maximum-reduction safety stage documented; the manual instead warns that extreme depth/high sharpness can mangle material or create non-resonant residue/distortion.

**Relative to porydaw.** Both respond dynamically to spectral prominence and both can use linked stereo analysis, but soothe2 exposes the shape, selectivity, stereo routing, sidechain, quality, and mix decisions that porydaw fixes in code. Porydaw’s exact bin width and latency are known; soothe2’s are not published.

### TBProAudio DSEQ3

**Documented behavior.** The [DSEQ3 product page](https://www.tbproaudio.de/products/dseq) and [official manual](https://www.tbproaudio.de/assets/content/manuals/DSEQ3%20manual.pdf) describe a frequency-domain dynamic processor. It analyzes the main or sidechain signal and triggers dynamic equalizers at each frequency available from the FFT. **Threshold** sets trigger level; **Selectivity** controls how far a trigger affects neighboring frequencies; **Attack** and **Release** control the common gain-reduction timing. **Slope** tilts the detector spectrum, and adaptive slope/threshold can be calculated from the material. The manual says quality can use more than 1000 dynamic equalizers.

**Resolution and targeting.** Quality mode determines FFT size, number of analyzed frequencies, and latency. The product page lists seven quality modes, 10 Hz–22 kHz processing, up to 4× oversampling, 12 independent pre-filter bands, custom threshold curves from audio, and gain-reduction spectrograms. Pre-filter sensitivity, frequency, Q, channel, and filter type can focus or de-emphasize detector regions. This is more explicit frequency-resolution control than porydaw’s fixed 2048-bin mask.

**Timing, channels, and phase/latency.** Attack/release are global controls for the many dynamic equalizers: lower values are shorter, higher values longer. The manual says analysis requires time and creates notable latency normally handled by DAW plug-in delay compensation; it does not give one fixed sample count. Channel mode is L/R or M/S, with a channel-link control for more shared or more separate processing. Sidechain input can trigger the dynamic filters. A **linear phase (LP) / natural phase (NP)** switch is documented: natural phase has less pre-ringing but more phasing than linear phase. Sample-exact bypass is listed as a feature. Oversampling and online/offline quality choices are separate controls.

**User protection.** **Max GR** limits maximum gain reduction; the product page explicitly presents this as avoiding over-compression and artifacts. GR strength provides compressor-like intensity, and mix/output gain, delta monitoring, loudness matching, meters, and smart-silence processing are available. No brickwall limiter is documented, so Max GR should not be described as a full output safety limiter.

**Relative to porydaw.** DSEQ3 is the most configurable counterpart: it gives a musician an explicit absolute threshold and detector-shaping toolset, whereas porydaw uses a fixed local-contrast law and fixed shipping curve. Both are frequency-domain and dynamic, but porydaw’s stereo mask and timing/latency are fixed and its product UI is only a switch.

### BABY Audio Smooth Operator Pro

**Documented behavior.** The [official product page](https://babyaud.io/smooth-operator-plugin) and [Pro manual](https://babyaudiosoftware.s3.us-east-2.amazonaws.com/Smooth+Operator+Pro+Baby+Audio+Manual.pdf) describe spectral peak reduction that acts only when frequencies cross a set threshold. The manual documents **Peak** detection (highest magnitude) and **RMS** detection (average spectral intensity), plus **Even** weighting or a psychoacoustically weighted **Skew** curve. Global threshold sets where reduction begins; **Ratio**, **Knee**, **Attack**, and **Release** provide compressor-style dynamics.

**Resolution and targeting.** **Detail** ranges from broad spectral trends to individual frequency peaks. **Isolation** controls how much adjacent material is included. Lo Preserve and Hi Preserve exclude frequency ranges from processing while leaving them audible. Graph nodes expose center frequency, width/Q, and a threshold offset from the global threshold. **Override Global** gives each node its own Focus, Comp, and Imaging settings. The official documentation does not publish FFT size, window, bin spacing, filter length, or a fixed latency number.

**Timing, channels, and phase/latency.** Attack and release are exposed, but no absolute time scale is specified in the manual. Imaging supports L/R or M/S, L/R-or-M/S skew, and stereo link: 0% detects/processes channels independently, while 100% sums the detector signal to mono. A sidechain mode can use another track’s spectral profile to tame the target. Baby Audio explicitly says Smooth Operator Pro uses **linear-phase processing**, but publishes no sample/millisecond latency figure and no alternate phase mode. The product page lists click-free plugin bypass.

**User protection.** Monitor can audition the removed spectral material; Mix, Out, Gain, and one-shot Auto Gain are provided. Auto Gain is explicitly not continuous, to avoid uneven level changes. There is no Max GR control or output limiter documented; the manual allows intentionally extreme spectral reshaping, so “program protection” here means threshold/compressor settings and the user’s mix/ratio choices, not a documented safety ceiling.

**Relative to porydaw.** Smooth Operator Pro offers the same musician-facing idea of dynamic spectral peak reduction but makes detection style, local thresholds, bandwidth, stereo placement, sidechain, and timing adjustable. Porydaw is narrower and less configurable, with a known fixed delay; Smooth Operator Pro’s exact transform and delay are not disclosed.

### Soundtheory Gullfoss

**Documented behavior.** The [official operation manual](https://www.soundtheory.com/static/Gullfoss%20Operation%20Manual.pdf) says Gullfoss bases calculations on an auditory-perception model and the information in the signal rather than a static spectral-power target. **Tame** treats dominant components; **Recover** treats dominated components. Gullfoss can therefore cut and boost different ranges to preserve perceived loudness and dynamics. The manual documents roughly 1000 auditory-model updates/s and more than 300 equalizer updates/s. This is a masking/unmasking objective, not a documented local-bin resonance gate.

**Resolution and targeting.** There is no published FFT size or bin resolution. **Bias** changes the classification balance between Recover and Tame; **Brighten** biases the unmasking result toward lower or higher frequencies; **Boost** changes perceived frequency balance. Two draggable frequency-range limiters restrict Tame/Recover, with smooth transitions. The user works from the live EQ graph rather than from an explicit threshold/ratio/attack/release panel.

**Timing, channels, and phase/latency.** The manual specifies mono-to-mono or stereo-to-stereo operation and compatibility with M/S channels. Standard Gullfoss and Gullfoss Master are approximately 20–21 ms; Gullfoss Live is approximately 2 ms and uses prediction/trade-offs for fast changes. The standard model’s update rates are documented, but there are no attack/release controls. Live has fixed internal quality; Standard offers Normal/Better/Best audio-quality settings, and Master is internally fixed to its highest quality. The manual does not document a linear/minimum-phase mode or filter topology. Sidechain is supported, but the vendor warns that timing differences between main and sidechain inputs can change the result and may require manual correction.

**User protection.** Soundtheory documents “artifact-free” processing and preservation of perceived loudness/dynamics as design goals, and the paired cuts/boosts are intended to avoid a loudness illusion. Bypass is latency/loudness-matched comparison but does not disable the processing engine. No maximum gain-reduction control or output limiter is documented.

**Relative to porydaw.** Gullfoss is not a direct substitute for porydaw’s steady narrowband suppressor. It may make a mix clearer by changing masking relationships, including positive Recover boosts; porydaw only applies a negative gain mask to bins that stand out above their local reference. Gullfoss provides edition/latency choices, while porydaw has a fixed enabled delay and no quality/phase mode.

## Documented facts versus cautious inferences

### Documented facts used above

- Porydaw’s detector law, FFT size/hop, knot curve, timing, stereo mask, transition behavior, and current product control surface are stated in the repository files linked above and reflected in the implementation.
- soothe2, DSEQ3, Smooth Operator Pro, and Gullfoss facts are limited to the linked first-party manuals/product pages. Claims such as “frequency-dependent attack” (soothe2), “linear/natural phase” (DSEQ3), “linear phase” (Smooth Operator Pro), and “perceived-loudness/dynamics preservation” (Gullfoss) are vendor statements, not reverse-engineered conclusions.

### Cautious inferences (not product claims)

- Porydaw’s source clearly implements an FFT/WOLA per-bin mask. It is reasonable to call that a fixed spectral-mask design, but it is **not** evidence that any commercial product uses the same FFT size, window, gain law, or filter topology.
- Commercial terms such as “dynamic equalizer,” “spectral peak,” “notch,” or “auditory model” describe function, not undisclosed internals. Exact windowing, filter-bank structure, detector smoothing, phase response, and proprietary masking equations remain unspecified unless the vendor publishes them.
- “Linear phase” is documented for Smooth Operator Pro, but the documentation does not provide its latency amount. Likewise, the absence of a published phase mode for soothe2 or Gullfoss must not be turned into a claim that either is minimum-phase, linear-phase, or zero-latency.
- Gullfoss’s update rates and edition latency are documented timing characteristics; they do not reveal its internal frequency resolution or prove that it is a conventional FFT suppressor.

## Source list

All links below are first-party vendor sources used for the comparison:

- oeksound, **soothe2 User Manual**: <https://oeksound.com/manuals/soothe2/>
- TBProAudio, **DSEQ3 product page**: <https://www.tbproaudio.de/products/dseq>
- TBProAudio, **DSEQ3 Manual (PDF)**: <https://www.tbproaudio.de/assets/content/manuals/DSEQ3%20manual.pdf>
- BABY Audio, **Smooth Operator Pro product page**: <https://babyaud.io/smooth-operator-plugin>
- BABY Audio, **Smooth Operator Pro Manual (PDF)**: <https://babyaudiosoftware.s3.us-east-2.amazonaws.com/Smooth+Operator+Pro+Baby+Audio+Manual.pdf>
- Soundtheory, **Gullfoss product page**: <https://www.soundtheory.com/gullfoss>
- Soundtheory, **Gullfoss Operation Manual (PDF)**: <https://www.soundtheory.com/static/Gullfoss%20Operation%20Manual.pdf>
