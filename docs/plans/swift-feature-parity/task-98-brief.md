# Task 98 brief — transport toolbar volume isolation, raster and key priority

# Context

Own the mounted transport toolbar's empty/loaded state, stable clock geometry,
output dial, song master volume, tab switching and keyboard priority. This is
not transport seeking, task 84's view-state persistence, or a new audio-engine
observation API.

Verified selection: **41 open rows (38 GAP + 3 PARTIAL)** in
`src/checks/workspace/proof.tabs_transport.txt`:
A006–A010, A013, A016–A023, A025–A027, A037–A042, A044, A046, A047,
A050, A053, A054, A056–A058, A060, A063, A065, A066, A068–A070,
A072, A073. **A062 remains open**: the old applied-song-volume engine-settings
observation has no equivalent public readback on `NativeAudio`; do not add a
test-only getter or claim the cfg value proves the engine's applied setting.

Oracle: `fceecd88:src/checks/workspace/tabs_transport.cpp`. Current owners:
`TransportBarPresenter.refresh/restoreOutputVolume/commitOutputVolume/
setOutputVolume/setMasterVolume`, `TransportBar.qml`,
`TransportOutputDial.qml`, and `runTransportBarChecks`. The current output
volume observation is real `NativeAudio.outputVolume`. The existing
`tst_ShellTransport.qml` already covers dial interaction, preference relaunch,
visual profiles, scale state and Space priority; extend those journeys.

# Exact write set

- `src/swift/app/transport/TransportBarPresenter.swift` — conditional selected toolbar repair.
- `src/ui/shell/TransportBar.qml` — conditional geometry/field repair.
- `src/ui/shell/TransportOutputDial.qml` — conditional dial/input repair.
- `src/checks/workspace/transport_checks.swift`
- `src/checks/editorqml/tst_ShellTransport.qml`
- `src/checks/workspace/proof.tabs_transport.txt` — selected 41 rows only.

No ApplicationSession, NativeAudio, audio renderer, ShellWindow, fixture
content, shared settings implementation or registration changes. The existing
real ApplicationSession/audio fixture and production PreferencesStore are
sufficient for selected output-volume observations.

# Prerequisites

Start after accepted Group A checkpoint and all 84/86/87/89 land. Rebase reads
of 84's `ApplicationSession.swift`/`DocumentWorkspace.swift`, 86's
`EditorSurface.qml` focus ingress, 87's window shortcut priorities and 89's
`DocumentSession.swift` bank/lifetime behavior. Preserve prior transport
ruler-seek regressions and task 42's scale controls; no other Group B task
writes this toolbar or its checks.

# Interface contract

- Keep the presenter's public methods and QML component interfaces. With no
  song, scale root/type/highlight/fold are disabled and the visible combined
  time readout is `0:00.0 / 0:00.0`. Reserve clock width from base-font metrics;
  changing current/total text does not move the adjacent toolbar geometry.
- The output dial paints endpoint ticks at 240° and −60°, with no tick at
  270°. Actual visible order is expanding spacer, Volume caption, song-volume
  field, Output caption, final dial. Prove expanding behavior across width
  changes rather than inspecting a deleted QWidget QSizePolicy.
- The loaded song-volume field is enabled and reflects that song's cfg.
  Output range is 0..100. Restored output 37 reaches both presenter and real
  NativeAudio. Output edits, including stationary click and the edit to 42,
  do not change song master volume, undo count or clean state; 42 reaches
  the real audio output and the persisted preference.
- Song master-volume editing updates that song and creates undoable history.
  Switching tabs displays the new song's own value, retains global output 37
  in the relevant fork journey and leaves the second song clean. Returning
  and undoing restores the first song's cfg, field value and clean state.
  Keep the separate 37-restored and 42-edited journeys independent.
- Numeric-field digits are consumed locally; bare Space still reaches the
  window transport command. Non-text scale chrome never captures bare Space.
  Test physical key effects, not QKeyEvent acceptance or Qt focus-policy enums.
- Planned dispositions: **29 MATCHED, 12 RETIRED-REPRESENTATION**. Retire only
  A007–A010 (QWidget NoFocus policy) and A016–A023 (QLabel/QWidget size-hint
  plumbing), with mounted priority and stable-font-sized geometry proof in
  this same task. Dial pixels, control order, volume, dirty/history and key
  outcomes are behavioral and must not be retired.

# Implementation steps

1. Extend `runTransportBarChecks` through the existing real app/audio fixture,
   with distinct anchors for preference→presenter→audio output, song cfg,
   undo count/index and clean state at each selected transition.
2. Stage and restore preference values with `PreferencesStore` backed by
   CFPreferences/UserDefaults and synchronize the domain. Never poison or
   compare persisted state by writing/reading a plist file: cached preferences
   are authoritative. Isolate the test domain and restore its original state.
3. Extend the mounted toolbar journeys with actual dial/field/tab/key input,
   image-sampled dial ticks and resized toolbar/clock geometry. Use existing
   visual profiles and real staged songs; do not alter checked-in fixture data.
4. Repair only demonstrated selected-law mismatch. **RED may be absent if
   production already matches; then the check is the deliverable.** Preserve
   existing messages and attach fresh evidence to only the 41 selected rows.

# Acceptance predicate

Controller-run after Group B settles. `runTransportBarChecks` is registered in
`swiftcore-projectsession`; `shell-transport` proves real toolbar painting,
interaction, focus priority and tab switching. Both are required.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Each process is capped at 180 s using the 175 s alarm after serialized lock
acquisition. Require fresh `build/proof-evidence/swiftcore-projectsession.json`
and `shell-transport.json`. Full shell means all 26 lanes (~40 s warm); full
verify (~10 s warm) is mandatory. No audible-output or physical-macOS-host
claim follows from null-backend/offscreen checks. A062 and the separate
`selftest_transport` seek/cursor rows remain unchanged.

# Task-specific constraints

Apply sprint-3 §10: no new C++; Swift 6.4 on touched Swift; comments ≤2 lines;
base-font sizing; WCAG AA beats pixel parity. Preserve one keyboard authority:
no second dispatcher, synthetic forwarding or focus memory; chrome never
claims bare Space. Ban `Qt.callLater` coalescing and new idempotence guards.
One message-anchored predicate per fork clause, existing messages verbatim,
real fixtures, no test-only seams. Settings are CFPreferences/UserDefaults-
backed, never plist-byte state. No fixture edits; any approved expansion must
first list every check asserting exact fixture contents. Workarounds need
user approval. Parked areas, deferred menus and savecore A016–A026 stay out.
