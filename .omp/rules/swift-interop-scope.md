---
description: C++ interop, exported module chains and by-value C aggregates are Porydaw's largest Swift compile costs
condition: "porydaw_swift_qt_interop|cxx-interoperability-mode|@_exported\\s+import|import\\s+(PorydawApp|PorydawAppPresentation|PorydawAppHistory|PorydawAppCommands|QtBridge)\\b|LoadedVoiceGroup"
scope: "tool:edit(CMakeLists.txt, **/CMakeLists.txt, src/checks/**/*.swift), tool:write(CMakeLists.txt, **/CMakeLists.txt, src/checks/**/*.swift)"
interruptMode: never
---
Module structure, not expression shape, dominated this repo's Swift compile time.

- C++ interop is the tax: 109 of 116 over-budget files were in interop modules; the slowest expression in an interop-free module took 10 ms. Lazy Clang imports bill 20–600 ms to arbitrary expressions and bodies. Dropping unused interop from `PorydawAppAudio` cut its compile 760 → 360 ms.
- Interop is contagious: `porydaw_swift_qt_interop` options are PUBLIC, so importing PorydawApp, PorydawAppPresentation, PorydawAppHistory, PorydawAppCommands or QtBridge makes the importer an interop module. Enable interop only for modules that call Qt/C++ APIs; C headers need only a module map.
- Core checks: a check needing no app/QtBridge type goes in `swift_core_check_logic` (interop-free, builds beside the app); shared fixtures go in `swift_core_check_support`; only app-facing checks go in `swift_core_check`.
- No chains of `@_exported` modules: six chained check lanes built serially (12 s); flat interop-free modules cut a PorydawCore API edit's check build 27.9 → 19 s. Use `@_exported` only as a module-wide import of a stable lower module.
- Never copy a large imported C struct by value (`let bank = pointer.pointee`): one `LoadedVoiceGroup` copy cost 57 s in the SendNonSendable SIL pass. Read fields through the pointer.
- Judge a structure change by `deno task build:checks` wall time for a declaration edit, not by per-file attribution.
