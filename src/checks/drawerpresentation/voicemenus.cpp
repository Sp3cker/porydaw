// Voice Changes context menu on the shared canvas popup session: the Quick
// surface that replaced the native Insert / Change voice / Delete menu.
// Every scenario drives the real right-press, the typed rows, and the shared
// picker; rows are located by typed id and clicked through the live panel,
// never the model. The edges pin the open-time capture: camera scrolls never
// drift or kill it, rewrites between a row's press and release reject the
// pick, outside right presses dismiss without the note menu's retarget, and
// a foreign takeover strands the displaced target.

#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QCoreApplication>
#include <QEnterEvent>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtTest>

#include <cstdint>
#include <utility>

#include "checks/drawerpresentation/fixtures.h"
#include "checks/quickpopupguard.h"
#include "checks/voicepickerdriver.h"
#include "core/songdocument.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timeruler.h"

using namespace checks::drawerpresentation;

namespace {

using VoiceMenuAction = VoiceChangeArea::VoiceMenuAction;

// The staged marker (tick 48, program 3) is the marker target; tick 144 is
// the empty-lane witness.
constexpr Tick kMarkerTick = 48;
constexpr int kMarkerVoice = 3;
constexpr Tick kEmptyTick = 144;

// One opened voice menu: session, rendered panel's typed row model, resolved
// rows, open-failure diagnostic.
struct VoiceMenu {
    songview::QuickPopupSession *session = nullptr;
    songview::QuickMenuModel *model = nullptr;
    int insertRow = -1;
    int changeRow = -1;
    int deleteRow = -1;
    QString diagnostic;
};

// Opens the voice menu through the real band right-press: live on the press
// itself, the paired release picking nothing.
VoiceMenu openVoiceMenu(VoiceTransactionFixture &fixture, Tick tick, QString diagnostic)
{
    VoiceMenu menu;
    menu.diagnostic = std::move(diagnostic);
    const QPointF point(fixture.xForTick(double(tick)), fixture.bandRect().height() / 2.0);
    sendMouse(fixture.input(), QEvent::MouseButtonPress, point, Qt::RightButton, Qt::RightButton);
    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(fixture.view())};
    if (!QTest::qWaitFor([&live] {
            return live && live->isOpen() && quick_popup::menuPanel(*live) &&
                   quick_popup::menuModel(*quick_popup::menuPanel(*live)) != nullptr;
        }))
        return menu;
    menu.session = live;
    menu.model = quick_popup::menuModel(*quick_popup::menuPanel(*live));
    menu.insertRow = menu.model->rowForId(int(VoiceMenuAction::InsertVoiceChange));
    menu.changeRow = menu.model->rowForId(int(VoiceMenuAction::ChangeVoice));
    menu.deleteRow = menu.model->rowForId(int(VoiceMenuAction::DeleteMarker));
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, point, Qt::RightButton);
    pump();
    return menu;
}

// Window-level right delivery: the open menu's frame and session see the
// press before any band does.
void windowPress(VoiceTransactionFixture &fixture, QQuickWindow &window, const QPointF &itemPoint)
{
    const QPoint point = fixture.input().mapToScene(itemPoint).toPoint();
    QEnterEvent enter(point, point, window.mapToGlobal(point));
    QCoreApplication::sendEvent(&window, &enter);
    QTest::mouseEvent(QTest::MouseMove, &window, Qt::NoButton, Qt::NoModifier, point);
    QTest::mouseEvent(QTest::MousePress, &window, Qt::RightButton, Qt::NoModifier, point);
}

void windowRelease(VoiceTransactionFixture &fixture, QQuickWindow &window, const QPointF &itemPoint)
{
    const QPoint point = fixture.input().mapToScene(itemPoint).toPoint();
    QTest::mouseEvent(QTest::MouseRelease, &window, Qt::RightButton, Qt::NoModifier, point);
}

} // namespace

