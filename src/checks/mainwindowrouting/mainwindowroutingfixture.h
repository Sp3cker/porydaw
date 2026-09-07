#pragma once

#include <algorithm>
#include <cstdint>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QIODevice>
#include <QKeySequence>
#include <QLineEdit>
#include <QList>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QObject>
#include <QPointer>
#include <QSettings>
#include <QSignalSpy>
#include <QTabBar>
#include <QTimer>
#include <QVariant>
#include <QWidget>

#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "project/sidecar.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/playheadoverlay.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/workspaceui.h"

namespace checks::mainwindowrouting {

class SettingsGuard final
{
  public:
    SettingsGuard()
    {
        for (const QString &key : m_settings.allKeys())
            m_values.emplace_back(key, m_settings.value(key));
        m_settings.clear();
    }
    ~SettingsGuard()
    {
        m_settings.clear();
        for (const auto &[key, value] : m_values)
            m_settings.setValue(key, value);
        m_settings.sync();
    }
    SettingsGuard(const SettingsGuard &) = delete;
    SettingsGuard &operator=(const SettingsGuard &) = delete;

  private:
    QSettings m_settings;
    std::vector<std::pair<QString, QVariant>> m_values;
};

struct Session final {
    std::unique_ptr<SettingsGuard> settings;
    std::unique_ptr<checks::ProjectFixture> fixture;
    std::unique_ptr<MainWindow> window;
    SongTab *a = nullptr;
    SongTab *b = nullptr;
};

class MainWindowRoutingFixture
{
  protected:
    std::optional<Session> openSession(const QString &projectRoot, const QString &songA,
                                       const QString &songB, bool awaitReady = true) const
    {
        auto settings = std::make_unique<SettingsGuard>();
        EditorViewState seed;
        seed.velocity = {true, 173};
        seed.automation = {false, std::nullopt};
        seed.voiceChanges = {false, std::nullopt};
        seed.activePage = EditorDrawerPage::Velocity;
        QSettings storage;
        saveEditorViewState(storage, seed);
        storage.sync();
        QString error;
        std::unique_ptr<checks::ProjectFixture> fixture =
            checks::ProjectFixture::copyOf(projectRoot, error);
        if (!fixture)
            return std::nullopt;
        auto window = std::make_unique<MainWindow>();
        if (!window->m_audioOk)
            return std::nullopt;
        const auto aName = SongName::create(songA);
        const auto bName = SongName::create(songB);
        if (!aName || !bName)
            return std::nullopt;
        window->m_workspace->requestProjectOpenAt(fixture->root());
        if (!waitForProjectReady(*window->m_workspace))
            return std::nullopt;
        window->resize(960, 640);
        window->show();
        window->m_workspace->requestSongOpen(*aName);
        SongTab *a = window->m_workspace->songTabFor(*aName);
        window->m_workspace->requestSongOpen(*bName, true);
        SongTab *b = window->m_workspace->selectedSongTab();
        if (awaitReady && (!waitForTabReady(*window->m_workspace, a) ||
                           !waitForTabReady(*window->m_workspace, b)))
            return std::nullopt;
        return Session{std::move(settings), std::move(fixture), std::move(window), a, b};
    }

    static bool waitForProjectReady(const WorkspaceUi &workspace)
    {
        return checks::async_wait::waitUntil([] { return true; },
                                             [&workspace] {
                                                 return workspace.projectState().state ==
                                                        ProjectOpenState::Ready;
                                             },
                                             30000, 1) == checks::async_wait::Result::Ready;
    }

    static bool waitForTabReady(const WorkspaceUi &workspace, SongTab *tab)
    {
        return tab &&
               checks::async_wait::waitUntil(
                   [&workspace, tab] { return workspace.songTabFor(tab->name()) == tab; },
                   [tab] { return tab->isReady(); }, 30000, 1) == checks::async_wait::Result::Ready;
    }

    static void sendKey(QWidget &target, Qt::Key key,
                        Qt::KeyboardModifiers modifiers = Qt::NoModifier)
    {
        checks::events::sendKey(target, QEvent::KeyPress, key, modifiers, QString(), false, 1);
        checks::events::sendKey(target, QEvent::KeyRelease, key, modifiers, QString(), false, 1);
    }

    static void sendShortcut(QObject &target, const QKeySequence &sequence)
    {
        const QKeyCombination combination = sequence[0];
        checks::events::sendKey(target, QEvent::KeyPress, combination.key(),
                                combination.keyboardModifiers(), QString(), false, 1);
        checks::events::sendKey(target, QEvent::KeyRelease, combination.key(),
                                combination.keyboardModifiers(), QString(), false, 1);
        QCoreApplication::processEvents();
    }

