# Task 171 brief — New Song creates from the current song and refuses MIDI collisions

# Context

`file.new_song` is a registered window command (`src/swift/app/commands/
KeybindingRegistry.swift:108`, "New Song", standard: .new) with no handler anywhere —
a user pressing the registered shortcut gets no response, where the fork created a
song. The fork's creation contract also includes collision refusal: creating a song
whose MIDI path already holds foreign bytes refuses with a nonempty failure, preserves
those bytes exactly, and leaves no stray output. The Songs dock, its confirmation
dialog machinery and the project song service all exist to carry this surface.

Surface: the New Song command on the shell window (registered keybinding/menu action)
and the Songs dock — prompt, creation from the current song, collision refusal.
Ledger spec: `src/checks/project/proof.iomutations.txt` A077–A087 (11 GAP), fork
`ProjectIoMutationsTest::creationCollisionRefusesLeavingStray`
(`src/checks/project/iomutations.cpp:476,481,490,492,499,501,503,505,507-509` at the
ledger's pinned revision): `CreateSongInput` from the open song's constant/player/cfg
and MIDI; a pre-existing stray MIDI at the target path yields a `CommandFailure` with
a nonempty message; the stray bytes are preserved byte-exactly; the stray file is
removed only when it was test-owned; no stray output remains.
Verify lanes: `deno task verify --filter projectstore-songsmk --verbose` family for
the service predicates and `deno task verify:shell --filter shell-songs --verbose`
for the mounted prompt journey.
Blocked rows left untouched: iomutations A073–A076 (private preview-cleanup result
contract) and A088+ (closed-worker shutdown); the New Voicegroup creation surfaces
remain user-excluded.

# Exact write set

- `src/swift/app/ProjectService+Songs.swift` — `createSong(label:from:)` with collision refusal and its error surface only.
- `src/swift/app/songlist/SongDockController.swift` — the New Song prompt request/accept/cancel flow, reusing the existing confirmation-dialog pattern.
- `src/ui/songview/quick/docks/SongConfirmDialog.qml` or the dock's existing prompt file — the name-entry variant only, conditional extension (no new QML files).
- `src/swift/app/shell/ShellPresenter.swift` — wiring the registered `file.new_song` command to the dock flow (action table entry + handler only).
- `src/checks/songlist/SongRegistrationChecks.swift` — service-level creation and collision-refusal predicates (stray-bytes preservation with independent literals).
- `src/checks/editorqml/tst_ShellSongs.qml` — mounted keybinding → prompt → create journey and the refusal journey.
- `src/checks/project/proof.iomutations.txt` — A077–A087 only.

# Prerequisites

None in-wave. Disjoint from 167/168 and every forbidden file (no GridScene/PianoGrid/
swiftroll rendering, no CMakeLists, no ShellQmlEntries — all hosts exist). Read
sprint-3 §20.

# Interface contract

Creation copies the current song's MIDI/constant/player/cfg into the new label's MIDI
path and registers it, then the song is openable from the dock. A collision (any
existing bytes at the target MIDI path, not just registered songs) refuses with a
nonempty error naming the label, changes nothing on disk, and leaves the dock/tab
state untouched. The prompt validates the label through the production song-name
rules before enabling acceptance. No bytes are compared against themselves: the stray
fixture uses independent literal bytes.

# Implementation steps

1. Implement the service creation with fail-closed collision checks (stat/read before
   any write; refusal path writes nothing).
2. Wire the command through the presenter action table to the dock prompt.
3. Service predicates: creation success (openable, correct metadata), collision
   refusal (message nonempty, stray bytes identical, no new files), per the fork
   clauses.
4. Mounted journey: keybinding opens the prompt, real input names the song, acceptance
   creates and selects it; the refusal leg stages stray bytes first.
5. Close A077–A087 in the same commit. Compact form for closed rows: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

The registered New Song shortcut works end-to-end and a MIDI collision refuses while
preserving the existing bytes — the fork's creation contract on the Swift surface.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectstore-songsmk --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
deno task proof check --executed
```

# Task-specific constraints

Scope flag for the controller: this builds the missing creation flow (the sprint's
existing-surface parity pattern — the registered command is the surface); if the
user prefers to defer new-feature scope, drop this brief before dispatch. No new
files, no registration/manifest edits, no project-store C++ changes; the prompt
reuses existing dialog machinery. Sibling ledgers and files stay untouched.
