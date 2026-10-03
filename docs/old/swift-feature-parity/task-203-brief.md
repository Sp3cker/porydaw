# Task 203 brief — the mounted session and transport lanes pin the already-stopped Stop, song-volume and active-tab residuals

# Context

Three mounted lanes have residual conjuncts that are observable today:

- `selftest_timeline` A020 (`previewWhileStoppedDoesNotStartTransport`,
  fork `workspace/selftest_timeline.cpp:146` at `85b97239`): the fork
  asserts Stop reaches `Stopped` when already stopped, before the stopped
  audition — "this distinct already-stopped Stop scenario is not exercised
  independently" is the only unproved conjunct. The mounted transport
  session lane (`tst_ShellTransportSession.qml`) drives a real Stop on a
  Stopped transport and a preview that must not start playback — a
  user-visible surface predicate, MATCHED.
- `tabs_transport` A062 (fork `workspace/tabs_transport.cpp:327` at
  `02dce75d`): `m_appliedSettings->songVolume` equals the edited song
  volume. The mounted `shell-transport-volume` lane already types a
  master-volume edit through `TransportBarPresenter.setMasterVolume` →
  `NativeAudio.updateSettings(config:)` → `m4a_engine_set_song_volume`
  (`TransportBarPresenter.swift:213–220`, `NativeAudio.swift:86–92`,
  `AudioRenderEngine.swift:176`). The only missing piece is an observable
  applied-song-volume publication on `NativeAudio`; the task adds it if no
  existing surface exposes the applied value, then pins the equality with an
  independent literal — MATCHED.
- `hostintegration` A004 (`twoTabReadySessionWithTwoNoteSeed`, fork
  `tst_hostintegration.cpp:148` at `c17d966f`): `session->active`'s
  selection model holds exactly two notes in a ready two-tab session. S011
  proves the two-note seed on the service layer; the residual is the
  active-tab context. `HostBehaviorChecks.swift` (the file 195 already
  extended) hosts the mounted check: the shell's selected tab's roll owns
  exactly the seeded two-note selection after the real open.

Surface: the mounted shell transport/session lanes and the host behavior
checks.

Ledger spec: `workspace/proof.selftest_timeline.txt` A020;
`workspace/proof.tabs_transport.txt` A062;
`host/proof.tst_hostintegration.txt` A004 — one row each, all closable.

Verify lanes:
`deno task verify:shell --filter shell-transport-session --verbose`,
`--filter shell-transport-volume`, and `deno task verify --filter
swiftcore --verbose` (host checks; or the host checks' existing lane if
they ride a different target — confirm before writing the lane commands).

Blocked rows left untouched: selftest_timeline A006/A009/A011/A014 and
selftest_transport's physical-output/ruled-deviation PARTIALs (Null
backend; cursor-never-seek rulings); session A024/A042 (`swift-project-store`);
hostintegration A087/A091 (WindowDeactivate ingress), A162/A174–A185
(window-close harness); hostadapter A079/A095.

# Exact write set

- `src/checks/editorqml/tst_ShellTransportSession.qml` — the
  already-stopped Stop + stopped-audition predicate (A020).
- `src/checks/editorqml/tst_ShellTransportVolume.qml` — the applied
  song-volume predicate (A062): after the typed master-volume edit the
  engine's applied `songVolume` equals the literal.
- `src/checks/host/HostBehaviorChecks.swift` — the mounted active-tab
  two-note selection predicate (A004).
- `src/swift/app/NativeAudio.swift` — only if the applied song volume is
  not observable through an existing surface: a minimal read-back
  publication (e.g. `renderer`-exposed applied setting), no behavior change.
- The three ledger files — the closed rows only.

# Prerequisites

Read sprint-3 §25 and the three fork sites at their pinned references.
Confirm the mounted volume lane's real input path reaches `setMasterVolume`
(a typed/committed editor value, not a presenter write). Confirm whether
`AudioRenderEngine` already exposes an applied `songVolume` read-back
before adding anything to `NativeAudio` — prefer the existing seam.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; expectations are independent literals (the expected
song volume is a fixture literal, not `presenter.masterVolume` read-back —
the *applied* value must come from the audio surface). Real mounted ingress
only; no test-only APIs; fail-closed staging. If a clause cannot be
observed without a queued-notification race, it stays PARTIAL — do not
paper over it.

# Implementation steps

1. Add the already-stopped Stop predicate to the transport session lane.
2. Add the applied song-volume predicate to the volume lane (plus the
   `NativeAudio` publication if needed).
3. Add the mounted active-tab selection predicate to HostBehaviorChecks.
4. Close the three rows, same commit.

# Acceptance predicate

The mounted lanes execute all three predicates with independent literals;
`proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport-session --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport-volume --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-25 writer of the three ledgers and the three check files (plus
`NativeAudio.swift` if the publication is needed). Do not touch
`tst_ShellTransport.qml` (200's wave-neighbour files are elsewhere but keep
scope tight), `tst_ShellTabs.qml` (204), or any `Shell*Support.qml`.
