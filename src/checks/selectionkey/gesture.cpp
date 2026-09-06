// Selection keyboard routing, gesture tier: standalone SongView rigs prove
// that a live pointer gesture owns its surface — overlap hit priority in the
// velocity plot, selected/unselected velocity transitions, roll note drags,
// automation pans — and that shared edit commands (Delete resolved through
// the live keymap) are consumed no-ops while a gesture is live, with the
// first Escape cancelling only the gesture and the second clearing the
// leftover selection. The discovered typed scrollbar thumbs (the root roll
// bar and nested drawer automation bar) get the same guard proof end to end:
// the live native MouseArea
// grab blocks Delete, Escape ungrabs it, held-button movement stays inert,
// and a physically released then newly pressed drag works normally.
//
// Every scenario builds a fresh world (song fixture + rig + Quick window), so
// one scenario's failure can never skip or poison another's. Programmatic
// staging is limited to selection, camera reveals, and section sizing; every
// interaction delivery is real QTest input into the shown QQuickWindow.

#include "checks/selectionkey/primitives.h"
#include "checks/support/asyncwait.h"
#include "checks/support/quickframebuffer.h"

#include "core/noteid.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songviewmodel.h"

#include <QApplication>
#include <QColor>
#include <QGuiApplication>
#include <QImage>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSize>
#include <QStyleHints>
#include <QtTest>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <optional>
#include <vector>

