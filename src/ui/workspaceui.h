#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QPair>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVector>

#include <cstdint>
#include <functional>
#include <vector>

#include "porydaw_scale.h"
#include "project/decompproject.h"
#include "ui/editorviewstate.h"
#include "ui/viewsidecar.h"
#include "ui/voicegroupbrowser.h"

class QAction;
class QDockWidget;
class QMainWindow;
class QMenu;
class QTabWidget;
class QWidget;
class SongListPanel;
class SongSession;
class SongView;
class TransportBar;

namespace checks {
class VoicegroupBrowserDriver;
}

namespace keymap {
class Registry;
}

// Owns all persistent workspace chrome and every open song page. The public
// seam describes application state and user intent; widget mechanics stay
// private to this module.
class WorkspaceUi final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(WorkspaceUi)

  public:
    enum class ActivationPolicy {
        PreserveCurrent,
        Activate,
    };

    enum class PlaybackState {
        Unavailable,
        Stopped,
        Paused,
        Playing,
    };

    struct SongFilters {
        QString search;
        int sortIndex = 0;
        QString categoryPrefix;
    };

    // The loaded/source pointers are non-owning presentation borrows. The
    // caller clears or replaces the presentation before either pointee dies.
    struct VoicegroupPresentation {
        const LoadedVoiceGroup *voicegroup = nullptr;
        VoicegroupSource *source = nullptr;
        QString currentArg;
        QStringList choices;
        QStringList sampleSymbols;
        QStringList waveSymbols;
        QList<QPair<QString, QString>> keysplits;
        QStringList drumkits;
        VgAdsrDefaults adsrDefaults;
        VgSynthCatalog synths;
        QHash<QString, VgSynthDesc> pendingSynths;
        std::function<QString(const VgSynthDesc &)> mintSynth;
        QSet<int> usedVoices;
    };

    struct ChromeObservation {
        bool transportVisible = false;
        bool songsVisible = false;
        bool voicegroupsVisible = false;
        qsizetype listedSongCount = 0;
        qsizetype listedVoiceCount = 0;
    };

    explicit WorkspaceUi(QMainWindow &host);

    SongView &attachSession(SongSession &session, const QString &title, const QString &toolTip,
                            const ViewSidecar::Snapshot &viewState,
                            ActivationPolicy activationPolicy);
    void detachSession(SongSession &session);
    void detachAllSessions();
    void activateSession(SongSession *session);
    void requestCloseSession(SongSession &session);
    SongSession *activeSession() const noexcept;
    bool isSessionAttached(const SongSession &session) const noexcept;
    SongView &viewFor(const SongSession &session);
    const SongView &viewFor(const SongSession &session) const;
    qsizetype openSessionCount() const noexcept;
    std::vector<SongSession *> sessionsInDisplayOrder() const;
    QString sessionTitle(const SongSession &session) const;
    void setSessionTitle(const SongSession &session, const QString &title, bool dirty,
                         const QString &toolTip);
    ViewSidecar::Snapshot sessionViewState(const SongSession &session) const;
    void applySessionViewState(SongSession &session, const ViewSidecar::Snapshot &viewState);

    void setSongs(const QVector<SongInfo> &songs);
    void setCurrentSong(int songId);
    void restoreSongFilters(const SongFilters &filters);
    SongFilters songFilters() const;
    void focusSongSearch();
    void focusSongList();
    bool isSongListed(const QString &label) const;
    qsizetype listedSongCount() const noexcept;
    void bindFindSongShortcut(keymap::Registry &registry);

    void setTransportPlaybackState(PlaybackState state);
    void setTransportSessionAvailable(bool available);
    void setTransportSongName(const QString &name);
    void setTransportTimeText(const QString &text);
    void setTransportMasterVolume(int volume, bool enabled);
    void setTransportOutputVolume(int volume);
    void setTransportScaleState(int root, porydaw_scale::ScaleId scale, bool highlight, bool fold);
    void setTransportResonanceSuppression(bool enabled);
    void triggerPlayPause();
    void addFollowPlayheadActionTo(QMenu &menu);

    void setVoicegroupPresentation(VoicegroupPresentation &&presentation);
    void clearVoicegroupPresentation();
    void setVoicegroupLoading(bool loading);
    void clearVoicegroupSource();
    void setVoicegroup(const LoadedVoiceGroup *voicegroup);
    void setVoicegroupUsedVoices(const QSet<int> &usedVoices);
    void setCurrentVoicegroupArg(const QString &arg);
    void setVoicegroupSampleInfoProvider(std::function<SamplePickInfo(const QString &)> provider);
    int currentVoicegroupSlot() const;
    void selectVoicegroupSlot(int slot);
    void revealVoicegroupSlot(int slot);
    void refreshVoicegroupSlot(int slot);
    void showVoicegroupPanel();
    void setVoicegroupDirty(bool dirty);

    void setVelocityColorMode(bool enabled);
    void setNoteNameMode(bool enabled);
    void setFollowPlayhead(bool enabled);
    void setEditorDrawerState(const EditorDrawerState &state);

    ChromeObservation observeChrome() const;

  signals:
    void activeSessionChanged(SongSession *session);
    void closeSessionRequested(SongSession *session);
    void sessionsReordered();

    void goToStartRequested();
    void playRequested();
    void playPauseRequested();
    void pauseRequested();
    void stopRequested();
    void loopEnabledChanged(bool enabled);
    void followPlayheadChanged(bool enabled);
    void resonanceSuppressionChanged(bool enabled);
    void masterVolumeChanged(int value);
    void outputVolumeChanged(int value);
    void scaleRootChanged(int root);
    void scaleIdChanged(porydaw_scale::ScaleId scale);
    void scaleHighlightChanged(bool enabled);
    void scaleFoldChanged(bool enabled);

    void songActivated(int songId);
    void songOpenInNewTabRequested(int songId);
    void songRegisterRequested(int songId);
    void songDeleteRequested(int songId);

    void auditionVoiceRequested(int voice, int key, int velocity);
    void sampleAuditionRequested(const QString &symbol, VgAuditionKind kind,
                                 const AuditionSlots::Adsr &adsr);
    void sampleAuditionStopRequested();
    void voiceEditRequested(int slot, const VgVoice &voice, bool structural);
    void newVoicegroupRequested();
    void newSampleRequested(int slot);
    void editSampleRequested(int slot);
    void voicegroupChangeRequested(const QString &arg);

  private:
    friend class checks::VoicegroupBrowserDriver;

    struct Page {
        SongSession *session = nullptr;
        SongView *view = nullptr;
    };

    void buildUi();
    SongView *findView(const SongSession &session) const noexcept;
    SongSession *findSessionForWidget(const QWidget *widget) const noexcept;
    void publishActiveSessionIfChanged();

    QMainWindow &m_host;
    TransportBar *m_transport = nullptr;
    SongListPanel *m_songList = nullptr;
    QDockWidget *m_songsDock = nullptr;
    VoicegroupBrowser *m_voicegroupBrowser = nullptr;
    QDockWidget *m_voicegroupDock = nullptr;
    QTabWidget *m_tabs = nullptr;
    QAction *m_findSongAction = nullptr;
    std::vector<Page> m_pages;
    QVector<SongInfo> m_songs;
    SongSession *m_publishedActiveSession = nullptr;
    bool m_velocityColorMode = false;
    bool m_noteNameMode = false;
    bool m_followPlayhead = true;
    bool m_hasVoicegroup = false;
    EditorDrawerState m_editorDrawerState;
};
