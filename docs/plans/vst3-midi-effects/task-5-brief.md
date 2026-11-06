# Context
Vendor the VST3 SDK source subset into `external/vst3sdk/`, following the `external/dr_libs` and `external/stb` convention, and compile it as a static target. Record the new native boundary in AGENTS.md only after G1 approval. Task 6 links the SDK into the helper and checks; task 13 adds the bridge. Read plan.md Global Constraints.

# Exact write set
- external/vst3sdk/ (new vendored copy, see contract)
- CMakeLists.txt (root): `add_subdirectory(src/pluginhost)`; license resource on the `porydaw` target
- src/pluginhost/CMakeLists.txt (new): target `porydaw_vst3_sdk`
- docs/BUILDING.md: a "Vendored VST3 SDK" section
- AGENTS.md: the G1 amendment only, verbatim from plan.md

Over-cap exception: one dependency behavior, "the SDK builds everywhere from in-tree sources".

# Prerequisites
Gate G1 approved by the user.

# Interface contract
- Exactly plan.md "Gates" G1. Apply this AGENTS.md "Native boundary" amendment verbatim:
  > C/C++ exists only at: `src/app/`, `src/audio/`, `src/project/`, `src/pluginhost/`, `src/ui/songview/quick/swiftroll/native/font_metrics.cpp`, and the display-list boundary in `src/render/` … `src/pluginhost/` builds `porydaw-vst3-host`, the helper executable that scans and hosts every VST3 plugin in its own process, and `pluginbridge.h`, the C wire format (shared-memory layout, control frames, cross-process wait/wake) that Swift imports. Porydaw's process never loads a plugin module. Steinberg SDK types, plugin threads, editor windows and editor key interception stay inside the helper. Native code never decides scan policy, capture pacing, crash or hang policy, which keys Porydaw owns, or which events reach the document.
  It also adds `src/swift/pluginhost/` (PorydawPluginHost: Core + Playback + PorydawPluginBridge) to the project map and module rules.
- **Vendored tree.** Taken from `steinbergmedia/vst3sdk` tag `v3.8.1_build_84` with its recorded `base`, `pluginterfaces` and `public.sdk` submodule commits, copied byte-identical:
  - `external/vst3sdk/base/{source,thread}/`;
  - `external/vst3sdk/pluginterfaces/{base,gui,vst}/`;
  - `external/vst3sdk/public.sdk/source/{common,main,vst}/`, excluding every `samples`, `testsuite` or `test*` directory;
  - `external/vst3sdk/public.sdk/LICENSE.txt`.
- **`external/vst3sdk/VERSION`.** Records the tag, the three upstream commit SHAs, and the exact directory list above.
- **`porydaw_vst3_sdk`.** A static C++17 target with an explicit source list mirroring `cmake/modules/SMTG_VST3_SDK.cmake` of that tag:
  - `base/source/{baseiids,fbuffer,fdebug,fdynlib,fobject,fstreamer,fstring,timer,updatehandler}.cpp`
  - `base/thread/source/{fcondition,flock}.cpp`
  - `pluginterfaces/base/{conststringtable,coreiids,funknown,ustring}.cpp`
  - `public.sdk/source/vst/hosting/{connectionproxy,eventlist,hostclasses,module,parameterchanges,processdata,plugprovider}.cpp`
  - `public.sdk/source/vst/vstinitiids.cpp`
  - `public.sdk/source/common/memorystream.cpp`, `public.sdk/source/vst/utility/stringconvert.cpp`
  - any further `.cpp` that the tag's `smtg_create_public_sdk_hosting_target` compiles and these sources reference at link time, each named with a comment citing that macro
  - exactly one of `module_mac.mm`, `module_win32.cpp` or `module_linux.cpp`

  Include directory `external/vst3sdk`, PUBLIC only to `src/pluginhost` targets, never to Swift module maps. Link the SDK only into the helper and checks, never Porydaw's process. `NDEBUG`/`RELEASE` defines as the SDK expects per build type. No VSTGUI, no SDK CMake, no project warning flags on vendored sources.
- **License resource.** `external/vst3sdk/public.sdk/LICENSE.txt` is added through the `porydaw` target's existing bundle-resource mechanism (as shell QML and fonts are) as `VST3-SDK-LICENSE.txt` on macOS. On Windows and Linux a `POST_BUILD` copy places it beside the executable, and the existing deploy steps carry it.

# Implementation steps
1. Copy the subset from a clean checkout of the tag. Write `VERSION`.
2. Add the SDK target, the root subdirectory and the license resource for each platform.
3. Document the subset, the pin, the update procedure (re-copy from a new tag, update `VERSION`, re-check the source list against the hosting macro) and the license in docs/BUILDING.md.
4. Apply the G1 AGENTS.md text verbatim.

# Acceptance predicate
A fresh configure builds `porydaw_vst3_sdk` on macOS, and the license file is present in the built app bundle. NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev format --check`

# Controller verification
Confirm `build/debug/porydaw.app/Contents/Resources/VST3-SDK-LICENSE.txt` exists. Windows MSVC and Linux compile coverage comes from CI `build.yml` on push.

# Task-specific constraints
- No edits to vendored files after copying.
- No submodules and no `tools/porydaw_dev` changes.
- `.github/workflows` edits only if CI fails to compile the SDK.