namespace {

using selectionkey::deliverKey;
using selectionkey::firstBinding;
using selectionkey::noteById;
using selectionkey::noteExists;
using selectionkey::rigDocument;
using selectionkey::rigInput;
using selectionkey::rigView;
using selectionkey::rigWindow;
using selectionkey::RigWorld;
using selectionkey::settle;

constexpr int kTrack = 0;
// Reserved gesture fixture ticks: the routing notes at 24/60/96 carry
// durations 48/24/24 (spans 24..72 / 60..84 / 96..120), so at the canonical
// timeZoom 96 the earlier stem, the following node, and the unselected stem
// sit ~36 px apart — every press has a dedicated target clear of the velocity
// hit radius. The CC 10 lane point reuses kFollowingTick.
constexpr uint64_t kEarlierTick = 24;
constexpr uint64_t kFollowingTick = 60;
constexpr uint64_t kLaterTick = 96;
constexpr uint32_t kEarlierDuration = 48;
constexpr uint32_t kFollowingDuration = 24;
constexpr uint32_t kLaterDuration = 24;
constexpr uint8_t kEarlierKey = 106;
constexpr uint8_t kFollowingKey = 105;
constexpr uint8_t kLaterKey = 104;
constexpr uint8_t kTiedKey = 103;
constexpr uint8_t kVelocity = 70;
constexpr uint8_t kAutomationController = 10;
// Canonical gesture drawer heights: the velocity plot needs its full 320 px
// stem range; 250 shows the automation lane; 180 forces the automation page
// to overflow so its nested scrollbar becomes scrollable (the proven
// scrollbar-check drag height).
constexpr int kVelocitySectionHeight = 320;
constexpr int kAutomationSectionHeight = 250;
constexpr int kScrollbarAutomationSectionHeight = 180;

bool sameSelection(const SongView &view, std::vector<NoteId> expected)
{
    return view.selectionModel().noteSelection() == expected;
}

bool focusPointerSurface(SongView &view, QQuickWindow *window, songview::TimelineInputItem *input,
                         songview::TimelineBand band)
{
    const QPointer<songview::TimelineInputItem> liveInput(input);
    if (!window || !liveInput || !view.focusTimelineBand(band, Qt::OtherFocusReason))
        return false;
    settle();
    return QTest::qWaitFor([&view, window, liveInput, band] {
        return liveInput && QGuiApplication::focusWindow() == window &&
               QGuiApplication::focusObject() == liveInput && liveInput->hasActiveFocus() &&
               view.focusedTimelineBand() == band;
    });
}

QPoint windowPoint(const songview::TimelineInputItem &input, QPointF itemPoint)
{
    return input.mapToScene(itemPoint).toPoint();
}

int colorDistance(const QColor &a, const QColor &b)
{
    return std::abs(a.red() - b.red()) + std::abs(a.green() - b.green()) +
           std::abs(a.blue() - b.blue());
}

songview::EditorSelectionModel::TimeSelection automationSelection()
{
    songview::EditorSelectionModel::TimeSelection selection;
    selection.startTick = kFollowingTick;
    selection.endTick = kFollowingTick + 24;
    selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    selection.lanes = {{kTrack, kAutomationController}};
    return selection;
}

std::vector<SongDocument::NewNote> gestureNoteSpecs()
{
    return {{kEarlierTick, kEarlierKey, kEarlierDuration, kVelocity},
            {kFollowingTick, kFollowingKey, kFollowingDuration, kVelocity},
            {kLaterTick, kLaterKey, kLaterDuration, kVelocity}};
}

checks::EditorRigConfig gestureRigConfig(EditorDrawerPage activePage, int sectionHeight)
{
    checks::EditorRigConfig config;
    config.track = kTrack;
    config.activePage = activePage;
    config.sections = {{activePage, sectionHeight}};
    config.timeZoom = 96.0;
    return config;
}

void prepareGestureDocument(SongDocument &document)
{
    document.addLanePoint(kTrack, kAutomationController, kFollowingTick, 64);
}

struct VelocitySurface {
    QPointer<songview::TimelineInputItem> input;
    QPointer<VelocityArea> area;
};

VelocitySurface velocitySurface(RigWorld &world)
{
    EditorDrawer *const drawer = rigView(world).editorDrawer();
    return {rigInput(world, "timelineVelocityInput"), drawer ? drawer->velocityArea() : nullptr};
}

// Every scenario owns a fresh world, so surface exposure is scenario
// readiness, not global setup.
bool velocitySurfaceReady(int &failures, RigWorld &world, const VelocitySurface &surface)
{
    return selectionkey::check(
        failures, surface.input != nullptr && surface.area != nullptr && QTest::qWaitFor([&] {
                      return !surface.input->bounds().isEmpty() &&
                             surface.input->window() == rigWindow(world);
                  }),
        "Velocity Quick delivery surface is unavailable", "selectionkeygesturecheck");
}

struct VelocityStemPoints {
    QPointF earlierStem;
    QPointF followingNode;
    QPointF followingStem;
};

// The three delivery points in velocity-input coordinates. Returning nullopt
// on a bounds miss keeps every later press inside the shown surface instead
// of delivering guessed coordinates.
std::optional<VelocityStemPoints> velocityStemPoints(RigWorld &world,
                                                     const songview::TimelineInputItem &input,
                                                     const VelocityArea &velocity)
{
    const SongView &songView = rigView(world);
    const auto point = [&songView, &input, &velocity](uint64_t tick) {
        return QPointF(songView.camera().displayX(double(tick), 0.0, input.devicePixelRatio()),
                       velocity.axis().velocityToY(kVelocity));
    };
    const VelocityStemPoints points{
        point(kEarlierTick + kEarlierDuration / 2),
        point(kFollowingTick),
        point(kFollowingTick + kFollowingDuration * 3 / 4),
    };
    const QRectF bounds = input.bounds();
    if (!bounds.contains(points.earlierStem) || !bounds.contains(points.followingNode) ||
        !bounds.contains(points.followingStem))
        return std::nullopt;
    return points;
}

// Scenario: the following node must visibly cover an earlier selected stem
// through idle, hover, selected, and zoomed presentations; own the
// press-drag; and preserve the existing node-versus-node hit tie-breaks.
void overlapNodeTargetsVisibleNode(int &failures, const QString &projectRoot,
                                   const QString &songLabel)
{
    QString error;
    auto world = selectionkey::makeRigWorld(
        projectRoot, songLabel, kTrack, gestureNoteSpecs(),
        gestureRigConfig(EditorDrawerPage::Velocity, kVelocitySectionHeight),
        prepareGestureDocument, error);
    if (world == nullptr) {
        selectionkey::fail(failures,
                           QStringLiteral("could not create the overlap-node world: %1").arg(error),
                           "selectionkeygesturecheck");
        return;
    }
    const VelocitySurface surface = velocitySurface(*world);
    if (!velocitySurfaceReady(failures, *world, surface))
        return;
    auto points = velocityStemPoints(*world, *surface.input, *surface.area);
    if (!selectionkey::check(failures, points.has_value(),
                             "production velocity geometry did not expose the test stems and node",
                             "selectionkeygesturecheck"))
        return;

    // velocityquick.cpp paints the following node center with its opaque track
    // color in idle, hover, selected, and zoomed states. Matching that color
    // proves the visible node won the stack; merely differing from highlight
    // would also accept an empty or background pixel.
    constexpr int kNodeColorTolerance = 12;
    const QColor expectedNodeColor = SongView::trackColor(kTrack);
    const auto nodePaintsAboveSelectedStem = [&](const VelocityStemPoints &overlapPoints,
                                                 const char *message) {
        checks::support::pumpQuick();
        QString captureError;
        const QImage frame = checks::support::captureQuickBand(
            rigView(*world), rigView(*world).rect(), &captureError);
        const QPoint sampleInView = rigView(*world).quickView()->mapTo(
            &rigView(*world), windowPoint(*surface.input, overlapPoints.followingNode));
        const QRect sampleRect =
            checks::support::devicePixelRect(frame, QRect(sampleInView, QSize(1, 1)));
        const QColor nodePixel = frame.isNull() || !frame.rect().contains(sampleRect.center())
                                     ? QColor{}
                                     : frame.pixelColor(sampleRect.center());
        return selectionkey::check(failures,
                                   !frame.isNull() && captureError.isEmpty() &&
                                       expectedNodeColor.isValid() && nodePixel.isValid() &&
                                       colorDistance(nodePixel, expectedNodeColor) <=
                                           kNodeColorTolerance,
                                   message, "selectionkeygesturecheck");
    };

    rigView(*world).selectionModel().setNoteSelection({world->notes[0]});
    if (!nodePaintsAboveSelectedStem(
            *points, "following velocity node was not rendered above the selected earlier stem"))
        return;

    const QPoint followingHover = windowPoint(*surface.input, points->followingNode);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, followingHover,
                                 Qt::NoButton);
    if (!nodePaintsAboveSelectedStem(
            *points, "hovered following velocity node was not rendered above the selected stem"))
        return;

