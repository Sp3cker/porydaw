#include "checks/selectionkey/session.h"
#include "checks/swiftbandkeys/keys_check.h"
#include "core/songdocument.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/swiftgrid/key_feed.h"
#include "ui/songview/quick/swiftgrid/session_feed.h"
#include "ui/songview/quick/swiftgrid/swift_roll_band.h"
#include "ui/songview/quick/timelineinput.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/workspaceui.h"

#include <QCoreApplication>
#include <QKeyEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest/QTest>

#include <cmath>
#include <memory>

namespace {

constexpr int32_t kVerdictDecline = 0;
constexpr int32_t kVerdictConsume = 1;
constexpr int32_t kVerdictExecute = 2;

SgkKeyFacts keyFacts(SongView::EditCommand command, bool autoRepeat, bool available)
{
    SgkKeyFacts facts{};
    facts.command = static_cast<int32_t>(command);
    facts.modifiers = static_cast<int32_t>(Qt::NoModifier);
    facts.origin = SGK_ORIGIN_TIMELINE;
    facts.autoRepeat = autoRepeat ? 1 : 0;
    facts.commandAvailable = available ? 1 : 0;
    return facts;
}

// One flag-on workspace window with the Swift band bound to a harness Swift
// surface and a registered session feed. The Swift surface is destroyed before
// the feed unregisters; document edits roll back through the real undo stack
// so the window close runs its genuine no-prompt branch.
class BandKeysRig
{
  public:
    BandKeysRig(const QString &projectRoot, const QString &song, QString &error)
    {
        if (!selectionkey::openWindowSession(m_session, projectRoot, error))
            return;
        m_tab = selectionkey::openSongTab(m_session, song, false, error);
        if (!m_tab)
            return;
        m_view = &m_tab->view();
        m_document = &m_tab->document();
        m_quickView = m_view->quickView();
        if (!m_quickView) {
            error = QStringLiteral("the song view has no Quick canvas");
            return;
        }
        m_quickWin = m_quickView->quickWindow();
        m_band = m_quickView->swiftRollBand();
        if (!m_band || !m_quickWin) {
            error = QStringLiteral("the Swift roll band is not registered");
            return;
        }
        m_targetId = m_band->targetId();
        m_feed = std::make_unique<SwiftGridSessionFeed>(*m_view);
        if (bandkeys_surface_create(m_targetId, m_feed->sessionId()) != 1) {
            error = QStringLiteral("the harness Swift surface did not bind");
            return;
        }
        m_swiftBound = true;
        // The first authoritative push lands after the surface binds.
        m_feed->pushSnapshot();
        m_ok = true;
    }

    ~BandKeysRig()
    {
        if (m_swiftBound)
            bandkeys_surface_destroy(m_targetId);
        if (m_tab) {
            QString error;
            selectionkey::undoTabToClean(*m_session.workspace, *m_document,
                                         QStringLiteral("swiftbandkeys rollback"), &error);
        }
    }

    BandKeysRig(const BandKeysRig &) = delete;
    BandKeysRig &operator=(const BandKeysRig &) = delete;

    bool ok() const { return m_ok; }
    SongView &view() const { return *m_view; }
    SongDocument &document() const { return *m_document; }
    songview::TimelineQuickView &quickView() const { return *m_quickView; }
    QQuickWindow &quickWin() const { return *m_quickWin; }
    songview::SwiftRollBand &band() const { return *m_band; }
    uint64_t targetId() const { return m_targetId; }
    SwiftGridSessionFeed &feed() const { return *m_feed; }

    bool focusRoll()
    {
        if (!m_quickView->focusBand(songview::TimelineBand::Roll, Qt::OtherFocusReason))
            return false;
        selectionkey::settle();
        return m_quickView->focusedBand() == songview::TimelineBand::Roll;
    }

    void sendKey(int key, bool autoRepeat = false)
    {
        QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier, QString{}, autoRepeat);
        QCoreApplication::sendEvent(m_quickWin, &press);
        QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier, QString{}, autoRepeat);
        QCoreApplication::sendEvent(m_quickWin, &release);
        selectionkey::settle();
    }

  private:
    selectionkey::WindowSession m_session;
    SongTab *m_tab = nullptr;
    SongView *m_view = nullptr;
    SongDocument *m_document = nullptr;
    songview::TimelineQuickView *m_quickView = nullptr;
    QQuickWindow *m_quickWin = nullptr;
    songview::SwiftRollBand *m_band = nullptr;
    uint64_t m_targetId = 0;
    std::unique_ptr<SwiftGridSessionFeed> m_feed;
    bool m_swiftBound = false;
    bool m_ok = false;
};

