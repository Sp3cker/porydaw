#pragma once

// Shared production-shell session for the selectionkey window, local-input,
// Qt Test tiers: one shown MainWindow with a scratch
// project and song opened through WorkspaceUi's non-dialog seams, plus the
// readiness waits and Quick lookups they share. Rig-agnostic
// delivery primitives live in checks/selectionkey/primitives.h, which this
// header includes; the sibling core/gesture suites drive standalone rigs and
// share only that header. The check runner redirects QSettings to a per-run
// directory, and SessionSettingsGuard restores each case's pre-case snapshot
// so the per-case MainWindow lifecycle stays order-independent.

#include "checks/selectionkey/primitives.h"
#include "checks/support/asyncwait.h"

#include "mainwindow.h"
#include "project/projectidentity.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/workspacequick/workspacequickhost.h"
#include "ui/workspaceui.h"

#include <QAction>
#include <QApplication>
#include <QMessageBox>
#include <QPointer>
#include <QSettings>
#include <QString>
#include <QTimer>
#include <QVariant>
#include <cstdio>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace selectionkey {

// Queued one-shot rejection of an unexpected active modal question box, so a
// regression that opens an unsaved-changes or load-failure prompt degrades into
// a finite, attributed failure instead of blocking the harness. The dismissal
// is queued into a Qt-owned event-loop turn because closing a native Cocoa
// modal reentrantly from a poll callback races the dialog teardown (the
// mainwindowroutingcheck failed-open precedent).
inline void dismissUnexpectedModal(const QString &stage)
{
    if (QPointer<QMessageBox> box = qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
        box && !box->property("dismissalQueued").toBool()) {
        std::fprintf(stderr, "selectionkeycheck: unexpected modal during %s: '%s'\n",
                     qUtf8Printable(stage), qUtf8Printable(box->windowTitle()));
        box->setProperty("dismissalQueued", true);
        QTimer::singleShot(0, box, [box] { box->reject(); });
    }
}

// Stage marker plus bounded modal decline for the production seams that can
// enter a nested modal loop synchronously or while a terminal publication is
// processed (song open, tab close, window close). The timer fires inside the
// prompt's own nested event loop and declines it with Cancel; the caller's
// follow-up assertions still decide the outcome, so nothing is weakened — the
// harness just stays finite and the stage line attributes where the prompt
// leaked.
class DeclineModalsWithin
{
  public:
    explicit DeclineModalsWithin(const QString &stage) : m_stage(stage)
    {
        std::fprintf(stderr, "selectionkeycheck: stage: %s\n", qUtf8Printable(m_stage));
        QObject::connect(&m_timer, &QTimer::timeout, &m_timer,
                         [this] { dismissUnexpectedModal(m_stage); });
        m_timer.start(200);
    }
    ~DeclineModalsWithin() { m_timer.stop(); }
    Q_DISABLE_COPY_MOVE(DeclineModalsWithin)

  private:
    QString m_stage;
    QTimer m_timer;
};

// Snapshot-and-restore isolation for the process QSettings location the check
// runner points at. Each per-case MainWindow seeds and persists editor state,
// so clearing before shell construction and restoring after teardown keeps
// suite cases order-independent without ever touching the user's settings.
class SessionSettingsGuard final
{
  public:
    SessionSettingsGuard()
    {
        for (const QString &key : m_settings.allKeys())
            m_values.emplace_back(key, m_settings.value(key));
        m_settings.clear();
    }
    ~SessionSettingsGuard()
    {
        m_settings.clear();
        for (const auto &[key, value] : m_values)
            m_settings.setValue(key, value);
        m_settings.sync();
    }
    SessionSettingsGuard(const SessionSettingsGuard &) = delete;
    SessionSettingsGuard &operator=(const SessionSettingsGuard &) = delete;

  private:
    QSettings m_settings;
    std::vector<std::pair<QString, QVariant>> m_values;
};

inline bool waitForProjectReady(const WorkspaceUi &workspace)
{
    return checks::async_wait::waitUntil(
               [] { return true; },
               [&workspace] { return workspace.projectState().state == ProjectOpenState::Ready; },
               30000, 10) == checks::async_wait::Result::Ready;
}

inline bool waitForTabReady(const WorkspaceUi &workspace, const SongTab *tab)
{
    const QPointer<const SongTab> liveTab(tab);
    const auto live = [&workspace, liveTab] {
        return liveTab && workspace.songTabFor(liveTab->name()) == liveTab.data();
    };
    return checks::async_wait::waitUntil(
               live, [liveTab] { return liveTab && liveTab->isReady(); }, 30000, 10) ==
           checks::async_wait::Result::Ready;
}

// A shown production shell with the scratch project open. The MainWindow dies
// with the session; tab pointers stay valid until a scenario explicitly
// closes or reopens songs.
struct WindowSession {
    std::unique_ptr<MainWindow> window;
    WorkspaceUi *workspace = nullptr;
};

inline bool openWindowSession(WindowSession &session, const QString &projectRoot, QString &error)
{
    session.window = std::make_unique<MainWindow>();
    session.workspace = session.window->findChild<WorkspaceUi *>();
    if (!session.workspace) {
        error = QStringLiteral("the production shell has no WorkspaceUi child");
        return false;
    }
    session.window->resize(960, 640);
    session.window->show();
    settle();
    session.workspace->requestProjectOpenAt(projectRoot);
    if (!waitForProjectReady(*session.workspace)) {
        error = QStringLiteral("the scratch project did not reach Ready");
        return false;
    }
    return true;
}