    rigView(*world).selectionModel().setNoteSelection({world->notes[0], world->notes[1]});
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove,
                                 windowPoint(*surface.input, points->followingStem), Qt::NoButton);
    if (!nodePaintsAboveSelectedStem(
            *points, "selected following velocity node was not rendered above the selected stem"))
        return;

    const double initialZoom = rigView(*world).camera().pxPerBeat();
    rigView(*world).setEditorTimeZoom(initialZoom * 2.0);
    settle();
    const auto zoomedPoints = velocityStemPoints(*world, *surface.input, *surface.area);
    if (!selectionkey::check(
            failures, zoomedPoints.has_value(),
            "zoomed velocity geometry did not expose the overlapping stem and node",
            "selectionkeygesturecheck") ||
        !nodePaintsAboveSelectedStem(
            *zoomedPoints,
            "zoomed selected velocity node was not rendered above the selected stem"))
        return;

    rigView(*world).setEditorTimeZoom(initialZoom);
    settle();
    points = velocityStemPoints(*world, *surface.input, *surface.area);
    if (!selectionkey::check(
            failures, points.has_value(),
            "restored velocity geometry did not expose the overlapping stem and node",
            "selectionkeygesturecheck"))
        return;
    rigView(*world).selectionModel().setNoteSelection({world->notes[0]});

    const QByteArray overlapBeforeDrag = rigDocument(*world).smf().write();
    const QPoint followingPress = windowPoint(*surface.input, points->followingNode);
    QPoint followingDrag = followingPress + QPoint(0, QApplication::startDragDistance() + 4);
    followingDrag.setY(
        std::min(followingDrag.y(),
                 windowPoint(*surface.input, surface.input->bounds().bottomLeft()).y() - 2));
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, followingPress,
                                 Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, followingPress,
                                 Qt::LeftButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, followingDrag,
                                 Qt::NoButton);
    if (!selectionkey::check(
            failures, QTest::qWaitFor([&] {
                return rigView(*world).userGestureActive() &&
                       sameSelection(rigView(*world), {world->notes[1]});
            }),
            "beginning an overlap-node drag did not target the visible following node",
            "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, followingDrag,
                                     Qt::LeftButton);
        return;
    }
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, followingDrag,
                                 Qt::LeftButton);
    // VelocityArea cancellation restores the selection captured before the
    // press ({earlier}); the committed drag's node targeting is asserted
    // next, so production cancellation stays untouched here.
    if (!selectionkey::check(
            failures,
            !rigView(*world).userGestureActive() &&
                sameSelection(rigView(*world), {world->notes[0]}) &&
                rigDocument(*world).smf().write() == overlapBeforeDrag,
            "cancelling an overlap-node drag did not restore its pre-press selection",
            "selectionkeygesturecheck"))
        return;

    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, followingPress,
                                 Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, followingPress,
                                 Qt::LeftButton);
    if (!selectionkey::check(
            failures,
            QTest::qWaitFor([&] { return sameSelection(rigView(*world), {world->notes[1]}); }),
            "clicking the following overlap node did not replace the earlier stem selection",
            "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, followingPress,
                                     Qt::LeftButton);
        return;
    }
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, followingPress,
                                 Qt::LeftButton);
    const auto followingBeforeArrow = noteById(rigDocument(*world), world->notes[1]);
    const auto earlierBeforeArrow = noteById(rigDocument(*world), world->notes[0]);
    if (!selectionkey::check(
            failures, followingBeforeArrow.has_value() && earlierBeforeArrow.has_value(),
            "an overlap note vanished before its arrow command", "selectionkeygesturecheck"))
        return;
    QTest::keyClick(rigWindow(*world), Qt::Key_Right);
    const auto followingAfterArrow = noteById(rigDocument(*world), world->notes[1]);
    const auto earlierAfterArrow = noteById(rigDocument(*world), world->notes[0]);
    if (!selectionkey::check(
            failures,
            followingAfterArrow.has_value() && earlierAfterArrow.has_value() &&
                followingAfterArrow->tick > followingBeforeArrow->tick &&
                earlierAfterArrow->tick == earlierBeforeArrow->tick,
            "arrow after overlap-node click did not target only the following note",
            "selectionkeygesturecheck"))
        return;

    QString tieError;
    const std::vector<NoteId> tiedNodes = selectionkey::insertIsolatedNotes(
        rigDocument(*world), kTrack, {{kLaterTick, kTiedKey, kLaterDuration, kVelocity}}, tieError);
    if (tiedNodes.size() != 1) {
        selectionkey::fail(
            failures,
            QStringLiteral("could not create the node-overlap tie fixture: %1").arg(tieError),
            "selectionkeygesturecheck");
        return;
    }
    if (!selectionkey::check(
            failures,
            noteExists(rigDocument(*world), world->notes[2]) &&
                noteExists(rigDocument(*world), tiedNodes.front()),
            "node-overlap tie fixture did not retain both coincident-velocity notes",
            "selectionkeygesturecheck")) {
        return;
    }
    settle();
    const QPointF tiedNode(rigView(*world).camera().displayX(double(kLaterTick), 0.0,
                                                             surface.input->devicePixelRatio()),
                           surface.area->axis().velocityToY(kVelocity));
    if (!selectionkey::check(failures, surface.input->bounds().contains(tiedNode),
                             "production velocity geometry did not expose the tied nodes",
                             "selectionkeygesturecheck"))
        return;
    const QPoint tiedPress = windowPoint(*surface.input, tiedNode);

    // Equal unselected circles retain model-order priority: the later node
    // wins. Selecting the earlier circle then retains the higher selected
    // priority before model order is considered.
    rigView(*world).selectionModel().setNoteSelection({});
    checks::support::pumpQuick();
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, tiedPress, Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, tiedPress,
                                 Qt::LeftButton);
    if (!selectionkey::check(
            failures,
            QTest::qWaitFor([&] { return sameSelection(rigView(*world), {tiedNodes.front()}); }),
            "equal unselected velocity nodes did not retain later-model-order priority",
            "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, tiedPress,
                                     Qt::LeftButton);
        return;
    }
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, tiedPress,
                                 Qt::LeftButton);

    rigView(*world).selectionModel().setNoteSelection({world->notes[2]});
    checks::support::pumpQuick();
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, tiedPress,
                                 Qt::LeftButton);
    if (!selectionkey::check(failures, QTest::qWaitFor([&] {
                                 return sameSelection(rigView(*world), {world->notes[2]});
                             }),
                             "selected velocity node did not retain priority over its tied sibling",
                             "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, tiedPress,
                                     Qt::LeftButton);
        return;
    }
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, tiedPress,
                                 Qt::LeftButton);
}

