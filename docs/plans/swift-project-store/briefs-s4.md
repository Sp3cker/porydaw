## Task 19: Delete SampleReg + Sidecar dead code

### Context

Sample registration and `.porydaw` sidecar-directory authoring do not cross the Swift seam. `synthDefinitions` never cross the seam (`swift_project_service.cpp:425` always passes `{}`), and the iomutations log carries zero sample rows, so there is no sample payload for Swift to own. The legacy C++ `SampleRegistrar` (`src/project/samplereg.{h,cpp}`) and `Sidecar` (`src/project/sidecar.{h,cpp}`) modules are therefore dead after caller detachment: nothing ports, nothing shims, nothing re-exports. This task performs the atomic four-file deletion plus build-list and proof-file retirement.

### Exact write set

Delete (filesystem removal, exactly these paths, no edits-in-place):

- `src/project/samplereg.h`
- `src/project/samplereg.cpp`
- `src/project/sidecar.h`
- `src/project/sidecar.cpp`
- `src/checks/project/proof.ignore.txt`

Edit (exactly one hunk):

- `CMakeLists.txt`: remove lines 207-210 (`src/project/samplereg.cpp`, `src/project/samplereg.h`, `src/project/sidecar.cpp`, `src/project/sidecar.h`) from the `porydaw_app` source list. No other `CMakeLists.txt` line is touched.

No other file is created, edited, renamed, or moved by this task.

### Prerequisites

- All caller-detachment work has landed: no compiled translation unit under `src/` includes `project/samplereg.h` or `project/sidecar.h`, and no `src/` file references `SampleRegistrar`, `SampleSidecar`, `SampleFormatProbe`, `SampleWavInfo`, or `Sidecar::`.
- The iomutations log has zero sample rows (verified at plan time); there is no sample payload awaiting a Swift port.
- `src/checks/project/ignore.cpp` (the `SidecarIgnoreTest` runner whose 39 assertion sites `proof.ignore.txt` inventories) is already deleted or deleted in the same commit as `proof.ignore.txt`; this task does not leave a proof file pointing at a missing runner or vice versa.

### Interface contract

- This task exports no API and adds no symbols. It removes the entire `SampleRegistrar` class (including `probeSampleFormat`, `sanitizeSampleName`, `validateSampleName`, `inspectSampleWav`, `registerSample`, `updateSample`, `sampleSidecarPath`, `sourceHashHex`, `writeSampleSidecar`, `readSampleSidecar`, `removeSampleSidecar` and the `SampleSidecar` / `SampleFormatProbe` / `SampleWavInfo` structs) and the entire `Sidecar` namespace (`ensureDir`, `dirPath` and gitignore authoring).
- No caller migration happens here. Any remaining `#include "project/samplereg.h"`, `#include "project/sidecar.h"`, `#include "samplereg.h"`, `#include "sidecar.h"`, or `SampleRegistrar` / `Sidecar::` reference under `src/` or `CMakeLists.txt` after this task is a failure of the Prerequisites, not an invitation to re-add a shim. Do not add forwarding headers, aliases, or deprecated paths.
- `plan.md Global Constraints` govern (clean cutover, no shims, MSVC-clean C++ where touched); this brief adds no global rule.

### Implementation steps

1. Delete all four modules together in one commit with the proof retirement: `git rm src/project/samplereg.h src/project/samplereg.cpp src/project/sidecar.h src/project/sidecar.cpp src/checks/project/proof.ignore.txt`. The four-way atomicity is decided: `samplereg.cpp` still compiles with `#include "sidecar.h"`, so deleting `samplereg.*` while keeping `sidecar.*` (or vice versa) is not a valid intermediate state.
2. Remove exactly `CMakeLists.txt` lines 207-210 (the four `src/project/samplereg.*` / `src/project/sidecar.*` entries). Leave lines 205-206 (`swift_project_service.*`) and 211-214 (`voicegroupprojectcontext.*`, `voicegroupsource.*`) byte-identical; do not re-sort or reformat the list.
3. Run the post-deletion grep sweep contract exactly as specified: `grep -rniE 'samplereg|SampleRegistrar|SampleSidecar|SampleFormatProbe|SampleWavInfo|project/sidecar|Sidecar::ensureDir|Sidecar::dirPath' src CMakeLists.txt --include='*.h' --include='*.cpp' --include='*.c' --include='*.txt' --include='CMakeLists.txt'` must return zero hits. Then run the repo-wide sweep `grep -rniE 'samplereg|SampleRegistrar|project/sidecar\.h' .` and accept only the permitted-remaining-hits list in the Acceptance predicate; any other hit is fixed by deleting the referencing dead code, never by restoring the deleted modules.
4. Run `deno task build:app` then `deno task build:checks`, both to green, with no new warnings referencing the deleted files.

### Acceptance predicate

- `src/project/samplereg.h`, `src/project/samplereg.cpp`, `src/project/sidecar.h`, `src/project/sidecar.cpp`, and `src/checks/project/proof.ignore.txt` do not exist on disk.
- `CMakeLists.txt` contains no `samplereg` or `sidecar` token; the diff to HEAD for `CMakeLists.txt` is exactly the four-line removal.
- Scoped sweep `grep` over `src` plus `CMakeLists.txt` returns zero hits.
- Repo-wide sweep returns only the permitted-remaining-hits list, and nothing else:
  - `docs/` historical records (sample-editor `PLAN.md`/`FORMATS.md`/`CONTEXT.md`, `PROJECT_THREAD_MINUTES.md`, `docs/old/project-io-thread-plan.md`, view-sidecar-removal and dress-down docs) that describe the retired design;
  - `docs/plans/swift-project-store/briefs-s4.md` (this brief) and the plan ledger entries recording the deletion;
  - `src/checks/samplecheck/proof.*.txt` and `src/checks/project/proof.*.txt` source-context quotations are NOT permitted to remain if they quote the deleted headers as live includes: any such inventory file owned by an already-retired runner is itself retired with it.
- Builds are green without the deleted translation units.
- NAMED CHECKS:
  - `deno task verify --filter swiftcore --verbose` covers that no remaining Swift-core proof inventory references the deleted `Sidecar::ensureDir` predicates (the retired `proof.ignore.txt` has no orphan consumer).
  - `deno task verify --filter projectstore --verbose` covers that the new Swift checks under `src/checks/projectstore/` build and pass with zero sample-row obligations (iomutations carries no sample rows; nothing ports).

### Task-specific constraints

- All four files delete together: `sidecar.h` is still included by the compiled `samplereg.cpp` (`#include "sidecar.h"`), so a partial deletion (samplereg without sidecar, or sidecar without samplereg) does not compile and is prohibited. The `proof.ignore.txt` retirement joins the same commit because it inventories only `Sidecar::ensureDir` sites with no Swift counterpart.
- iomutations has zero sample rows: the implementer does not port, translate, or preserve any sample-registration or sample-sidecar behavior into Swift. `writeSampleSidecar` / `readSampleSidecar` / `removeSampleSidecar` / `probeSampleFormat` have no Swift equivalent by decision, not by omission.
- For Windows first-party, modulemap, `completeBaseName`, and `registrationGaps`/`synthDefinitions` non-crossing rules, see `plan.md Global Constraints`; no delta in this task.
