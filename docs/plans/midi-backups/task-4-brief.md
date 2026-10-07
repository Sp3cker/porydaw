# Context
Move backup storage regressions outside the app. Read plan.md Global Constraints and spec.md first.
# Exact write set
- src/checks/projectstore/MidiBackupChecks.swift
- src/swift/backups/Tests/MidiBackupStoreTests.swift
# Interface contract
`import PorydawBackups`; public actor MidiBackupStore has shared, init(root: URL? = nil), directory(), preserveOriginal(songName: String, bytes: [UInt8], at: Date = Date()), record(songName: String, bytes: [UInt8], at: Date = Date()). The package has no Porydaw/Qt dependencies. Its Package.swift/build integration is owned elsewhere.
# Implementation steps
1. Move storage-only assertions from MidiBackupChecks to native async Swift Testing tests. Use only Foundation, Testing, and PorydawBackups. Use per-test temporary roots with deterministic cleanup and explicit dates; no runBlocking/CheckReport/Porydaw fixtures.
2. Preserve exact independent filename/byte oracles for Unicode/shared folder, immutable original, increment restart, dedup, 10-recent union 30-first-active-day retention excluding file 1, inactive days, failed creation without pruning, unrelated directories/nonregular files/symlinks/noncanonical names, clock rollback, and unreadable previous snapshot. Avoid duplicate suites or unnecessary test scaffolding. Each test owns a coherent behavior.
3. Add focused consumer-visible edge coverage for invalid song names/timestamps and occupied destination not being overwritten, where not already covered; verify previous bytes/filename sets remain intact. Do not test source text or wiring.
4. Delete storage-only fixtures/dispatch from the app check file; retain its contents helper and actual service/session checks unchanged except import/API migration (songName from source.label). Keep runMidiBackupChecks entry point. No test loss or duplicated storage suite.
5. Inspect locally; defer build/test/lint/formatter commands to controller on the settled tree.
# Acceptance predicate
`deno task checks:backups` runs storage tests using SwiftPM without building/importing Porydaw or Qt; `deno task checks --filter swiftcore-projectsession --verbose` retains real integration protection. Controller also runs full non-windowing checks and formats.
# Task-specific constraints
SHARED_TREE. No sleeps, real app-data writes, production edits, CMake/Package.swift/deno edits, or custom runner. Minimal fixture helpers, no mocks. No proof ledgers exist in this checkout; report any unexpected ledger dependency. Return full result contract; no scratch/report files or commits.