// Scenario: a selected duration-stem drag retains the whole selection and
// blocks edit keys; an unselected stem is a real replacement selection
// transition.
void velocityStemDragGuardsEdits(int &failures, const QString &projectRoot,
                                 const QString &songLabel)
{
    const auto deleteKey = firstBinding(QStringLiteral("roll.delete"));
    if (!selectionkey::check(failures, deleteKey.has_value(),
                             "roll.delete has no single-key binding", "selectionkeygesturecheck"))
        return;
    QString error;
    auto world = selectionkey::makeRigWorld(
        projectRoot, songLabel, kTrack, gestureNoteSpecs(),
        gestureRigConfig(EditorDrawerPage::Velocity, kVelocitySectionHeight),
        prepareGestureDocument, error);
    if (world == nullptr) {
        selectionkey::fail(
            failures, QStringLiteral("could not create the velocity-stem world: %1").arg(error),
            "selectionkeygesturecheck");
        return;
    }
    const VelocitySurface surface = velocitySurface(*world);
    if (!velocitySurfaceReady(failures, *world, surface))
        return;
    const auto points = velocityStemPoints(*world, *surface.input, *surface.area);
    if (!selectionkey::check(failures, points.has_value(),
                             "production velocity geometry did not expose the test stems and node",
                             "selectionkeygesturecheck"))
        return;

    rigView(*world).selectionModel().setNoteSelection({world->notes[0], world->notes[2]});
    const QByteArray velocityBeforeGesture = rigDocument(*world).smf().write();
    const QPoint earlierPress = windowPoint(*surface.input, points->earlierStem);
    QPoint earlierDrag = earlierPress + QPoint(0, QApplication::startDragDistance() + 4);
    earlierDrag.setY(
        std::min(earlierDrag.y(),
                 windowPoint(*surface.input, surface.input->bounds().bottomLeft()).y() - 2));
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, earlierPress, Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, earlierPress,
                                 Qt::LeftButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, earlierDrag, Qt::NoButton);
    if (!selectionkey::check(
            failures,
            QTest::qWaitFor([&] { return rigView(*world).userGestureActive(); }) &&
                sameSelection(rigView(*world), {world->notes[0], world->notes[2]}),
            "selected velocity-stem drag did not retain its captured note selection",
            "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, earlierDrag,
                                     Qt::LeftButton);
        return;
    }
    QTest::keyClick(rigWindow(*world), Qt::Key_Right);
    deliverKey(rigWindow(*world), deleteKey->key(), deleteKey->keyboardModifiers());
    if (!selectionkey::check(
            failures,
            rigDocument(*world).smf().write() == velocityBeforeGesture &&
                sameSelection(rigView(*world), {world->notes[0], world->notes[2]}),
            "an edit key mutated selection or notes during a live velocity gesture",
            "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, earlierDrag,
                                     Qt::LeftButton);
        return;
    }
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, earlierDrag,
                                 Qt::LeftButton);
    if (!selectionkey::check(
            failures,
            !rigView(*world).userGestureActive() &&
                sameSelection(rigView(*world), {world->notes[0], world->notes[2]}) &&
                rigDocument(*world).smf().write() == velocityBeforeGesture,
            "first Escape did not cancel the velocity gesture and restore its selection",
            "selectionkeygesturecheck"))
        return;
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    if (!selectionkey::check(
            failures, rigView(*world).selectionModel().noteSelection().empty(),
            "second Escape after a velocity gesture did not clear the remaining selection",
            "selectionkeygesturecheck"))
        return;

    rigView(*world).selectionModel().setNoteSelection({world->notes[0], world->notes[2]});
    const QPoint unselectedStem = windowPoint(*surface.input, points->followingStem);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, unselectedStem,
                                 Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, unselectedStem,
                                 Qt::LeftButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, unselectedStem,
                                 Qt::LeftButton);
    if (!selectionkey::check(
            failures, sameSelection(rigView(*world), {world->notes[1]}),
            "clicking an unselected velocity stem did not replace the note selection",
            "selectionkeygesturecheck"))
        return;
}

