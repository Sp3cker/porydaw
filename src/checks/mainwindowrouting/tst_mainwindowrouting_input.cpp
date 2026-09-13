#include "mainwindowroutingfixture.h"

#include "checks/clipcheck_support.h"
#include "checks/quickpopupguard.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/timeruler.h"
#include <QDockWidget>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

namespace {

struct InsertTimePromptSession {
    QQuickWindow *window = nullptr;
    songview::QuickPopupSession *popup = nullptr;
    QString diagnostic = QStringLiteral("the Insert Time prompt did not open");
};

InsertTimePromptSession openedInsertTimePrompt(SongView &view)
{
    InsertTimePromptSession session;
    songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
    if (!popup || !popup->isOpen() || !popup->window()) {
        session.diagnostic =
            QStringLiteral("the Insert Time action did not open its canvas prompt");
        return session;
    }
    session.popup = popup;
    session.window = popup->window();
    if (!quick_popup::promptItem(*popup, QLatin1String("insertTimePrompt")) ||
        !quick_popup::promptItem(*popup, QLatin1String("insertTimeBars")) ||
        !quick_popup::promptItem(*popup, QLatin1String("insertTimeBeats")) ||
        !quick_popup::promptItem(*popup, QLatin1String("insertTimeBeatFractions"))) {
        session.diagnostic = QStringLiteral("the Insert Time prompt visual tree is incomplete");
        return session;
    }
    if (checks::async_wait::waitUntil([] { return true; },
                                      [&session] {
                                          return quick_popup::inputHasActiveFocus(
                                              *session.window, QLatin1String("insertTimeBars"));
                                      },
                                      5000, 10) != checks::async_wait::Result::Ready) {
        session.diagnostic = QStringLiteral("the Insert Time bars field did not take focus");
        return session;
    }
    session.diagnostic.clear();
    return session;
}

bool enterInsertTimeValues(QQuickWindow &window, const QKeySequence &bars,
                           const QKeySequence &beats, const QKeySequence &fractions)
{
    QTest::keySequence(&window, bars);
    QTest::keyClick(&window, Qt::Key_Tab);
    QCoreApplication::processEvents();
    if (!quick_popup::inputHasActiveFocus(window, QLatin1String("insertTimeBeats")))
        return false;

    QTest::keySequence(&window, beats);
    QTest::keyClick(&window, Qt::Key_Tab);
    QCoreApplication::processEvents();
    if (!quick_popup::inputHasActiveFocus(window, QLatin1String("insertTimeBeatFractions")))
        return false;

    QTest::keySequence(&window, fractions);
    QCoreApplication::processEvents();
    return quick_popup::inputHasActiveFocus(window, QLatin1String("insertTimeBeatFractions"));
}

uint8_t freeNoteKey(SongTab &tab, int track, uint64_t tick)
{
    for (int key = 0; key < 128; ++key) {
        DocNote existing;
        if (!tab.document().findNote(track, tick, uint8_t(key), &existing))
            return uint8_t(key);
    }
    return 0;
}
} // namespace

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

    void catalogueViewBindingsReachPersistentQuickFocus()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongView &view = session->b->view();
        const auto &keys = keymap::Registry::instance();
        QAction *const automation = window.m_automationDrawerAction;
        QAction *const velocity = window.m_velocityDrawerAction;
        QAction *const voiceChanges = window.m_voiceChangesDrawerAction;
        QVERIFY(window.m_polyDock);
        QAction *const polyphony = window.m_polyDock->toggleViewAction();
        QVERIFY(automation);
        QVERIFY(velocity);
        QVERIFY(voiceChanges);
        QVERIFY(polyphony);

        QCOMPARE(automation->shortcuts(), keys.sequences(QStringLiteral("view.automation_drawer")));
        QCOMPARE(velocity->shortcuts(), keys.sequences(QStringLiteral("view.velocity_drawer")));
        QCOMPARE(voiceChanges->shortcuts(),
                 keys.sequences(QStringLiteral("view.voice_changes_drawer")));
        QCOMPARE(polyphony->shortcuts(), keys.sequences(QStringLiteral("view.polyphony_debugger")));
        for (QAction *const action : {automation, velocity, voiceChanges, polyphony}) {
            QCOMPARE(action->shortcutContext(), Qt::WindowShortcut);
            QVERIFY(!action->shortcut().isEmpty());
        }
        QVERIFY(automation->toolTip().endsWith(
            QStringLiteral("(%1)").arg(automation->shortcut().toString(QKeySequence::NativeText))));
        QVERIFY(velocity->toolTip().endsWith(
            QStringLiteral("(%1)").arg(velocity->shortcut().toString(QKeySequence::NativeText))));
        QVERIFY(voiceChanges->toolTip().endsWith(QStringLiteral("(%1)").arg(
            voiceChanges->shortcut().toString(QKeySequence::NativeText))));

        songview::TimelineQuickView *const quick = view.quickView();
        QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
        QQuickItem *const velocityToggle = quick && quick->rootObject()
                                               ? quick->rootObject()->findChild<QQuickItem *>(
                                                     QStringLiteral("drawerVelocityToggle"))
                                               : nullptr;
        QVERIFY2(quickWindow && velocityToggle,
                 "the active tab's persistent velocity drawer toggle is unavailable");
        velocityToggle->forceActiveFocus(Qt::OtherFocusReason);
        QTRY_VERIFY(velocityToggle->hasActiveFocus());
        QCOMPARE(quickWindow->activeFocusItem(), velocityToggle);

        QSignalSpy automationTriggered(automation, &QAction::triggered);
        QSignalSpy velocityTriggered(velocity, &QAction::triggered);
        QSignalSpy voiceChangesTriggered(voiceChanges, &QAction::triggered);
        QSignalSpy polyphonyTriggered(polyphony, &QAction::triggered);

        QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::Automations));
        QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Velocity));
        QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
        QVERIFY(!window.m_polyDock->isVisible());
        sendShortcut(*quickWindow, automation->shortcut());
        QCOMPARE(automationTriggered.count(), 1);
        QVERIFY(view.drawerSectionVisible(EditorDrawerPage::Automations));
        sendShortcut(*quickWindow, velocity->shortcut());
        QCOMPARE(velocityTriggered.count(), 1);
        QVERIFY(!view.drawerSectionVisible(EditorDrawerPage::Velocity));
        sendShortcut(*quickWindow, voiceChanges->shortcut());
        QCOMPARE(voiceChangesTriggered.count(), 1);
        QVERIFY(view.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
        sendShortcut(*quickWindow, polyphony->shortcut());
        QCOMPARE(polyphonyTriggered.count(), 1);
        QVERIFY(window.m_polyDock->isVisible());
    }

    void copyActionRoutesCompleteClipAndTimeSelection()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        QAction *copy = window.m_copyAction;
        QVERIFY(copy);
        const QList<QKeySequence> bindings =
            keymap::Registry::instance().sequences(QStringLiteral("roll.copy"));

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
        QVERIFY(surface == session->b || session->b->isAncestorOf(surface));
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
        QAction *solo = window.m_soloAction;
        QVERIFY(solo);
        const QList<QKeySequence> bindings =
            keymap::Registry::instance().sequences(QStringLiteral("roll.solo_tracks"));
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
        QVERIFY(surface == session->b || session->b->isAncestorOf(surface));
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
        const int sourceTrack = view.selectionModel().primaryTrack();
        std::optional<DocNote> wholeSongNote;
        for (int track = 0; track < tab.document().engineTrackCount() && !wholeSongNote; ++track) {
            if (track == sourceTrack)
                continue;
            const std::vector<DocNote> notes = tab.document().notesForTrack(track);
            if (!notes.empty())
                wholeSongNote = notes.front();
        }
        QVERIFY(wholeSongNote.has_value());
        window.m_workspace->selectSongTab(&tab);
        QAction *action = window.m_insertTimeAction;
        QVERIFY(action);
        for (const EditorDrawerPage page :
             {EditorDrawerPage::Automations, EditorDrawerPage::Velocity,
              EditorDrawerPage::VoiceChanges})
            view.setDrawerSectionVisible(page, false);
        view.setEventListVisible(false);
        const quick_popup::PromptGuard guard(view);

        // The fixture's 24 PPQN supports a denominator-scaled one-tick beat,
        // so a nonzero quarter fraction must use ceiling rather than truncation.
        tab.document().setTimeSig(0, 3, 6);
        QTRY_VERIFY(view.grid().segmentAt(source->tick).beatTicks == uint64_t{1} &&
                    view.grid().segmentAt(source->tick).beatsPerBar == uint64_t{3});
        const songview::Grid::Segment segment = view.grid().segmentAt(source->tick);

        QString insertDiagnostic;
        const auto insert = [&](bool playing, const QKeySequence &bars, const QKeySequence &beats,
                                const QKeySequence &fractions, uint64_t expectedSpan,
                                bool acceptWithReturn) {
            const QByteArray before = tab.document().smf().write();
            const QByteArray inactiveBefore = session->a->document().smf().write();
            const int undoIndex = tab.document().undoStack()->index();
            const uint64_t revision = tab.document().revision();
            const auto rollback = [&tab, undoIndex] {
                while (tab.document().undoStack()->index() > undoIndex &&
                       tab.document().undoStack()->canUndo())
                    tab.document().undoStack()->undo();
            };
            if (!view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason)) {
                insertDiagnostic = QStringLiteral("the Roll input could not establish focus");
                return false;
            }
            if (checks::async_wait::waitUntil(
                    [] { return true; },
                    [&view] { return view.focusedTimelineBand() == songview::TimelineBand::Roll; },
                    5000, 10) != checks::async_wait::Result::Ready) {
                insertDiagnostic =
                    QStringLiteral("the Roll input did not retain focus before opening");
                return false;
            }
            const std::optional<songview::TimelineBand> origin = view.focusedTimelineBand();
            if (!origin) {
                insertDiagnostic = QStringLiteral("Insert Time had no focused timeline origin");
                return false;
            }
            // Insert Time anchors on the edit cursor in every transport
            // state: park the playhead away from it, and while playing let
            // the playhead keep advancing under the open form.
            const uint64_t playheadTick = source->tick == 0 ? segment.beatTicks : 0;
            if (playing) {
                view.setEditCursorTick(source->tick);
                view.setPlayheadSample(tab.timeline()->sampleForTick(playheadTick), true);
            } else {
                window.stopPlayback();
                view.setPlayheadSample(tab.timeline()->sampleForTick(playheadTick), false);
                view.commitEditCursor(source->tick);
            }
            if (view.editCursorTick() != source->tick ||
                uint64_t(view.playheadTick() + 0.5) == source->tick) {
                insertDiagnostic =
                    QStringLiteral("Insert Time could not separate the edit cursor and playhead");
                return false;
            }

            action->trigger();
            const InsertTimePromptSession opened = openedInsertTimePrompt(view);
            if (!opened.window) {
                insertDiagnostic = opened.diagnostic;
                return false;
            }
            QQuickItem *const barsInput =
                quick_popup::promptItem(*opened.popup, QLatin1String("insertTimeBars"));
            QQuickItem *const beatsInput =
                quick_popup::promptItem(*opened.popup, QLatin1String("insertTimeBeats"));
            QQuickItem *const fractionsInput =
                quick_popup::promptItem(*opened.popup, QLatin1String("insertTimeBeatFractions"));
            if (!barsInput || !beatsInput || !fractionsInput ||
                barsInput->property("text").toString() != QStringLiteral("1") ||
                beatsInput->property("text").toString() != QStringLiteral("0") ||
                fractionsInput->property("text").toString() != QStringLiteral("0")) {
                insertDiagnostic = QStringLiteral("the Insert Time visual defaults are incorrect");
                return false;
            }
            if (playing) {
                // The form captured the edit cursor at open; the advancing
                // playhead must not retarget the pending insertion.
                uint64_t advancedTick = playheadTick + segment.beatTicks;
                if (advancedTick == source->tick)
                    advancedTick += segment.beatTicks;
                view.setPlayheadSample(tab.timeline()->sampleForTick(advancedTick), true);
                if (uint64_t(view.playheadTick() + 0.5) == source->tick) {
                    insertDiagnostic = QStringLiteral(
                        "the advancing playhead did not move under the Insert Time form");
                    return false;
                }
            }

            if (!enterInsertTimeValues(*opened.window, bars, beats, fractions)) {
                insertDiagnostic =
                    QStringLiteral("Tab did not keep Insert Time editing inside the popup");
                return false;
            }
            if (acceptWithReturn)
                QTest::keyClick(opened.window, Qt::Key_Return);
            else if (!quick_popup::clickPromptButton(*opened.popup,
                                                     QLatin1String("insertTimeAccept"))) {
                insertDiagnostic = QStringLiteral("the Insert Time prompt has no OK button");
                return false;
            }
            QCoreApplication::processEvents();

            songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
            DocNote shifted;
            DocNote wholeSongShifted;
            const bool sourceFound = tab.document().findNote(source->noteId, &shifted);
            const bool wholeSongFound =
                tab.document().findNote(wholeSongNote->noteId, &wholeSongShifted);
            const int actualUndoIndex = tab.document().undoStack()->index();
            const int actualUndoCount = tab.document().undoStack()->count();
            const uint64_t actualRevision = tab.document().revision();
            const bool committed = popup && !popup->isOpen() && sourceFound && wholeSongFound &&
                                   actualUndoIndex == undoIndex + 1 &&
                                   actualRevision == revision + 1 &&
                                   shifted.tick == source->tick + expectedSpan &&
                                   wholeSongShifted.tick == wholeSongNote->tick + expectedSpan &&
                                   session->a->document().smf().write() == inactiveBefore;
            if (!committed) {
                rollback();
                insertDiagnostic =
                    QStringLiteral("Insert Time commit: source %1 expected %2, whole-song %3 "
                                   "expected %4, undo index %5 expected %6, undo count %7, "
                                   "revision %8 expected %9")
                        .arg(sourceFound ? QString::number(shifted.tick)
                                         : QStringLiteral("missing"))
                        .arg(source->tick + expectedSpan)
                        .arg(wholeSongFound ? QString::number(wholeSongShifted.tick)
                                            : QStringLiteral("missing"))
                        .arg(wholeSongNote->tick + expectedSpan)
                        .arg(actualUndoIndex)
                        .arg(undoIndex + 1)
                        .arg(actualUndoCount)
                        .arg(actualRevision)
                        .arg(revision + 1);
                return false;
            }
            const bool restored =
                checks::async_wait::waitUntil(
                    [] { return true; },
                    [&view, origin] { return view.focusedTimelineBand() == origin; }, 5000,
                    10) == checks::async_wait::Result::Ready;
            rollback();
            if (!restored || tab.document().smf().write() != before ||
                tab.document().undoStack()->index() != undoIndex ||
                session->a->document().smf().write() != inactiveBefore) {
                insertDiagnostic = QStringLiteral(
                    "Insert Time did not restore its timeline origin and undo bytes");
                return false;
            }
            return true;
        };

        QVERIFY2(insert(false, QKeySequence(Qt::Key_0), QKeySequence(Qt::Key_2),
                        QKeySequence(Qt::Key_0), 2 * segment.beatTicks, false),
                 qUtf8Printable(insertDiagnostic));
        QVERIFY2(insert(true, QKeySequence(Qt::Key_1), QKeySequence(Qt::Key_0),
                        QKeySequence(Qt::Key_0), segment.beatTicks * segment.beatsPerBar, false),
                 qUtf8Printable(insertDiagnostic));
        QVERIFY2(insert(true, QKeySequence(Qt::Key_0), QKeySequence(Qt::Key_0),
                        QKeySequence(Qt::Key_1), (segment.beatTicks + 3) / 4, true),
                 qUtf8Printable(insertDiagnostic));

        const QByteArray beforeZero = tab.document().smf().write();
        const QByteArray inactiveBeforeZero = session->a->document().smf().write();
        const int zeroUndo = tab.document().undoStack()->index();
        const int zeroUndoCount = tab.document().undoStack()->count();
        const uint64_t zeroRevision = tab.document().revision();
        window.stopPlayback();
        view.commitEditCursor(source->tick);
        action->trigger();
        const InsertTimePromptSession zero = openedInsertTimePrompt(view);
        QVERIFY2(zero.window && zero.popup, qUtf8Printable(zero.diagnostic));
        QVERIFY2(enterInsertTimeValues(*zero.window, QKeySequence(Qt::Key_0),
                                       QKeySequence(Qt::Key_0), QKeySequence(Qt::Key_0)),
                 "the zero-span Insert Time fields could not be edited");
        QVERIFY2(quick_popup::clickPromptButton(*zero.popup, QLatin1String("insertTimeAccept")),
                 "the zero-span Insert Time prompt has no OK button");
        QCoreApplication::processEvents();
        songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
        QVERIFY(popup && !popup->isOpen());
        QCOMPARE(tab.document().smf().write(), beforeZero);
        QCOMPARE(tab.document().undoStack()->index(), zeroUndo);
        QCOMPARE(tab.document().undoStack()->count(), zeroUndoCount);
        QCOMPARE(tab.document().revision(), zeroRevision);
        QCOMPARE(session->a->document().smf().write(), inactiveBeforeZero);

        const QByteArray beforeCancel = tab.document().smf().write();
        const int cancelUndo = tab.document().undoStack()->index();
        const uint64_t cancelRevision = tab.document().revision();
        action->trigger();
        const InsertTimePromptSession cancelled = openedInsertTimePrompt(view);
        QVERIFY2(cancelled.window && cancelled.popup, qUtf8Printable(cancelled.diagnostic));
        QVERIFY2(enterInsertTimeValues(*cancelled.window, QKeySequence(Qt::Key_1),
                                       QKeySequence(Qt::Key_0), QKeySequence(Qt::Key_0)),
                 "the cancellation Insert Time fields could not be edited");
        QVERIFY2(
            quick_popup::clickPromptButton(*cancelled.popup, QLatin1String("insertTimeCancel")),
            "the Insert Time prompt has no Cancel button");
        QCoreApplication::processEvents();
        QVERIFY(popup && !popup->isOpen());
        QCOMPARE(tab.document().smf().write(), beforeCancel);
        QCOMPARE(tab.document().undoStack()->index(), cancelUndo);
        QCOMPARE(tab.document().revision(), cancelRevision);

        action->trigger();
        const InsertTimePromptSession stale = openedInsertTimePrompt(view);
        QVERIFY2(stale.window && stale.popup, qUtf8Printable(stale.diagnostic));
        QVERIFY2(enterInsertTimeValues(*stale.window, QKeySequence(Qt::Key_1),
                                       QKeySequence(Qt::Key_0), QKeySequence(Qt::Key_1)),
                 "the stale Insert Time fields could not be edited");
        tab.document().setTimeSig(source->tick + 1, 3, 5);
        const QByteArray afterInterveningEdit = tab.document().smf().write();
        const int staleUndo = tab.document().undoStack()->index();
        const int staleUndoCount = tab.document().undoStack()->count();
        const uint64_t staleRevision = tab.document().revision();
        if (popup->isOpen())
            QVERIFY2(
                quick_popup::clickPromptButton(*stale.popup, QLatin1String("insertTimeAccept")),
                "the stale Insert Time prompt has no OK button");
        QCoreApplication::processEvents();
        QVERIFY(popup && !popup->isOpen());
        QCOMPARE(tab.document().smf().write(), afterInterveningEdit);
        QCOMPARE(tab.document().undoStack()->index(), staleUndo);
        QCOMPARE(tab.document().undoStack()->count(), staleUndoCount);
        QCOMPARE(tab.document().revision(), staleRevision);
        view.setPlayheadSample(0, false);
    }

    void insertTimeActionAnchorsSelectionDuringPlayback()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab &tab = *session->b;
        SongView &view = tab.view();
        QAction *action = window.m_insertTimeAction;
        QVERIFY(action);
        QVERIFY(action->isEnabled());

        const std::optional<DocNote> source = selectFirstNote(tab);
        QVERIFY(source.has_value());
        const int track = view.selectionModel().primaryTrack();
        const uint64_t span = tab.timeline()->ticksPerBeat;
        const uint64_t selectionStart = source->tick + span;
        const uint64_t selectionEnd = selectionStart + span;
        const uint8_t probeKey = freeNoteKey(tab, track, selectionEnd);
        tab.document().addNote(track, selectionEnd, probeKey, uint32_t(span), 80);
        DocNote probe;
        QVERIFY2(tab.document().findNote(track, selectionEnd, probeKey, &probe),
                 "could not seed the insert probe note");
        std::optional<DocNote> untouched;
        for (int candidate = 0; candidate < tab.document().engineTrackCount() && !untouched;
             ++candidate) {
            if (candidate == track)
                continue;
            const std::vector<DocNote> notes = tab.document().notesForTrack(candidate);
            if (!notes.empty())
                untouched = notes.front();
        }
        QVERIFY(untouched.has_value());

        window.m_workspace->selectSongTab(&tab);
        view.selectTrack(track);
        songview::EditorSelectionModel::TimeSelection selection;
        selection.startTick = selectionStart;
        selection.endTick = selectionEnd;
        view.selectionModel().setTimeSelection(selection);
        const QByteArray before = tab.document().smf().write();
        const QByteArray inactiveBefore = session->a->document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();
        const uint64_t revision = tab.document().revision();

        // Playback parks the playhead and edit cursor away from the selection
        // span: the unified command must anchor on the selection, not either.
        window.stopPlayback();
        view.requestPlayPauseFrom(source->tick);
        QCOMPARE(window.m_audio.transport(), Transport::Playing);
        QCOMPARE(view.editCursorTick(), source->tick);
        QVERIFY(view.playheadTick() < double(selectionStart));

        action->trigger();
        QCoreApplication::processEvents();
        songview::QuickPopupSession *popup = quick_popup::popupSession(view);
        QVERIFY(!popup || !popup->isOpen());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        QCOMPARE(tab.document().revision(), revision + 1);
        const songview::EditorSelectionModel::TimeSelection retained =
            view.selectionModel().timeSelection();
        QVERIFY(retained.active());
        QCOMPARE(retained.startTick, selectionStart);
        QCOMPARE(retained.endTick, selectionEnd);
        QCOMPARE(retained.scope, songview::EditorSelectionModel::TimeSelection::Tracks);
        QCOMPARE(view.editCursorTick(), selectionStart);
        DocNote probeAfter;
        QVERIFY(tab.document().findNote(probe.noteId, &probeAfter));
        QCOMPARE(probeAfter.tick, selectionEnd + span);
        QCOMPARE(probeAfter.key, probe.key);
        DocNote untouchedAfter;
        QVERIFY(tab.document().findNote(untouched->noteId, &untouchedAfter));
        QCOMPARE(untouchedAfter.tick, untouched->tick);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);

        window.stopPlayback();
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().smf().write(), before);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
        view.setPlayheadSample(0, false);
    }

    void insertTimeRulerMenuAnchorsEditCursor()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab &tab = *session->b;
        SongView &view = tab.view();
        window.m_workspace->selectSongTab(&tab);
        const std::optional<DocNote> source = selectFirstNote(tab);
        QVERIFY(source.has_value());
        view.selectionModel().clearTimeSelection();
        window.stopPlayback();

        auto *const quick =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        QVERIFY(quick && quick->rootObject());
        auto *const rulerInput = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRulerInput"));
        QVERIFY2(rulerInput, "could not find the time ruler Quick input");

        // The outside-selection ruler path commits the clicked tick as the
        // edit cursor before its menu opens; Insert Time then prompts at
        // that cursor rather than the playhead.
        const uint64_t rawTick = source->tick;
        const QPointF local(
            view.camera().displayX(double(rawTick), 0.0, rulerInput->devicePixelRatio()),
            (std::max)(1.0, rulerInput->height() * 0.75));
        QVERIFY2(rulerInput->bounds().contains(local),
                 "the ruler menu point is outside the live ruler input");
        checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, local, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, local, Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
        const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(view)};
        QVERIFY2(QTest::qWaitFor([&live] {
                     return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                            quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
                 }),
                 "the ruler right-click did not open the shared ruler menu");
        const uint64_t target = view.editCursorTick();
        QCOMPARE(target, view.grid().snapTick(double(rawTick)));
        songview::QuickMenuModel *const model =
            quick_popup::menuModel(*quick_popup::menuPanel(*live));
        const int insertRow = model->rowForId(int(songview::RulerMenuAction::InsertBlank));
        QVERIFY2(insertRow >= 0 && model->itemAt(insertRow)->enabled,
                 "the cursor ruler menu omitted an enabled Insert Time row");

        const QByteArray before = tab.document().smf().write();
        const QByteArray inactiveBefore = session->a->document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();
        const uint64_t revision = tab.document().revision();
        const uint64_t insertSpan = view.grid().segmentAt(target).beatTicks;

        QVERIFY2(quick_popup::clickMenuRow(*live, insertRow),
                 "the ruler Insert Time row did not receive a real click");
        const InsertTimePromptSession opened = openedInsertTimePrompt(view);
        QVERIFY2(opened.window && opened.popup, qUtf8Printable(opened.diagnostic));
        QVERIFY2(enterInsertTimeValues(*opened.window, QKeySequence(Qt::Key_0),
                                       QKeySequence(Qt::Key_1), QKeySequence(Qt::Key_0)),
                 "the ruler-flow Insert Time fields could not be edited");
        QVERIFY2(quick_popup::clickPromptButton(*opened.popup, QLatin1String("insertTimeAccept")),
                 "the ruler-flow Insert Time prompt has no OK button");
        QCoreApplication::processEvents();
        songview::QuickPopupSession *const popup = quick_popup::popupSession(view);
        QVERIFY(popup && !popup->isOpen());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        QCOMPARE(tab.document().revision(), revision + 1);
        DocNote shifted;
        QVERIFY(tab.document().findNote(source->noteId, &shifted));
        QCOMPARE(shifted.tick, source->tick + insertSpan);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
    }

    void deleteTimeActionRipplesScopedAndWholeSongSelections()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        SongTab &tab = *session->b;
        SongView &view = tab.view();
        QAction *action = window.m_deleteTimeAction;
        QVERIFY(action);
        QVERIFY(!action->isEnabled());

        const std::optional<DocNote> source = selectFirstNote(tab);
        QVERIFY(source.has_value());
        const int track = view.selectionModel().primaryTrack();
        const uint64_t span = tab.timeline()->ticksPerBeat;
        const uint64_t selectionStart = source->tick + span;
        const uint64_t selectionEnd = selectionStart + span;
        const uint64_t wholeEnd = selectionEnd + span;
        const uint8_t insideKey = freeNoteKey(tab, track, selectionStart);
        tab.document().addNote(track, selectionStart, insideKey, uint32_t(span), 80);
        DocNote inside;
        QVERIFY2(tab.document().findNote(track, selectionStart, insideKey, &inside),
                 "could not seed the removed-range probe note");
        const uint8_t laterKey = freeNoteKey(tab, track, wholeEnd);
        tab.document().addNote(track, wholeEnd, laterKey, uint32_t(span), 80);
        DocNote later;
        QVERIFY2(tab.document().findNote(track, wholeEnd, laterKey, &later),
                 "could not seed the later-event probe note");
        std::optional<DocNote> untouched;
        for (int candidate = 0; candidate < tab.document().engineTrackCount() && !untouched;
             ++candidate) {
            if (candidate == track)
                continue;
            const std::vector<DocNote> notes = tab.document().notesForTrack(candidate);
            if (!notes.empty())
                untouched = notes.front();
        }
        QVERIFY(untouched.has_value());
        const int untouchedTrack = untouched->engineTrack;
        const uint8_t excludedKey = freeNoteKey(tab, untouchedTrack, span);
        tab.document().addNote(untouchedTrack, span, excludedKey, uint32_t(span), 80);
        DocNote excluded;
        QVERIFY2(tab.document().findNote(untouchedTrack, span, excludedKey, &excluded),
                 "could not seed the excluded-track probe note");
        const uint8_t excludedLaterKey = freeNoteKey(tab, untouchedTrack, wholeEnd + span);
        tab.document().addNote(untouchedTrack, wholeEnd + span, excludedLaterKey, uint32_t(span),
                               80);
        DocNote excludedLater;
        QVERIFY2(tab.document().findNote(untouchedTrack, wholeEnd + span, excludedLaterKey,
                                         &excludedLater),
                 "could not seed the excluded later-event probe note");

        window.m_workspace->selectSongTab(&tab);
        const QByteArray before = tab.document().smf().write();
        const QByteArray inactiveBefore = session->a->document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();

        // Scoped ripple removal: in-range content goes, later events shift
        // left, the selection clears, and the cursor parks at the seam.
        view.selectTrack(track);
        songview::EditorSelectionModel::TimeSelection selection;
        selection.startTick = selectionStart;
        selection.endTick = selectionEnd;
        view.selectionModel().setTimeSelection(selection);
        QVERIFY(action->isEnabled());
        const uint64_t revision = tab.document().revision();
        action->trigger();
        QCoreApplication::processEvents();
        songview::QuickPopupSession *popup = quick_popup::popupSession(view);
        QVERIFY(!popup || !popup->isOpen());
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        QCOMPARE(tab.document().revision(), revision + 1);
        QVERIFY(!view.selectionModel().timeSelection().active());
        QCOMPARE(view.editCursorTick(), selectionStart);
        DocNote scratch;
        QVERIFY(!tab.document().findNote(inside.noteId, &scratch));
        DocNote laterAfter;
        QVERIFY(tab.document().findNote(later.noteId, &laterAfter));
        QCOMPARE(laterAfter.tick, selectionEnd);
        DocNote sourceAfter;
        QVERIFY(tab.document().findNote(source->noteId, &sourceAfter));
        QCOMPARE(sourceAfter.tick, source->tick);
        DocNote untouchedAfter;
        QVERIFY(tab.document().findNote(untouched->noteId, &untouchedAfter));
        QCOMPARE(untouchedAfter.tick, untouched->tick);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().smf().write(), before);

        // Whole-song routing: content outside the scoped case participates.
        uint32_t usedMask = 0;
        for (int candidate = 0; candidate < 16; ++candidate)
            if (tab.timeline()->tracks[candidate].used)
                usedMask |= 1u << candidate;
        QVERIFY(usedMask != 0);
        view.selectTrack(track);
        songview::EditorSelectionModel::TimeSelection whole;
        whole.startTick = 0;
        whole.endTick = wholeEnd;
        view.selectionModel().setTimeSelectionAndTrackScope(whole, 0xFFFFu);
        QVERIFY(view.selectionModel().timeSelection().active());
        QCOMPARE(view.selectionModel().storedTrackScope(), 0xFFFFu);
        QVERIFY(view.selectionModel().timeSelectionCoversTempo(usedMask));
        const uint64_t wholeRevision = tab.document().revision();
        action->trigger();
        QCoreApplication::processEvents();
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        QCOMPARE(tab.document().revision(), wholeRevision + 1);
        QVERIFY(!view.selectionModel().timeSelection().active());
        QCOMPARE(view.editCursorTick(), uint64_t{0});
        QVERIFY(!tab.document().findNote(source->noteId, &sourceAfter));
        QVERIFY(!tab.document().findNote(inside.noteId, &scratch));
        QVERIFY(!tab.document().findNote(excluded.noteId, &scratch));
        DocNote excludedLaterAfter;
        QVERIFY(tab.document().findNote(excludedLater.noteId, &excludedLaterAfter));
        QCOMPARE(excludedLaterAfter.tick, span);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
        tab.document().undoStack()->undo();
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().smf().write(), before);
        QCOMPARE(session->a->document().smf().write(), inactiveBefore);
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
