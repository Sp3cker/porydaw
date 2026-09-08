// Qt Test fixture for the selectionkey protected-local-input tier: per-case
// production-shell lifecycle (fresh MainWindow, scratch project, first song
// tab), the shared text-binding/focus seams, clipboard and settings isolation,
// and the clean-session close contract every case ends with. Scenario bodies
// live in localinputtier_text.cpp, localinputtier_pitchbend.cpp, and
// localinputtier_eventlist.cpp.

#include "checks/fwd.hpp"
#include "checks/selectionkey/tst_localinputtier.h"

#include <QApplication>
#include <QCloseEvent>
#include <QGuiApplication>
#include <QWidget>

#include <utility>
#include <vector>

#include "checks/support/asyncwait.h"
#include "ui/songview.h"

SelectionLocalInputTierTest::SelectionLocalInputTierTest(QString projectRoot, QString songLabel)
    : m_projectRoot(std::move(projectRoot))
    , m_songLabel(std::move(songLabel))
{}

SongView &SelectionLocalInputTierTest::view() const
{
    return m_tab->view();
}

SongDocument &SelectionLocalInputTierTest::document() const
{
    return m_tab->document();
}

QQuickWindow *SelectionLocalInputTierTest::quickWindow() const
{
    return m_quickWindow.data();
}

std::optional<QString> SelectionLocalInputTierTest::singleKeyText(const QKeyCombination &binding)
{
    if (binding.keyboardModifiers() != Qt::NoModifier)
        return std::nullopt;
    const int key = int(binding.key());
    if (key >= int(Qt::Key_A) && key <= int(Qt::Key_Z))
        return QString(QChar::fromLatin1(char('a' + (key - int(Qt::Key_A)))));
    if (key >= int(Qt::Key_0) && key <= int(Qt::Key_9))
        return QString(QChar::fromLatin1(char('0' + (key - int(Qt::Key_0)))));
    return std::nullopt;
}

void SelectionLocalInputTierTest::activateShellForCommands()
{
    QWidget *const shell = m_session.window.get();
    QVERIFY2(shell, "the view has no shell window for resumed commands");
    // Cocoa activation alone selects a key window without foregrounding the app.
    // A fresh shell must also reclaim the foreground after the prior case closes.
    shell->raise();
    shell->activateWindow();
    checks::async_wait::waitUntil([] { return true; }, [shell] { return shell->isActiveWindow(); },
                                  5000, 10);
    QVERIFY2(shell->isActiveWindow(),
             "the production shell did not become the active window for resumed commands");
}

QString SelectionLocalInputTierTest::applicationFocusState() const
{
    return QStringLiteral("QWidget=%1 QGui-object=%2 QGui-window=%3")
        .arg(selectionkey::focusObjectIdentity(QApplication::focusWidget()),
             selectionkey::focusObjectIdentity(QGuiApplication::focusObject()),
             selectionkey::focusObjectIdentity(QGuiApplication::focusWindow()));
}

std::optional<SelectionLocalInputTierTest::NoteRef>
SelectionLocalInputTierTest::addNote(int track, uint64_t tick, uint8_t key, uint32_t duration)
{
    QString error;
    const std::vector<NoteId> inserted =
        selectionkey::insertIsolatedNotes(document(), track, {{tick, key, duration, 100}}, error);
    if (inserted.size() != 1)
        return std::nullopt;
    const std::optional<DocNote> note = selectionkey::noteById(document(), inserted.front());
    if (!note)
        return std::nullopt;
    return NoteRef{inserted.front(), *note};
}

void SelectionLocalInputTierTest::init()
{
    m_counts = {};
    m_settings = std::make_unique<selectionkey::SessionSettingsGuard>();
    m_clipboard = std::make_unique<clipcheck_support::ClipboardStateGuard>();

    QString error;
    QVERIFY2(selectionkey::openWindowSession(m_session, m_projectRoot, error),
             qUtf8Printable(error));
    m_workspace = m_session.workspace;
    SongTab *const tab = selectionkey::openSongTab(m_session, m_songLabel, false, error);
    QVERIFY2(tab, qUtf8Printable(error));
    m_tab = tab;
    QVERIFY2(selectionkey::observeWindowActions(*m_session.window, m_counts),
             "the production shell is missing the window actions");

    songview::TimelineQuickView *const quick = selectionkey::quickCanvas(view());
    QVERIFY2(quick, "the tab Quick surface is missing");
    m_quickWindow = quick->quickWindow();
    QVERIFY2(m_quickWindow && quick->rootObject(),
             "the tab Quick window or root object is missing");
}

void SelectionLocalInputTierTest::cleanup()
{
    // Unconditional teardown, independent of how the case ended: drop any
    // residual grab, then end the session through the guarded production close
    // path. Outcomes are computed first and asserted last, so a failed
    // assertion can never skip the remaining teardown.
    bool released = true;
    if (m_quickWindow) {
        if (QQuickItem *grabber = m_quickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        released = QTest::qWaitFor(
            [this] { return m_quickWindow.isNull() || !m_quickWindow->mouseGrabberItem(); });
    }
    m_quickWindow.clear();
    m_tab.clear();

    // Every scenario rolls its edits back through the real undo stack; a
    // dirty tab here means a rollback or cleanup path regressed.
    QString dirtyProblem;
    if (m_session.window && m_session.workspace) {
        if (m_session.workspace->selectedSongDirty())
            dirtyProblem = QStringLiteral("the case left the selected tab dirty before the "
                                          "explicit close");
        {
            selectionkey::DeclineModalsWithin guard(QStringLiteral("closing the window session"));
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
    QVERIFY2(dirtyProblem.isEmpty(), qPrintable(dirtyProblem));
}

// Dispatched once per process by the selectionkey-local-input catalog row; the
// catalog already passed only the Qt payload (everything after --qt) and this
// forwards it verbatim into exactly one qExec.
int runSelectionKeyLocalInputCheck(const QString &projectRoot, const QString &songLabel,
                                   const QStringList &qtArguments)
{
    SelectionLocalInputTierTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("selectionkey-local-input")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
