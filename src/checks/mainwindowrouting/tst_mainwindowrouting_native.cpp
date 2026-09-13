#include "mainwindowroutingfixture.h"

#include "checks/clipcheck_support.h"
#include "checks/quickpopupguard.h"
#include "ui/songview/editactions.h"
#include "ui/songview/timelinebandlayout.h"
#include <QPoint>
#include <QScopeGuard>

#include <QtTest>
namespace checks::mainwindowrouting {

class MainWindowRoutingNativeTest final : public QObject, private MainWindowRoutingFixture
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MainWindowRoutingNativeTest)

  public:
    MainWindowRoutingNativeTest(QString projectRoot, QString songA, QString songB)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
    {}

  private slots:
    void nativeMenuAndWindowShortcutRouting()
    {
        if (QApplication::platformName() != QLatin1String("cocoa"))
            QSKIP("requires the Cocoa WindowSystem backend");
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        const auto activated = checks::async_wait::waitUntil([] { return true; },
                                                             [&window] {
                                                                 window.activateWindow();
                                                                 window.raise();
                                                                 return window.isActiveWindow();
                                                             },
                                                             5000, 1);
        QVERIFY2(activated == checks::async_wait::Result::Ready,
                 "Cocoa did not make MainWindow active after show()");

        QMenu *menu = editMenu(window);
        QVERIFY(menu);
        QAction *copy = window.m_copyAction;
        QAction *solo = window.m_soloAction;
        QVERIFY(copy);
        QVERIFY(solo);
        menu->popup(window.mapToGlobal(QPoint(12, 12)));
        QTRY_VERIFY(menu->isVisible());
        menu->hide();

        SongView &view = session->b->view();
        std::optional<DocNote> note;
        for (int track = 0; track < session->b->document().engineTrackCount() && !note; ++track) {
            const std::vector<DocNote> notes = session->b->document().notesForTrack(track);
            if (!notes.empty()) {
                view.selectTrack(track);
                view.selectionModel().setNoteSelection({notes.front().noteId});
                note = notes.front();
            }
        }
        QVERIFY(note.has_value());
        window.m_workspace->selectSongTab(session->b);
        view.focusActiveSurface();
        QCoreApplication::processEvents();
        QWidget *target = QApplication::focusWidget();
        QVERIFY(target && (target == session->b || session->b->isAncestorOf(target)));
        const QList<QKeySequence> copyBindings = copy->shortcuts();
        QVERIFY(!copyBindings.isEmpty());
        QSignalSpy copyTriggered(copy, &QAction::triggered);
        sendShortcut(*target, copyBindings.front());
        QCOMPARE(copyTriggered.count(), 1);
        const auto copied = clipcheck_support::checkClipboardClip();
        QVERIFY(copied.has_value());
        QCOMPARE(copied->clip.tracks.size(), size_t{1});
        QCOMPARE(copied->clip.tracks.front().notes.size(), size_t{1});
        QCOMPARE(copied->clip.tracks.front().notes.front().key, note->key);

        // Native QWidget text copy stays available with no musical selection:
        // the real composed Copy key carries the focused field's own text.
        view.selectionModel().clearNoteSelection();
        QLineEdit text(&window);
        text.setText(QStringLiteral("native copy text probe"));
        text.selectAll();
        text.show();
        text.setFocus();
        QCoreApplication::processEvents();
        QCOMPARE(QApplication::focusWidget(), &text);
        QApplication::clipboard()->clear();
        sendShortcut(text, QKeySequence(QKeySequence::Copy));
        QCOMPARE(QApplication::clipboard()->text(), QStringLiteral("native copy text probe"));

        const QList<QKeySequence> soloBindings = solo->shortcuts();
        QVERIFY(!soloBindings.isEmpty());
        const int selectedTrack = view.selectionModel().primaryTrack();
        view.setTrackSolo(selectedTrack, false);
        QSignalSpy soloTriggered(solo, &QAction::triggered);
        // Cocoa owns the visible menu bar natively, so QWidget focus can remain on
        // the line edit above. Use an explicit non-text child for the window route.
        QWidget shortcutTarget(&window);
        shortcutTarget.setFocusPolicy(Qt::StrongFocus);
        shortcutTarget.show();
        shortcutTarget.setFocus(Qt::OtherFocusReason);
        QCoreApplication::processEvents();
        QCOMPARE(QApplication::focusWidget(), &shortcutTarget);
        sendShortcut(shortcutTarget, soloBindings.front());
        QVERIFY(view.trackSoloed(selectedTrack));
        QCOMPARE(soloTriggered.count(), 1);
        sendShortcut(shortcutTarget, soloBindings.front());
        QVERIFY(!view.trackSoloed(selectedTrack));
        QCOMPARE(soloTriggered.count(), 2);
        view.focusActiveSurface();
        target = QApplication::focusWidget();
        QVERIFY(target && (target == session->b || session->b->isAncestorOf(target)));
        sendShortcut(*target, soloBindings.front());
        QVERIFY(view.trackSoloed(selectedTrack));
        QCOMPARE(soloTriggered.count(), 3);
        sendShortcut(*target, soloBindings.front());
        QVERIFY(!view.trackSoloed(selectedTrack));
        QCOMPARE(soloTriggered.count(), 4);
        text.setFocus();
        sendShortcut(text, soloBindings.front());
        QVERIFY(!view.trackSoloed(selectedTrack));
        QCOMPARE(soloTriggered.count(), 4);
    }

    // A foreign non-modal window owns its ordinary keys: while it is active,
    // the installed-but-closed native Edit menu and the window-scoped action
    // set contribute nothing — no song edit, no activation. The modal-foreign
    // case is vacuous: Cocoa disables the menu items for a modal session.
    void nativeForeignWindowKeepsLocalKeys()
    {
        if (QApplication::platformName() != QLatin1String("cocoa"))
            QSKIP("requires the Cocoa WindowSystem backend");
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        const auto activated = checks::async_wait::waitUntil([] { return true; },
                                                             [&window] {
                                                                 window.activateWindow();
                                                                 window.raise();
                                                                 return window.isActiveWindow();
                                                             },
                                                             5000, 1);
        QVERIFY2(activated == checks::async_wait::Result::Ready,
                 "Cocoa did not make MainWindow active after show()");
        QMenu *menu = editMenu(window);
        QVERIFY(menu);
        QVERIFY(!menu->isVisible());
        QAction *copy = window.m_copyAction;
        QAction *solo = window.m_soloAction;
        QVERIFY(copy && solo);
        SongView &view = session->b->view();
        // Copy has no standalone arm: it is only enabled with an eligible
        // musical selection (correctly disabled at fresh open). Establish one
        // so this slot exercises an enabled Editor action throughout.
        std::optional<DocNote> seedNote;
        for (int track = 0; track < session->b->document().engineTrackCount() && !seedNote;
             ++track) {
            const std::vector<DocNote> notes = session->b->document().notesForTrack(track);
            if (!notes.empty()) {
                view.selectTrack(track);
                view.selectionModel().setNoteSelection({notes.front().noteId});
                seedNote = notes.front();
            }
        }
        QVERIFY(seedNote.has_value());
        QVERIFY(copy->isEnabled() && solo->isEnabled());
        const QList<QKeySequence> copyBindings = copy->shortcuts();
        const QList<QKeySequence> soloBindings = solo->shortcuts();
        QVERIFY(!copyBindings.isEmpty() && !soloBindings.isEmpty());
        const int track = view.selectionModel().primaryTrack();
        view.setTrackSolo(track, false);
        const QByteArray beforeB = session->b->document().smf().write();
        const QByteArray beforeA = session->a->document().smf().write();
        QSignalSpy copyTriggered(copy, &QAction::triggered);
        QSignalSpy soloTriggered(solo, &QAction::triggered);

        QWidget foreign;
        foreign.setWindowTitle(QStringLiteral("foreign probe"));
        QLineEdit foreignText(&foreign);
        foreignText.setText(QStringLiteral("foreign draft"));
        foreignText.selectAll();
        foreign.show();
        foreignText.setFocus(Qt::OtherFocusReason);
        const auto foreignActive =
            checks::async_wait::waitUntil([] { return true; },
                                          [&foreign] {
                                              foreign.activateWindow();
                                              foreign.raise();
                                              return foreign.isActiveWindow();
                                          },
                                          5000, 1);
        QVERIFY2(foreignActive == checks::async_wait::Result::Ready,
                 "Cocoa did not activate the foreign window");
        QCOMPARE(QApplication::focusWidget(), &foreignText);

        // The Copy binding stays with the field's own text; the window Copy
        // owner never sees the foreign delivery.
        QApplication::clipboard()->clear();
        sendShortcut(foreignText, copyBindings.front());
        QCOMPARE(QApplication::clipboard()->text(), QStringLiteral("foreign draft"));
        QCOMPARE(copyTriggered.count(), 0);
        // Ordinary keys stay local to the field: typing replaces the selected
        // field text while both songs stay untouched.
        checks::events::sendKey(foreignText, QEvent::KeyPress, Qt::Key_X, Qt::NoModifier,
                                QStringLiteral("x"), false, 1);
        checks::events::sendKey(foreignText, QEvent::KeyRelease, Qt::Key_X, Qt::NoModifier,
                                QStringLiteral("x"), false, 1);
        QCOMPARE(foreignText.text(), QStringLiteral("x"));
        sendShortcut(foreignText, soloBindings.front());
        QCOMPARE(soloTriggered.count(), 0);
        QVERIFY(!view.trackSoloed(track));
        QCOMPARE(session->b->document().smf().write(), beforeB);
        QCOMPARE(session->a->document().smf().write(), beforeA);

        // Protected popup input stays local on the same native shell: the
        // Insert Time prompt owns its command bindings while it is open.
        foreign.hide();
        const auto reactivated = checks::async_wait::waitUntil([] { return true; },
                                                               [&window] {
                                                                   window.activateWindow();
                                                                   window.raise();
                                                                   return window.isActiveWindow();
                                                               },
                                                               5000, 1);
        QVERIFY2(reactivated == checks::async_wait::Result::Ready,
                 "Cocoa did not reactivate MainWindow after the foreign window hid");
        QVERIFY(window.m_insertTimeAction && window.m_insertTimeAction->isEnabled());
        QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
                 "the Roll band could not take focus before the Insert Time prompt");
        window.m_insertTimeAction->trigger();
        songview::QuickPopupSession *popup = quick_popup::popupSession(view);
        QTRY_VERIFY(popup && popup->isOpen() && popup->window());
        QTRY_VERIFY(
            quick_popup::inputHasActiveFocus(*popup->window(), QLatin1String("insertTimeBars")));
        sendShortcut(*popup->window(), soloBindings.front());
        QVERIFY2(popup->isOpen() && soloTriggered.count() == 0 && !view.trackSoloed(track),
                 "a window command fired while the Insert Time prompt owned the keys");
        sendShortcut(*popup->window(), copyBindings.front());
        QVERIFY2(popup->isOpen() && copyTriggered.count() == 0,
                 "window Copy fired while the Insert Time prompt owned the keys");
        QTest::keyClick(popup->window(), Qt::Key_Escape);
        QTRY_VERIFY(!popup->isOpen());
        QCOMPARE(session->b->document().smf().write(), beforeB);
        QCOMPARE(session->a->document().smf().write(), beforeA);
    }

    // Destroying the bound SongView without an external unbind: the tab-hide
    // cancels the prompt while the closing view is still bound, and the
    // destructor's unbind follows in the same synchronous stack — no input
    // can land between them. The durable contract is sole post-close
    // ownership: the surviving tab is the only target and stays actionable.
    void nativeBoundViewTeardownUnbindsActions()
    {
        if (QApplication::platformName() != QLatin1String("cocoa"))
            QSKIP("requires the Cocoa WindowSystem backend");
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab *closing = session->b;
        const SongName closingName = closing->name();
        SongView &view = closing->view();
        QCOMPARE(window.m_editActions->target(), &view);
        QAction *solo = window.m_soloAction;
        QVERIFY(solo && solo->isEnabled());
        window.m_workspace->selectSongTab(closing);
        QVERIFY2(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason),
                 "the Roll band could not take focus before the Insert Time prompt");
        QVERIFY(window.m_insertTimeAction && window.m_insertTimeAction->isEnabled());
        window.m_insertTimeAction->trigger();
        songview::QuickPopupSession *popup = quick_popup::popupSession(view);
        QTRY_VERIFY(popup && popup->isOpen());
        bool observed = false;
        QSignalSpy soloTriggered(solo, &QAction::triggered);
        QObject::connect(popup, &songview::QuickPopupSession::cancelled, &window,
                         [&] { observed = true; });
        window.m_workspace->requestCloseSelectedTab();
        QCoreApplication::processEvents();
        QVERIFY2(!QApplication::activeModalWidget(),
                 "closing a clean tab produced an unexpected modal prompt");
        QVERIFY2(observed, "the open popup was not cancelled during the bound view's teardown");
        QCOMPARE(soloTriggered.count(), 0);
        QVERIFY2(window.m_workspace->songTabFor(closingName) == nullptr,
                 "the clean tab did not close");
        QCOMPARE(window.m_editActions->target(), &session->a->view());
        QVERIFY(solo->isEnabled());
    }

    // Offscreen lifecycle owns byte and snapshot boundaries; this native case verifies
    // the Cocoa modal delivery keeps the existing live tab interactive.
    void nativeFailedProjectDialogPreservesLiveTab()
    {
        if (QApplication::platformName() != QLatin1String("cocoa"))
            QSKIP("requires the Cocoa WindowSystem backend");
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab *old = session->b;
        const qsizetype count = window.m_workspace->openTabCount();
        const QString label = old->document().label();
        QVERIFY(!old->document().isDirty());
        window.m_workspace->requestSongOpen(old->name());
        window.m_workspace->requestProjectOpenAt(session->fixture->root() +
                                                 QStringLiteral("/missing-native-project"));
        const auto failed = [&window] {
            if (QPointer<QMessageBox> box =
                    qobject_cast<QMessageBox *>(QApplication::activeModalWidget());
                box && !box->property("dismissalQueued").toBool()) {
                box->setProperty("dismissalQueued", true);
                QTimer::singleShot(0, box, [box] { box->reject(); });
            }
            return window.m_workspace->projectState().state == ProjectOpenState::Failed;
        };
        QCOMPARE(checks::async_wait::waitUntil([] { return true; }, failed, 30000, 1),
                 checks::async_wait::Result::Ready);
        QCOMPARE(window.m_workspace->selectedSongTab(), old);
        QCOMPARE(window.m_workspace->openTabCount(), count);
        QCOMPARE(window.m_workspace->projectState().snapshot.root(), session->fixture->root());
        QVERIFY(waitForTabReady(*window.m_workspace, old));
        QCOMPARE(old->document().label(), label);
    }

  private:
    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
};

int runMainWindowRoutingNativeCheck(const QString &projectRoot, const QString &songA,
                                    const QString &songB, const QStringList &qtArguments)
{
    MainWindowRoutingNativeTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("mainwindow-routing-native")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace checks::mainwindowrouting

#include "tst_mainwindowrouting_native.moc"
