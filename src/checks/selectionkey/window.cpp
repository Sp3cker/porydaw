// Qt Test fixture for the selectionkey window tier: per-case production-shell
// lifecycle (fresh MainWindow, scratch project, first song tab), the shared
// document/focus seams, failure-safe input release, and the clean-session
// close contract every case ends with. Scenario bodies live in
// windowtier_keyboard.cpp, windowtier_gestures.cpp, and
// windowtier_lifetime.cpp.

#include "checks/fwd.hpp"
#include "checks/selectionkey/tst_windowtier.h"

#include <QApplication>
#include <QCloseEvent>
#include <QQuickItem>

#include <utility>
#include <vector>

#include "checks/support/asyncwait.h"
#include "ui/songview.h"

SelectionWindowTierTest::SelectionWindowTierTest(QString projectRoot, QString songA, QString songB)
    : m_projectRoot(std::move(projectRoot))
    , m_songA(std::move(songA))
    , m_songB(std::move(songB))
{}

SongView &SelectionWindowTierTest::view() const
{
    return m_tab->view();
}

SongDocument &SelectionWindowTierTest::document() const
{
    return m_tab->document();
}

QQuickWindow *SelectionWindowTierTest::quickWindow() const
{
    return m_quickWindow.data();
}

std::optional<SelectionWindowTierTest::NotePair>
SelectionWindowTierTest::addNotePair(SongDocument &document, int track, uint64_t firstTick)
{
    const std::vector<SongDocument::NewNote> specs{{firstTick, 60, 48, 100},
                                                   {firstTick + 96, 64, 48, 96}};
    QString error;
    const std::vector<NoteId> inserted =
        selectionkey::insertIsolatedNotes(document, track, specs, error);
    if (inserted.size() != 2)
        return std::nullopt;
    NotePair pair;
    pair.ids = {inserted[0], inserted[1]};
    for (int index = 0; index < 2; ++index) {
        const std::optional<DocNote> note =
            selectionkey::noteById(document, pair.ids[std::size_t(index)]);
        if (!note)
            return std::nullopt;
        pair.notes[std::size_t(index)] = *note;
    }
    return pair;
}

bool SelectionWindowTierTest::notePairUnchanged(SongDocument &document, const NotePair &pair) const
{
    for (int index = 0; index < 2; ++index) {
        const std::optional<DocNote> note =
            selectionkey::noteById(document, pair.ids[std::size_t(index)]);
        if (!note)
            return false;
        const DocNote &original = pair.notes[std::size_t(index)];
        if (note->tick != original.tick || note->key != original.key)
            return false;
    }
    return true;
}

bool SelectionWindowTierTest::focusAutomationBand(SongView &view) const
{
    return view.focusTimelineBand(songview::TimelineBand::Automation, Qt::MouseFocusReason);
}

void SelectionWindowTierTest::trackPointer(const QPoint &windowPos)
{
    m_heldButton = Qt::LeftButton;
    m_lastWindowPos = windowPos;
}

void SelectionWindowTierTest::trackRelease()
{
    m_heldButton = Qt::NoButton;
}

void SelectionWindowTierTest::init()
{
    m_counts = {};
    m_heldButton = Qt::NoButton;
    m_lastWindowPos = QPoint();
    m_settings = std::make_unique<selectionkey::SessionSettingsGuard>();
    m_clipboard = std::make_unique<clipcheck_support::ClipboardStateGuard>();

    QString error;
    QVERIFY2(selectionkey::openWindowSession(m_session, m_projectRoot, error),
             qUtf8Printable(error));
    m_workspace = m_session.workspace;
    SongTab *const tab = selectionkey::openSongTab(m_session, m_songA, false, error);
    QVERIFY2(tab, qUtf8Printable(error));
    m_tab = tab;
    QVERIFY2(selectionkey::observeWindowActions(*m_session.window, m_counts),
             "the production shell is missing the window actions");

    // Qt::WindowShortcut actions match only while the shell is QApplication's
    // active window (the qWidgetShortcutContextMatcher prerequisite
    // RoutingRuntimeRepair measured), and a gated background process can have
    // macOS deny activation outright. Activate before any band focus —
    // activating after focusing a Quick band clears the scene's
    // activeFocusItem — then observe the prerequisite honestly so a denial is
    // its own attributed failure instead of shortcut assertions masquerading
    // as routing regressions.
    m_session.window->activateWindow();
    QVERIFY2(
        checks::async_wait::waitUntil(
            [] { return true; },
            [this] { return QApplication::activeWindow() == m_session.window.get(); }, 2000,
            10) == checks::async_wait::Result::Ready,
        "the production shell never became the active window, so window shortcuts cannot fire");

    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view());
    QVERIFY2(quick, "the tab Quick surface is missing");
    m_quickWindow = quick->quickWindow();
    QVERIFY2(m_quickWindow && quick->rootObject(),
             "the tab Quick window or root object is missing");
}

void SelectionWindowTierTest::cleanup()
{
    // Unconditional teardown, independent of how the case ended: release every
    // recorded held press, drop any residual grab, then end the session the
    // way a clean user session ends. Outcomes are computed first and asserted
    // last, so a failed assertion can never skip the remaining teardown.
    bool released = true;
    if (m_quickWindow) {
        if (m_heldButton != Qt::NoButton) {
            QTest::mouseRelease(m_quickWindow, m_heldButton, Qt::NoModifier, m_lastWindowPos);
            m_heldButton = Qt::NoButton;
            selectionkey::settle();
        }
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        released = QTest::qWaitFor(
            [this] { return m_quickWindow.isNull() || !m_quickWindow->mouseGrabberItem(); });
    }
    m_quickWindow.clear();
    m_tab.clear();

    // Every scenario rolls its edits back through the real undo stack, so the
    // explicit close below runs production's genuine no-prompt branch. A dirty
    // tab here means the production close path would prompt, and the modal
    // guard must never be what hides that regression.
    QString closeProblem;
    if (m_session.window && m_session.workspace) {
        const bool cleanShell =
            m_session.workspace->projectState().state == ProjectOpenState::Ready &&
            !m_session.workspace->selectedSongDirty() && !m_session.workspace->hasPendingSaveWork();
        {
            selectionkey::DeclineModalsWithin guard(QStringLiteral("closing the window session"));
            QCloseEvent closeEvent;
            QApplication::sendEvent(m_session.window.get(), &closeEvent);
            if (cleanShell && !closeEvent.isAccepted())
                closeProblem = QStringLiteral("the clean session close was not accepted by the "
                                              "production shell");
            m_session.window->close();
            selectionkey::settle();
        }
    }
    // Reset the shell even when a partial open left it without a WorkspaceUi,
    // so no init-failure path can leak the window into the next case.
    m_session.window.reset();
    m_session.workspace = nullptr;
    m_workspace = nullptr;
    m_clipboard.reset();
    m_settings.reset();
    QVERIFY2(released, "the Quick mouse grab survived the case teardown");
    QVERIFY2(closeProblem.isEmpty(), qPrintable(closeProblem));
}

// Dispatched once per process by the selectionkey-window catalog row; the
// catalog already passed only the Qt payload (everything after --qt) and this
// forwards it verbatim into exactly one qExec.
int runSelectionKeyWindowCheck(const QString &projectRoot, const QString &songA,
                               const QString &songB, const QStringList &qtArguments)
{
    SelectionWindowTierTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("selectionkey-window")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
