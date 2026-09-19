# Scale-sweep micro-benchmark: C++ vs Bend 2

Kernel: `porydaw_scale::{scaleMask,isScalePitch}` over a non-negative domain —
28 scales x 12 roots x 128 pitches = 43,008 pitch tests per sweep.
Bend table is a 29-def match chain (Peano `Nat` has no literal patterns);
C++ uses the `uint16_t` table. Same semantics, verified by checksum.

## Results (M4 Pro, macOS, wall clock)

| config | checksum | time | per sweep | vs C++ |
|---|---|---|---|---|
| C++ `-O2`, 100k reps x3 | 2368000000 | 242-244ms | **2.43us** | 1x |
| Bend 2.0.10 interpreted, 1 rep | 23680 | 31.2s | ~31s | ~1e7x |
| Bend native (`-o`), Nat loop, 30/300 reps | 710400 / 7104000 | 0.2-0.3s incl ~0.2s init | ~0.5-1ms marginal | ~300x |
| Bend native, U32 loop, 300/3000 reps | 7104000 / 71040000 | 0.16-0.27s incl init | tens of us marginal | ~20x |

Per-sweep checksums agree exactly: 23680 everywhere (710400/30,
7104000/300, 71040000/3000, 2368000000/100000).

## Cost drivers, in order

1. **Interpreted overhead** (~1e7x): `bend file` runs the checker + tree
   evaluator; Peano `Nat.mod/add/sub` per pitch dominates.
2. **Nat vs U32** (~11x native): `scale_sweep_u32.bend` keeps pitches,
   roots and masks as machine words; `Nat` survives only as loop fuel
   (termination) and the `shrn` index via `U32.to_nat`.
3. **Runtime init** (~0.2s fixed): BendRT thread-pool/startup dwarfs the
   kernel at this size — 30 vs 300 reps barely moves wall time.
4. **Remaining ~20x**: affine/`+` refcounts, generic runtime vs `-O2` ints.

## Reproduce

./run.sh        # C++ 100k + native Nat-30 + native U32-300, builds first
bend scale_sweep_x1.bend   # interpreted, ~30s, expect 23680

## Takeaway for Porydaw

Bend 2 is viable for proving small pure kernels correct (checksum match),
not for hot paths: even the tuned U32 native build trails `-O2` by ~20x
on fine-grained integer work, and the parallel/GPU story needs workloads
at mandelbrot/nbody grain — a 43k-op sweep is far below BendRT's efficient
fork threshold. Keep DSP/audio in C++; reach for Bend only where a
machine-checked law is worth the tax.