// Submits the real browser-placement request and returns as soon as the tab
// exists. Newly created tabs are deliberately still unready at this point, so
// readiness-gating cases can observe the production load interval before
// waiting for its terminal payload.
inline SongTab *requestSongTab(WindowSession &session, const QString &songLabel, bool newTab,
                               QString &error)
{
    const std::optional<SongName> name = SongName::create(songLabel);
    if (!name) {
        error = QStringLiteral("%1 is not a valid song label").arg(songLabel);
        return nullptr;
    }
    const QString stage = QStringLiteral("opening song '%1' (%2)")
                              .arg(songLabel, newTab ? QStringLiteral("new tab")
                                                     : QStringLiteral("replace or focus"));
    DeclineModalsWithin guard(stage);
    std::fprintf(stderr, "selectionkeycheck: phase: %s: request-song\n", qUtf8Printable(stage));
    session.workspace->requestSongOpen(*name, newTab);
    std::fprintf(stderr, "selectionkeycheck: phase: %s: request-song-returned\n",
                 qUtf8Printable(stage));
    SongTab *const tab = session.workspace->songTabFor(*name);
    if (!tab) {
        error = QStringLiteral("the %1 request returned without creating or finding its tab")
                    .arg(songLabel);
        return nullptr;
    }
    return tab;
}

// Opens (or focuses) the song's tab and waits for its terminal payload. The
// modal guard spans the asynchronous readiness wait, during which a failed
// load can publish a warning.
inline SongTab *openSongTab(WindowSession &session, const QString &songLabel, bool newTab,
                            QString &error)
{
    SongTab *const tab = requestSongTab(session, songLabel, newTab, error);
    if (!tab)
        return nullptr;
    const QString stage = QStringLiteral("waiting for song '%1'").arg(songLabel);
    DeclineModalsWithin guard(stage);
    std::fprintf(stderr, "selectionkeycheck: phase: %s\n", qUtf8Printable(stage));
    if (!waitForTabReady(*session.workspace, tab)) {
        error = QStringLiteral("the %1 tab never became ready").arg(songLabel);
        return nullptr;
    }
    settle();
    std::fprintf(stderr, "selectionkeycheck: phase: %s: complete\n", qUtf8Printable(stage));
    return tab;
}

// The Quick host of the timeline bands for a tab's view.
inline songview::TimelineQuickView *quickCanvas(const SongView &view)
{
    return view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"),
                                                         Qt::FindDirectChildrenOnly);
}

// Shell-tier input uses the one WorkspaceQuickHost already owned by the live
// MainWindow. It is never a fixture-created host: all pages and their shared
// window stay under the real WorkspaceUi lifecycle.
inline WorkspaceQuickHost *workspaceQuickHost(const WindowSession &session)
{
    return session.window ? session.window->findChild<WorkspaceQuickHost *>() : nullptr;
}

// Rolls a shell scenario's document edits back through the real undo stack,
// then clears both selection domains. This keeps every window/local-input
// scenario independent even when it returns early.
class ScenarioRollback final
{
  public:
    ScenarioRollback(SongView &view, SongDocument &document)
        : m_view(view)
        , m_document(document)
        , m_baseline(document.undoStack()->index())
    {}

    ~ScenarioRollback()
    {
        m_view.selectionModel().clearNoteSelection();
        m_view.selectionModel().clearTimeSelection();
        while (m_document.undoStack()->index() > m_baseline)
            m_document.undoStack()->undo();
        settle();
    }

    ScenarioRollback(const ScenarioRollback &) = delete;
    ScenarioRollback &operator=(const ScenarioRollback &) = delete;

  private:
    SongView &m_view;
    SongDocument &m_document;
    int m_baseline;
};

// Undo every document edit through the tab's real undo stack so production
// clean-lifecycle paths (song open, tab close, window close) run their
// genuine no-prompt branch. Returns false with a stage-labeled error when the
// supplied document itself still counts as dirty afterwards.
inline bool undoTabToClean(SongDocument &document, const QString &stage, QString *error = nullptr)
{
    while (document.undoStack()->index() > 0)
        document.undoStack()->undo();
    settle();
    if (document.isDirty()) {
        if (error)
            *error = QStringLiteral("%1 (processed document dirty=%2 undo-index=%3)")
                         .arg(stage.isEmpty() ? QStringLiteral("the tab stayed dirty "
                                                               "after undoing its document edits")
                                              : stage)
                         .arg(document.isDirty())
                         .arg(document.undoStack()->index());
        return false;
    }
    return true;
}

struct ActionCounts {
    int copy = 0;
    int solo = 0;
};

// Counts every triggered copy/solo window action for the session lifetime;
// exactly-once assertions compare deltas against these baselines.
inline bool observeWindowActions(MainWindow &window, ActionCounts &counts)
{
    QAction *const copy = window.findChild<QAction *>(QStringLiteral("copyWindowAction"));
    QAction *const solo = window.findChild<QAction *>(QStringLiteral("soloWindowAction"));
    if (!copy || !solo)
        return false;
    QObject::connect(copy, &QAction::triggered, &window, [&counts] { ++counts.copy; });
    QObject::connect(solo, &QAction::triggered, &window, [&counts] { ++counts.solo; });
    return true;
}

} // namespace selectionkey
