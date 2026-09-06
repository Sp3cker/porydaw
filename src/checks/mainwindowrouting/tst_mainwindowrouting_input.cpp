#include "mainwindowroutingfixture.h"

#include "checks/clipcheck_support.h"

#include <QtTest>

namespace checks::mainwindowrouting {

class MainWindowRoutingInputTest final : public QObject, private MainWindowRoutingFixture
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(MainWindowRoutingInputTest)

  public:
    MainWindowRoutingInputTest(QString projectRoot, QString songA, QString songB)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
        , m_songB(std::move(songB))
    {}

  private slots:
    void freshTabsWithholdReadinessAndAuditionFromTick()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB, false);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        QCOMPARE(window.m_workspace->openTabCount(), qsizetype{2});
        QVERIFY(session->a != session->b);
        QVERIFY(!session->a->isReady());
        QVERIFY(!session->b->isReady());
        QVERIFY(session->a->view().isEnabled());
        QVERIFY(session->b->view().isEnabled());
        QVERIFY(waitForTabReady(*window.m_workspace, session->a));
        QVERIFY(waitForTabReady(*window.m_workspace, session->b));

        constexpr uint64_t tick = 24;
        window.stopPlayback();
        session->b->view().commitEditCursor(0);
        session->b->view().requestPlayPauseFrom(tick);
        QCOMPARE(window.m_audio.transport(), Transport::Playing);
        QCOMPARE(session->b->view().editCursorTick(), tick);
        session->b->view().requestPlayPauseFrom(tick);
        QCOMPARE(window.m_audio.transport(), Transport::Paused);
        QCOMPARE(uint64_t(session->b->view().playheadTick() + 0.5), tick);
    }

    void copyActionRoutesCompleteClipAndTimeSelection()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        QMenu *menu = editMenu(window);
        QAction *copy = window.m_copyAction;
        QAction *insertTime = window.m_insertTimeAction;
        QVERIFY(menu);
        QVERIFY(copy);
        QVERIFY(insertTime);
        QCOMPARE(copy->parent(), &window);
        QCOMPARE(insertTime->parent(), &window);
        QVERIFY(menu->actions().contains(copy));
        QVERIFY(menu->actions().contains(insertTime));
        QCOMPARE(copy->shortcutContext(), Qt::WindowShortcut);
        QCOMPARE(insertTime->shortcutContext(), Qt::WindowShortcut);
        const QList<QKeySequence> bindings =
            keymap::Registry::instance().bindings(QStringLiteral("roll.copy"));
        QCOMPARE(copy->shortcuts(), bindings);
        QCOMPARE(insertTime->shortcuts(),
                 keymap::Registry::instance().bindings(QStringLiteral("edit.insert_time")));
        int owners = 0;
        for (QAction *action : window.findChildren<QAction *>()) {
            if (action->isEnabled() &&
                std::any_of(bindings.cbegin(), bindings.cend(), [action](const QKeySequence &key) {
                    return action->shortcuts().contains(key);
                }))
                ++owners;
        }
        QVERIFY(bindings.isEmpty() || owners == 1);

        const std::optional<DocNote> note = selectFirstNote(*session->b);
        QVERIFY(note.has_value());
        songview::EditorSelectionModel::TimeSelection time;
        time.startTick = 0;
        session->b->view().setPlayheadSample(session->b->timeline()->sampleForTick(24), false);
        auto *overlay = session->b->view().findChild<songview::PlayheadOverlay *>();
        QVERIFY(overlay);
        for (const EditorDrawerPage page :
             {EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
              EditorDrawerPage::VoiceChanges})
            session->b->view().setDrawerSectionVisible(page, false);
        QVERIFY(!session->b->view().hasVisibleDrawerSection());
        time.endTick = session->a->timeline()->ticksPerBeat;
        session->a->view().selectionModel().setTimeSelection(time);
        window.m_workspace->selectSongTab(session->b);
        session->b->view().focusActiveSurface();
        QCoreApplication::processEvents();
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents();
        QCOMPARE(session->b->view().focusedTimelineBand(), songview::TimelineBand::Roll);
        QWidget *surface = QApplication::focusWidget();
        QVERIFY(surface);
        QVERIFY(surface == &session->b->view() || session->b->view().isAncestorOf(surface));
        QVERIFY(!bindings.isEmpty());
        QSignalSpy triggered(copy, &QAction::triggered);
        const QKeyCombination key = bindings.front()[0];
        sendKey(*surface, key.key(), key.keyboardModifiers());
        QCOMPARE(triggered.count(), 1);
        const auto clip = clipcheck_support::checkClipboardClip();
        QVERIFY(clip.has_value());
        QCOMPARE(clip->ticksPerBeat, session->b->timeline()->ticksPerBeat);
        QCOMPARE(clip->clip.span, uint64_t{0});
        QCOMPARE(clip->clip.tracks.size(), size_t{1});
        QCOMPARE(clip->clip.tracks.front().notes.size(), size_t{1});
        QCOMPARE(clip->clip.tracks.front().notes.front().key, note->key);
        QCOMPARE(clip->clip.tracks.front().notes.front().velocity, note->velocity);

        window.m_workspace->selectSongTab(session->a);
        QCoreApplication::processEvents();
        QCoreApplication::sendPostedEvents();
        QCoreApplication::processEvents();
        copy->trigger();
        const auto timeClip = clipcheck_support::checkClipboardClip();
        QVERIFY(timeClip.has_value());
        QCOMPARE(timeClip->ticksPerBeat, session->a->timeline()->ticksPerBeat);
        QCOMPARE(timeClip->clip.span, time.endTick);

        QLineEdit text(&window);
        text.setText(QStringLiteral("copy probe"));
        text.selectAll();
        text.show();
        text.setFocus(Qt::OtherFocusReason);
        QCOMPARE(QApplication::focusWidget(), &text);
        QCOMPARE(text.selectedText(), QStringLiteral("copy probe"));
        QApplication::clipboard()->clear();
        sendShortcut(text, QKeySequence(QKeySequence::Copy));
        QCOMPARE(QApplication::clipboard()->text(), QStringLiteral("copy probe"));
    }

    void soloActionUsesSingleWindowOwnerAndRespectsTextFocus()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        QMenu *menu = editMenu(window);
        QAction *solo = window.m_soloAction;
        QVERIFY(menu);
        QVERIFY(solo);
        QCOMPARE(solo->parent(), &window);
        QVERIFY(menu->actions().contains(solo));
        QCOMPARE(solo->shortcutContext(), Qt::WindowShortcut);
        const QList<QKeySequence> bindings =
            keymap::Registry::instance().bindings(QStringLiteral("roll.solo_tracks"));
        QCOMPARE(solo->shortcuts(), bindings);
        QVERIFY(!bindings.isEmpty());
        const int track = session->b->view().selectionModel().primaryTrack();
        session->b->view().setTrackSolo(track, false);
        window.m_workspace->selectSongTab(session->b);
        QSignalSpy triggered(solo, &QAction::triggered);
        const QKeyCombination key = bindings.front()[0];
        window.menuBar()->setFocus();
        sendKey(*window.menuBar(), key.key(), key.keyboardModifiers());
        QVERIFY(session->b->view().trackSoloed(track));
        QCOMPARE(triggered.count(), 1);
        sendKey(*window.menuBar(), key.key(), key.keyboardModifiers());
        QVERIFY(!session->b->view().trackSoloed(track));
        QCOMPARE(triggered.count(), 2);
        session->b->view().focusActiveSurface();
        QWidget *surface = QApplication::focusWidget();
        QVERIFY(surface);
        QVERIFY(surface == &session->b->view() || session->b->view().isAncestorOf(surface));
        sendKey(*surface, key.key(), key.keyboardModifiers());
        QVERIFY(session->b->view().trackSoloed(track));
        QCOMPARE(triggered.count(), 3);
        sendKey(*surface, key.key(), key.keyboardModifiers());
        QVERIFY(!session->b->view().trackSoloed(track));
        QCOMPARE(triggered.count(), 4);
        QLineEdit text(&window);
        text.show();
        text.setFocus();
        sendKey(text, key.key(), key.keyboardModifiers());
        QVERIFY(!session->b->view().trackSoloed(track));
        QCOMPARE(triggered.count(), 4);
    }

    void insertTimeRoutesActiveSongAndRestoresUndoBytes()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab &tab = *session->b;
        SongView &view = tab.view();
        const std::optional<DocNote> source = selectFirstNote(tab);
        QVERIFY(source.has_value());
        window.m_workspace->selectSongTab(&tab);
        QAction *action = window.m_insertTimeAction;
        QVERIFY(action);
        const auto insert = [&](bool playing, int bars, int beats, int fractions,
                                uint64_t expectedSpan) {
            const QByteArray before = tab.document().smf().write();
            const int undoIndex = tab.document().undoStack()->index();
            const uint64_t cursor = playing ? source->tick : uint64_t{0};
            view.setPlayheadSample(tab.timeline()->sampleForTick(cursor), playing);
            if (!playing)
                view.commitEditCursor(source->tick);
            bool foundShape = false;
            QTimer dialogWaiter;
            QTimer::singleShot(0, &dialogWaiter, [&foundShape, bars, beats, fractions] {
                auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
                auto *barsSpin =
                    dialog ? dialog->findChild<DragSpinBox *>(QStringLiteral("insertTimeBars"))
                           : nullptr;
                auto *beatsSpin =
                    dialog ? dialog->findChild<DragSpinBox *>(QStringLiteral("insertTimeBeats"))
                           : nullptr;
                auto *fractionsSpin = dialog ? dialog->findChild<DragSpinBox *>(
                                                   QStringLiteral("insertTimeBeatFractions"))
                                             : nullptr;
                foundShape = dialog && barsSpin && beatsSpin && fractionsSpin;
                if (!foundShape) {
                    if (dialog)
                        dialog->reject();
                    return;
                }
                barsSpin->setValue(bars);
                beatsSpin->setValue(beats);
                fractionsSpin->setValue(fractions);
                dialog->accept();
            });
            action->trigger();
            QVERIFY2(foundShape,
                     "Insert Time dialog is missing its three required DragSpinBox fields");
            DocNote shifted;
            QVERIFY(tab.document().findNote(source->noteId, &shifted));
            QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
            QCOMPARE(shifted.tick, source->tick + expectedSpan);
            tab.document().undoStack()->undo();
            QCOMPARE(tab.document().smf().write(), before);
        };
        const songview::Grid::Segment segment = view.grid().segmentAt(source->tick);
        insert(false, 0, 2, 0, 2 * segment.beatTicks);
        insert(true, 1, 0, 0, segment.beatTicks * segment.beatsPerBar);
        insert(true, 0, 0, 2, (2 * segment.beatTicks + 3) / 4);
        view.setPlayheadSample(0, false);
    }

  private:
    QString m_projectRoot;
    QString m_songA;
    QString m_songB;
};

int runMainWindowRoutingInputCheck(const QString &projectRoot, const QString &songA,
                                   const QString &songB, const QStringList &qtArguments)
{
    MainWindowRoutingInputTest test(projectRoot, songA, songB);
    QStringList arguments{QStringLiteral("mainwindow-routing-input")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

} // namespace checks::mainwindowrouting

#include "tst_mainwindowrouting_input.moc"
