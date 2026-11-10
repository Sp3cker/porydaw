# Context
Remove unnecessary capture/live-take working allocations while preserving exact note pairing, segment replacement and capture output ownership.

# Exact write set
src/swift/pluginhost/CaptureDriver.swift; CaptureTransport.swift; LiveTake.swift (the latter two in same directory); src/swift/core/EngineNoteNormalizer.swift only fixed pitch-index scratch and exact pending/final-result reserve counts; src/checks/pluginhost/PluginHostChecks.swift. No other files.

# Prerequisites
Accepted tasks16/18 capture contract. No interface dependency on tasks23/24.

# Interface contract
All public signatures/result shapes, timing, note IDs, FIFO repeated-key pairing, sample/tick endpoints, event limits/degraded behavior, cancellation/progress cadence and immutable retained outputs stay unchanged. Callback/bridge live paths remain allocation-free. Keep the ring's stable storage and ownership; no ring representation changes.

# Implementation steps
1. Put CaptureWorker's fixed 4096 output events inline in its already-owned worker rather than an additional heap Array; adapt only private capture plumbing, keeping spans inside worker access.
2. Replace CaptureTransport's outer heap Array and per-pitch dynamically growing queues with one compact owned pending-note working store and inline per-pitch bookkeeping. Use an exact-count preparation pass if needed to allocate once without guessed capacities; preserve FIFO pairing, original monotonic IDs, clipping/chase/release and sort ties. Do not increase asymptotic work, cap input or allocate a max-size arena. Prefer a contiguous pitch-bucket schedule over per-node pointer abstractions.
3. In LiveTake segment pairing, avoid building disposable full pair-result arrays then copying them into replacement. Append/update pairs directly in the required replacement through a nonescaping local helper, with compact shared FIFO working storage instead of a separate Array per key. Preserve ID-vs-pitch pairing, unmatched releases, forced closure, retained out-of-span old pairs, sorted off-before-on order, cap and degraded semantics. Reuse scratch between old/incoming passes where valid; do not retain snapshots merely for scratch reuse.
4. Replace EngineNoteNormalizer.normalize's two heap allocations of the fixed 128-entry lastByPitch map with one InlineArray<128, Int?> and an inline reset. Reserve pairing storage from the exact onset count (isOn && velocity != 0), not events.count/2; reserve final notes from the exact surviving candidate count after trimming, preserving noteLimit errors. Change no pairing, sorting, quantization, reports or public declarations. Preserve and, for uncertain edge transitions only, extend existing real capture/take checks (overlaps, IDs, unmatched/clipped notes, replacement/cap). No reserve-wiring/source-text/tautological tests or SDK retesting.

# Acceptance predicate
Existing real helper capture/cancellation/live-take and exact timing checks pass, with worker Array allocation, per-pitch heap queue sets and temporary pair-result arrays eliminated. Controller runs uv run --no-sync dev checks --filter pluginhost --no-windowing-checks --pool=3 ; same --asan and --release.

# Task-specific constraints
Read plan.md Global Constraints and spec.md. Absolute WT paths only. Over-cap5 files: one capture/take buffer ownership behavior with its existing harness, including the VST-only normalizer's fixed scratch. No state-machine changes, hard limits, shared lattice or arpeggiator changes.
The counted LiveTake slab is intentional: one index per onset plus bucket metadata trades a hashed preparation pass for compact repeated-key storage. A linked queue would require a second index per onset here; unlike EngineNoteNormalizer, LiveTake no longer owns Pending pair records in which to keep that link. Neither representation dominates every workload; do not add adaptive modes without measurements.
