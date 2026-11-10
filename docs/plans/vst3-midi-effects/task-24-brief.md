# Context
Remove avoidable Swift helper framing and state-conversion copies. The native consumer in task23 preserves exactly the current protocol.

# Exact write set
src/swift/pluginhost/HelperProcess.swift; src/checks/pluginhost/BridgeChecks.swift. No other sources/registration/docs.

# Prerequisites
Accepted task18; task23 consumes unchanged wire only, implementations independent.

# Interface contract
All HelperProcess public/internal callable signatures and helper lifecycles, task joins, deadlines, cancellation, EOF/termination, main-actor isolation and bounds stay unchanged. Data retained across suspension must own its bytes. Synchronous parsing borrows only for the current frame; no escaping raw views or dangling Data regions.

# Implementation steps
1. Inspect complete framing/receive/readBytes/readText/remainder and send/getState/setState paths. Resolve refs before any exported symbol change; none intended.
2. Parse headers/fields in their existing input buffer using offsets/ranges, not subdata copies per header/field. Handle partial/coalesced frames, nonzero Data.startIndex and consumed prefixes correctly. Avoid copying the consumed remainder after every frame; retain reusable accumulation capacity where ownership permits. Do not retain an entire unbounded receive buffer merely to deliver a tiny result.
3. Build each request in one final owned frame with exact length reservation, writing bytes/text directly rather than Data(bytes)/Data(text.utf8) intermediates plus a second payload-to-frame copy. Preserve little endian encoding, class UID and size limits. Do not replace necessary continuation/deadline/task ownership with unsafe borrowed storage or add a pool/dispatcher.
4. Decode successful state replies directly from the synchronous receive buffer into their one required owned [UInt8] result, never through an owned remainder Data plus Array. Model reply outcomes explicitly; derive the state-reply distinction from existing request/message identity where possible instead of an unrelated mode flag. Preserve owned Data for ordinary replies, whose small bodies are inline. Catch state decode failures locally and fail only that request, not the helper; preserve every malformed response/end check. Use direct Data slices for Array/String field reads, not escaping lazy-map capture contexts. When the locked read staging buffer is empty, adopt the incoming owned Data chunk rather than appending/copying it into new storage. Add only real protocol regression coverage for fragmented/coalesced or boundary payload behavior if needed in BridgeChecks, no source-text/allocation-counter wiring tests.

# Acceptance predicate
Real helper create/setup/state/latency/digest/callback/shutdown paths retain behavior with redundant Data materializations removed. Controller runs uv run --no-sync dev checks --filter pluginhost --filter pluginbridge --no-windowing-checks --pool=3 ; same with --asan and --release.

# Task-specific constraints
Read plan.md Global Constraints and spec.md. Absolute WT paths only. No native sources, capture sources or ABI changes. A required owned result and cross-actor/file-read buffer are not an allocation defect; eliminate intermediates, not ownership.
