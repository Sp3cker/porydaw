# projio-bench — startup project-IO benchmark

Isolated worktree answering: does all project IO need a dedicated executor,
or is the `ProjectStore`/`ProjectService` actor sufficient?

## What it does

Emulates application load through the first song-tab request, executing the
real project-layer Swift sources **unmodified** (same files, same order as
the app) and timing each stage on the calling thread — the same placement as
the actor's cooperative-pool executor today:

| Stage | App code |
|---|---|
| `open` | `ProjectStore.open` + midi.cfg/songs.mk + budgets |
| `listing` | `ProjectService.songs` via `SongRegistration.statuses` |
| `catalog` | `ProjectService.voicegroupCatalog` file-IO core |
| `songTab` | `DocumentSession.open` minus the native bank load (MIDI read + `VoicegroupSource.open` + `MidiFile.decode` + `SongDocument` init) |

A 1 ms heartbeat task runs alongside each stage and reports max overshoot —
a direct probe of cooperative-pool stall while the actor thread is blocked.

## What it excludes, and why

`ProjectContext.open` / `context.load` (native loader): their file IO
already runs off-pool by construction — dedicated `ContextWorker` thread plus
up to 4 private file-read threads (`ProjectContext.swift:88`,
`FileIo.swift:58-71`). The actor thread only parks on the worker latch.
UI presenters / QML / audio: no file IO.

## Run
```sh
tools/projio-bench/build.sh
tools/projio-bench/.build/projio-bench [--songs 450] [--voicegroup-files 64]
  [--project /path/to/real/decomp] [--song mus_label] [--runs 6] [--regen]
```

The build retains `-O` optimization, adds `-g` debug information, and on macOS
generates `.build/projio-bench.dSYM` beside the executable. Record with the newly built
executable; its dSYM must have the same UUID. If Instruments does not locate
symbols automatically, add that bundle through its Symbols interface.

The synthetic fixture lives in a stable tmp dir and is generated once, then
only read (regenerated on `--regen` or scale change), so runs measure reads
without rewrite I/O. True cold-disk numbers need a cache drop between runs.

`--project` measures a real decomp checkout (best fidelity); otherwise a
synthetic project is generated in tmp. `NativeStub.swift` backs one
unexecuted type (`BankHandle`); `build.sh` fails the build if any measured
source references it.

## Catalog discovery optimization

`SongCatalog.load` filters registered MIDI labels before sorting discovered
files and extracts candidate filenames once instead of in every comparison.
Known MIDI paths use explicit file intent when appending their URL component;
the separate existence check remains. Filename ordering still uses Swift
string comparison, including Unicode semantics.

Compare optimized and baseline binaries with the same `--project` fixture
and `--runs` count, excluding run 0 from warm measurements. Include both an
all-registered fixture and one with unregistered MIDI files. This change
affects the `open` stage; `catalog` measures voicegroup discovery, not
`SongCatalog.load`. Reduced function counts alone are not a speedup result.

Local optimized-build comparison against `05281554`, using five alternating
before/after batches of 50 runs per fixture (median of warm batch medians):

| Fixture | Open before / after | Total before / after |
|---|---|---|
| 450 registered songs, 64 voicegroup files | 12.13 / 4.28 ms | 18.77 / 10.88 ms |
| Same base, plus 200 numbered unregistered MIDI files and additional filename/file-eligibility edge cases | 14.56 / 6.23 ms | 21.50 / 12.82 ms |

Complete catalog values matched before/after for both fixtures; the mixed
fixture included missing registered MIDI, Unicode-equivalent labels,
hidden files, uppercase suffixes, directories, and valid/broken symlinks.
These are warm synthetic-project results, not full application startup times.

## Voicegroup parsing optimization

`CatalogLines.voiceFields` validates field count and extracts the symbol and
envelope in one traversal instead of counting commas in a separate pass.
Macro matching checks the shared `voice_` prefix once and rejects unrelated
macro families by their next byte before comparing full macro names. Existing
macro precedence, spacing, numeric overflow, and malformed-input behavior stay
unchanged.

Compared with the catalog-optimized `-O -g` binary immediately before this
parser change, five alternating batches of 50 runs gave:

| Fixture | Voicegroup stage before / after | Total before / after |
|---|---|---|
| 450 songs, 64 voicegroup files | 4.74 / 4.47 ms | 11.01 / 10.68 ms |
| Same base plus 5,000 randomized valid/malformed assembly lines | 6.11 / 5.73 ms | 12.39 / 12.15 ms |

Values are medians of warm batch medians. All voicegroup datasets matched,
including sorted per-family and per-symbol ADSR maps; the existing
`projectstore-synthcatalog` harness passed. These modest gains do not establish
that replacing the file-reading API would improve performance.

## Load-scoped directory cache

`ProjectDirectoryCache` owns one visible-entry listing, cached file metadata,
and native filenames for a single catalog load. Registered MIDI lookup and
unregistered discovery reuse that listing. Only byte-exact non-symlink file
or directory hits supply cached existence evidence. Misses, aliases,
symlinks, and unavailable metadata retain filesystem lookup; enumeration
failure also leaves lookup to the filesystem. No cache survives a reload.

Compared with the parser-optimized binary, five alternating batches of 50
runs gave these medians of warm batch medians:

| Fixture | Open before / after | Total before / after |
|---|---|---|
| 450 registered songs, 64 voicegroup files | 4.30 / 3.77 ms | 10.54 / 9.97 ms |
| Same base, 200 unregistered MIDI files plus lookup/eligibility edge cases | 6.02 / 4.57 ms | 12.26 / 10.83 ms |

Complete catalog values matched both fixtures and a permission-limited
directory. The `projectstore-catalog` harness covers case aliases, directories,
valid/broken links, and external changes observed on reload; both that harness
and `projectstore-synthcatalog` passed.

Integration into `swift-qml-grid` retains that branch's byte-based song-table
parser. Single 50-run smoke batches measured open/total medians of 2.94/9.23 ms
for the standard fixture and 3.62/9.84 ms for the mixed fixture. These are not
a paired comparison. The complete catalog suite also passed in a standalone
runner against the merged Swift modules.
