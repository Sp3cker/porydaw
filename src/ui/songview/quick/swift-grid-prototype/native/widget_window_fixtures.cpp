// Fixture factory for every standalone QWidget window except Theme.
//
// Mock data is in-memory only: a deterministic EngineSettings/SongTarget,
// a synthesized ImportedSample waveform, a synthetic Sf2File pool + zones,
// and a small deterministic SmfFile. Nothing here reads a project root,
// writes a file, touches QSettings, or shows/opens/execs anything.
//
// The New Voicegroup and Export WAV kinds are prototype-only mirrors of the
// inline source forms at src/ui/workspaceui_project.cpp:617 and
// src/mainwindow.cpp:1199 — deliberately not extracted production code.

#include "widget_window_fixtures.h"

#include <QComboBox>
#include <QDialogButtonBox>
#include <QDoubleSpinBox>
#include <QFileDialog>
#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QProgressDialog>
#include <QRegularExpressionValidator>
#include <QSpinBox>
#include <QVBoxLayout>

#include <cmath>
#include <optional>

#include "audio/sampledata.h"
#include "audio/sf2reader.h"
#include "core/smf.h"
#include "ui/layout.h"
#include "ui/newsongwizard.h"
#include "ui/sampleeditordialog.h"
#include "ui/settingsdialog.h"
#include "ui/sf2zonepicker.h"

namespace {

// ---- Shared mock catalog ----------------------------------------------------

EngineSettings fixtureEngineSettings()
{
    // Mirrors the deterministic check fixtures (tst_settingsdialog,
    // visual/dialogs): fixed mixer/rate/channels so every run matches.
    EngineSettings settings;
    settings.pcmMixer = M4A_PCM_MIXER_SAPPY;
    settings.maxPcmChannels = 8;
    settings.pcmMixRate = 13379.0f;
    settings.analogFilter = false;
    return settings;
}

SongTarget fixtureSongTarget()
{
    SongCfg cfg;
    cfg.voicegroupArg = QStringLiteral("_abandoned_ship");
    cfg.masterVolume = 110;
    cfg.reverb = 50;
    cfg.priority = 0;
    cfg.exactGate = true;
    return {cfg, QStringLiteral("mus_route101")};
}

QStringList fixtureVoicegroups()
{
    return {QStringLiteral("_abandoned_ship"), QStringLiteral("_route101")};
}

NewSongWizard::ProjectData fixtureProjectData()
{
    NewSongWizard::ProjectData data;
    data.players.append({QStringLiteral("MUSIC_PLAYER_BGM"), 0, -1});
    data.players.append({QStringLiteral("MUSIC_PLAYER_SE"), 1, 1});
    data.voicegroupArgs = fixtureVoicegroups();
    data.canCreateVoicegroup = true;
    SongInfo existing;
    existing.id = 0;
    existing.label = QStringLiteral("mus_route101");
    existing.constant = QStringLiteral("MUS_ROUTE101");
    existing.player = QStringLiteral("MUSIC_PLAYER_BGM");
    data.songs.append(existing);
    return data;
}

// Conductor tempo track plus two note tracks, mirroring the visual check's
// import SMF shape so the wizard's analysis page renders a real table.
SmfFile fixtureImportSmf()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    smf.tracks.resize(3);

    SmfEvent tempo;
    tempo.tick = 0;
    tempo.status = 0xFF;
    tempo.metaType = 0x51;
    tempo.blob = QByteArray("\x07\xA1\x20", 3);
    smf.tracks[0].events.push_back(tempo);
    smf.tracks[0].endTick = 0;

    const auto note = [](SmfTrack &track, Tick tick, uint8_t status, uint8_t d0, uint8_t d1) {
        SmfEvent ev;
        ev.tick = tick;
        ev.status = status;
        ev.data0 = d0;
        ev.data1 = d1;
        track.events.push_back(ev);
    };
    note(smf.tracks[1], 0, 0xC0, 12, 0);
    note(smf.tracks[1], 0, 0xB0, 7, 100);
    for (int i = 0; i < 8; ++i) {
        note(smf.tracks[1], Tick(i * 48), 0x90, uint8_t(60 + (i % 5)), 96);
        note(smf.tracks[1], Tick(i * 48 + 40), 0x80, uint8_t(60 + (i % 5)), 64);
    }
    smf.tracks[1].endTick = 8 * 48;
    note(smf.tracks[2], 0, 0xC1, 33, 0);
    for (int i = 0; i < 4; ++i) {
        note(smf.tracks[2], Tick(i * 96), 0x91, uint8_t(36 + i), 100);
        note(smf.tracks[2], Tick(i * 96 + 80), 0x81, uint8_t(36 + i), 64);
    }
    smf.tracks[2].endTick = 4 * 96;
    return smf;
}