songview::TimelinePointerInput pointerInput(const QPointF &scenePos, const QPoint &globalPos,
                                            Qt::MouseButton button, Qt::MouseButtons buttons)
{
    songview::TimelinePointerInput input{};
    input.position = scenePos;
    input.globalPosition = QPointF(globalPos);
    input.button = button;
    input.buttons = buttons;
    input.modifiers = Qt::NoModifier;
    input.surface = songview::TimelineInputSurface::Plot;
    input.host = nullptr;
    return input;
}

} // namespace

class SwiftBandKeysTest : public QObject
{
    Q_OBJECT

  public:
    SwiftBandKeysTest(QString projectRoot, QString songA)
        : m_projectRoot(std::move(projectRoot))
        , m_songA(std::move(songA))
    {}
  private slots:
    void initTestCase()
    {
        qputenv("PORYDAW_AUDIO_BACKEND", "null");
        qputenv("PORYDAW_SWIFT_ROLL", "1");
    }

    void cleanupTestCase() { qunsetenv("PORYDAW_SWIFT_ROLL"); }

    // Registry-matched command ids arrive through the real window: Delete
    // reaches Swift as the Delete ordinal, not as a QKeyEvent.
    void testCommandIdArrivalViaRealWindow()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        QVERIFY(rig.focusRoll());
        // Genuinely empty selection across both domains, pushed before the
        // key: the decline verdict below mirrors the host's live unavailable
        // answer, not fixture state.
        rig.view().selectionModel().clearNoteSelection();
        rig.view().selectionModel().clearTimeSelection();
        rig.feed().pushSnapshot();
        selectionkey::settle();

        rig.sendKey(Qt::Key_Delete);