void DrawerPresentationTest::voiceContextMenuTransactions()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    quick_popup::PromptGuard guard(fixture.view());
    SongView &view = fixture.view();
    const Snapshot before = fixture.snapshot();

    // Empty lane: the Insert pick hands the captured target to the shared picker.
    const VoiceMenu inserted =
        openVoiceMenu(fixture, kEmptyTick,
                      QStringLiteral("the empty-lane right-press did not open the voice menu"));
    QVERIFY2(inserted.session, qUtf8Printable(inserted.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*inserted.session, inserted.insertRow),
             "the Insert row did not receive a real click");
    checks::voicepicker::Picker picker;
    QTRY_VERIFY((picker = checks::voicepicker::active(view)));
    QVERIFY2(!quick_popup::menuPanel(*picker.session),
             "the Insert pick left the voice menu panel up");
    checks::voicepicker::filter(picker, QStringLiteral("007"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 7));
    checks::voicepicker::accept(picker);
    QTRY_VERIFY(!checks::voicepicker::active(view));

    DocLanePoint point;
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QCOMPARE(point.value, 7);
    QCOMPARE(fixture.document().revision(), before.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), before.undoIndex + 1);

    // Marker lane: Change Voice reuses the direct double-click picker with the
    // captured marker voice preselected.
    const Snapshot changed = fixture.snapshot();
    const VoiceMenu changeMenu = openVoiceMenu(
        fixture, kEmptyTick, QStringLiteral("the marker right-press did not open the voice menu"));
    QVERIFY2(changeMenu.session, qUtf8Printable(changeMenu.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*changeMenu.session, changeMenu.changeRow),
             "the Change Voice row did not receive a real click");
    QTRY_VERIFY((picker = checks::voicepicker::active(view)));
    QCOMPARE(picker.list->property("currentIndex").toInt(), 7);
    checks::voicepicker::filter(picker, QStringLiteral("003"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 3));
    checks::voicepicker::accept(picker);
    QTRY_VERIFY(!checks::voicepicker::active(view));
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QCOMPARE(point.value, 3);
    QCOMPARE(fixture.document().revision(), changed.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), changed.undoIndex + 1);

    // The Delete pick removes exactly the captured marker.
    const Snapshot changedAgain = fixture.snapshot();
    const VoiceMenu deleteMenu =
        openVoiceMenu(fixture, kEmptyTick,
                      QStringLiteral("the marker right-press did not reopen the voice menu"));
    QVERIFY2(deleteMenu.session, qUtf8Printable(deleteMenu.diagnostic));
    QVERIFY2(quick_popup::clickMenuRow(*deleteMenu.session, deleteMenu.deleteRow),
             "the Delete row did not receive a real click");
    QVERIFY2(!deleteMenu.session->isOpen(), "the Delete pick left the voice menu open");
    QVERIFY(!fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QCOMPARE(fixture.document().revision(), changedAgain.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), changedAgain.undoIndex + 1);

    // Undo walks the three menu transactions back to the untouched song.
    fixture.document().undoStack()->undo();
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QCOMPARE(point.value, 3);
    fixture.document().undoStack()->undo();
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QCOMPARE(point.value, 7);
    fixture.document().undoStack()->undo();
    QVERIFY(!fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QVERIFY(fixture.document().smf().write() == before.smf);
}