// Synthesized 440 Hz sine at 22050 Hz: a realistic mono pipeline input with
// a loop and real pitch metadata. The editor copies it, so no lifetime
// holder is needed.
ImportedSample fixtureImportedSample()
{
    ImportedSample sample;
    constexpr int frames = 2048;
    constexpr double rate = 22050.0;
    sample.buffer.reserve(size_t(frames));
    for (int i = 0; i < frames; ++i)
        sample.buffer.push_back(float(0.7 * std::sin(2.0 * M_PI * 440.0 * i / rate)));
    sample.sampleRate = rate;
    sample.baseKey = 69;
    sample.fracSemitone = 0.0;
    sample.hasLoop = true;
    sample.loopStart = 256;
    sample.loopEndIncl = 1791;
    sample.playLength = frames;
    sample.hasPitchMetadata = true;
    sample.suggestedName = QStringLiteral("fixture_tone");
    sample.sourcePath = QStringLiteral("fixture:fixture_tone.wav");
    sample.sourceKind = ImportedSample::Wav;
    sample.sourceChannels = 1;
    sample.sourceBits = 16;
    return sample;
}

// Sf2ZonePicker borrows its file by const reference, so the parsed font is
// held by a child QObject that dies with the dialog it feeds.
class Sf2Holder final : public QObject
{
  public:
    explicit Sf2Holder(QObject *parent = nullptr) : QObject(parent) {}
    Sf2File file;
};

Sf2Holder *makeSoundFont()
{
    auto *holder = new Sf2Holder;
    Sf2File &font = holder->file;
    font.sourcePath = QStringLiteral("fixture:visual_zones.sf2");
    // 2400-frame 16-bit pool backing every zone below; the picker only
    // renders zone metadata, but a real pool keeps zone extraction honest.
    constexpr quint32 frames = 2400;
    font.pool.resize(int(frames * 2));
    for (quint32 i = 0; i < frames; ++i) {
        const auto v = qint16(10000.0 * std::sin(2.0 * M_PI * 220.0 * i / 22050.0));
        font.pool[int(i * 2)] = char(v & 0xFF);
        font.pool[int(i * 2 + 1)] = char((v >> 8) & 0xFF);
    }
    const auto zone = [](const char *name, const char *instrument, const char *preset,
                         quint32 start, quint32 end, quint32 loopStart, quint32 loopEnd,
                         quint32 rate, int pitch, quint16 type) {
        Sf2Zone z;
        z.name = QString::fromLatin1(name);
        z.instrument = QString::fromLatin1(instrument);
        z.preset = QString::fromLatin1(preset);
        z.start = start;
        z.end = end;
        z.loopStart = loopStart;
        z.loopEndExcl = loopEnd;
        z.sampleRate = rate;
        z.originalPitch = pitch;
        z.sampleType = type;
        return z;
    };
    font.zones.push_back(
        zone("Lead Tone", "LeadInst", "LeadPreset", 0, 400, 100, 300, 22050, 69, 1));
    font.zones.push_back(
        zone("Lead Octave", "LeadInst", "LeadPreset", 400, 700, 450, 650, 22050, 60, 1));
    font.zones.push_back(
        zone("Pad Left", "PadInst", "PadPreset", 700, 1100, 750, 1050, 32000, 60, 4));
    font.zones.push_back(
        zone("Pad Right", "PadInst", "PadPreset", 1100, 1500, 1150, 1450, 32000, 60, 8));
    font.zones.push_back(zone("Loose One", "", "", 1500, 1800, 0, 0, 22050, 60, 1));
    font.zones.push_back(zone("Loose Two", "", "", 1800, 2400, 1900, 2300, 22050, 62, 1));
    return holder;
}

// ---- Prototype-only mirrors -------------------------------------------------
//
// Faithful to the inline source forms, but prototype-owned: the rows match
// the production forms while titles and notes identify them as mirrors that
// create, write, and render nothing.

