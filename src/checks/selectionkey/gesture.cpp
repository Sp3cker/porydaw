// Entry point and per-case lifecycle for the selection-keyboard-routing
// gesture Qt Test: exactly one qExec, the live-keymap reset with RAII
// restore, fresh-rig staging, and the failure-safe held-input cleanup. The
// scenarios live beside this file in gesturevelocity.cpp,
// gesturecommands.cpp, and gesturethumbs.cpp; their shared contract is
// gesturecheck.h.

#include "checks/selectionkey/gesturecheck.h"

#include "checks/fwd.hpp"

#include <QApplication>
#include <QEvent>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <utility>

#include "ui/editordrawer/editordrawer.h"

namespace {

// Nothing here: fixture assembly is a member concern so the scenario files
// share one staging seam.

} // namespace

int runSelectionKeyGestureCheck(const QString &projectRoot, const QString &songLabel,
                                const QStringList &qtArguments)
{
    SelectionKeyGestureTest test{projectRoot, songLabel};
    QStringList arguments{QStringLiteral("selectionkey-gesture")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

SelectionKeyGestureTest::SelectionKeyGestureTest(QString projectRoot, QString songLabel)
    : mProjectRoot{std::move(projectRoot)}
    , mSongLabel{std::move(songLabel)}
{}

std::vector<SongDocument::NewNote> SelectionKeyGestureTest::gestureNoteSpecs()
{
    return {{kEarlierTick, kEarlierKey, kEarlierDuration, kVelocity},
            {kFollowingTick, kFollowingKey, kFollowingDuration, kVelocity},
            {kLaterTick, kLaterKey, kLaterDuration, kVelocity}};
}

void SelectionKeyGestureTest::prepareGestureDocument(SongDocument &document)
{
    document.addLanePoint(kTrack, kAutomationController, kFollowingTick, 64);
}

void SelectionKeyGestureTest::initTestCase()
{
    // Snapshot before wiping, exactly like the legacy runner: every scenario
    // resolves roll.delete through the live keymap, and the RAII restore
    // puts any catalog-level overrides back when the test object dies.
    mKeymapRestore.emplace();
    mKeymapRestore->registry().resetAll();
}

void SelectionKeyGestureTest::init()
{
    mHeldButton = Qt::NoButton;
    mLastWindowPos = QPoint();
}

void SelectionKeyGestureTest::cleanup()
{
    // Unconditional quiesce, separate from any verification and independent
    // of how the body ended — including a mid-gesture assertion failure:
    // cancel any surviving interaction, release the recorded held button,
    // then drop any residual Quick grab.
    bool mouseGrabCleared = true;
    if (!mQuickWindow.isNull()) {
        QTest::keyClick(mQuickWindow, Qt::Key_Escape);
        if (mHeldButton != Qt::NoButton)
            QTest::mouseRelease(mQuickWindow, mHeldButton, Qt::NoModifier, mLastWindowPos);
        if (QQuickItem *grabber = mQuickWindow->mouseGrabberItem())
            grabber->ungrabMouse();
        mouseGrabCleared = QTest::qWaitFor(
            [this] { return mQuickWindow.isNull() || !mQuickWindow->mouseGrabberItem(); });
    }
    mHeldButton = Qt::NoButton;
    mLastWindowPos = QPoint();
    mVelocityInput.clear();
    mVelocityArea.clear();
    mRollInput.clear();
    mAutomationInput.clear();
    mQuickWindow.clear();
    mWorld.reset();

    QVERIFY(mouseGrabCleared);
}

bool SelectionKeyGestureTest::stageWorld(const char *worldLabel, EditorDrawerPage activePage,
                                         int sectionHeight)
{
    checks::EditorRigConfig config;
    config.track = kTrack;
    config.activePage = activePage;
    config.sections = {{activePage, sectionHeight}};
    config.timeZoom = 96.0;

    QString error;
    mWorld = selectionkey::makeRigWorld(mProjectRoot, mSongLabel, kTrack, gestureNoteSpecs(),
                                        config, prepareGestureDocument, error);
    if (mWorld == nullptr) {
        QTest::qFail(qPrintable(QStringLiteral("could not create the %1 world: %2")
                                    .arg(QString::fromLatin1(worldLabel), error)),
                     __FILE__, __LINE__);
        return false;
    }
    mQuickWindow = selectionkey::rigWindow(*mWorld);
    if (mQuickWindow.isNull()) {
        QTest::qFail("production Quick window is unavailable", __FILE__, __LINE__);
        return false;
    }
    return true;
}

bool SelectionKeyGestureTest::stageVelocitySurface()
{
    EditorDrawer *const drawer = view().editorDrawer();
    mVelocityInput = selectionkey::rigInput(*mWorld, "timelineVelocityInput");
    mVelocityArea = drawer ? drawer->velocityArea() : nullptr;
    // Every scenario owns a fresh world, so surface exposure is scenario
    // readiness, not global setup.
    const bool ready =
        !mVelocityInput.isNull() && !mVelocityArea.isNull() && QTest::qWaitFor([this] {
            return !mVelocityInput->bounds().isEmpty() && mVelocityInput->window() == mQuickWindow;
        });
    if (!ready)
        QTest::qFail("Velocity Quick delivery surface is unavailable", __FILE__, __LINE__);
    return ready;
}

std::optional<SelectionKeyGestureTest::VelocityStemPoints>
SelectionKeyGestureTest::velocityStemPoints()
{
    const auto point = [this](uint64_t tick) {
        return QPointF(
            view().camera().displayX(double(tick), 0.0, mVelocityInput->devicePixelRatio()),
            mVelocityArea->axis().velocityToY(kVelocity));
    };
    const VelocityStemPoints points{
        point(kEarlierTick + kEarlierDuration / 2),
        point(kFollowingTick),
        point(kFollowingTick + kFollowingDuration * 3 / 4),
    };
    const QRectF bounds = mVelocityInput->bounds();
    if (!bounds.contains(points.earlierStem) || !bounds.contains(points.followingNode) ||
        !bounds.contains(points.followingStem))
        return std::nullopt;
    return points;
}

bool SelectionKeyGestureTest::focusPointerSurface(songview::TimelineInputItem *input,
                                                  songview::TimelineBand band)
{
    const QPointer<songview::TimelineInputItem> liveInput(input);
    if (mQuickWindow.isNull() || liveInput.isNull() ||
        !view().focusTimelineBand(band, Qt::OtherFocusReason))
        return false;
    selectionkey::settle();
    return QTest::qWaitFor([this, &liveInput, band] {
        return liveInput && QGuiApplication::focusWindow() == mQuickWindow &&
               QGuiApplication::focusObject() == liveInput && liveInput->hasActiveFocus() &&
               view().focusedTimelineBand() == band;
    });
}

SongView &SelectionKeyGestureTest::view()
{
    return selectionkey::rigView(*mWorld);
}

SongDocument &SelectionKeyGestureTest::document()
{
    return selectionkey::rigDocument(*mWorld);
}

QQuickWindow *SelectionKeyGestureTest::window()
{
    return mQuickWindow.data();
}

QPoint SelectionKeyGestureTest::windowPoint(const songview::TimelineInputItem &input,
                                            QPointF itemPoint) const
{
    return input.mapToScene(itemPoint).toPoint();
}

bool SelectionKeyGestureTest::noteSelectionIs(const std::vector<NoteId> &expected)
{
    return view().selectionModel().noteSelection() == expected;
}

void SelectionKeyGestureTest::mousePress(Qt::MouseButton button, const QPoint &windowPos)
{
    selectionkey::sendMouseEvent(*mQuickWindow, QEvent::MouseButtonPress, windowPos, button);
    mHeldButton = button;
    mLastWindowPos = windowPos;
}

void SelectionKeyGestureTest::mouseMove(const QPoint &windowPos)
{
    selectionkey::sendMouseEvent(*mQuickWindow, QEvent::MouseMove, windowPos, Qt::NoButton);
    mLastWindowPos = windowPos;
}

void SelectionKeyGestureTest::mouseRelease(Qt::MouseButton button, const QPoint &windowPos)
{
    selectionkey::sendMouseEvent(*mQuickWindow, QEvent::MouseButtonRelease, windowPos, button);
    if (mHeldButton == button)
        mHeldButton = Qt::NoButton;
}
