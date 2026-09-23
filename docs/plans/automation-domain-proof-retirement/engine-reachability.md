# Automation domain engine reachability after check retirement

This report records the pre-cleanup proof tally. The 62-site
`proof.xcmd.txt` ledger was subsequently retired after all sites were
`MATCHED` and its Swift predicates passed; recover it from Git revision
`4c52acd8c1193d27167c301002c67f18165938b8`.

## Retired check family

Before deleting `src/checks/automation/domain/tst_automationdomain.h`, the scoped harness search

```text
grep pattern="#include\\s*[\"<](?:.*\\/)?tst_automationdomain\\.h[\">]" path="src/"
No matches found.
```

found no remaining includers after `gestures.cpp` and `xcmd.cpp` were retired. C++ LSP `references` for `runAutomationDomainCheck` found only its declaration at `tst_automationdomain.h:89`. The now-orphaned header was deleted; no CMake target changed.

`deno task proof list --area automation/domain` after deleting `xcmd.cpp` reported:

```text
proof.gestures.txt                 MATCHED 66, RETIRED-REPRESENTATION 1, PARTIAL 0, GAP 0
proof.tst_automationdomain.txt     MATCHED 106, RETIRED-REPRESENTATION 1, PARTIAL 0, GAP 0
proof.xcmd.txt                    MATCHED 62, PARTIAL 0, GAP 0, NATIVE 0
```

## Target audit

`glob path="CMakeLists.txt;src/**/CMakeLists.txt"` found five manifests: root, `src/checks`, and `src/swift/{core,app,playback}`. A scoped harness search for `xcmd|nodelane|cclanes|songdocument|gestures|automationdomain` in all five found **no legacy C++ `xcmd`, `nodelane`, `cclanes`, `songdocument`, `gestures`, or `automationdomain` `.cpp`/`.h` target entries**. It did find active Swift entries, which must not be mistaken for legacy C++ targets:

```text
src/checks/CMakeLists.txt:118-120   editcheck/tst_songdocument_{songraw,runner,songranges}.swift
src/checks/CMakeLists.txt:158-161   automation/domain/{tst_automationdomain,gestures,xcmd,xcmdRanges}.swift
src/swift/core/CMakeLists.txt:7,13 SongDocument.swift; Xcmd.swift
```

The exact search also found other `editcheck/tst_songdocument_*.swift` entries. Thus the old engine/check sources still exist where noted below but are **not built by the current CMake targets**; the Swift counterparts are built and registered. No check original or engine source was silently reintroduced into a target.

## Dormant native blocker chain; no engine deletion

Fresh `#include` search scoped to `src/core;src/ui/editordrawer` identified `core/xcmd.h` consumers at `src/core/songdocument.h:19`, `src/core/midiimport.cpp:11`, `src/core/xcmd.cpp:1`, and `src/ui/editordrawer/cclanes.cpp:10`. Inside the dormant UI family, `automationprojection.{cpp,h}`, `automationviewmodel.cpp`, `cclanes.h`, `tempolane.h`, and `nodelane/{batchcommit.h,gesture.h,hover.{cpp,h},nodelane.cpp,pencilgesture.h}` include `nodelane.h` or `cclanes.h`. These are source-level dependencies even though their legacy C++ implementation is not in a current target. Removing `xcmd`, song-document, CC-lane, or node-lane engine files requires a separate dependency/reachability decision; this plan deletes none of them. The editcheck retirement plan §8 records the same song-document dependency boundary.

The registered native and QML lanes outside this uncompiled domain family remain necessary and untouched: `src/checks/CMakeLists.txt:32-75` retains native checks, `:103-226` builds `swift_core_check` and its QtTest bridge, and `:255-340` defines the separate Swift-hosted editor QML test lane. `src/checks/checkcatalog.cpp:112-115,154-169` retains the scale check, Swift core, and Quick/selection checks. This report is not an argument to retire any of those checks or their production code.
