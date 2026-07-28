#pragma once

#include <QWizard>

#include "core/midiimport.h"
#include "core/smf.h"
#include "project/decompproject.h"

class IdentityPage;
class SoundPage;
class AnalysisPage;

// The New Song wizard (SPEC.md §6.3) and the external-MIDI import flow
// (§6.2) — the same wizard with an extra page in import mode:
//
//   blank:  Identity -> Sound
//   import: Analysis -> Identity -> Sound
//
// The wizard only collects choices; MainWindow writes the .mid + midi.cfg
// line and registers the song in the three registration files.
//
// `voicegroupArgs` is the project's -G choices (SongRegistry::voicegroupArgs);
// the caller passes it in because scanning every voicegroup file is too slow
// to redo per dialog — MainWindow hands over its cached catalog.
class NewSongWizard : public QWizard
{
    Q_OBJECT

public:
    // Blank new song.
    NewSongWizard(DecompProject *project, const QStringList &voicegroupArgs,
                  QWidget *parent = nullptr);
    // Import: `imported` is the parsed external file (kept as-is apart from
    // the analysis page's optional division rescale).
    NewSongWizard(DecompProject *project, SmfFile imported,
                  const QString &sourcePath, const QStringList &voicegroupArgs,
                  QWidget *parent = nullptr);
    // Drag-and-drop import with a preflight track requirement.
    NewSongWizard(DecompProject *project, SmfFile imported,
                  const QString &sourcePath, const QStringList &voicegroupArgs,
                  int minimumTrackCount, QWidget *parent = nullptr);

    QString label() const;
    QString constant() const;
    QString player() const;
    SongCfg cfg() const;
    // The song to write: the blank template, or the import with the
    // optional division rescale applied.
    SmfFile songFile() const;
    // Non-empty when the user chose "(create a new voicegroup for this song)"
    // on the Sound page: the voicegroup to create (named after the song; cfg()
    // already carries its -G arg). Empty for an existing voicegroup.
    QString newVoicegroupName() const;

private:
    void buildPages(const QString &sourcePath, const QStringList &voicegroupArgs,
                    int minimumTrackCount = 0,
                    bool requireCompatiblePlayer = false);

    DecompProject *m_project;
    bool m_importMode = false;
    SmfFile m_imported;
    ImportAnalysis m_analysis;

    IdentityPage *m_identity = nullptr;
    SoundPage *m_sound = nullptr;
    AnalysisPage *m_analysisPage = nullptr;
};