QDialog *makeNewVoicegroupMirror()
{
    // Mirrors WorkspaceUi::runCreateVoicegroupFlow
    // (src/ui/workspaceui_project.cpp:617): Name + Source rows over
    // Ok/Cancel. The source entry is a fixture label, never a project path.
    auto *dialog = new QDialog(nullptr);
    dialog->setWindowTitle(QDialog::tr("New Voicegroup (prototype mirror)"));
    auto *form = new QFormLayout(dialog);
    const int margin = ::layout::space(::layout::Space::Three);
    form->setContentsMargins(margin, margin, margin, margin);
    form->setSpacing(::layout::space(::layout::Space::Two));

    auto *note = new QLabel(
        QDialog::tr("Prototype mirror of the New Voicegroup form — creates nothing."), dialog);
    note->setWordWrap(true);
    note->setEnabled(false);
    form->addRow(note);

    auto *nameEdit = new QLineEdit(dialog);
    nameEdit->setValidator(new QRegularExpressionValidator(
        QRegularExpression(QStringLiteral("[A-Za-z][A-Za-z0-9_]*")), nameEdit));
    nameEdit->setText(QStringLiteral("fixture_voice"));
    form->addRow(QDialog::tr("Name"), nameEdit);

    auto *sourceCombo = new QComboBox(dialog);
    sourceCombo->addItem(QDialog::tr("Copy of voicegroup_abandoned_ship.inc"),
                         QStringLiteral("fixture:voicegroup_abandoned_ship.inc"));
    sourceCombo->addItem(QDialog::tr("Empty (dummy template)"), QString());
    form->addRow(QDialog::tr("Source"), sourceCombo);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, dialog);
    QObject::connect(buttons, &QDialogButtonBox::accepted, dialog, &QDialog::accept);
    QObject::connect(buttons, &QDialogButtonBox::rejected, dialog, &QDialog::reject);
    form->addRow(buttons);
    dialog->setMinimumSize(::layout::fontPx(30), ::layout::fontPx(12));
    return dialog;
}

QDialog *makeExportWavMirror()
{
    // Mirrors MainWindow::exportWav's looping options form
    // (src/mainwindow.cpp:1199): rate + loop-count + fadeout rows with a
    // duration readout. The duration is a static fixture preview — no
    // timeline rebuild, no save dialog, no QSettings, no render.
    auto *dialog = new QDialog(nullptr);
    dialog->setWindowTitle(QDialog::tr("Export WAV (prototype mirror)"));
    auto *form = new QFormLayout(dialog);
    const int margin = ::layout::space(::layout::Space::Three);
    form->setContentsMargins(margin, margin, margin, margin);
    form->setSpacing(::layout::space(::layout::Space::Two));

    auto *note = new QLabel(
        QDialog::tr("Prototype mirror of the Export WAV form — renders nothing."), dialog);
    note->setWordWrap(true);
    note->setEnabled(false);
    form->addRow(note);

    auto *rateBox = new QComboBox(dialog);
    for (int rate : {32000, 44100, 48000})
        rateBox->addItem(QDialog::tr("%1 Hz").arg(rate), rate);
    rateBox->setCurrentIndex(2);
    form->addRow(QDialog::tr("Sample rate:"), rateBox);

    auto *loopCountBox = new QSpinBox(dialog);
    loopCountBox->setRange(1, 99);
    loopCountBox->setValue(2);
    form->addRow(QDialog::tr("Loop count:"), loopCountBox);

    auto *fadeoutBox = new QDoubleSpinBox(dialog);
    fadeoutBox->setRange(0.0, 60.0);
    fadeoutBox->setDecimals(1);
    fadeoutBox->setValue(5.0);
    fadeoutBox->setSuffix(QDialog::tr(" s"));
    form->addRow(QDialog::tr("Fadeout:"), fadeoutBox);

    auto *durationLabel = new QLabel(QDialog::tr("0:07 (fixture preview)"), dialog);
    form->addRow(QDialog::tr("Duration:"), durationLabel);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, dialog);
    QObject::connect(buttons, &QDialogButtonBox::accepted, dialog, &QDialog::accept);
    QObject::connect(buttons, &QDialogButtonBox::rejected, dialog, &QDialog::reject);
    form->addRow(buttons);
    dialog->setMinimumSize(::layout::fontPx(30), ::layout::fontPx(14));
    return dialog;
}

} // namespace

