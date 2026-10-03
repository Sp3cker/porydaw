# Brief 08 — Delete the unused context-property seam

## Context

Finding H (audit §2), callers re-verified to zero: the Qt 6-discouraged
`rootContext()->setContextProperty` path survives as a Swift wrapper around
a C ABI that nothing calls — one more C/C++ boundary every agent must reason
about (owner's economics #2). Production reaches QML through registered QML
elements and property injection (spec Q3); spec forbids reintroducing
context properties.

## Exact write set

- `/src/swift/app/QmlEngineAccess.swift`
- `/src/app/qml_engine_host.h`
- `/src/app/qml_engine_host.cpp`

No `src/checks/**` write; no proof ledger mentions these symbols (verified
sweep — only historical comments in `src/checks/rollqml/tst_SwiftRoll.qml:61`
and `tst_SwiftRollWindowing.qml:58`, which are out of the write set and stay).

## Prerequisites

02. Parallel with 05/06/07 (disjoint files).

## Interface contract — deletions

| What | Site |
|---|---|
| `QmlEngineAccess.setContextProperty(_:_:)` (whole method) | `QmlEngineAccess.swift:16-18` |
| `pd_qml_set_context_property` declaration | `qml_engine_host.h:11` |
| `pd_qml_set_context_property` definition | `qml_engine_host.cpp:21-28` |

STAY unchanged: `pd_qml_engine()`, `pd_qml_module_prefix()`
(`qml_engine_host.cpp:9-12` — load-bearing: `QmlEngineAccess.swift:8-10`,
contentUrls), `pd_qml_add_import_path`, and `QmlEngineAccess.isAvailable` /
`addImportPath` / `moduleResourcePrefix`.

## Implementation steps

1. `lsp references` both Swift and C symbols (the C header is consumed via
   the Swift C-interop umbrella; text sweep for `pd_qml_set_context_property`
   across `src/` too). Expected: exactly the wrapper↔ABI pair.
2. Delete the three declarations.
3. If the definition was the only user of an include or the `[[nodiscard]]`
   helper chain in `qml_engine_host.cpp`, drop the now-unused includes;
   touch nothing else.
4. Local inspection: diagnostics on the Swift file; read the final C++ file
   top-to-bottom once.

Edge cases: if any reference appears outside the pair (e.g. a check binary
declares it), stop and report `NEEDS_CONTEXT` — do not delete a live ABI.

## Acceptance predicate

NAMED CHECKS (controller): `deno task build:app` green (app links without
the seam); `deno task build:checks` green; `deno task format:check` green
(clang-format covers `src/app/*.{h,cpp}`); `deno task verify:shell
--verbose` green (production shell smoke — the app must mount QML exactly
as before, proving nothing depended on the seam).

## Task-specific constraints

- Deletion only: no replacement registration mechanism, no new C++.
- The historical `setContextProperty` comments in `src/checks/rollqml/`
  test files are out of scope here (a later touching brief owns them).
