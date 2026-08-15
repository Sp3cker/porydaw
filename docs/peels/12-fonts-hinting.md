# Peel 12 — Font rendering & system-font toggle fixes (⚠ PARTLY BLOCKED ON USER INPUT)

Read `docs/peels/GROUND-RULES.md` first. Source: branch commit `8c1972f`
("fix(font): update bundled Atkinson faces"). Fully independent of the drawer.
The commit bundles FOUR unrelated changes — evaluate each separately and commit
separately. Two need user/author input before landing.

## 12a — Hinting policy change (land it; the actual fix)

`src/ui/typography.cpp` (branch `:30-31`, `:149-150`): `PreferFullHinting` →
`PreferNoHinting`, plus `styleStrategy |= QFont::PreferAntialias`, in BOTH
`setFace()` and `bodyMono()`. This re-renders all UI text unhinted/antialiased —
most visible on Windows at 100% scale (the branch's fontcheck comment says
"gasp 10, DirectWrite"). `src/fontcheck.cpp` asserts the strategy — update the
assertions in the same commit and negative-test them. Flag for the user's
Windows feel-check (the WSL/offscreen harness can't judge glyph rendering).

## 12b — System-font toggle repaint fix (land it)

Branch `mainwindow.cpp:100-112` + `:791-801`: the View → Use System Font toggle
stops calling `ThemeController::reapply()` (deleted on the branch — main still
has it) and instead calls `QApplication::setFont()` followed by
`resetInheritedWidgetFonts()` — walking `QApplication::allWidgets()` and
re-asserting inheritance on widgets with an empty font resolve mask. Stated
reason: repolishing the stylesheet is unsafe while playback is painting on
Windows (crash/repaint hazard). Port it; keep `reapply()` only if something else
on main still calls it (check; if dead, delete it). Verify against main's
startup-font machinery (the qt6ct font-freeze and typography reassert order are
load-bearing — see the Use System Font implementation d152c1d and the apply()
ordering; run the font-related checks and the system-font toggle path offscreen).

## 12c — Regenerated font binaries (ASK BEFORE LANDING)

The branch replaces `AtkinsonHyperlegibleNext-Regular.ttf`, `-SemiBold.ttf`, and
`AtkinsonHyperlegibleMono-Regular.ttf` with files of IDENTICAL byte length but
~91% differing content, with no provenance note. Do not land binaries of unknown
origin. Ask the user to get provenance from the branch author (new upstream
release? re-subset? which tool?). If provenance arrives, land with the source
recorded in the commit message; verify fontcheck + themecheck + the piano-roll
label fitting probes (label metrics may shift) at SF 1/1.5/2.

## 12d — Unused Light face (recommend: skip)

Branch adds `AtkinsonHyperlegibleNext-Light.ttf` (61 KB), registers it in
`fonts.qrc`, loads it in `typography.cpp` and adds it to the load-failure gate —
but NOTHING selects a Light weight anywhere on the branch. Dead weight plus a new
failure mode. Skip unless the user says a Light-weight consumer is planned
(possibly by the velocity axis in some later design); record the decision here.

## Tests

- fontcheck assertions updated + negative-tested (12a); a check that the
  system-font toggle round-trips while the engine is playing offscreen without
  font drift (12b — extend the harness that covers d152c1d if present);
  full ASAN sweep + ctest. CHANGELOG entries for 12a/12b (user-visible).
- Windows visual confirmation owed for 12a (user).