    static QMenu *editMenu(MainWindow &window)
    {
        for (QAction *menuAction : window.menuBar()->actions()) {
            QMenu *menu = menuAction->menu();
            if (menu && QString(menu->title()).remove(QLatin1Char('&')) == QStringLiteral("Edit"))
                return menu;
        }
        return nullptr;
    }

    static QByteArray fileContents(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
    }

    static std::map<QString, QByteArray> porydawSnapshot(const QString &projectRoot)
    {
        std::map<QString, QByteArray> snapshot;
        const std::function<void(const QString &, const QString &)> visit =
            [&snapshot, &visit](const QString &directory, const QString &prefix) {
                const QDir dir(directory);
                for (const QFileInfo &entry :
                     dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
                    const QString relative = prefix.isEmpty()
                                                 ? entry.fileName()
                                                 : prefix + QLatin1Char('/') + entry.fileName();
                    if (entry.isDir())
                        visit(entry.absoluteFilePath(), relative);
                    else
                        snapshot.emplace(relative, fileContents(entry.absoluteFilePath()));
                }
            };
        const QString sidecar = Sidecar::dirPath(projectRoot);
        if (QDir(sidecar).exists())
            visit(sidecar, QString());
        return snapshot;
    }

    static bool sameViewState(const SongView::ViewState &left, const SongView::ViewState &right)
    {
        return left.valid == right.valid && left.pxPerBeat == right.pxPerBeat &&
               left.keyHeight == right.keyHeight && left.scrollPx == right.scrollPx &&
               left.scrollY == right.scrollY && left.selectedTrack == right.selectedTrack &&
               left.editCursorTick == right.editCursorTick &&
               left.gridMinDenom == right.gridMinDenom && left.gridTriplet == right.gridTriplet &&
               left.eventList == right.eventList;
    }

    static bool hasCanonicalFreshViewState(SongView &view, const MidiTimeline &timeline)
    {
        const SongView::ViewState defaults;
        const SongView::ViewState landed = view.viewState();
        if (!landed.valid || landed.pxPerBeat != defaults.pxPerBeat ||
            landed.keyHeight != defaults.keyHeight || landed.editCursorTick != 0 ||
            landed.gridMinDenom != 0 || landed.gridTriplet || landed.eventList)
            return false;
        int firstUsedTrack = 0;
        for (int track = 0; track < 16; ++track) {
            if (timeline.tracks[track].used) {
                firstUsedTrack = track;
                break;
            }
        }
        if (landed.selectedTrack != firstUsedTrack)
            return false;
        view.resetScrollPosition();
        const SongView::ViewState reset = view.viewState();
        return landed.scrollPx == reset.scrollPx && landed.scrollY == reset.scrollY;
    }

    static EditorViewState completeSeed()
    {
        const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
        const EditorAutomationRowId hiddenFirst{EditorAutomationRowKind::ControlChange, 1, 7};
        const EditorAutomationRowId hiddenSecond{EditorAutomationRowKind::ControlChange, 0, 80};
        const EditorAutomationRowId tempo{EditorAutomationRowKind::Tempo, 0, 0};
        const int floor = layout::fontPx(7.0 / 3.0);
        const int ceiling = layout::fontPx(32.0 / 3.0);
        EditorViewState state;
        state.velocity = {true, 173};
        state.automation = {true, 44};
        state.voiceChanges = {true, 55};
        state.activePage = EditorDrawerPage::Automations;
        state.laneHeight = (floor + ceiling) / 2;
        state.laneHeights = {{lane, floor + 3}, {hiddenFirst, floor + 5}};
        state.laneRanges = {{lane, 90}, {tempo, 100}};
        state.emptyLanes.insert(lane);
        state.hideLane(hiddenFirst);
        state.hideLane(hiddenSecond);
        return state;
    }

    static std::optional<DocNote> selectFirstNote(SongTab &tab)
    {
        SongView &view = tab.view();
        for (int track = 0; track < tab.document().engineTrackCount(); ++track) {
            const std::vector<DocNote> notes = tab.document().notesForTrack(track);
            if (notes.empty())
                continue;
            view.selectTrack(track);
            view.selectionModel().setNoteSelection({notes.front().noteId});
            return notes.front();
        }
        return std::nullopt;
    }
};

} // namespace checks::mainwindowrouting
