---
description: Owned JSON uses Foundation JSONEncoder/JSONDecoder; YYJSON and yyjson-backed libraries are permanently rejected
condition:
  - "(?i)\\bimport\\s+(?:YYJSON|ReerJSON|Ananda)\\b"
  - "\\bYYJSON(?:Encoder|Decoder|Value|Serialization|ContentDecoder|ContentEncoder)\\b"
  - "(?i)\\byyjson\\b"
  - "(?i)\\bReerJSON\\b"
  - "nixzhu/Ananda"
scope: "tool:edit(*.swift), tool:write(*.swift), tool:edit(Package.swift), tool:write(Package.swift)"
interruptMode: never
---
Owned JSON boundaries (Vapor content, `MapperProtocol` codecs, Wings, Stripe, Clerk, SQLite payload text, plugin state, CLI output) encode and decode with Foundation `JSONEncoder`/`JSONDecoder`. Do not add a custom codec layer.

The user permanently rejected YYJSON on 2026-10-17; it is not deferred. Do not propose or reintroduce swift-yyjson, a package that wraps or vendors the yyjson C library (for example ReerJSON or Ananda), or a YYJSON adapter, in any scope: decoding, encoding only, DOM access, tooling or tests. Commit `1e8fc1ba` removed the last dependency.

Evidence behind the rejection (swift-yyjson 0.6.0, measured on the real `MapperContract` DTOs, release build):

- Its `Codable` decoder is not strict, and no option makes it strict. Keyed `Bool` accepts numbers and `"true"/"1"/"0"`; keyed `String` accepts numbers and booleans; `Int` accepts numeric strings; fractions truncate into integers (`1.9` → `1`). Overflowing `Int8`/`UInt16`/`Int32` fields trap the process.
- `numberDecodingStrategy = .fast` additionally decodes `9223372036854775808` as `Int64.min` and rejects a valid `UInt64.max`.
- Speed did not offset this. In a local, in-process codec-only benchmark (second run; not end-to-end or customer-path timing), encoding was 1.28–1.79× faster, decoding was mixed, and `.fast` gained little.

Keep each site's existing date and data strategies; they define wire semantics. Existing `.sortedKeys` settings are current formatting, not a correctness requirement: no consumer hashes, signs or byte-compares encoded JSON. Third-party internals (JWTKit, Vapor form coders, GRDB) stay as their owners ship them.

A library that is not YYJSON-backed replaces Foundation for a scope only on release-build evidence from that scope's real DTOs and coder settings (the `MapperContract` DTOs for `MapperProtocol`): decode and encode outcomes identical to Foundation's (type, range, grammar and date cases), no traps or hangs, and a measured gain over the current code path that is not just dropped `.sortedKeys` work. A library that needs vendor patches or owned unsafe code does not qualify.
