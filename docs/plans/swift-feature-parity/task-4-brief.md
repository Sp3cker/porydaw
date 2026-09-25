# Context
Repair R01: ProjectStore.run invokes a nonisolated asynchronous closure rather than serializing its body, and the already-observed projectstore-actor A03 fails. This task produces the concrete actor API consumed by later shared-bank work. Read plan.md Global constraints and spec.md.

# Exact write set
- src/swift/project/ProjectStore.swift
- src/swift/app/ProjectService.swift
- src/checks/projectstore/ProjectStoreActorChecks.swift
- src/swift/project/ProjectStore+Open.swift
- src/swift/project/ProjectStore+Bank.swift
- src/swift/project/ProjectStore+Edit.swift
- src/swift/project/ProjectStore+Save.swift

# Prerequisites
None. Preserve all pre-existing work.

# Interface contract
Remove ProjectStore.run and migrate every production caller. Add actor-owned synchronous throwing readFile(_ path: String) -> Data and writeFile(_ path: String, data: Data), delegating to ProjectFileStore. Add actor-owned voicegroupCatalog() -> (groups: VgCatalogScan, direct: VgDirectSoundScan), using the store projectRoot. ProjectService converts this project-owned result into its existing app catalog type. No async generic closure executor or compatibility alias survives. Preserve ProjectService public API and existing save ordering/error mapping.

Preserve the Linux main-actor/Qt-event-loop integration from `c47b55f4` and the native loader's `ProjectContext` dedicated worker. The user reports a Linux Qt timer/thread-affinity issue was fixed today. Removing the generic closure must not move native loader calls or QML publication onto the wrong executor. macOS verification does not qualify Linux runtime behavior.

# Implementation steps
1. Inspect references before changing the exported run API; migrate qualified and unqualified actor-extension callers as well as check users. The correction pass owns the four extension files separately; collapse their run/private-method forwarding pairs into the existing public actor methods without changing observable contracts.
2. Put the filesystem/catalog operations inside the existing store actor. Preserve atomic writes and propagate real filesystem errors.
3. Migrate ProjectService without moving PorydawApp types into PorydawProject.
4. Replace implementation-only wrapper/nested-run tests with deterministic real file read/write/error and concurrent atomic-write behavior checks. Preserve the registered suite entry. No mock counter/echo assertions or sleeps. Use private scratch paths and remove them.
5. Return affected proof identities, if any; do not edit proof files.

# Acceptance predicate
The registered projectstore-actor lane exercises real serialized operations and the project-service consumers retain save/open/catalog behavior: controller runs `deno task verify --filter projectstore --filter swiftcore --verbose`. All assertions pass; no ProjectStore.run caller remains.

# Task-specific constraints
SHARED_TREE. Skip all builds, tests, lint and formatters; controller runs gates after writers settle. No comments, commits, scratch reports, new generic queue or isolation suppression.
