import Base

# Scale-sweep, U32-valued hot loop. Same algorithm and table as
# scale_sweep.bend; pitches/roots/masks are machine words, Nat survives
# only as loop fuel (termination) and the shr index. Expect 23680/sweep.

def mask_27(s: Nat) -> U32:
  match s:
    case 0n:
      653
    case 1n+rest:
      0

def mask_26(s: Nat) -> U32:
  match s:
    case 0n:
      1123
    case 1n+rest:
      mask_27(rest)

def mask_25(s: Nat) -> U32:
  match s:
    case 0n:
      1187
    case 1n+rest:
      mask_26(rest)

def mask_24(s: Nat) -> U32:
  match s:
    case 0n:
      397
    case 1n+rest:
      mask_25(rest)

def mask_23(s: Nat) -> U32:
  match s:
    case 0n:
      2509
    case 1n+rest:
      mask_24(rest)

def mask_22(s: Nat) -> U32:
  match s:
    case 0n:
      2483
    case 1n+rest:
      mask_23(rest)

def mask_21(s: Nat) -> U32:
  match s:
    case 0n:
      1403
    case 1n+rest:
      mask_22(rest)

def mask_20(s: Nat) -> U32:
  match s:
    case 0n:
      1371
    case 1n+rest:
      mask_21(rest)

def mask_19(s: Nat) -> U32:
  match s:
    case 0n:
      1749
    case 1n+rest:
      mask_20(rest)

def mask_18(s: Nat) -> U32:
  match s:
    case 0n:
      2901
    case 1n+rest:
      mask_19(rest)

def mask_17(s: Nat) -> U32:
  match s:
    case 0n:
      1459
    case 1n+rest:
      mask_18(rest)

def mask_16(s: Nat) -> U32:
  match s:
    case 0n:
      1741
    case 1n+rest:
      mask_17(rest)

def mask_15(s: Nat) -> U32:
  match s:
    case 0n:
      2925
    case 1n+rest:
      mask_16(rest)

def mask_14(s: Nat) -> U32:
  match s:
    case 0n:
      1755
    case 1n+rest:
      mask_15(rest)

def mask_13(s: Nat) -> U32:
  match s:
    case 0n:
      1365
    case 1n+rest:
      mask_14(rest)

def mask_12(s: Nat) -> U32:
  match s:
    case 0n:
      1257
    case 1n+rest:
      mask_13(rest)

def mask_11(s: Nat) -> U32:
  match s:
    case 0n:
      1193
    case 1n+rest:
      mask_12(rest)

def mask_10(s: Nat) -> U32:
  match s:
    case 0n:
      661
    case 1n+rest:
      mask_11(rest)

def mask_09(s: Nat) -> U32:
  match s:
    case 0n:
      2485
    case 1n+rest:
      mask_10(rest)

def mask_08(s: Nat) -> U32:
  match s:
    case 0n:
      2733
    case 1n+rest:
      mask_09(rest)

def mask_07(s: Nat) -> U32:
  match s:
    case 0n:
      2477
    case 1n+rest:
      mask_08(rest)

def mask_06(s: Nat) -> U32:
  match s:
    case 0n:
      1387
    case 1n+rest:
      mask_07(rest)

def mask_05(s: Nat) -> U32:
  match s:
    case 0n:
      1717
    case 1n+rest:
      mask_06(rest)

def mask_04(s: Nat) -> U32:
  match s:
    case 0n:
      2773
    case 1n+rest:
      mask_05(rest)

def mask_03(s: Nat) -> U32:
  match s:
    case 0n:
      1451
    case 1n+rest:
      mask_04(rest)

def mask_02(s: Nat) -> U32:
  match s:
    case 0n:
      1709
    case 1n+rest:
      mask_03(rest)

def mask_01(s: Nat) -> U32:
  match s:
    case 0n:
      1453
    case 1n+rest:
      mask_02(rest)

def mask_of(s: Nat) -> U32:
  match s:
    case 0n:
      2741
    case 1n+rest:
      mask_01(rest)

def hit_decide(hit: Bool) -> U32:
  match hit:
    case True{}:
      1
    case False{}:
      0

def interval_u(pitch: U32, root: U32) -> U32:
  pm = U32.mod(pitch, 12)
  rm = U32.mod(root, 12)
  U32.mod(U32.sub(U32.add(pm, 12), rm), 12)

def hit_u(mask: U32, pitch: U32, root: U32) -> U32:
  bit = U32.to_nat(interval_u(pitch, root))
  shifted = U32.shrn(mask, bit)
  masked = U32.and(shifted, 1)
  hit_decide(U32.is_ne(masked, 0))

def sweep_pitch_u(fuel: Nat, +mask: U32, +root: U32, +pitch: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      h = hit_u(mask, pitch, root)
      sweep_pitch_u(f, mask, root, U32.add(pitch, 1), (acc + h : U32))

def sweep_root_u(fuel: Nat, +mask: U32, +root: U32, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      sub = sweep_pitch_u(128n, mask, root, 0, 0)
      sweep_root_u(f, mask, U32.add(root, 1), (acc + sub : U32))

def sweep_scale_u(fuel: Nat, +scale: Nat, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      sub = sweep_root_u(12n, mask_of(scale), 0, 0)
      sweep_scale_u(f, Nat.add(scale, 1n), (acc + sub : U32))

def reps_u(fuel: Nat, acc: U32) -> U32:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      reps_u(f, (acc + sweep_scale_u(28n, 0n, 0) : U32))

def main() -> U32:
  reps_u(3000n, 0)
