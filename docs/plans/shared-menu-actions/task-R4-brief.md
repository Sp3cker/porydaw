# Task R4 — SettingsDialog Tab machine → one song pointer (K-M4)

## Route and seat

**SDD-track**. Reason: deletes a public enum route and rewrites MainWindow call sites plus both consumers; reviewer verifies the fallback semantics survive the bool. Seat: `qt-cpp-reviewer`.

## Context

`SettingsDialog` carries a two-value `Tab` era machine: `Tab`/`currentTab`/`setCurrentTab` (`settingsdialog.h:23-26,36-37`; `settingsdialog.cpp:59-81` including a `Song`-without-song silent Engine fallback pinned at `tst_settingsdialog.cpp:87-93`), the `m_songTab`/`m_songWidget` duality (`:22-26`), and `apply()` that is nothing but `emit applyRequested()` (`:83-86`). MainWindow connects-and-calls the same lambda on Accepted (`mainwindow.cpp` ~1326-1339) via one-line `openSongSettings`/`openEngineSettings` forwards. Signed-off remedy: construct with `bool songFirst`, drop the enum, connect Apply straight to the signal, collapse the MainWindow trio.

## Exact write set

- `src/ui/settingsdialog.h`
- `src/ui/settingsdialog.cpp`
- `src/mainwindow.cpp` (with `src/ui/settingsdialog` consumer read-adjustments in `src/checks/mainwindowrouting/tst_settingsdialog.cpp` as a mechanical exception — the two enum consumers there are exact and enumerable)

Mechanical exception: the check file is a third file only because the deleted enum pins live there and cannot be silently kept.

## Prerequisites

None (independent of R1–R3).

## Interface contract

Constructor becomes `SettingsDialog(engineSettings, song, voicegroupArgs, bool songFirst = false, QWidget *parent = nullptr)` selecting `m_tabs->setCurrentIndex(song && songFirst ? 1 : 0)` — reproducing exactly the old fallback semantics (song present + songFirst → Song tab; otherwise Engine; null song keeps the disabled placeholder). `apply()` is deleted; apply is wired signal-to-signal: `connect(applyButton, &QPushButton::clicked, this, &SettingsDialog::applyRequested)` — the `bool` `clicked` arg is simply dropped by Qt's new-style connect; this is a legal signal-to-signal connection (signed-off) and makes the signal the only public seam (no change to `applyRequested()`'s signature). Callers collapse to `openSettings(bool songFirst)`; callers of `currentTab()/setCurrentTab()` are removed with the enum. Keep m_songWidget as the only song pointer (songCfg() already null-checks it at settingsdialog.cpp:52-57). Spec amendment: replace `spec.md#source-evidence` line "…`src/ui/settingsdialog.{h,cpp}`, `keyboardshortcutsdialog.{h,cpp}`: Keyboard tab and immediate remapping/rollback" with "…: settings dialog entry construction (Keyboard dialog deleted); a songFirst bool selects the shown tab." No change to `spec.md#menu-inventory`'s settings rows — the entries themselves are unchanged.

## Implementation steps ≤5

1. Delete `Tab`, `currentTab()`, `setCurrentTab()`, `m_songTab`, `apply()` from settingsdialog.h; keep `applyRequested` and the two getters.
2. Rebuild the constructor as the signoff remedy above (`songFirst` bool, `setCurrentIndex`, placeholder `QWidget` tab when song absent, disabled when no song). No new `forEngine/forSong` factories needed — the bool matches the signoff's lighter option.
3. Connect apply signal-to-signal; delete `MainWindow::openSongSettings/openEngineSettings` and rewrite the ~1326-1339 accept-AND-connect block to a single connection on Accepted (controller-side note: verify `mainwindow.cpp:1326-1328` lambda is now only connected, not also called, per the signoff correction).
4. Rewrite `unavailableSongTabFallsBackToEngine` in tst_settingsdialog.cpp as "construct with null song → song tab disabled, current index 0" — deleting the index-1 magic digits the old check pinned (also addressing K-m9's stale numeric pin for this surface).
5. Read-only sweep for any remaining `Tab::`/`setCurrentTab`/`currentTab()` consumers (grep across src/ and src/checks/).

## Acceptance predicate

No `SettingsDialog::Tab` symbol survives anywhere; song-present + songFirst opens the Song tab, everything else opens Engine, null-song opens the disabled Engine fallback exactly as before; Apply still emits `applyRequested` exactly once per click through the signal-to-signal connection and the Accepted handler is connected (not additionally invoked). Selected checks: `deno task verify --filter settings-dialog --filter mainwindow-routing-state --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not remove the Apply action itself or change engineSettings()/songCfg() shapes; do not rebuild a three-tab dialog or expose the tab index as a public constant — the null-song fallback is described behavior, not a numeric API.
