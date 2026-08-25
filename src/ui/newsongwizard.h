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
// ProjectData is a detached copy of the project values needed to populate
// hints and choices. In particular, the wizard never scans the project root
// while the user types.
class NewSongWizard : public QWizard
{
    Q_OBJECT

  public:
    struct ProjectData {
        QVector<SongInfo> songs;
        QVector<MusicPlayer> players;
        QStringList voicegroupArgs;
        bool canCreateVoicegroup = false;
    };

    // Constructors taking ProjectData are the no-I/O interface for callers
    // that already own a project snapshot or catalog.
    NewSongWizard(ProjectData projectData, QWidget *parent = nullptr);
    NewSongWizard(ProjectData projectData, SmfFile imported, const QString &sourcePath,
                  QWidget *parent = nullptr);

    // Compatibility constructors build ProjectData from the project's
    // already-cached values. They do not read the project root.
    NewSongWizard(DecompProject *project, const QStringList &voicegroupArgs,
                  QWidget *parent = nullptr);
    NewSongWizard(DecompProject *project, SmfFile imported, const QString &sourcePath,
                  const QStringList &voicegroupArgs, QWidget *parent = nullptr);

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
    void buildPages(const QString &sourcePath);

    ProjectData m_projectData;
    bool m_importMode = false;
    SmfFile m_imported;
    ImportAnalysis m_analysis;

    IdentityPage *m_identity = nullptr;
    SoundPage *m_sound = nullptr;
    AnalysisPage *m_analysisPage = nullptr;
};