extern "C" QDialog *sgw_createWindowFixture(int kind)
{
    switch (kind) {
    case SgwWindowSettings:
        // In-memory engine settings + detached song target; the dialog
        // copies both, so nothing outlives the call and no QSettings load
        // or save is involved.
        return new SettingsDialog(fixtureEngineSettings(),
                                  std::optional<SongTarget>(fixtureSongTarget()),
                                  fixtureVoicegroups(), false, nullptr);
    case SgwWindowSampleEditor: {
        // Null engine disables the audition strip (header contract); the
        // always-true validator keeps naming project-free. Null destAdsr.
        ImportedSample sample = fixtureImportedSample();
        SampleEditorDialog::NameValidator validator = [](const QString &, QString *) {
            return true;
        };
        return new SampleEditorDialog(std::move(sample), std::move(validator), nullptr, nullptr,
                                      nullptr);
    }
    case SgwWindowSf2Picker: {
        // The picker borrows the font: reparent the holder under the dialog
        // so the zones outlive every rebuild() for the full dialog lifetime.
        Sf2Holder *holder = makeSoundFont();
        auto *picker = new Sf2ZonePicker(holder->file, nullptr);
        holder->setParent(picker);
        return picker;
    }
    case SgwWindowImportMidi:
        // Import-mode wizard over the detached catalog + in-memory SMF; the
        // source path is a fixture label, never read from disk.
        return new NewSongWizard(fixtureProjectData(), fixtureImportSmf(),
                                 QStringLiteral("fixture/external_import.mid"), nullptr);
    case SgwWindowNewVoicegroup:
        return makeNewVoicegroupMirror();
    case SgwWindowExportWav:
        return makeExportWavMirror();
    case SgwWindowProgress: {
        // Real progress dialog, parked mid-render. autoClose/autoReset stay
        // off so the bridge's shown window remains visible until the user
        // dismisses it instead of vanishing at the bounds.
        auto *progress = new QProgressDialog(QDialog::tr("Rendering mus_route101..."),
                                             QDialog::tr("Cancel"), 0, 1000, nullptr);
        progress->setWindowTitle(QDialog::tr("Rendering song (prototype fixture)"));
        progress->setWindowModality(Qt::WindowModal);
        progress->setMinimumDuration(0);
        progress->setAutoClose(false);
        progress->setAutoReset(false);
        progress->setValue(250);
        return progress;
    }
    case SgwWindowOpenFile: {
        // Native defaults preserved: no DontUseNativeDialog, no project
        // directory, no selection — just the accept/file modes and filters.
        auto *dialog = new QFileDialog(nullptr, QDialog::tr("Open MIDI File (prototype fixture)"));
        dialog->setAcceptMode(QFileDialog::AcceptOpen);
        dialog->setFileMode(QFileDialog::ExistingFile);
        dialog->setNameFilters(
            {QDialog::tr("MIDI files (*.mid *.midi)"), QDialog::tr("All files (*)")});
        return dialog;
    }
    case SgwWindowSaveFile: {
        auto *dialog = new QFileDialog(nullptr, QDialog::tr("Export WAV (prototype fixture)"));
        dialog->setAcceptMode(QFileDialog::AcceptSave);
        dialog->setFileMode(QFileDialog::AnyFile);
        dialog->setDefaultSuffix(QStringLiteral("wav"));
        dialog->setNameFilters({QDialog::tr("WAV files (*.wav)"), QDialog::tr("All files (*)")});
        return dialog;
    }
    case SgwWindowDirectory: {
        auto *dialog =
            new QFileDialog(nullptr, QDialog::tr("Choose Directory (prototype fixture)"));
        dialog->setAcceptMode(QFileDialog::AcceptOpen);
        dialog->setFileMode(QFileDialog::Directory);
        dialog->setOption(QFileDialog::ShowDirsOnly, true);
        return dialog;
    }
    case SgwWindowConfirmation: {
        auto *box = new QMessageBox(QMessageBox::Question, QDialog::tr("Discard changes?"),
                                    QDialog::tr("Discard unsaved changes to mus_route101?"),
                                    QMessageBox::Ok | QMessageBox::Cancel, nullptr);
        box->setInformativeText(QDialog::tr("Prototype fixture — nothing is actually discarded."));
        box->setDefaultButton(QMessageBox::Cancel);
        return box;
    }
    case SgwWindowError: {
        auto *box = new QMessageBox(QMessageBox::Critical, QDialog::tr("Import failed"),
                                    QDialog::tr("Could not parse fixture/external_import.mid."),
                                    QMessageBox::Ok, nullptr);
        box->setInformativeText(QDialog::tr("Truncated track chunk at byte 128."));
        return box;
    }
    case SgwWindowAbout: {
        auto *box = new QMessageBox(
            QMessageBox::Information, QDialog::tr("About Porydaw (prototype fixture)"),
            QDialog::tr("Porydaw prototype fixture."), QMessageBox::Close, nullptr);
        box->setInformativeText(
            QDialog::tr("Standalone window fixtures for the Swift/QML interop prototype."));
        return box;
    }
    default:
        return nullptr;
    }
}