// A camera-only scroll after the menu opens neither drifts the captured
// target nor closes the menu.
void DrawerPresentationTest::voiceMenuTargetHoldsAcrossCameraScroll()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    quick_popup::PromptGuard guard(fixture.view());
    SongView &view = fixture.view();
    const Snapshot before = fixture.snapshot();
    // Full lane baseline: the SMF already stages program state, so never assume a count.
    const auto beforePoints = fixture.document().lanePoints(0, DOC_CC_VOICE);

    const VoiceMenu menu = openVoiceMenu(
        fixture, kMarkerTick, QStringLiteral("the marker right-press did not open the voice menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    view.setEditorHorizontalScroll(view.camera().scrollX() + 200.0);
    pump();
    QVERIFY2(menu.session->isOpen(), "a camera-only scroll closed the useful voice menu");
    QVERIFY2(quick_popup::clickMenuRow(*menu.session, menu.changeRow),
             "the scrolled Change Voice row did not receive a real click");
    checks::voicepicker::Picker picker;
    QTRY_VERIFY((picker = checks::voicepicker::active(view)));
    QVERIFY2(!quick_popup::menuPanel(*picker.session),
             "the Change pick left the voice menu panel up");
    QCOMPARE(picker.list->property("currentIndex").toInt(), kMarkerVoice);
    checks::voicepicker::filter(picker, QStringLiteral("007"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 7));
    checks::voicepicker::accept(picker);
    QTRY_VERIFY(!checks::voicepicker::active(view));

    // Exactly the captured marker moved to 7; every pre-existing unrelated
    // point stands untouched.
    const auto afterPoints = fixture.document().lanePoints(0, DOC_CC_VOICE);
    QCOMPARE(afterPoints.size(), beforePoints.size());
    for (const DocLanePoint &beforePoint : beforePoints) {
        DocLanePoint afterPoint;
        QVERIFY2(fixture.document().findLanePoint(0, DOC_CC_VOICE, beforePoint.tick, &afterPoint),
                 "a pre-existing lane point went missing across the camera scroll");
        if (beforePoint.tick == kMarkerTick)
            QCOMPARE(afterPoint.value, 7);
        else
            QCOMPARE(afterPoint.value, beforePoint.value);
    }
    QCOMPARE(fixture.document().revision(), before.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), before.undoIndex + 1);
}

// A rewrite between a row's press and its release makes the activation
// stale: exactly the rewrite stands.
void DrawerPresentationTest::voiceMenuStaleDocumentRejectsPick()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    quick_popup::PromptGuard guard(fixture.view());
    SongView &view = fixture.view();

    const VoiceMenu menu = openVoiceMenu(
        fixture, kMarkerTick, QStringLiteral("the marker right-press did not open the voice menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    // The rewrite must land between the row press and its release.
    QQuickItem *const panel = quick_popup::menuPanel(*menu.session);
    QVERIFY2(panel, "the voice menu lost its rendered panel before the stale probe");
    const QPointF deleteCenter = quick_popup::menuRowSceneCenter(*panel, menu.deleteRow);
    QVERIFY2(!deleteCenter.isNull(), "the Delete row never rendered");
    QQuickWindow *const menuWindow = menu.session->window();
    QVERIFY(menuWindow);
    // Real pointer path onto the rendered delegate: enter the menu window and
    // hover the Delete row first (the same enter/move/press order the
    // windowPress helper and repo input fixtures use), so the held press
    // starts on the rendered row and the post-rewrite release completes on it.
    const QPoint deletePoint = deleteCenter.toPoint();
    QEnterEvent enter(deletePoint, deletePoint, menuWindow->mapToGlobal(deletePoint));
    QCoreApplication::sendEvent(menuWindow, &enter);
    QTest::mouseMove(menuWindow, deletePoint);
    QTest::mousePress(menuWindow, Qt::LeftButton, Qt::NoModifier, deletePoint);
    pump();
    fixture.document().addLanePoint(0, DOC_CC_VOICE, kEmptyTick, 5);
    pump();
    const Snapshot rewritten = fixture.snapshot();

    QTest::mouseRelease(menuWindow, Qt::LeftButton, Qt::NoModifier, deletePoint);
    pump();

    // Whether the rewrite cancelled the menu or the release ran stale, the
    // outcome is identical.
    QVERIFY2(!menu.session->isOpen(), "the stale request left a popup open");
    QVERIFY2(!quick_popup::popupSession(view)->isOpen(), "the stale request reopened a popup");
    QVERIFY(fixture.snapshot() == rewritten);
    DocLanePoint point;
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kMarkerTick, &point));
    QCOMPARE(point.value, kMarkerVoice);
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kEmptyTick, &point));
    QCOMPARE(point.value, 5);
}

