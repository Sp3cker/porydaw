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
class QDialog;
extern "C" QDialog *sgw_createWindowFixture(int kind);
#else
extern void *sgw_createWindowFixture(int kind);
#endif