// Scenario: a roll note drag is a live surface owner — the shared Delete is
// a consumed no-op mid-drag, the first Escape cancels only the drag and
// restores the captured selection, and the idle Escape then clears it.
void rollNoteDragGuardsSharedCommands(int &failures, const QString &projectRoot,
                                      const QString &songLabel)
{
    const auto deleteKey = firstBinding(QStringLiteral("roll.delete"));
    if (!selectionkey::check(failures, deleteKey.has_value(),
                             "roll.delete has no single-key binding", "selectionkeygesturecheck"))
        return;
    QString error;
    auto world = selectionkey::makeRigWorld(
        projectRoot, songLabel, kTrack, gestureNoteSpecs(),
        gestureRigConfig(EditorDrawerPage::Automations, kAutomationSectionHeight),
        prepareGestureDocument, error);
    if (world == nullptr) {
        selectionkey::fail(failures,
                           QStringLiteral("could not create the roll-gesture world: %1").arg(error),
                           "selectionkeygesturecheck");
        return;
    }
    SongView &songView = rigView(*world);
    const QPointer<songview::TimelineInputItem> rollInput = rigInput(*world, "timelineRollInput");
    if (!selectionkey::check(failures, rollInput != nullptr && !rollInput->bounds().isEmpty(),
                             "roll Quick input is unavailable", "selectionkeygesturecheck"))
        return;
    if (!selectionkey::check(failures,
                             focusPointerSurface(songView, rigWindow(*world), rollInput,
                                                 songview::TimelineBand::Roll),
                             "roll drag surface did not own live Quick and native focus",
                             "selectionkeygesturecheck")) {
        return;
    }

    // Reveal through the production SongView seams first (the camera mutators
    // that wrap the shared camera state), then read camera().displayX —
    // computing coordinates from a stale camera is what left the press
    // missing the note. The roll hit-test reads the view model, so the
    // fixture note must also be published there before the press.
    songView.ensureTickVisible(kEarlierTick);
    songView.ensureKeyVisible(kEarlierKey);
    settle();
    // Stage the selection before the press: the gesture captures the
    // pre-press selection, so the cancel-restore assertion needs the same
    // staging order as a user selecting, then dragging.
    songView.selectionModel().setNoteSelection({world->notes[0]});
    const NoteId routedNoteId = world->notes[0];
    if (!selectionkey::check(failures,
                             checks::async_wait::waitUntil(
                                 [] { return true; },
                                 [&songView, routedNoteId] {
                                     const auto &notes = songView.model().notes;
                                     return std::any_of(notes.cbegin(), notes.cend(),
                                                        [routedNoteId](const ViewNote &viewNote) {
                                                            return viewNote.noteId == routedNoteId;
                                                        });
                                 },
                                 5000, 10) == checks::async_wait::Result::Ready,
                             "the roll view model never exposed the fixture note for the gesture",
                             "selectionkeygesturecheck"))
        return;

    const qreal rollDpr = rollInput->devicePixelRatio();
    const qreal rollX = songView.camera().displayX(
        double(kEarlierTick) + double(kEarlierDuration) / 2.0, 0.0, rollDpr);
    const auto rollEdge = [&](int row) {
        return std::round((row * songView.camera().keyHeight() - songView.camera().scrollY()) *
                          rollDpr) /
               rollDpr;
    };
    const qreal rollY = (rollEdge(127 - kEarlierKey) + rollEdge(128 - kEarlierKey)) / 2.0;
    const QPointF rollPoint(rollX, rollY);
    if (!selectionkey::check(
            failures, rollInput->bounds().contains(rollPoint),
            "production roll geometry did not expose the fixture note for the drag",
            "selectionkeygesturecheck"))
        return;
    const QPoint rollPress = windowPoint(*rollInput, rollPoint);
    const QByteArray rollBeforeGesture = rigDocument(*world).smf().write();
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, rollPress, Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, rollPress,
                                 Qt::LeftButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove,
                                 rollPress + QPoint(QApplication::startDragDistance() + 4, 0),
                                 Qt::NoButton);
    if (!selectionkey::check(
            failures, QTest::qWaitFor([&] { return songView.userGestureActive(); }),
            "roll note drag did not become a live gesture", "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, rollPress,
                                     Qt::LeftButton);
        return;
    }
    deliverKey(rigWindow(*world), deleteKey->key(), deleteKey->keyboardModifiers());
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, rollPress,
                                 Qt::LeftButton);
    if (!selectionkey::check(failures,
                             !songView.userGestureActive() &&
                                 rigDocument(*world).smf().write() == rollBeforeGesture &&
                                 sameSelection(songView, {world->notes[0]}),
                             "roll gesture did not block Delete and restore selection on Escape",
                             "selectionkeygesturecheck"))
        return;
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    if (!selectionkey::check(failures, songView.selectionModel().noteSelection().empty(),
                             "idle Escape after roll cancellation did not clear note selection",
                             "selectionkeygesturecheck"))
        return;
}

