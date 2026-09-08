#include "mainwindowroutingfixture.h"

#include "checks/clipcheck_support.h"
#include "checks/quickpopupguard.h"
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

// Menu-bar mode is read while a QMenuBar is constructed, so widget-menu
// coverage builds its own MainWindow under the scoped attribute instead of
// toggling an already-created native menu at runtime.
class ScopedApplicationAttribute final
{
  public:
    ScopedApplicationAttribute(Qt::ApplicationAttribute attribute, bool set)
        : m_attribute(attribute)
        , m_wasSet(QCoreApplication::testAttribute(attribute))
    {
        QCoreApplication::setAttribute(attribute, set);
    }
    ~ScopedApplicationAttribute() { QCoreApplication::setAttribute(m_attribute, m_wasSet); }
    ScopedApplicationAttribute(const ScopedApplicationAttribute &) = delete;
    ScopedApplicationAttribute &operator=(const ScopedApplicationAttribute &) = delete;

  private:
    Qt::ApplicationAttribute m_attribute;
    bool m_wasSet;
};

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
            if (playing)
                view.setPlayheadSample(tab.timeline()->sampleForTick(source->tick), true);
            else {
                window.stopPlayback();
                view.setPlayheadSample(tab.timeline()->sampleForTick(source->tick), false);
                view.commitEditCursor(source->tick);
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

    // 6.7.1-2: both adapters live in the Edit menu after Copy with their
    // mnemonics, belong to the window, carry no shortcut, and enable only
    // for a ready selected tab with a nonempty note selection — before any
    // song exists, while readiness is pending, and the moment a selection
    // appears or clears.
    void noteLengthActionsExistAndEnableFromSelection()
    {
        {
            SettingsGuard settings;
            auto emptyWindow = std::make_unique<MainWindow>();
            if (!emptyWindow->m_audioOk)
                QSKIP("audio backend unavailable");
            QAction *lengthen = emptyWindow->m_lengthenNoteAction;
            QAction *shorten = emptyWindow->m_shortenNoteAction;
            QVERIFY(lengthen && shorten);
            QCOMPARE(editAction(*emptyWindow, QStringLiteral("lengthenNoteWindowAction")),
                     lengthen);
            QCOMPARE(editAction(*emptyWindow, QStringLiteral("shortenNoteWindowAction")), shorten);
            QVERIFY(!lengthen->isEnabled());
            QVERIFY(!shorten->isEnabled());
            QVERIFY(lengthen->shortcuts().isEmpty());
            QVERIFY(shorten->shortcuts().isEmpty());
        }

        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB, false);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        QMenu *menu = editMenu(window);
        QAction *lengthen = window.m_lengthenNoteAction;
        QAction *shorten = window.m_shortenNoteAction;
        QVERIFY(menu);
        QVERIFY(lengthen && shorten);
        QCOMPARE(lengthen->parent(), &window);
        QCOMPARE(shorten->parent(), &window);
        QVERIFY(menu->actions().contains(lengthen));
        QVERIFY(menu->actions().contains(shorten));
        QCOMPARE(editAction(window, QStringLiteral("lengthenNoteWindowAction")), lengthen);
        QCOMPARE(editAction(window, QStringLiteral("shortenNoteWindowAction")), shorten);
        const QList<QAction *> rows = menu->actions();
        QVERIFY(rows.indexOf(window.m_copyAction) < rows.indexOf(lengthen));
        QVERIFY(rows.indexOf(lengthen) < rows.indexOf(shorten));
        QVERIFY(rows.indexOf(shorten) < rows.indexOf(window.m_insertTimeAction));
        QVERIFY(lengthen->shortcuts().isEmpty());
        QVERIFY(shorten->shortcuts().isEmpty());
        QCOMPARE(bareTitle(lengthen), QStringLiteral("&Lengthen Note"));
        QCOMPARE(bareTitle(shorten), QStringLiteral("Sho&rten Note"));
        if (window.menuBar()->isNativeMenuBar()) {
            QVERIFY(!lengthen->text().contains(u'\t'));
            QVERIFY(!shorten->text().contains(u'\t'));
        }

        QVERIFY(!lengthen->isEnabled());
        QVERIFY(!shorten->isEnabled());
        QVERIFY(waitForTabReady(*window.m_workspace, session->a));
        QVERIFY(waitForTabReady(*window.m_workspace, session->b));
        window.m_workspace->selectSongTab(session->b);
        QVERIFY(!lengthen->isEnabled());
        QVERIFY(!shorten->isEnabled());

        const std::optional<DocNote> note = selectFirstNote(*session->b);
        QVERIFY(note.has_value());
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());
        session->b->view().selectionModel().clearNoteSelection();
        QVERIFY(!lengthen->isEnabled());
        QVERIFY(!shorten->isEnabled());
        session->b->view().selectionModel().setNoteSelection({note->noteId});
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());
    }

    // 6.7.3: direct menu activation moves the selected note's right edge by
    // the live editing grid, including a grid change between triggers, and
    // starts, pitches, and velocities stay put.
    void noteLengthActionTriggersFollowLiveGrid()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        window.m_workspace->selectSongTab(session->b);
        SongTab &tab = *session->b;
        SongView &view = tab.view();
        QAction *lengthen = window.m_lengthenNoteAction;
        QAction *shorten = window.m_shortenNoteAction;
        QVERIFY(lengthen && shorten);
        const std::optional<DocNote> seeded = selectTerminatedNote(tab);
        QVERIFY(seeded.has_value());
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());

        view.setGridSelection(songview::GridSelection::musical(8));
        QTRY_VERIFY(view.gridSelection() == songview::GridSelection::musical(8));
        const QByteArray before = tab.document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();

        lengthen->trigger();
        DocNote resized = *seeded;
        QVERIFY2(tab.document().findNote(seeded->noteId, &resized),
                 "the lengthened note disappeared from the document");
        QCOMPARE(uint64_t(resized.duration), expectedResizedDuration(view, *seeded, true));
        QCOMPARE(resized.tick, seeded->tick);
        QCOMPARE(resized.key, seeded->key);
        QCOMPARE(resized.velocity, seeded->velocity);

        view.setGridSelection(songview::GridSelection::musical(4));
        QTRY_VERIFY(view.gridSelection() == songview::GridSelection::musical(4));
        lengthen->trigger();
        DocNote coarser = resized;
        QVERIFY(tab.document().findNote(seeded->noteId, &coarser));
        QCOMPARE(uint64_t(coarser.duration), expectedResizedDuration(view, resized, true));

        shorten->trigger();
        DocNote shortened = coarser;
        QVERIFY(tab.document().findNote(seeded->noteId, &shortened));
        QCOMPARE(uint64_t(shortened.duration), expectedResizedDuration(view, coarser, false));
        QCOMPARE(shortened.tick, seeded->tick);

        while (tab.document().undoStack()->index() > undoIndex &&
               tab.document().undoStack()->canUndo())
            tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);
    }

    // 6.7.4: menu activation edits only the newly selected tab, and
    // enablement follows the selected tab's note selection immediately
    // through the replaced noteSelectionChanged connection — a deselected
    // tab's selection churn never drives the actions.
    void noteLengthActivationEditsSelectedTabOnly()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        window.m_workspace->selectSongTab(session->b);
        QAction *lengthen = window.m_lengthenNoteAction;
        QAction *shorten = window.m_shortenNoteAction;
        QVERIFY(lengthen && shorten);
        SongTab &tabB = *session->b;
        SongTab &tabA = *session->a;
        const std::optional<DocNote> seededB = selectTerminatedNote(tabB);
        QVERIFY(seededB.has_value());
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());

        const QByteArray aBefore = tabA.document().smf().write();
        const QByteArray bBefore = tabB.document().smf().write();
        const int undoB = tabB.document().undoStack()->index();

        lengthen->trigger();
        DocNote resizedB = *seededB;
        QVERIFY(tabB.document().findNote(seededB->noteId, &resizedB));
        QCOMPARE(uint64_t(resizedB.duration), expectedResizedDuration(tabB.view(), *seededB, true));
        QCOMPARE(tabA.document().smf().write(), aBefore);
        const QByteArray bResized = tabB.document().smf().write();

        const std::optional<DocNote> seededA = selectTerminatedNote(tabA);
        QVERIFY(seededA.has_value());
        window.m_workspace->selectSongTab(session->a);
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());
        const int undoA = tabA.document().undoStack()->index();

        shorten->trigger();
        DocNote resizedA = *seededA;
        QVERIFY(tabA.document().findNote(seededA->noteId, &resizedA));
        QCOMPARE(uint64_t(resizedA.duration),
                 expectedResizedDuration(tabA.view(), *seededA, false));
        QCOMPARE(tabA.document().undoStack()->index(), undoA + 1);
        QCOMPARE(tabB.document().undoStack()->index(), undoB + 1);
        QCOMPARE(tabB.document().smf().write(), bResized);
        const QByteArray aResized = tabA.document().smf().write();

        tabA.view().selectionModel().clearNoteSelection();
        QVERIFY(!lengthen->isEnabled());
        QVERIFY(!shorten->isEnabled());
        tabB.view().selectionModel().clearNoteSelection();
        QVERIFY(!lengthen->isEnabled());
        tabB.view().selectionModel().setNoteSelection({seededB->noteId});
        QVERIFY(!lengthen->isEnabled());
        QVERIFY(!shorten->isEnabled());
        tabA.view().selectionModel().setNoteSelection({seededA->noteId});
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());

        window.m_workspace->selectSongTab(session->b);
        QVERIFY(lengthen->isEnabled());
        QVERIFY(shorten->isEnabled());
        QCOMPARE(tabB.document().smf().write(), bResized);
        QCOMPARE(tabA.document().smf().write(), aResized);

        while (tabB.document().undoStack()->index() > undoB &&
               tabB.document().undoStack()->canUndo())
            tabB.document().undoStack()->undo();
        while (tabA.document().undoStack()->index() > undoA &&
               tabA.document().undoStack()->canUndo())
            tabA.document().undoStack()->undo();
        QCOMPARE(tabA.document().smf().write(), aBefore);
        QCOMPARE(tabB.document().smf().write(), bBefore);
    }

    // 6.7.5: presentation follows the rebindable registry while the actions
    // stay shortcut-free. A native menu bar keeps bare titles across any
    // rebinding; a widget menu bar — a fresh MainWindow built under a scoped
    // AA_DontUseNativeMenuBar — carries the binding after a tab and
    // refreshes on bindingsChanged.
    void noteLengthBindingPresentationTracksMenuBarMode()
    {
        keymap::Registry &keys = keymap::Registry::instance();
        const QString lengthenId = QStringLiteral("roll.lengthen_note");
        const QString shortenId = QStringLiteral("roll.shorten_note");
        const QKeySequence reboundLengthen(QStringLiteral("Ctrl+Shift+Right"));
        const QKeySequence reboundShorten(QStringLiteral("Ctrl+Shift+Left"));
        const auto suffixed = [](const QString &title, const QKeySequence &binding) {
            return binding.isEmpty() ? title
                                     : title + u'\t' + binding.toString(QKeySequence::NativeText);
        };

        std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        QAction *lengthen = window.m_lengthenNoteAction;
        QAction *shorten = window.m_shortenNoteAction;
        QVERIFY(lengthen && shorten);
        const QString lengthenTitle = bareTitle(lengthen);
        const QString shortenTitle = bareTitle(shorten);
        QCOMPARE(lengthenTitle, QStringLiteral("&Lengthen Note"));
        QCOMPARE(shortenTitle, QStringLiteral("Sho&rten Note"));
        const bool native = window.menuBar()->isNativeMenuBar();
        const auto expectedLengthen = [&lengthenTitle, native,
                                       suffixed](const QKeySequence &binding) {
            return native ? lengthenTitle : suffixed(lengthenTitle, binding);
        };
        const auto expectedShorten = [&shortenTitle, native,
                                      suffixed](const QKeySequence &binding) {
            return native ? shortenTitle : suffixed(shortenTitle, binding);
        };

        const keymap::Registry::OverrideSnapshot snapshot = keys.snapshotOverrides();
        keys.setBinding(lengthenId, reboundLengthen);
        keys.setBinding(shortenId, reboundShorten);
        QCOMPARE(lengthen->text(), expectedLengthen(reboundLengthen));
        QCOMPARE(shorten->text(), expectedShorten(reboundShorten));
        QVERIFY(lengthen->shortcuts().isEmpty());
        QVERIFY(shorten->shortcuts().isEmpty());
        keys.setBinding(lengthenId, QKeySequence());
        QCOMPARE(lengthen->text(), expectedLengthen(QKeySequence()));
        keys.restoreOverrides(snapshot);
        QCOMPARE(lengthen->text(), expectedLengthen(keys.bindings(lengthenId).value(0)));
        QCOMPARE(shorten->text(), expectedShorten(keys.bindings(shortenId).value(0)));
        QVERIFY(lengthen->shortcuts().isEmpty());
        QVERIFY(shorten->shortcuts().isEmpty());
        session.reset();

        ScopedApplicationAttribute scoped(Qt::AA_DontUseNativeMenuBar, true);
        const std::optional<Session> widgetSession = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(widgetSession.has_value());
        MainWindow &widgetWindow = *widgetSession->window;
        QVERIFY(!widgetWindow.menuBar()->isNativeMenuBar());
        QAction *widgetLengthen = widgetWindow.m_lengthenNoteAction;
        QAction *widgetShorten = widgetWindow.m_shortenNoteAction;
        QVERIFY(widgetLengthen && widgetShorten);
        const QString widgetLengthenTitle = bareTitle(widgetLengthen);
        const QString widgetShortenTitle = bareTitle(widgetShorten);
        QCOMPARE(widgetLengthenTitle, QStringLiteral("&Lengthen Note"));
        QCOMPARE(widgetShortenTitle, QStringLiteral("Sho&rten Note"));
        QCOMPARE(widgetLengthen->text(),
                 suffixed(widgetLengthenTitle, keys.bindings(lengthenId).value(0)));
        QCOMPARE(widgetShorten->text(),
                 suffixed(widgetShortenTitle, keys.bindings(shortenId).value(0)));

        const keymap::Registry::OverrideSnapshot widgetSnapshot = keys.snapshotOverrides();
        keys.setBinding(lengthenId, reboundLengthen);
        QCOMPARE(widgetLengthen->text(), suffixed(widgetLengthenTitle, reboundLengthen));
        keys.setBinding(shortenId, reboundShorten);
        QCOMPARE(widgetShorten->text(), suffixed(widgetShortenTitle, reboundShorten));
        QVERIFY(widgetLengthen->shortcuts().isEmpty());
        QVERIFY(widgetShorten->shortcuts().isEmpty());
        keys.setBinding(lengthenId, QKeySequence());
        QCOMPARE(widgetLengthen->text(), widgetLengthenTitle);
        keys.restoreOverrides(widgetSnapshot);
        QCOMPARE(widgetLengthen->text(),
                 suffixed(widgetLengthenTitle, keys.bindings(lengthenId).value(0)));
        QCOMPARE(widgetShorten->text(),
                 suffixed(widgetShortenTitle, keys.bindings(shortenId).value(0)));
        QVERIFY(widgetLengthen->shortcuts().isEmpty());
        QVERIFY(widgetShorten->shortcuts().isEmpty());
    }

    // 6.7.6: the production roll input surface resizes exactly once per
    // keystroke — one grid step and one history entry per gesture — while
    // neither shortcut-free menu action ever fires.
    void noteLengthKeysRouteOnceWithoutMenuActions()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        window.m_workspace->selectSongTab(session->b);
        SongTab &tab = *session->b;
        SongView &view = tab.view();
        QAction *lengthen = window.m_lengthenNoteAction;
        QAction *shorten = window.m_shortenNoteAction;
        QVERIFY(lengthen && shorten);
        const std::optional<DocNote> seeded = selectTerminatedNote(tab);
        QVERIFY(seeded.has_value());
        view.setGridSelection(songview::GridSelection::musical(4));
        QTRY_VERIFY(view.gridSelection() == songview::GridSelection::musical(4));

        songview::TimelineQuickView *const quick = view.quickView();
        QQuickWindow *const quickWindow = quick ? quick->quickWindow() : nullptr;
        QVERIFY2(quickWindow && QTest::qWaitFor([&quickWindow] {
                     return quickWindow->isVisible() && quickWindow->isExposed();
                 }),
                 "the roll Quick window never became visible for key delivery");
        QVERIFY(view.focusTimelineBand(songview::TimelineBand::Roll, Qt::OtherFocusReason));
        QCOMPARE(checks::async_wait::waitUntil(
                     [] { return true; },
                     [&view] { return view.focusedTimelineBand() == songview::TimelineBand::Roll; },
                     5000, 10),
                 checks::async_wait::Result::Ready);
        QCoreApplication::processEvents();
        // Production band input is the live QQuickView window; the container
        // widget holds focus only to bridge activation into the scene.
        const auto deliver = [quickWindow](Qt::Key key, Qt::KeyboardModifiers modifiers) {
            QTest::keyClick(quickWindow, key, modifiers);
            QCoreApplication::sendPostedEvents();
            QCoreApplication::processEvents();
        };

        keymap::Registry &keys = keymap::Registry::instance();
        const QList<QKeySequence> lengthenKeys =
            keys.bindings(QStringLiteral("roll.lengthen_note"));
        QVERIFY(!lengthenKeys.isEmpty());
        const QList<QKeySequence> shortenKeys = keys.bindings(QStringLiteral("roll.shorten_note"));
        QVERIFY(!shortenKeys.isEmpty());
        QSignalSpy lengthenTriggered(lengthen, &QAction::triggered);
        QSignalSpy shortenTriggered(shorten, &QAction::triggered);

        const QByteArray before = tab.document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();
        const int undoCount = tab.document().undoStack()->count();

        const QKeyCombination lengthenKey = lengthenKeys.front()[0];
        deliver(lengthenKey.key(), lengthenKey.keyboardModifiers());
        DocNote resized = *seeded;
        QVERIFY(tab.document().findNote(seeded->noteId, &resized));
        QCOMPARE(uint64_t(resized.duration), expectedResizedDuration(view, *seeded, true));
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        QCOMPARE(tab.document().undoStack()->count(), undoCount + 1);
        QCOMPARE(lengthenTriggered.count(), 0);
        QCOMPARE(shortenTriggered.count(), 0);

        const QKeyCombination shortenKey = shortenKeys.front()[0];
        deliver(shortenKey.key(), shortenKey.keyboardModifiers());
        DocNote paired = resized;
        QVERIFY(tab.document().findNote(seeded->noteId, &paired));
        QCOMPARE(uint64_t(paired.duration), expectedResizedDuration(view, resized, false));
        QCOMPARE(tab.document().undoStack()->index(), undoIndex + 1);
        QCOMPARE(lengthenTriggered.count(), 0);
        QCOMPARE(shortenTriggered.count(), 0);

        while (tab.document().undoStack()->index() > undoIndex &&
               tab.document().undoStack()->canUndo())
            tab.document().undoStack()->undo();
        QCOMPARE(tab.document().smf().write(), before);
    }

    // 6.7.7: protected text input keeps Shift+Arrow local — the text
    // selection moves, neither menu action fires, and the song stays
    // byte-identical with no history.
    void noteLengthKeysStayLocalInTextInput()
    {
        const std::optional<Session> session = openSession(m_projectRoot, m_songA, m_songB);
        QVERIFY(session.has_value());
        MainWindow &window = *session->window;
        window.m_workspace->selectSongTab(session->b);
        SongTab &tab = *session->b;
        const std::optional<DocNote> seeded = selectTerminatedNote(tab);
        QVERIFY(seeded.has_value());
        QAction *lengthen = window.m_lengthenNoteAction;
        QAction *shorten = window.m_shortenNoteAction;
        QVERIFY(lengthen && shorten);

        QLineEdit text(&window);
        text.setText(QStringLiteral("shift"));
        text.setCursorPosition(0);
        text.show();
        text.setFocus(Qt::OtherFocusReason);
        QCoreApplication::processEvents();
        QCOMPARE(QApplication::focusWidget(), &text);

        const QByteArray before = tab.document().smf().write();
        const int undoIndex = tab.document().undoStack()->index();
        const int undoCount = tab.document().undoStack()->count();
        QSignalSpy lengthenTriggered(lengthen, &QAction::triggered);
        QSignalSpy shortenTriggered(shorten, &QAction::triggered);

        sendKey(text, Qt::Key_Right, Qt::ShiftModifier);
        QCOMPARE(text.selectedText(), QStringLiteral("s"));
        QCOMPARE(text.cursorPosition(), 1);
        sendKey(text, Qt::Key_Left, Qt::ShiftModifier);
        QCOMPARE(text.cursorPosition(), 0);
        QVERIFY(text.selectedText().isEmpty());
        QCOMPARE(lengthenTriggered.count(), 0);
        QCOMPARE(shortenTriggered.count(), 0);
        QCOMPARE(tab.document().smf().write(), before);
        QCOMPARE(tab.document().undoStack()->index(), undoIndex);
        QCOMPARE(tab.document().undoStack()->count(), undoCount);
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
