#include "mainwindowroutingfixture.h"

#include "checks/clipcheck_support.h"
#include <QPoint>

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
        QVERIFY(session->hostWindow);
        QVERIFY(view.focusedTimelineBand().has_value());
        QVERIFY(session->hostWindow->activeFocusItem());
        const QList<QKeySequence> copyBindings = copy->shortcuts();
        QVERIFY(!copyBindings.isEmpty());
        QSignalSpy copyTriggered(copy, &QAction::triggered);
        sendShortcut(surfaceKeyTarget(*session), copyBindings.front());
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
        QCoreApplication::processEvents();
        QVERIFY(view.focusedTimelineBand().has_value());
        QVERIFY(session->hostWindow->activeFocusItem());
        sendShortcut(surfaceKeyTarget(*session), soloBindings.front());
        QVERIFY(view.trackSoloed(selectedTrack));
        QCOMPARE(soloTriggered.count(), 3);
        sendShortcut(surfaceKeyTarget(*session), soloBindings.front());
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
