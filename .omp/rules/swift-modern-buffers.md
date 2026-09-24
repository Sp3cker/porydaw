---
description: Swift 6.4 toolchain — prefer Span/RawSpan/MutableSpan/OutputSpan and InlineArray over Unsafe*Pointer; keep pointer code only on measured hot paths
condition: "Unsafe(Mutable)?(Raw)?(Buffer)?Pointer|withUnsafe(Mutable)?(Bytes|BufferPointer|Pointer)|withMemoryRebound|withUnsafeTemporaryAllocation"
scope: "tool:edit(*.swift), tool:write(*.swift)"
interruptMode: never
---
The toolchain is Swift 6.4. Use the safe buffer types before unsafe pointers.

|Need|Use|
|---|---|
|Read-only view of contiguous elements (parameters, scans)|`borrowing Span<T>` (see `NoteEditing.swift`, `NoteMovement.swift`)|
|Byte view (decode, checksum, C byte blobs)|`RawSpan`|
|In-place mutation of a buffer|`MutableSpan<T>` / `MutableRawSpan`|
|Fill an uninitialized buffer|`OutputSpan` initializers|
|Fixed-size inline storage (128 voice slots, per-track counters)|`InlineArray<N, T>`|
|Off-main CPU work|a `nonisolated` async function or `@concurrent`|

- Take a `.span` from `Array`, `InlineArray` or `String.UTF8View` where the API provides one. Do not
  build a pointer, then wrap it.
- Unsafe pointers stay legal in two cases only:
  1. C interop that requires a pointer (a C function argument, or a C fixed-size array imported
     as a tuple). Keep the unsafe region as small as possible, and return safe values from it.
  2. A measured hot path. Put a comment beside it that states the measured cost, like
     `NoteProjection.swift`. The Span version there cost 5–10%, so the pointer code stays.
- Audio and playback render code (`src/swift/playback`, `src/swift/app/audio`) is CPU-critical.
  Do not convert it without a before/after benchmark.