        const uint64_t target = rig.targetId();
        QCOMPARE(bandkeys_arrival_count(target), 1);
        QCOMPARE(bandkeys_last_command(target),
                 static_cast<int32_t>(SongView::EditCommand::Delete));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictDecline);
        QCOMPARE(bandkeys_last_handled(target), 0);
    }

    // Eligibility flips with the sgs_ selection state while the key stays
    // deferred: decline without a selection, execute with one, and the
    // deferred execute really deletes through the host path.
    void testEligibilityGatingWithAndWithoutSelection()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();

        const std::vector<DocNote> notes =
            rig.document().notesForTrack(rig.view().selectionModel().primaryTrack());
        QVERIFY(!notes.empty());
        // Swift mirrors production: it never judges selection itself, so each
        // leg feeds the host's live editCommandAvailable answer (exactly what
        // the band computes on the real key path) over a genuinely empty vs.
        // populated selection. Both selection domains clear: Delete's range
        // operation would otherwise target a live time selection.
        rig.view().selectionModel().clearNoteSelection();
        rig.view().selectionModel().clearTimeSelection();
        rig.feed().pushSnapshot();
        const bool availableEmpty = rig.view().editCommandAvailable(SongView::EditCommand::Delete);
        QVERIFY(!availableEmpty);
        const SgkKeyFacts emptyFacts =
            keyFacts(SongView::EditCommand::Delete, false, availableEmpty);
        QVERIFY(!sgk_deliver(target, &emptyFacts));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictDecline);
        QCOMPARE(bandkeys_last_handled(target), 0);

        rig.view().selectionModel().setNoteSelection({notes.front().noteId});
        rig.feed().pushSnapshot();
        const bool availableFull = rig.view().editCommandAvailable(SongView::EditCommand::Delete);
        QVERIFY(availableFull);
        const SgkKeyFacts fullFacts = keyFacts(SongView::EditCommand::Delete, false, availableFull);
        QVERIFY(!sgk_deliver(target, &fullFacts));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictExecute);
        QCOMPARE(bandkeys_last_handled(target), 0);

        QVERIFY(rig.focusRoll());
        const qsizetype before = static_cast<qsizetype>(rig.document().notesForTrack(0).size());
        rig.sendKey(Qt::Key_Delete);
        QCOMPARE(static_cast<qsizetype>(rig.document().notesForTrack(0).size()), before - 1);
    }

    // A live Swift gesture blocks non-surviving keys at the band (consumed,
    // never executed) while surviving policy still defers; the host's
    // gesture query answers from the Swift surface.
    void testGestureActiveBlocking()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();
        QVERIFY(rig.focusRoll());

        auto *const rollInput = rig.quickWin().findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput != nullptr);
        const QPointF scenePos =
            rollInput->mapToScene(QPointF(rollInput->width() / 2, rollInput->height() / 2));
        const QPoint globalPos = rig.quickWin().mapToGlobal(scenePos.toPoint());

        QVERIFY(rig.band().pointerPress(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton)));
        QVERIFY(rig.band().gestureActive());
        QVERIFY(rig.quickView().gestureActive());
        QCOMPARE(bandkeys_gesture_active(target), 1);

        const SgkKeyFacts autoRepeatDelete = keyFacts(SongView::EditCommand::Delete, true, true);
        QVERIFY(sgk_deliver(target, &autoRepeatDelete));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictConsume);
        QCOMPARE(bandkeys_last_handled(target), 1);

        const qsizetype before = static_cast<qsizetype>(rig.document().notesForTrack(0).size());
        rig.sendKey(Qt::Key_Delete);
        QCOMPARE(static_cast<qsizetype>(rig.document().notesForTrack(0).size()), before);
        QCOMPARE(bandkeys_last_verdict(target), kVerdictConsume);

        const SgkKeyFacts pencil = keyFacts(SongView::EditCommand::PencilMode, false, true);
        QVERIFY(!sgk_deliver(target, &pencil));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictExecute);
        QCOMPARE(bandkeys_last_handled(target), 0);

        QVERIFY(rig.band().pointerRelease(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::NoButton)));
        QVERIFY(!rig.band().gestureActive());
    }

    // AutoRepeat consumption is a band-side verdict: the same eligible
    // command consumes on repeat and defers on first press.
    void testAutoRepeatConsumption()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();

        const SgkKeyFacts repeat = keyFacts(SongView::EditCommand::PencilMode, true, true);
        QVERIFY(sgk_deliver(target, &repeat));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictConsume);
        QCOMPARE(bandkeys_last_handled(target), 1);

        const SgkKeyFacts first = keyFacts(SongView::EditCommand::PencilMode, false, true);
        QVERIFY(!sgk_deliver(target, &first));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictExecute);
        QCOMPARE(bandkeys_last_handled(target), 0);
    }

    // With no Swift recipient the band returns to the existing fallback
    // order: Delete executes through the normal policy and no arrival logs.
    void testFallbackWhenUnhandled()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();
        QVERIFY(rig.focusRoll());

        sgk_clear_delivery(target);
        const std::vector<DocNote> notes =
            rig.document().notesForTrack(rig.view().selectionModel().primaryTrack());
        QVERIFY(!notes.empty());
        rig.view().selectionModel().setNoteSelection({notes.front().noteId});
        rig.feed().pushSnapshot();

        const qsizetype before = static_cast<qsizetype>(rig.document().notesForTrack(0).size());
        rig.sendKey(Qt::Key_Delete);
        QCOMPARE(static_cast<qsizetype>(rig.document().notesForTrack(0).size()), before - 1);
        QCOMPARE(bandkeys_arrival_count(target), 0);
    }

    // All four named cancel reasons end a live gesture mid-stream and land
    // distinctly in the Swift log.
    void testCancelReasonsMidGesture()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();

        auto *const rollInput = rig.quickWin().findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput != nullptr);
        const QPointF scenePos =
            rollInput->mapToScene(QPointF(rollInput->width() / 2, rollInput->height() / 2));
        const QPoint globalPos = rig.quickWin().mapToGlobal(scenePos.toPoint());
        const songview::TimelinePointerInput press =
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton);

        const songview::TimelineInputCancelReason reasons[] = {
            songview::TimelineInputCancelReason::FocusLost,
            songview::TimelineInputCancelReason::PointerUngrabbed,
            songview::TimelineInputCancelReason::Hidden,
            songview::TimelineInputCancelReason::WindowDeactivated,
        };
        for (int index = 0; index < 4; ++index) {
            QVERIFY(rig.band().pointerPress(press));
            QVERIFY(rig.band().gestureActive());
            rig.band().inputCancelled(reasons[index]);
            QVERIFY(!rig.band().gestureActive());
        }
        QCOMPARE(bandkeys_cancel_count(target), 4);
        for (int index = 0; index < 4; ++index)
            QCOMPARE(bandkeys_cancel_at(target, index), static_cast<int32_t>(reasons[index]));
        QCOMPARE(bandkeys_gesture_active(target), 0);
    }

    // Pointer, wheel, and leave cross as plain values with per-sample
    // handled/declined verdicts: hover moves decline, owned moves handle,
    // wheels decline to the host, releases absorb.
    void testPointerWheelLeaveForwarding()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();

        auto *const rollInput = rig.quickWin().findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput != nullptr);
        const QPointF scenePos =
            rollInput->mapToScene(QPointF(rollInput->width() / 2, rollInput->height() / 2));
        const QPoint globalPos = rig.quickWin().mapToGlobal(scenePos.toPoint());

        QVERIFY(
            !rig.band().pointerMove(pointerInput(scenePos, globalPos, Qt::NoButton, Qt::NoButton)));
        QVERIFY(rig.band().pointerPress(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton)));
        QVERIFY(rig.band().pointerMove(pointerInput(
            scenePos + QPointF(10, 0), globalPos + QPoint(10, 0), Qt::NoButton, Qt::LeftButton)));

        songview::TimelineWheelInput wheel{};
        wheel.position = scenePos;
        wheel.globalPosition = QPointF(globalPos);
        wheel.angleDelta = QPoint(0, -120);
        wheel.modifiers = Qt::NoModifier;
        wheel.surface = songview::TimelineInputSurface::Plot;
        wheel.host = nullptr;
        wheel.inverted = false;
        QVERIFY(!rig.band().wheel(wheel));

        rig.band().pointerLeave();
        QVERIFY(rig.band().pointerRelease(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::NoButton)));

        QCOMPARE(bandkeys_pointer_count(target), 4);
        QCOMPARE(bandkeys_last_pointer_kind(target), static_cast<int32_t>(SGB_POINTER_RELEASE));
        const int32_t key = bandkeys_last_pointer_key(target);
        QVERIFY(key >= -1 && key <= 127);
        QVERIFY(std::isfinite(bandkeys_last_pointer_tick(target)));
        // Full release facts: LeftButton released, no buttons still held, no
        // modifiers, plot surface.
        QCOMPARE(bandkeys_last_pointer_button(target), static_cast<int32_t>(Qt::LeftButton));
        QCOMPARE(bandkeys_last_pointer_buttons(target), static_cast<int32_t>(Qt::NoButton));
        QCOMPARE(bandkeys_last_pointer_modifiers(target), 0);
        QCOMPARE(bandkeys_last_pointer_surface(target), static_cast<int32_t>(SGB_SURFACE_PLOT));

        // Full wheel facts: the -120 angle step crosses intact; pixel deltas
        // default to zero, no modifiers, plot surface, not inverted.
        QCOMPARE(bandkeys_wheel_count(target), 1);
        QVERIFY(std::isfinite(bandkeys_last_wheel_tick(target)));
        const int32_t wheelKey = bandkeys_last_wheel_key(target);
        QVERIFY(wheelKey >= -1 && wheelKey <= 127);
        QCOMPARE(bandkeys_last_wheel_pixel_delta_x(target), 0);
        QCOMPARE(bandkeys_last_wheel_pixel_delta_y(target), 0);
        QCOMPARE(bandkeys_last_wheel_angle_delta_x(target), 0);
        QCOMPARE(bandkeys_last_wheel_angle_delta_y(target), -120);
        QCOMPARE(bandkeys_last_wheel_modifiers(target), 0);
        QCOMPARE(bandkeys_last_wheel_surface(target), static_cast<int32_t>(SGB_SURFACE_PLOT));
        QCOMPARE(bandkeys_last_wheel_inverted(target), 0);

        // Gutter-local x is not a content coordinate: the press forwards the
        // key with the invalid-tick sentinel and still absorbs. The matching
        // release closes the gutter gesture.
        auto gutter = pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton);
        gutter.surface = songview::TimelineInputSurface::Gutter;
        QVERIFY(rig.band().pointerPress(gutter));
        QCOMPARE(bandkeys_pointer_count(target), 5);
        QCOMPARE(bandkeys_last_pointer_surface(target), static_cast<int32_t>(SGB_SURFACE_GUTTER));
        QCOMPARE(bandkeys_last_pointer_tick(target), SGB_INVALID_TICK);
        QVERIFY(rig.band().pointerRelease(gutter));

        // Second press kind: double-click reopens the gesture and absorbs.
        QVERIFY(rig.band().pointerDoubleClick(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton)));
        QCOMPARE(bandkeys_pointer_count(target), 7);
        QCOMPARE(bandkeys_last_pointer_kind(target),
                 static_cast<int32_t>(SGB_POINTER_DOUBLE_CLICK));
        QVERIFY(rig.band().pointerRelease(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::NoButton)));

        QCOMPARE(bandkeys_leave_count(target), 1);
    }

  private:
    QString m_projectRoot;
    QString m_songA;
};

int runSwiftBandKeysCheck(const QString &projectRoot, const QString &songA, const QString &,
                          const QStringList &qtArguments)
{
    SwiftBandKeysTest test(projectRoot, songA);
    QStringList arguments = {QStringLiteral("swiftbandkeys")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_swiftbandkeys.moc"