// Scenario: the automation band's middle-button pan is a live surface owner
// — the shared Delete is a consumed no-op mid-pan, the first Escape cancels
// only the pan and preserves the staged time selection, and the idle Escape
// then clears it.
void automationPanGuardsSharedCommands(int &failures, const QString &projectRoot,
                                       const QString &songLabel)
{
    const auto deleteKey = firstBinding(QStringLiteral("roll.delete"));
    if (!selectionkey::check(failures, deleteKey.has_value(),
                             "roll.delete has no single-key binding", "selectionkeygesturecheck"))
        return;
    QString error;
    auto world = selectionkey::makeRigWorld(
        projectRoot, songLabel, kTrack, gestureNoteSpecs(),
        gestureRigConfig(EditorDrawerPage::Automations, kAutomationSectionHeight),
        prepareGestureDocument, error);
    if (world == nullptr) {
        selectionkey::fail(
            failures,
            QStringLiteral("could not create the automation-gesture world: %1").arg(error),
            "selectionkeygesturecheck");
        return;
    }
    SongView &songView = rigView(*world);
    const QPointer<songview::TimelineInputItem> automationInput =
        rigInput(*world, "timelineAutomationInput");
    AutomationPage *const automation =
        songView.editorDrawer() ? songView.editorDrawer()->automationPage() : nullptr;
    if (!selectionkey::check(
            failures, automation != nullptr && automationInput != nullptr && QTest::qWaitFor([&] {
                          return !automationInput->bounds().isEmpty();
                      }),
            "automation Quick input is unavailable", "selectionkeygesturecheck"))
        return;
    if (!selectionkey::check(failures,
                             focusPointerSurface(songView, rigWindow(*world), automationInput,
                                                 songview::TimelineBand::Automation),
                             "automation pan surface did not own live Quick and native focus",
                             "selectionkeygesturecheck")) {
        return;
    }
    const auto laneRow = [&]() -> std::optional<LaneHandle> {
        const auto &rows = automation->canvas()->rows();
        for (int index = 0; index < int(rows.size()); ++index) {
            const AutomationRow &candidate = rows[std::size_t(index)];
            if (candidate.id.kind == EditorAutomationRowKind::ControlChange &&
                candidate.id.track == kTrack && candidate.id.controller == kAutomationController)
                return LaneHandle{index + 1};
        }
        return std::nullopt;
    };
    const bool presented =
        checks::async_wait::waitUntil([] { return true; }, [&] { return laneRow().has_value(); },
                                      5000, 10) == checks::async_wait::Result::Ready;
    const auto row = presented ? laneRow() : std::nullopt;
    if (!selectionkey::check(failures, row.has_value(), "automation fixture lane was not presented",
                             "selectionkeygesturecheck"))
        return;
    const QRect body = automation->canvas()->laneBody(*row);
    const QPointF automationPoint(songView.camera().displayX(double(kFollowingTick), 0.0,
                                                             automationInput->devicePixelRatio()),
                                  body.center().y() - automation->verticalScroll());
    if (!selectionkey::check(failures, automationInput->bounds().contains(automationPoint),
                             "production automation geometry did not expose the gesture point",
                             "selectionkeygesturecheck"))
        return;
    songView.selectionModel().setTimeSelection(automationSelection());
    const QByteArray automationBeforeGesture = rigDocument(*world).smf().write();
    const QPoint automationPress = windowPoint(*automationInput, automationPoint);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseMove, automationPress,
                                 Qt::NoButton);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonPress, automationPress,
                                 Qt::MiddleButton);
    if (!selectionkey::check(
            failures, QTest::qWaitFor([&] { return songView.userGestureActive(); }),
            "automation pan did not become a live gesture", "selectionkeygesturecheck")) {
        selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease,
                                     automationPress, Qt::MiddleButton);
        return;
    }
    deliverKey(rigWindow(*world), deleteKey->key(), deleteKey->keyboardModifiers());
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    selectionkey::sendMouseEvent(*rigWindow(*world), QEvent::MouseButtonRelease, automationPress,
                                 Qt::MiddleButton);
    if (!selectionkey::check(
            failures,
            !songView.userGestureActive() &&
                rigDocument(*world).smf().write() == automationBeforeGesture &&
                songView.selectionModel().timeSelection().active(),
            "automation gesture did not block Delete and preserve its time selection on "
            "Escape",
            "selectionkeygesturecheck"))
        return;
    QTest::keyClick(rigWindow(*world), Qt::Key_Escape);
    if (!selectionkey::check(
            failures, !songView.selectionModel().timeSelection().active(),
            "second Escape after automation cancellation did not clear time selection",
            "selectionkeygesturecheck"))
        return;
}

