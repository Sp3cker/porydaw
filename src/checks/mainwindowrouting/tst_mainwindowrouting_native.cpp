#include "mainwindowroutingfixture.h"

#include "checks/clipcheck_support.h"
#include "checks/quickpopupguard.h"
#include <QPoint>
#include <QScopeGuard>

#include <QtTest>

uint8_t freeNoteKey(SongTab &tab, int track, uint64_t tick)
{
    for (int key = 0; key < 128; ++key) {
        DocNote existing;
        if (!tab.document().findNote(track, tick, uint8_t(key), &existing))
            return uint8_t(key);
    }
    return 0;
}

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
        QAction *insertTime = window.m_insertTimeAction;
        QVERIFY(copy);
        QVERIFY(solo);
        QVERIFY(insertTime);
        menu->popup(window.mapToGlobal(QPoint(12, 12)));
        QTRY_VERIFY(menu->isVisible());
        menu->hide();
        QCOMPARE(copy->parent(), &window);
        QCOMPARE(solo->parent(), &window);
        QCOMPARE(insertTime->parent(), &window);
        QVERIFY(menu->actions().contains(copy));
        QVERIFY(menu->actions().contains(solo));
        QVERIFY(menu->actions().contains(insertTime));
        QCOMPARE(copy->shortcutContext(), Qt::WindowShortcut);
        QCOMPARE(solo->shortcutContext(), Qt::WindowShortcut);
        QCOMPARE(insertTime->shortcutContext(), Qt::WindowShortcut);
        QCOMPARE(copy->shortcuts(),
                 keymap::Registry::instance().bindings(QStringLiteral("roll.copy")));
        QCOMPARE(solo->shortcuts(),
                 keymap::Registry::instance().bindings(QStringLiteral("roll.solo_tracks")));
        QCOMPARE(insertTime->shortcuts(),
                 keymap::Registry::instance().bindings(QStringLiteral("edit.insert_time")));

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

        QLineEdit text(&window);
        text.setText(QStringLiteral("native copy text probe"));
        text.selectAll();
        text.show();
        text.setFocus();
        QCoreApplication::processEvents();
        copy->trigger();
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

    // Dedicated native proof for window time editing: the configured Insert
    // shortcut commits exactly one selection-span transaction, ordinary Delete
    // only clears contents, the Edit menu row and a temporarily rebound
    // registry shortcut both dispatch ripple removal, and text plus
    // prompt-local input keep their keys instead of invoking a time edit.
    void nativeTimeEditingDispatchAndLocalInput()
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
        QAction *insertTime = window.m_insertTimeAction;
        QAction *deleteTime = window.m_deleteTimeAction;
        QVERIFY(insertTime);
        QVERIFY(deleteTime);
        QVERIFY(menu->actions().contains(insertTime));
        QVERIFY(menu->actions().contains(deleteTime));
        QCOMPARE(deleteTime->shortcutContext(), Qt::WindowShortcut);

        SongTab &tab = *session->b;
        SongView &view = tab.view();
        const std::optional<DocNote> source = selectFirstNote(tab);
        QVERIFY(source.has_value());
        const int track = view.selectionModel().primaryTrack();
        const uint64_t span = tab.timeline()->ticksPerBeat;
        const uint64_t selectionStart = source->tick + span;
        const uint64_t selectionEnd = selectionStart + span;
        const uint8_t insertProbeKey = freeNoteKey(tab, track, selectionEnd);
        tab.document().addNote(track, selectionEnd, insertProbeKey, uint32_t(span), 80);
        DocNote insertProbe;
        QVERIFY(tab.document().findNote(track, selectionEnd, insertProbeKey, &insertProbe));
        const uint8_t insideKey = freeNoteKey(tab, track, selectionStart);
        tab.document().addNote(track, selectionStart, insideKey, uint32_t(span), 80);
        DocNote inside;
        QVERIFY(tab.document().findNote(track, selectionStart, insideKey, &inside));
        const uint8_t laterKey = freeNoteKey(tab, track, selectionEnd + span);
        tab.document().addNote(track, selectionEnd + span, laterKey, uint32_t(span), 80);
        DocNote later;
        QVERIFY(tab.document().findNote(track, selectionEnd + span, laterKey, &later));

        window.m_workspace->selectSongTab(session->b);
        const QByteArray before = tab.document().smf().write();
        const QByteArray inactiveBefore = session->a->document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();
        const auto selectSpan = [&view, track, selectionStart, selectionEnd] {
            view.selectTrack(track);
            songview::EditorSelectionModel::TimeSelection selection;
            selection.startTick = selectionStart;
            selection.endTick = selectionEnd;
            view.selectionModel().setTimeSelection(selection);
        };

        // The configured Insert shortcut runs the selection-first command
        // through real input dispatch: one trigger, one undo transaction, no
        // duration prompt.
        const QList<QKeySequence> insertBindings = insertTime->shortcuts();
        QVERIFY(!insertBindings.isEmpty());
        selectSpan();
        view.focusActiveSurface();
        QCoreApplication::processEvents();
        QWidget *target = QApplication::focusWidget();
        QVERIFY(target && (target == session->b || session->b->isAncestorOf(target)));
        QSignalSpy insertTriggered(insertTime, &QAction::triggered);
        sendShortcut(*target, insertBindings.front());
        QCOMPARE(insertTriggered.count(), 1);
        songview::QuickPopupSession *popup = quick_popup::popupSession(view);
        QVERIFY(!popup || !popup->isOpen());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        DocNote insertProbeAfter;
        QVERIFY(tab.document().findNote(insertProbe.noteId, &insertProbeAfter));
        QCOMPARE(insertProbeAfter.tick, selectionEnd + span);
        QCOMPARE(view.editCursorTick(), selectionStart);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);

        // Ordinary Delete only clears the span's contents: the interval stays
        // open and later events keep their positions.
        selectSpan();
        view.focusActiveSurface();
        QCoreApplication::processEvents();
        target = QApplication::focusWidget();
        QVERIFY(target && (target == session->b || session->b->isAncestorOf(target)));
        sendKey(*target, Qt::Key_Delete);
        QCoreApplication::processEvents();
        DocNote scratch;
        QVERIFY(!tab.document().findNote(inside.noteId, &scratch));
        DocNote laterAfter;
        QVERIFY(tab.document().findNote(later.noteId, &laterAfter));
        QCOMPARE(laterAfter.tick, later.tick);
        QVERIFY(view.selectionModel().timeSelection().active());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);

        // The real Edit menu row routes ripple removal into the selected tab.
        selectSpan();
        menu->popup(window.mapToGlobal(QPoint(12, 12)));
        QTRY_VERIFY(menu->isVisible());
        QVERIFY(deleteTime->isEnabled());
        const QRect deleteRow = menu->actionGeometry(deleteTime);
        QVERIFY(deleteRow.isValid());
        QTest::mouseClick(menu, Qt::LeftButton, Qt::NoModifier, deleteRow.center());
        QTRY_VERIFY(!menu->isVisible());
        QVERIFY(!view.selectionModel().timeSelection().active());
        QCOMPARE(view.editCursorTick(), selectionStart);
        QVERIFY(!tab.document().findNote(inside.noteId, &scratch));
        QVERIFY(tab.document().findNote(later.noteId, &laterAfter));
        QCOMPARE(laterAfter.tick, selectionEnd);
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);

        // A temporarily rebound registry shortcut dispatches the same command;
        // the guard restores the binding even on early assertion exits.
        auto &registry = keymap::Registry::instance();
        const keymap::Registry::OverrideSnapshot overrides = registry.snapshotOverrides();
        const QKeySequence rebound(QStringLiteral("Ctrl+Alt+K"));
        registry.setBinding(QStringLiteral("edit.delete_time"), rebound);
        auto restoreBindings =
            qScopeGuard([&registry, overrides] { registry.restoreOverrides(overrides); });
        QCOMPARE(deleteTime->shortcuts(), QList<QKeySequence>{rebound});
        selectSpan();
        QWidget shortcutTarget(&window);
        shortcutTarget.setFocusPolicy(Qt::StrongFocus);
        shortcutTarget.show();
        shortcutTarget.setFocus(Qt::OtherFocusReason);
        QCoreApplication::processEvents();
        QCOMPARE(QApplication::focusWidget(), &shortcutTarget);
        QSignalSpy deleteTriggered(deleteTime, &QAction::triggered);
        sendShortcut(shortcutTarget, rebound);
        QCOMPARE(deleteTriggered.count(), 1);
        QVERIFY(!view.selectionModel().timeSelection().active());
        QCOMPARE(view.editCursorTick(), selectionStart);
        QVERIFY(!tab.document().findNote(inside.noteId, &scratch));
        QVERIFY(tab.document().findNote(later.noteId, &laterAfter));
        QCOMPARE(laterAfter.tick, selectionEnd);
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);

        // While the rebound binding is live, focused text input keeps the
        // chord local instead of deleting time.
        QLineEdit text(&window);
        text.setText(QStringLiteral("local probe"));
        text.show();
        text.setFocus(Qt::OtherFocusReason);
        QCoreApplication::processEvents();
        QCOMPARE(QApplication::focusWidget(), &text);
        sendShortcut(text, rebound);
        QCOMPARE(deleteTriggered.count(), 1);
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().smf().write(), before);
        QCOMPARE(text.text(), QStringLiteral("local probe"));

        registry.restoreOverrides(overrides);
        restoreBindings.dismiss();
        QCOMPARE(deleteTime->shortcuts(),
                 keymap::Registry::instance().bindings(QStringLiteral("edit.delete_time")));

        // Restored ownership: the configured Insert chord stays local to text
        // and to the open prompt instead of invoking another time edit.
        text.setFocus(Qt::OtherFocusReason);
        QCoreApplication::processEvents();
        QCOMPARE(QApplication::focusWidget(), &text);
        QSignalSpy localInsert(insertTime, &QAction::triggered);
        sendShortcut(text, insertBindings.front());
        QCOMPARE(localInsert.count(), 0);
        popup = quick_popup::popupSession(view);
        QVERIFY(!popup || !popup->isOpen());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().smf().write(), before);

        insertTime->trigger();
        popup = quick_popup::popupSession(view);
        QVERIFY2(popup && popup->isOpen(), "the Insert Time prompt did not open");
        if (checks::async_wait::waitUntil([] { return true; },
                                          [&popup] {
                                              return quick_popup::inputHasActiveFocus(
                                                  *popup->window(),
                                                  QLatin1String("insertTimeBars"));
                                          },
                                          5000, 10) != checks::async_wait::Result::Ready)
            QFAIL("the Insert Time bars field did not take focus");
        QCOMPARE(localInsert.count(), 1);
        sendShortcut(*popup->window(), insertBindings.front());
        QCOMPARE(localInsert.count(), 1);
        QVERIFY(popup->isOpen());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().smf().write(), before);
        {
            quick_popup::PromptGuard guard(view);
        }
        QCoreApplication::processEvents();
        popup = quick_popup::popupSession(view);
        QVERIFY(!popup || !popup->isOpen());
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
