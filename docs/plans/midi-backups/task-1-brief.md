# Context
Extract the existing backup storage as a standalone module without changing its behavior. Read plan.md Global Constraints and spec.md first.
# Exact write set
- src/swift/project/MidiBackupStore.swift (move, no copy)
- src/swift/backups/MidiBackupStore.swift
- src/swift/backups/Package.swift
- src/swift/backups/CMakeLists.txt
- CMakeLists.txt
- src/swift/project/CMakeLists.txt
- src/swift/document/CMakeLists.txt
- src/swift/app/CMakeLists.txt
- src/swift/document/service/ProjectService.swift
- src/swift/document/service/ProjectService+Bank.swift
- src/swift/app/shell/ShellPresenter.swift
File-count exception: one module extraction plus mechanical import/build/callsite migration. Do not edit checks, docs, deno.json, or ignore files.
# Implementation steps
1. Move the actor to `src/swift/backups/MidiBackupStore.swift`. Import only Foundation. Replace SongSource with `songName: String` in both public write methods and contextual errors. Keep shared/default root, directory, bytes, date, cancellation, atomic no-overwrite publish, filename scanning, and retention semantics.
2. Remove ProjectFileStore dependency. Preserve existing POSIX/UNC/drive-rooted absolute-path behavior with the small local predicate, not another shared module. Consolidate exists/isDirectory/isRegularFile into a single optional file-type lookup that catches only no-such-file; preserve symlink and error behavior.
3. Add minimal Swift 6 Package.swift: library/target PorydawBackups, source path "." with only MidiBackupStore.swift, test target PorydawBackupsTests path "Tests". Exclude CMakeLists.txt and Tests from library target. No external dependencies. Match deployment needs without requiring Qt. Add matching CMake static Swift module using existing Qt-free module conventions; remove source from PorydawProject, register before consumers, link direct consumers explicitly.
4. Migrate the service and shell imports/calls, with `songName: snapshot.destination.label`. No compatibility aliases or re-export. Preserve every save/lifecycle guard and suspension-point ordering.
5. Inspect final declarations and dependencies locally; no build/test/lint/formatter mid-flight.
# Acceptance predicate
One Foundation-only implementation compiles via standalone SwiftPM and Porydaw CMake; existing storage and save behavior passes. Controller runs `deno task checks:backups`, `deno task build:checks`, `deno task checks --filter swiftcore-projectsession --verbose`, `deno task checks --no-windowing-checks`, `deno task build:app`, `deno task format --check`, plus an external-consumer runtime smoke.
# Task-specific constraints
SHARED_TREE. SourceKit symbols work but references are empty and diagnostics report missing PorydawCore; controller supplies covering compile evidence. Do not weaken safety, add abstractions, or introduce duplicate sources. Check sources and Package test files belong to the regression task. Return full result contract; no scratch/report files and no commits.