// Scenario: a registered scrollbar thumb (root roll bar, nested drawer
// automation bar) is a live gesture surface exactly like the bands — the
// shared Delete is a consumed no-op mid-drag, Escape releases the native
// MouseArea grab, the still-held button cannot move or page the model, and a
// physical release permits a fresh drag before the same binding deletes.
void scrollbarThumbDragGuardsSharedCommands(int &failures, const QString &projectRoot,
                                            const QString &songLabel)
{
    const auto deleteKey = firstBinding(QStringLiteral("roll.delete"));
    if (!selectionkey::check(failures, deleteKey.has_value(),
                             "roll.delete has no single-key binding", "selectionkeygesturecheck"))
        return;
    QString error;
    auto world = selectionkey::makeRigWorld(
        projectRoot, songLabel, kTrack, gestureNoteSpecs(),
        gestureRigConfig(EditorDrawerPage::Automations, kScrollbarAutomationSectionHeight),
        prepareGestureDocument, error);
    if (world == nullptr) {
        selectionkey::fail(
            failures, QStringLiteral("could not create the scrollbar-gesture world: %1").arg(error),
            "selectionkeygesturecheck");
        return;
    }
    SongView &songView = rigView(*world);
    QQuickWindow *const quickWindow = rigWindow(*world);
    AutomationPage *const automation =
        songView.editorDrawer() ? songView.editorDrawer()->automationPage() : nullptr;
    if (!selectionkey::check(failures, quickWindow != nullptr && automation != nullptr,
                             "scrollbar-gesture delivery surface is unavailable",
                             "selectionkeygesturecheck"))
        return;

    struct ThumbSurface {
        const char *bar;
        const char *thumb;
        const char *input;
        const char *label;
        songview::TimelineBand band;
        NoteId victim;
        std::function<qreal()> scrollValue;
    };
    const std::array<ThumbSurface, 2> surfaces{{
        {"timelineRollScrollBar", "timelineRollScrollThumb", "timelineRollInput", "roll scrollbar",
         songview::TimelineBand::Roll, world->notes[0],
         [&] { return songView.camera().scrollY(); }},
        {"drawerAutomationScrollBar", "drawerAutomationScrollThumb", "timelineAutomationInput",
         "automation scrollbar", songview::TimelineBand::Automation, world->notes[2],
         [&] { return automation->verticalScroll(); }},
    }};
    for (const ThumbSurface &surface : surfaces) {
        // Keep the registration surface in the failure line, so a regression
        // names which scrollbar lost its guard.
        const auto surfaceCheck = [&](bool condition, const char *message) {
            if (!condition)
                selectionkey::fail(failures,
                                   QStringLiteral("%1: %2").arg(QLatin1String(surface.label),
                                                                QLatin1String(message)),
                                   "selectionkeygesturecheck");
            return condition;
        };
        if (!surfaceCheck(focusPointerSurface(songView, quickWindow,
                                              rigInput(*world, surface.input), surface.band),
                          "owning timeline band did not have live Quick and native focus")) {
            continue;
        }
        QPointer<QQuickItem> root;
        QPointer<QQuickItem> bar;
        QPointer<QQuickItem> thumb;
        const auto resolveControls = [&] {
            root = world->rig->quickRoot();
            bar = root ? root->findChild<QQuickItem *>(QLatin1String(surface.bar)) : nullptr;
            thumb = root ? root->findChild<QQuickItem *>(QLatin1String(surface.thumb)) : nullptr;
            return bar && thumb;
        };
        if (!surfaceCheck(resolveControls() && bar->isVisible() && thumb->isVisible() &&
                              !thumb->boundingRect().isEmpty() &&
                              bar->property("thumbTravel").toReal() > 0.0,
                          "registered scrollbar thumb was not draggable in the shown window")) {
            continue;
        }

        songView.selectionModel().setNoteSelection({surface.victim});
        const QByteArray beforeDrag = rigDocument(*world).smf().write();
        const qreal scrollBefore = surface.scrollValue();
        const QPointF pressPosition = thumb->mapToScene(thumb->boundingRect().center());
        const qreal activation = QGuiApplication::styleHints()->startDragDistance() + 1.0;
        const QPoint activationPosition = (pressPosition + QPointF(1.0, activation)).toPoint();
        const QPoint dragPosition = activationPosition + QPoint(0, 1);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, pressPosition.toPoint(),
                                     Qt::NoButton);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonPress,
                                     pressPosition.toPoint(), Qt::LeftButton);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, activationPosition,
                                     Qt::NoButton);
        if (!surfaceCheck(QTest::qWaitFor([&] { return songView.userGestureActive(); }),
                          "thumb drag did not become a live gesture")) {
            selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease,
                                         activationPosition, Qt::LeftButton);
            continue;
        }
        // The smoothed native MouseArea drag establishes its threshold
        // baseline on this move. A distinct move after activation is the
        // first one that must displace the proxy and request a model value.
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, dragPosition, Qt::NoButton);
        if (!surfaceCheck(QTest::qWaitFor([&] { return surface.scrollValue() > scrollBefore; }),
                          "thumb drag did not move its owning scroll model")) {
            selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, dragPosition,
                                         Qt::LeftButton);
            continue;
        }
        deliverKey(quickWindow, deleteKey->key(), deleteKey->keyboardModifiers());
        if (!surfaceCheck(rigDocument(*world).smf().write() == beforeDrag &&
                              sameSelection(songView, {surface.victim}),
                          "the registered live gesture did not block the shared Delete")) {
            selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, dragPosition,
                                         Qt::LeftButton);
            continue;
        }
        deliverKey(quickWindow, Qt::Key_Escape);
        if (!surfaceCheck(!songView.userGestureActive(),
                          "Escape did not cancel the registered thumb drag by releasing its "
                          "native mouse grab")) {
            selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, dragPosition,
                                         Qt::LeftButton);
            continue;
        }
        const qreal scrollAfterCancel = surface.scrollValue();
        const QPoint heldMove = dragPosition + QPoint(0, qCeil(activation) + 4);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, heldMove, Qt::NoButton);
        if (!surfaceCheck(surface.scrollValue() == scrollAfterCancel,
                          "movement with the button held after Escape changed the scroll model")) {
            selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, heldMove,
                                         Qt::LeftButton);
            continue;
        }
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, heldMove,
                                     Qt::LeftButton);
        if (!surfaceCheck(!songView.userGestureActive() &&
                              surface.scrollValue() == scrollAfterCancel,
                          "physical release after cancellation changed the scroll model"))
            continue;

        if (!surfaceCheck(resolveControls() && bar->isVisible() && thumb->isVisible() &&
                              !thumb->boundingRect().isEmpty(),
                          "registered scrollbar controls disappeared before the fresh drag")) {
            continue;
        }
        const qreal maximum = bar->property("maximum").toReal();
        const int restartDirection = scrollAfterCancel < maximum ? 1 : -1;
        const QPointF restartPress = thumb->mapToScene(thumb->boundingRect().center());
        const QPoint restartActivation =
            (restartPress + QPointF(1.0, restartDirection * activation)).toPoint();
        const QPoint restartDrag = restartActivation + QPoint(0, restartDirection);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, restartPress.toPoint(),
                                     Qt::NoButton);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonPress, restartPress.toPoint(),
                                     Qt::LeftButton);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, restartActivation,
                                     Qt::NoButton);
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseMove, restartDrag, Qt::NoButton);
        if (!surfaceCheck(QTest::qWaitFor([&] {
                              return songView.userGestureActive() &&
                                     surface.scrollValue() != scrollAfterCancel;
                          }),
                          "a fresh press after physical release did not start a new thumb drag")) {
            selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, restartDrag,
                                         Qt::LeftButton);
            continue;
        }
        selectionkey::sendMouseEvent(*quickWindow, QEvent::MouseButtonRelease, restartDrag,
                                     Qt::LeftButton);
        if (!surfaceCheck(!songView.userGestureActive() &&
                              surface.scrollValue() != scrollAfterCancel,
                          "the fresh thumb drag did not end on physical release"))
            continue;
        deliverKey(quickWindow, deleteKey->key(), deleteKey->keyboardModifiers());
        if (!surfaceCheck(!noteExists(rigDocument(*world), surface.victim) &&
                              rigDocument(*world).smf().write() != beforeDrag,
                          "the shared Delete did not resume after the thumb drag ended"))
            continue;
    }
}

} // namespace

int runSelectionKeyGestureCheck(const QString &projectRoot, const QString &songLabel)
{
    selectionkey::KeymapRestore keymapRestore;
    keymapRestore.registry().resetAll();
    int failures = 0;
    overlapNodeTargetsVisibleNode(failures, projectRoot, songLabel);
    velocityStemDragGuardsEdits(failures, projectRoot, songLabel);
    rollNoteDragGuardsSharedCommands(failures, projectRoot, songLabel);
    automationPanGuardsSharedCommands(failures, projectRoot, songLabel);
    scrollbarThumbDragGuardsSharedCommands(failures, projectRoot, songLabel);
    std::fprintf(stderr, "selectionkeygesturecheck: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
