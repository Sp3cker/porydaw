# Context
Integrate the storage contract into real documents and saves. Read plan.md Global Constraints and spec.md.
# Exact write set
- src/swift/document/DocumentSession.swift
- src/swift/document/service/ProjectService.swift
- src/swift/document/service/ProjectService+Bank.swift
- src/swift/app/ApplicationSession+Tabs.swift
# Prerequisites
Consume task 1 public interfaces from spec.md; do not wait for its implementation or edit its files.
# Interface contract
ProjectService init(backups: MidiBackupStore = .shared), retained internal backups, public backup(_ snapshot: SaveSnapshot) async throws. DocumentSession backupNow() async throws and onBackupFailure callback per spec. Preserve all existing exported signatures except defaulted service initializer parameter addition.
# Implementation steps
1. Add service backup dependency and implement raw-source baseline + periodic snapshot operation.
2. Gate actual MIDI overwrites on byte-preserving backup success, preserving bank-before-MIDI-before-flags order and existing conflict errors. Distinguish absent source from unreadable source.
3. Add one weak-self periodic task per document and deterministic backupNow; capture only dirty changed state, preserve dirty/history, retry after failures, cancel on close/deinit, revalidate after awaits.
4. Connect failures to ApplicationSession existing user-visible reporting for every opened session including prefetched songs/background tabs; avoid repeated modal storms.
5. Inspect save/edit-during-await and tab/project close paths for wrong-source writes or leaked tasks.
# Acceptance predicate
Before-save raw bytes survive a successful save; failed backup blocks MIDI overwrite and preserves dirty state; autosave does not save/mark clean and closed sessions cannot back up: controller runs deno task build:checks, deno task checks --filter swiftcore-projectsession --verbose, deno task checks --filter projectstore-save --verbose, and real scratch edit/timer/save smoke.
# Task-specific constraints
No proof ledger edits. Storage failure is a real failure, not a reason to silently proceed. Keep I/O off main actor through actor storage/service. Keep comments at most two lines in additions.
