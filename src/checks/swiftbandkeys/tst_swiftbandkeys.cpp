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

// One flag-on workspace window with a private scratch pair for Swift-side
// observation: a SwiftGridKeyRouter + SwiftRollBand on the rig's view, never
// attached to input items (nothing routes to it), with a fully-bound harness
// surface on its target. The rig drives that band's key path and pointer
// forwarding directly, exactly as the roll input item does for the production
// band. The production band's sgb_ and sgk_ slots both belong to the mounted
// grid once editing binds, so the harness never claims the production target:
// production ownership is proven by the key-ownership row below, and every
// row that needs Swift-side arrivals drives the scratch pair.
//
// The scratch surface is destroyed before the scratch feed unregisters;
// document edits roll back through the real undo stack so the window close
// runs its genuine no-prompt branch.
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
        m_scratchFeed = std::make_unique<SwiftGridSessionFeed>(*m_view);
        m_scratchRouter = std::make_unique<songview::SwiftGridKeyRouter>();
        m_scratchBand = std::make_unique<songview::SwiftRollBand>(*m_view, *m_scratchRouter);
        m_scratchTargetId = m_scratchRouter->targetId();
        if (bandkeys_surface_create_full(m_scratchTargetId, m_scratchFeed->sessionId()) != 1) {
            error = QStringLiteral("the scratch Swift surface did not bind");
            return;
        }
        m_scratchBound = true;
        // The first authoritative push lands after the surface binds.
        m_scratchFeed->pushSnapshot();
        m_ok = true;
    }

    ~BandKeysRig()
    {
        // The scratch surface clears its sgb_/sgk_ slots before the scratch
        // pair unregisters its endpoints (member destruction below).
        if (m_scratchBound)
            bandkeys_surface_destroy(m_scratchTargetId);
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
    SwiftGridSessionFeed &scratchFeed() const { return *m_scratchFeed; }
    songview::SwiftRollBand &scratchBand() const { return *m_scratchBand; }
    uint64_t scratchTargetId() const { return m_scratchTargetId; }
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

    // The scratch band's registry-matched key path, driven exactly as the roll
    // input item drives the production band: keymap::Registry lookup, host
    // eligibility facts, one synchronous sgk_ delivery.
    bool scratchKeyPress(int key, bool autoRepeat = false) const
    {
        return m_scratchBand->keyPress(
            songview::TimelineKeyInput{key, Qt::NoModifier, QString{}, autoRepeat});
    }

    // The second tier of the real key path: the roll input item consults the
    // shared song policy for a key its interaction declined
    // (TimelineInputItem::keyPressEvent; the policy TimelineQuickView installs
    // routes to SongView::handleEditKey with the Timeline origin).
    bool hostKeyPolicy(int key, bool autoRepeat = false) const
    {
        return m_view->handleEditKey(
            songview::TimelineKeyInput{key, Qt::NoModifier, QString{}, autoRepeat},
            SongView::EditKeyOrigin::Timeline);
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
    // The scratch pair is destroyed (in reverse declaration order) after the
    // harness surface above unregisters: the scratch band's endpoint
    // unregisters before the router's, and the feed's session unregisters
    // last.
    std::unique_ptr<SwiftGridSessionFeed> m_scratchFeed;
    std::unique_ptr<songview::SwiftGridKeyRouter> m_scratchRouter;
    std::unique_ptr<songview::SwiftRollBand> m_scratchBand;
    uint64_t m_scratchTargetId = 0;
    bool m_scratchBound = false;
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

    // Registry-matched command ids arrive at the Swift band: Delete reaches
    // Swift as the Delete ordinal, not as a QKeyEvent. The scratch band's key
    // path is the whole delivery contract under test (keymap::Registry lookup
    // then one sgk_ delivery); the production target's slot answers through
    // the mounted grid, so its arrivals belong to the ownership row below.
    void testCommandIdArrivalThroughBandKeyPath()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.scratchTargetId();
        // Genuinely empty selection across both domains, pushed before the
        // key: the decline verdict below mirrors the host's live unavailable
        // answer, not fixture state.
        rig.view().selectionModel().clearNoteSelection();
        rig.view().selectionModel().clearTimeSelection();
        rig.scratchFeed().pushSnapshot();
        selectionkey::settle();

        QVERIFY(!rig.scratchKeyPress(Qt::Key_Delete));

        QCOMPARE(bandkeys_arrival_count(target), 1);
        QCOMPARE(bandkeys_last_command(target),
                 static_cast<int32_t>(SongView::EditCommand::Delete));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictDecline);
        QCOMPARE(bandkeys_last_handled(target), 0);
    }

    // The production band's key slot belongs to the mounted grid, not to the
    // harness: every SwiftRollBand keyPress lands on the grid's recipient and
    // is answered through the same shared eligibility the harness surface
    // uses. A repeat of an available pencil toggle is consumed (handled), the
    // first press defers — with nothing bound both deliveries would return
    // false.
    void testProductionKeyOwnership()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.targetId();

        const SgkKeyFacts repeat = keyFacts(SongView::EditCommand::PencilMode, true, true);
        QVERIFY(sgk_deliver(target, &repeat));

        const SgkKeyFacts first = keyFacts(SongView::EditCommand::PencilMode, false, true);
        QVERIFY(!sgk_deliver(target, &first));
    }

    // Eligibility flips with the sgs_ selection state while the key stays
    // deferred: decline without a selection, execute with one, and the
    // deferred execute really deletes through the shared song policy the roll
    // input item consults for a declined key.
    void testEligibilityGatingWithAndWithoutSelection()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.scratchTargetId();

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
        rig.scratchFeed().pushSnapshot();
        const bool availableEmpty = rig.view().editCommandAvailable(SongView::EditCommand::Delete);
        QVERIFY(!availableEmpty);
        const SgkKeyFacts emptyFacts =
            keyFacts(SongView::EditCommand::Delete, false, availableEmpty);
        QVERIFY(!sgk_deliver(target, &emptyFacts));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictDecline);
        QCOMPARE(bandkeys_last_handled(target), 0);

        rig.view().selectionModel().setNoteSelection({notes.front().noteId});
        rig.scratchFeed().pushSnapshot();
        const bool availableFull = rig.view().editCommandAvailable(SongView::EditCommand::Delete);
        QVERIFY(availableFull);
        const SgkKeyFacts fullFacts = keyFacts(SongView::EditCommand::Delete, false, availableFull);
        QVERIFY(!sgk_deliver(target, &fullFacts));
        QCOMPARE(bandkeys_last_verdict(target), kVerdictExecute);
        QCOMPARE(bandkeys_last_handled(target), 0);

        // The deferred execute: the band declines the key and the fallback
        // tier runs it, exactly the two tiers TimelineInputItem drives.
        QVERIFY(rig.focusRoll());
        const qsizetype before = static_cast<qsizetype>(rig.document().notesForTrack(0).size());
        QVERIFY(!rig.scratchKeyPress(Qt::Key_Delete));
        QVERIFY(rig.hostKeyPolicy(Qt::Key_Delete));
        QCOMPARE(static_cast<qsizetype>(rig.document().notesForTrack(0).size()), before - 1);
    }

    // A live Swift gesture blocks non-surviving keys at the band (consumed,
    // never executed) while surviving policy still defers. The host honors
    // the production surface's gesture through the real band; verdicts under
    // a live gesture are also proven directly on the scratch pair, where the
    // harness surface sees every delivery and its answer.
    void testGestureActiveBlocking()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t scratch = rig.scratchTargetId();
        QVERIFY(rig.focusRoll());

        auto *const rollInput = rig.quickWin().findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput != nullptr);
        const QPointF scenePos =
            rollInput->mapToScene(QPointF(rollInput->width() / 2, rollInput->height() / 2));
        const QPoint globalPos = rig.quickWin().mapToGlobal(scenePos.toPoint());
        const songview::TimelinePointerInput press =
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton);
        const songview::TimelinePointerInput release =
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::NoButton);

        // Host honors gating on the production path: a real press opens the
        // production gesture (band and host agree), a real Delete is
        // swallowed mid-gesture, release closes it.
        QVERIFY(rig.band().pointerPress(press));
        QVERIFY(rig.band().gestureActive());
        QVERIFY(rig.quickView().gestureActive());
        const qsizetype before = static_cast<qsizetype>(rig.document().notesForTrack(0).size());
        rig.sendKey(Qt::Key_Delete);
        QCOMPARE(static_cast<qsizetype>(rig.document().notesForTrack(0).size()), before);
        QVERIFY(rig.band().pointerRelease(release));
        QVERIFY(!rig.band().gestureActive());
        QVERIFY(!rig.quickView().gestureActive());

        // Verdicts under a live gesture on the scratch pair: the scratch
        // surface answers sgk_ deliveries with its own live gesture state.
        QVERIFY(rig.scratchBand().pointerPress(press));
        QVERIFY(rig.scratchBand().gestureActive());
        QCOMPARE(bandkeys_gesture_active(scratch), 1);

        const SgkKeyFacts autoRepeatDelete = keyFacts(SongView::EditCommand::Delete, true, true);
        QVERIFY(sgk_deliver(scratch, &autoRepeatDelete));
        QCOMPARE(bandkeys_last_verdict(scratch), kVerdictConsume);
        QCOMPARE(bandkeys_last_handled(scratch), 1);

        const SgkKeyFacts pencil = keyFacts(SongView::EditCommand::PencilMode, false, true);
        QVERIFY(!sgk_deliver(scratch, &pencil));
        QCOMPARE(bandkeys_last_verdict(scratch), kVerdictExecute);
        QCOMPARE(bandkeys_last_handled(scratch), 0);

        QVERIFY(rig.scratchBand().pointerRelease(release));
        QVERIFY(!rig.scratchBand().gestureActive());
        QCOMPARE(bandkeys_gesture_active(scratch), 0);
    }

    // AutoRepeat consumption is a band-side verdict: the same eligible
    // command consumes on repeat and defers on first press.
    void testAutoRepeatConsumption()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.scratchTargetId();

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
    // order: Delete executes through the shared song policy and no arrival
    // logs.
    void testFallbackWhenUnhandled()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.scratchTargetId();
        QVERIFY(rig.focusRoll());

        sgk_clear_delivery(target);
        const std::vector<DocNote> notes =
            rig.document().notesForTrack(rig.view().selectionModel().primaryTrack());
        QVERIFY(!notes.empty());
        rig.view().selectionModel().setNoteSelection({notes.front().noteId});
        rig.scratchFeed().pushSnapshot();

        const qsizetype before = static_cast<qsizetype>(rig.document().notesForTrack(0).size());
        QVERIFY(!rig.scratchKeyPress(Qt::Key_Delete));
        QVERIFY(rig.hostKeyPolicy(Qt::Key_Delete));
        QCOMPARE(static_cast<qsizetype>(rig.document().notesForTrack(0).size()), before - 1);
        QCOMPARE(bandkeys_arrival_count(target), 0);
    }

    // All four named cancel reasons end a live gesture mid-stream and land
    // distinctly in the Swift log. Driven on the scratch pair: the
    // production band's deliveries belong to the production grid's surface.
    void testCancelReasonsMidGesture()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t scratch = rig.scratchTargetId();

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
            QVERIFY(rig.scratchBand().pointerPress(press));
            QVERIFY(rig.scratchBand().gestureActive());
            rig.scratchBand().inputCancelled(reasons[index]);
            QVERIFY(!rig.scratchBand().gestureActive());
        }
        QCOMPARE(bandkeys_cancel_count(scratch), 4);
        for (int index = 0; index < 4; ++index)
            QCOMPARE(bandkeys_cancel_at(scratch, index), static_cast<int32_t>(reasons[index]));
        QCOMPARE(bandkeys_gesture_active(scratch), 0);
    }

    // Pointer, wheel, and leave cross as plain values with per-sample
    // handled/declined verdicts: hover moves decline, owned moves handle,
    // wheels decline to the host, releases absorb. Driven on the scratch
    // pair: the production band's deliveries belong to the production
    // grid's surface.
    void testPointerWheelLeaveForwarding()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.scratchTargetId();
        songview::SwiftRollBand &band = rig.scratchBand();

        auto *const rollInput = rig.quickWin().findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput != nullptr);
        const QPointF scenePos =
            rollInput->mapToScene(QPointF(rollInput->width() / 2, rollInput->height() / 2));
        const QPoint globalPos = rig.quickWin().mapToGlobal(scenePos.toPoint());

        QVERIFY(!band.pointerMove(pointerInput(scenePos, globalPos, Qt::NoButton, Qt::NoButton)));
        QVERIFY(
            band.pointerPress(pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton)));
        QVERIFY(band.pointerMove(pointerInput(scenePos + QPointF(10, 0), globalPos + QPoint(10, 0),
                                              Qt::NoButton, Qt::LeftButton)));

        songview::TimelineWheelInput wheel{};
        wheel.position = scenePos;
        wheel.globalPosition = QPointF(globalPos);
        wheel.angleDelta = QPoint(0, -120);
        wheel.modifiers = Qt::NoModifier;
        wheel.surface = songview::TimelineInputSurface::Plot;
        wheel.host = nullptr;
        wheel.inverted = false;
        QVERIFY(!band.wheel(wheel));

        band.pointerLeave();
        QVERIFY(
            band.pointerRelease(pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::NoButton)));

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
        QVERIFY(band.pointerPress(gutter));
        QCOMPARE(bandkeys_pointer_count(target), 5);
        QCOMPARE(bandkeys_last_pointer_surface(target), static_cast<int32_t>(SGB_SURFACE_GUTTER));
        QCOMPARE(bandkeys_last_pointer_tick(target), SGB_INVALID_TICK);
        QVERIFY(band.pointerRelease(gutter));

        // Second press kind: double-click reopens the gesture and absorbs.
        QVERIFY(band.pointerDoubleClick(
            pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::LeftButton)));
        QCOMPARE(bandkeys_pointer_count(target), 7);
        QCOMPARE(bandkeys_last_pointer_kind(target),
                 static_cast<int32_t>(SGB_POINTER_DOUBLE_CLICK));
        QVERIFY(
            band.pointerRelease(pointerInput(scenePos, globalPos, Qt::LeftButton, Qt::NoButton)));

        QCOMPARE(bandkeys_leave_count(target), 1);
    }

    // Press decline rules mirror PianoRoll::pointerPress: the gutter serves
    // left presses only (it auditions by key), the plot serves
    // left/right/middle only. Declined presses are recorded but never open a
    // gesture. Driven on the scratch pair: the production band's deliveries
    // belong to the production grid's surface.
    void testPressDeclineRules()
    {
        QString error;
        BandKeysRig rig(m_projectRoot, m_songA, error);
        QVERIFY2(rig.ok(), qUtf8Printable(error));
        const uint64_t target = rig.scratchTargetId();
        songview::SwiftRollBand &band = rig.scratchBand();

        auto *const rollInput = rig.quickWin().findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        QVERIFY(rollInput != nullptr);
        const QPointF scenePos =
            rollInput->mapToScene(QPointF(rollInput->width() / 2, rollInput->height() / 2));
        const QPoint globalPos = rig.quickWin().mapToGlobal(scenePos.toPoint());

        // Right-button press on the gutter declines.
        auto gutterRight = pointerInput(scenePos, globalPos, Qt::RightButton, Qt::RightButton);
        gutterRight.surface = songview::TimelineInputSurface::Gutter;
        QVERIFY(!band.pointerPress(gutterRight));
        // Middle-button press on the gutter declines for the same reason.
        auto gutterMiddle = pointerInput(scenePos, globalPos, Qt::MiddleButton, Qt::MiddleButton);
        gutterMiddle.surface = songview::TimelineInputSurface::Gutter;
        QVERIFY(!band.pointerPress(gutterMiddle));
        // Exotic-button press on the plot declines.
        QVERIFY(!band.pointerPress(pointerInput(scenePos, globalPos, Qt::XButton1, Qt::XButton1)));

        QCOMPARE(bandkeys_pointer_count(target), 3);
        QCOMPARE(bandkeys_gesture_active(target), 0);
        QVERIFY(!band.gestureActive());
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
