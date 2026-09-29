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

The synthetic fixture lives in a stable tmp dir and is generated once, then
only read (regenerated on `--regen` or scale change), so runs measure reads
without rewrite I/O. True cold-disk numbers need a cache drop between runs.

`--project` measures a real decomp checkout (best fidelity); otherwise a
synthetic project is generated in tmp. `NativeStub.swift` backs one
unexecuted type (`BankHandle`); `build.sh` fails the build if any measured
source references it.
