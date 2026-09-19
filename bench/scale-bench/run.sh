#!/bin/bash
# Scale-sweep micro-benchmark: C++ -O2 vs Bend 2 native.
# Interpreted runs are excluded here (1 sweep ~= 31s); use
#   bend scale_sweep_x1.bend   # expect 23680
set -u
cd "$(dirname "$0")"
export PATH="$HOME/.bend/bin:$PATH"
export BEND_NO_TELEMETRY=1

echo "== build =="
c++ -O2 -std=c++20 -o bench_scale bench_scale.cpp
bend scale_sweep.bend -o scale_sweep_native
bend scale_sweep_u32.bend -o scale_sweep_u32

echo "== C++ -O2, 100k reps =="
./bench_scale 100000

echo "== Bend native Nat loop, 30 reps (expect 710400) =="
/usr/bin/time -p ./scale_sweep_native

echo "== Bend native U32 loop, 300 reps (expect 7104000) =="
/usr/bin/time -p ./scale_sweep_u32
