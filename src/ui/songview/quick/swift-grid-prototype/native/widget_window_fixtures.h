#pragma once

// Standalone QWidget window fixtures for the Swift/QML song-tab prototype.
//
// Factory over every standalone widget window except Theme: real reusable
// production dialogs where they exist (Settings, Sample Editor, SoundFont
// zone picker, MIDI-import wizard), prototype-only mirrors of the two
// inline source forms (New Voicegroup, Export WAV), and the standard
// Qt windows (progress, file open/save/directory, confirmation, error,
// About). All fixtures are mock-data only: nothing reads a project root,
// writes a file, or saves settings.
//
// The sgw_visual* catalog below is the one definition of that mock data: the
// factory builds every window from it, and the frozen-appearance checks
// (src/checks/visual) pin the same surfaces from the same values instead of
// carrying private copies of the fixtures.
//
// Caller contract (same lifecycle as widget_interop's launches):
// - Call only after the interop host installed the production layout
//   (sgw_installWidgetInteropHost from the root ApplicationWindow's
//   Component.onCompleted). The prototype-only mirror forms use
//   layout::space/fontPx, which require that initialization.
// - Returns a parentless dialog the caller owns (show/open, modality, and
//   the platform transient parent are the bridge's business, as is the
//   single-outcome wiring). The factory itself never shows, opens, execs,
//   or deletes the dialog.
// - Borrowed mock data lives as long as the dialog: value-copied where the
//   production class copies (Settings, Sample Editor, wizard), and held by
//   a child QObject where the production class borrows (Sf2ZonePicker's
//   const Sf2File&).
// - Unknown kind returns nullptr.

enum {
    SgwWindowSettings = 1,
    SgwWindowSampleEditor = 2,
    SgwWindowSf2Picker = 3,
    SgwWindowImportMidi = 4,
    SgwWindowNewVoicegroup = 5,
    SgwWindowExportWav = 6,
    SgwWindowProgress = 7,
    SgwWindowOpenFile = 8,
    SgwWindowSaveFile = 9,
    SgwWindowDirectory = 10,
    SgwWindowConfirmation = 11,
    SgwWindowError = 12,
    SgwWindowAbout = 13
};

#ifdef __cplusplus

#include "audio/sf2reader.h"
#include "core/smf.h"
#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"

#include <QStringList>

// ---- Canonical mock catalog -------------------------------------------------
// Every builder returns a fresh value the caller owns; nothing here reads a
// project root, a file, the environment, or QSettings.

/// Fixed mixer/rate/channel engine settings, so the Settings dialog's engine
/// tab renders identical rows on every run.
EngineSettings sgw_visualEngineSettings();

/// Detached song target for the Settings dialog's song tab.
SongTarget sgw_visualSongTarget();

/// The voicegroup names the song tab and the new-song wizard offer.
QStringList sgw_visualVoicegroups();

/// Players, existing songs, and the voicegroup catalog for the new-song
/// wizard.
NewSongWizard::ProjectData sgw_visualProjectData();

/// Conductor tempo track plus two note tracks, so the import wizard's
/// analysis page renders a real table.
SmfFile sgw_visualImportSmf();

/// Parsed-font stand-in with two instrument groups plus ungrouped zones,
/// backed by a real sample pool. Sf2ZonePicker borrows its font, so a caller
/// that shows the picker must keep the result alive for the dialog's lifetime.
Sf2File sgw_visualSoundFont();

extern "C" QDialog *sgw_createWindowFixture(int kind);
#else
extern void *sgw_createWindowFixture(int kind);
#endif