// The native voice menu had no outside-right retarget handler; dismiss plus
// the swallowed paired release is preserved.
void DrawerPresentationTest::voiceMenuOutsideRightDismissesWithoutRetarget()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    quick_popup::PromptGuard guard(fixture.view());
    SongView &view = fixture.view();
    const Snapshot before = fixture.snapshot();

    // The dismissal restores the pre-menu active-focus item: stage real
    // voice-band focus first. The fixture only stages page visibility, and
    // pointer presses never drive band focus, so without this the session
    // captures the root item and restores that.
    QVERIFY(view.focusTimelineBand(songview::TimelineBand::VoiceChanges, Qt::OtherFocusReason));
    QTRY_VERIFY(view.focusedTimelineBand() == songview::TimelineBand::VoiceChanges);
    const VoiceMenu menu = openVoiceMenu(
        fixture, kMarkerTick, QStringLiteral("the marker right-press did not open the voice menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    const QPointF miss(fixture.xForTick(double(kEmptyTick)), fixture.bandRect().height() / 2.0);
    QQuickWindow *const menuWindow = menu.session->window();
    QVERIFY(menuWindow);
    windowPress(fixture, *menuWindow, miss);
    pump();
    QVERIFY2(!menu.session->isOpen(), "an outside right press did not dismiss the voice menu");
    windowRelease(fixture, *menuWindow, miss);
    pump();
    QVERIFY2(!quick_popup::popupSession(view)->isOpen(),
             "the dismissed voice menu leaked its paired release into a new popup");
    QVERIFY(!checks::voicepicker::active(view));
    QVERIFY(fixture.snapshot() == before);
    QTRY_VERIFY2(view.quickView()->focusedBand() == songview::TimelineBand::VoiceChanges,
                 "the dismissal did not restore the voice band focus");
}

// A foreign session takeover strands the pending voice target: the ruler's
// real open method publishes live rows and the displaced target never fires.
void DrawerPresentationTest::voiceMenuForeignTakeoverStaysUsable()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    quick_popup::PromptGuard guard(fixture.view());
    SongView &view = fixture.view();
    const Snapshot before = fixture.snapshot();

    const VoiceMenu menu = openVoiceMenu(
        fixture, kMarkerTick, QStringLiteral("the marker right-press did not open the voice menu"));
    QVERIFY2(menu.session, qUtf8Printable(menu.diagnostic));

    QQuickItem *const root = view.quickView()->rootObject();
    QVERIFY(root);
    auto *const rulerInput =
        root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRulerInput"));
    QVERIFY(rulerInput);
    auto *const ruler = dynamic_cast<songview::TimeRuler *>(rulerInput->interaction());
    QVERIFY(ruler);
    QQuickItem *const division =
        root->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"));
    QVERIFY(division);
    ruler->openDivisionMenu(
        division->mapToScene(QPointF(division->width() / 2.0, division->height() / 2.0)));

    const QPointer<songview::QuickPopupSession> live{quick_popup::popupSession(view)};
    QVERIFY(live);
    QVERIFY2(QTest::qWaitFor([&live] {
                 QQuickItem *const foreignPanel = quick_popup::menuPanel(*live);
                 return live->isOpen() && foreignPanel &&
                        quick_popup::menuModel(*foreignPanel) != nullptr;
             }),
             "the foreign ruler menu did not publish over the pending voice menu");

    // The foreign menu keeps working: a real row pick changes the grid.
    const int currentDenom = view.viewState().gridMinDenom;
    const int targetDenom = currentDenom == 8 ? 16 : 8;
    const int targetRow =
        quick_popup::menuModel(*quick_popup::menuPanel(*live))->rowForId(targetDenom);
    QVERIFY2(targetRow >= 0, "the foreign division menu omitted the chosen denominator");
    QVERIFY2(quick_popup::clickMenuRow(*live, targetRow),
             "the foreign division row did not receive a real click");
    pump();
    QVERIFY2(!live->isOpen(), "the foreign division pick left the shared menu open");
    QCOMPARE(view.viewState().gridMinDenom, targetDenom);
    QTRY_VERIFY2(division->hasActiveFocus(),
                 "the foreign pick did not return focus to the ruler control");

    // The displaced voice target never fired: exactly nothing was written,
    // the marker stays, and no picker surfaced late.
    QVERIFY(fixture.snapshot() == before);
    DocLanePoint point;
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, kMarkerTick, &point));
    QCOMPARE(point.value, kMarkerVoice);
    QVERIFY(!checks::voicepicker::active(view));
    QVERIFY(!quick_popup::popupSession(view)->isOpen());
}
