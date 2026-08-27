#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"

#include "core/velocitymodel.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/velocityaxis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <utility>
#include <vector>

#include <QApplication>
#include <QEvent>
#include <QFontMetricsF>
#include <QImage>
#include <QPainter>
#include <QTemporaryDir>
#include <QToolButton>

#include "core/miditimeline.h"
#include "core/noteid.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"
#include "ui/velocitygesturemodel.h"

namespace {
SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

bool samePixels(const QImage &left, const QImage &right)
{
    if (left.size() != right.size())
        return false;
    for (int y = 0; y < left.height(); ++y) {
        for (int x = 0; x < left.width(); ++x) {
            if (left.pixel(x, y) != right.pixel(x, y))
                return false;
        }
    }
    return true;
}

bool hasColorNear(const QImage &image, const QRect &bounds, const QColor &expected, int tolerance)
{
    const QRect clipped = bounds.intersected(image.rect());
    for (int y = clipped.top(); y <= clipped.bottom(); ++y) {
        for (int x = clipped.left(); x <= clipped.right(); ++x) {
            const QColor actual(image.pixel(x, y));
            if (std::abs(actual.red() - expected.red()) <= tolerance &&
                std::abs(actual.green() - expected.green()) <= tolerance &&
                std::abs(actual.blue() - expected.blue()) <= tolerance) {
                return true;
            }
        }
    }
    return false;
}

bool hasDarkOutlinePixel(const QImage &image, const QPointF center, qreal innerRadius,
                         qreal outerRadius)
{
    const int left = std::max(0, int(std::floor(center.x() - outerRadius)));
    const int right = std::min(image.width() - 1, int(std::ceil(center.x() + outerRadius)));
    const int top = std::max(0, int(std::floor(center.y() - outerRadius)));
    const int bottom = std::min(image.height() - 1, int(std::ceil(center.y() + outerRadius)));
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const qreal dx = qreal(x) + 0.5 - center.x();
            const qreal dy = qreal(y) + 0.5 - center.y();
            const qreal distance = std::hypot(dx, dy);
            if (dx >= 0.0 || distance < innerRadius || distance > outerRadius)
                continue;
            const QColor pixel(image.pixel(x, y));
            if (std::max({pixel.red(), pixel.green(), pixel.blue()}) <= 160 &&
                pixel.red() + pixel.green() + pixel.blue() <= 320) {
                return true;
            }
        }
    }
    return false;
}
void velocityFail(int &failures, bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "velocity-page: FAIL: %s\n", message);
    failures += !condition;
}

QRect toPixels(const QRectF &logical, qreal scale)
{
    return QRect(qRound(logical.x() * scale), qRound(logical.y() * scale),
                 qMax(1, qRound(logical.width() * scale)),
                 qMax(1, qRound(logical.height() * scale)));
}

struct ExpectedVelocityGeometry {
    int plotOrigin;
    int pianoKeyboardWidth;
    int densityThresholdD2;
    int densityThresholdD4;
    qreal nodePaintRadius;
    qreal nodeOutlineDipWidth;
};

ExpectedVelocityGeometry expectedVelocityGeometry()
{
    const int pianoKeyboardWidth = layout::fontPx(13.0 / 3.0);
    return {
        layout::fontPx(17.5 + 13.0 / 3.0), pianoKeyboardWidth,
        layout::fontPx(25.0 / 3.0),        layout::fontPx(24.0),
        layout::fontPxF(7.0 / 24.0),       layout::fontPxF(1.0 / 12.0),
    };
}

struct VelocityAreaEnv {
    SongDocument &document;
    std::unique_ptr<MidiTimeline> &timeline;
    LoadedVoiceGroup &voicegroup;
    const ToneData &directSound;
    const ToneData &square;
    const ToneData &wave;
    const ToneData &noise;
    const std::vector<DocNote> &notes;
    SongView &view;
    VelocityArea &area;
    QWidget *drawer = nullptr;
    QWidget *drawerSections = nullptr;
    QToolButton *velToggle = nullptr;
    QWidget *automationBar = nullptr;
    QToolButton *automationToggle = nullptr;
    QToolButton *detentToggle = nullptr;
    DrawerPageLiveState &live;
    ExpectedVelocityGeometry expected;
    VelocityMap map;
    uint8_t hoveredPsgVelocity = 0;
    std::size_t hoveredPsgLevel = 0;
    qreal imageScale = 1.0;
    qreal outlineRadius = 0.0;
    qreal outlineWidth = 0.0;
};

struct VelocityAreaRig {
    VelocityAreaEnv &env;
    VelocityMap currentMap;
    double nodeX = 0.0;
    DocNote paintFirstBefore{};
    DocNote paintThirdBefore{};
    DocNote graduatedFirst{};
    DocNote graduatedSecond{};

    double paintGestureX(const DocNote &note) const
    {
        return double(env.area.plotOrigin()) +
               double(note.tick) * env.view.pxPerBeat() / double(env.timeline->ticksPerBeat) -
               env.view.viewState().scrollPx;
    }

    QPointF velocityNode(const DocNote &note) const
    {
        const double x =
            double(env.area.plotOrigin()) +
            double(note.tick) * env.live.timeZoom / double(env.timeline->ticksPerBeat) -
            env.live.horizontalScroll;
        const std::optional<std::size_t> level = currentMap.levelOf(note.velocity);
        const bool intrinsic = env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
                               env.area.axis().map().compatibleWith(currentMap);
        const double y = intrinsic && level ? env.area.axis().levelToY(int(*level))
                                            : env.area.axis().velocityToY(note.velocity);
        return QPointF(x, y);
    }
};

int checkDrawerToggleGeometry(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const QRect toggleGroup =
        env.automationToggle && env.velToggle
            ? env.automationToggle->geometry().united(env.velToggle->geometry())
            : QRect{};
    const int pianoKeysCenter = env.area.geometry().x() + env.area.plotOrigin() / 2;
    check(env.velToggle && env.automationBar && env.automationToggle &&
              env.automationBar->geometry().contains(env.velToggle->geometry()) &&
              env.velToggle->x() == env.automationToggle->x() + env.automationToggle->width() +
                                        layout::space(layout::Space::One) &&
              env.velToggle->y() == env.automationToggle->y() &&
              std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
          "drawer toggles must sit together beneath the piano keys");
    return failures;
}

int checkDirectSoundChromeAndFocus(VelocityAreaEnv &env)
{
    auto *detentToggle = env.detentToggle =
        env.drawer->findChild<QToolButton *>(QStringLiteral("velocityDetentToggle"));
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    check(env.detentToggle && env.detentToggle->parentWidget() &&
              env.detentToggle->parentWidget()->objectName() == QStringLiteral("drawerSections") &&
              env.detentToggle->isCheckable() && !env.detentToggle->isChecked() &&
              !env.detentToggle->isEnabled() && !env.detentToggle->isVisible() &&
              env.detentToggle->focusPolicy() == Qt::NoFocus,
          "drawer-owned velocity detent toggle must hide for DirectSound");
    check(env.area.axis().mode() == VelocityAxis::Mode::Continuous &&
              static_cast<const QWidget &>(env.area).accessibleDescription() ==
                  QStringLiteral("Velocity"),
          "DirectSound with no selection should publish the continuous accessible axis");
    check(env.area.focusPolicy() == Qt::ClickFocus && !VelocityAxis::nodesFocusable() &&
              !VelocityAxis::graduationLabelsFocusable(),
          "velocity nodes and ruler labels must add no focus targets");
    return failures;
}

int checkContinuousGraduationDensity(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    env.area.resize(env.expected.plotOrigin + layout::space(layout::Space::Eight),
                    env.expected.densityThresholdD2 + layout::space(layout::Space::One));
    QApplication::processEvents();
    const auto &directSoundLabels = env.area.axis().labels();
    check(env.area.axis().tickCount() == 9 && env.area.axis().labelCount() == 5 &&
              directSoundLabels[0].velocity == 127 && directSoundLabels[1].velocity == 96 &&
              directSoundLabels[2].velocity == 64 && directSoundLabels[3].velocity == 32 &&
              directSoundLabels[4].velocity == 1,
          "DirectSound must retain the original medium-height continuous graduations");
    env.area.resize(env.expected.plotOrigin + layout::space(layout::Space::Eight),
                    env.expected.densityThresholdD4 + layout::space(layout::Space::Six));
    QApplication::processEvents();
    return failures;
}

int checkGridContinuesPastSongEnd(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    // This fixture has no time signature, so the implicit grid is 4/4.
    const auto ticksPerBar = uint64_t{env.timeline->ticksPerBeat} * 4;
    const auto firstBarPastSongEnd = (env.timeline->lengthTicks / ticksPerBar + 1) * ticksPerBar;
    env.area.resize(env.area.plotOrigin() +
                        qCeil(double(firstBarPastSongEnd + env.timeline->ticksPerBeat) *
                              env.live.timeZoom / double(env.timeline->ticksPerBeat)),
                    env.expected.densityThresholdD4 + layout::space(layout::Space::Six));
    QApplication::processEvents();
    const auto gridPastSongEnd = env.area.grab().toImage();
    const auto gridScale = gridPastSongEnd.devicePixelRatio();
    const auto firstBarPastSongEndX =
        qRound((double(env.area.plotOrigin()) + double(firstBarPastSongEnd) * env.live.timeZoom /
                                                    double(env.timeline->ticksPerBeat)) *
               gridScale);
    auto expectedGrid = QImage(gridPastSongEnd.size(), QImage::Format_ARGB32);
    expectedGrid.setDevicePixelRatio(gridScale);
    const auto gridBackground = themes::color(themes::Role::song_view_piano_roll_background).rgba();
    expectedGrid.fill(gridBackground);
    {
        auto expectedGridPainter = QPainter(&expectedGrid);
        env.view.paintGrid(expectedGridPainter,
                           QRect(env.area.plotOrigin(), 0, env.area.plotWidth(), env.area.height()),
                           env.area.plotOrigin());
    }
    const auto pastSongEndBounds = QRect(firstBarPastSongEndX - 2, 0, 5, gridPastSongEnd.height())
                                       .intersected(gridPastSongEnd.rect());
    auto matchedExpectedGrid = false;
    for (int y = pastSongEndBounds.top(); y <= pastSongEndBounds.bottom(); ++y) {
        for (int x = pastSongEndBounds.left(); x <= pastSongEndBounds.right(); ++x) {
            if (expectedGrid.pixel(x, y) != gridBackground &&
                gridPastSongEnd.pixel(x, y) == expectedGrid.pixel(x, y)) {
                matchedExpectedGrid = true;
                break;
            }
        }
        if (matchedExpectedGrid)
            break;
    }
    check(matchedExpectedGrid, "velocity grid must continue to the piano grid beyond the song end");
    return failures;
}

int checkPanClampAtTickZero(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.live.editCursorTick = 0;
    env.view.goToStart();
    env.live.timeZoom = env.view.pxPerBeat();
    env.live.horizontalScroll = env.view.viewState().scrollPx;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const auto beforePanPastZero = env.area.grab().toImage();
    const auto panStart =
        QPointF(env.area.plotOrigin() + layout::space(layout::Space::Two), env.area.height() / 2.0);
    const auto panLeftPastZero = panStart + QPointF(layout::space(layout::Space::Eight), 0.0);
    checks::events::sendMouse(env.area, QEvent::MouseButtonPress, panStart, Qt::MiddleButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(env.area, QEvent::MouseMove, panLeftPastZero, Qt::NoButton,
                              Qt::MiddleButton, Qt::NoModifier);
    checks::events::sendMouse(env.area, QEvent::MouseButtonRelease, panLeftPastZero,
                              Qt::MiddleButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto afterPanPastZero = env.area.grab().toImage();
    check(env.view.viewState().scrollPx == env.live.horizontalScroll &&
              samePixels(beforePanPastZero, afterPanPastZero),
          "panning left at tick zero must not visually overscroll the velocity lane");
    return failures;
}

int checkPsgAxisContexts(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId, env.notes[1].noteId});
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    env.voicegroup.voices[0] = env.square;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              static_cast<const QWidget &>(env.area).accessibleDescription() ==
                  QStringLiteral("Velocity. Square 1 has 16 volume levels."),
          "compatible Square selection should publish intrinsic graduations");
    env.voicegroup.voices[0] = env.wave;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              env.area.axis().graduationCount() == 5 &&
              static_cast<const QWidget &>(env.area).accessibleDescription() ==
                  QStringLiteral("Velocity. Programmable Wave has 5 volume levels."),
          "Wave selection should publish five intrinsic graduations");
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              env.area.axis().graduationCount() == 16 &&
              static_cast<const QWidget &>(env.area).accessibleDescription() ==
                  QStringLiteral("Velocity. Noise has 16 volume levels."),
          "Noise selection should publish all intrinsic graduations");

    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    return failures;
}

int checkHoverAxisContext(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.area.resize(env.expected.plotOrigin +
                        qCeil(double(env.timeline->lengthTicks) * env.live.timeZoom /
                              double(env.timeline->ticksPerBeat)) +
                        layout::space(layout::Space::Two),
                    env.expected.densityThresholdD4 + layout::space(layout::Space::Six));
    QApplication::processEvents();
    env.map = VelocityMap::resolve(&env.noise, env.notes[0].key);
    env.hoveredPsgVelocity = 74;
    env.hoveredPsgLevel = 9;
    check(env.view.beginVelocityGesture({env.notes[1]}) &&
              env.view.updateVelocityGesture({{env.notes[1].noteId, env.hoveredPsgVelocity}}),
          "could not stage the nonrepresentative PSG hover velocity");
    QApplication::processEvents();
    std::array<ToneData, 128> hoverSplitChildren{};
    hoverSplitChildren[60] = env.noise;
    hoverSplitChildren[64] = env.wave;
    ToneData hoverSplit{};
    hoverSplit.type = VOICE_KEYSPLIT_ALL;
    hoverSplit.subGroup = hoverSplitChildren.data();
    env.voicegroup.voices[0] = hoverSplit;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[2].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const VelocityMap selectedMap = VelocityMap::resolve(&env.wave, env.notes[2].key);
    const VelocityAxis hoveredNoiseProjection(env.map, env.area.axis().geometry());
    check(env.area.axis().map() == selectedMap && selectedMap != env.map,
          "hover context fixture must begin on the selected Wave note");
    checks::events::sendMouse(env.area, QEvent::MouseMove,
                              QPointF(double(env.area.plotOrigin()) +
                                          double(env.notes[1].tick) * env.live.timeZoom /
                                              double(env.timeline->ticksPerBeat) -
                                          env.live.horizontalScroll,
                                      hoveredNoiseProjection.levelToY(int(env.hoveredPsgLevel))),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto &contextGraduations = env.area.axis().graduations();
    check(env.area.axis().map() == env.map &&
              env.area.axis().graduationCount() == env.map.levelCount() &&
              contextGraduations[env.hoveredPsgLevel].active,
          "hovered PSG node must replace an incompatible selected-note axis context");
    QEvent mismatchedContextLeave(QEvent::Leave);
    QApplication::sendEvent(&env.area, &mismatchedContextLeave);
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    return failures;
}

int checkVelocityRendering(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const std::optional<std::size_t> selectedLevel = env.map.levelOf(env.notes[0].velocity);
    const std::optional<std::size_t> unselectedLevel = env.map.levelOf(env.notes[1].velocity);
    const double paintNodeX =
        double(env.area.plotOrigin()) +
        double(env.notes[0].tick) * env.live.timeZoom / double(env.timeline->ticksPerBeat) -
        env.live.horizontalScroll;
    const double selectedY = selectedLevel ? env.area.axis().levelToY(int(*selectedLevel))
                                           : env.area.axis().velocityToY(env.notes[0].velocity);
    const double unselectedY = env.area.axis().levelToY(int(env.hoveredPsgLevel));
    const QImage velocityImage = env.area.grab().toImage();
    const qreal imageScale = velocityImage.devicePixelRatio();
    env.imageScale = imageScale;
    const QColor expectedStem = songview::mixTowardOklab(env.live.trackColor, Qt::black, 1.0 / 3.0);
    const QRect velocityLabelBounds =
        toPixels(QRectF(double(layout::space(layout::Space::Two)), 0.0,
                        double(env.area.plotOrigin() - 2 * layout::space(layout::Space::Two)),
                        env.area.height()),
                 env.imageScale);
    checks::events::sendMouse(env.area, QEvent::MouseMove, QPointF(paintNodeX, unselectedY),
                              Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage hoveredVelocityImage = env.area.grab().toImage();
    const auto &hoveredGraduations = env.area.axis().graduations();
    const auto activeHoveredGraduationCount = std::count_if(
        hoveredGraduations.begin(), hoveredGraduations.begin() + env.area.axis().graduationCount(),
        [](const VelocityAxisGraduation &graduation) { return graduation.active; });
    const auto hoveredPreview = env.view.previewVelocity(env.notes[1].noteId);
    check(env.area.useDetents() && env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              hoveredPreview && *hoveredPreview == env.hoveredPsgVelocity &&
              env.map.representative(int(env.hoveredPsgLevel)) == 76 &&
              hoveredGraduations[env.hoveredPsgLevel].active && activeHoveredGraduationCount == 1 &&
              !samePixels(velocityImage.copy(velocityLabelBounds),
                          hoveredVelocityImage.copy(velocityLabelBounds)),
          "with PSG detents enabled, hovering MIDI velocity 74 must isolate Noise Vol 10 "
          "instead of raw MIDI 74");
    env.area.setUseDetents(false);
    QApplication::processEvents();
    const QImage rawHoveredVelocityImage = env.area.grab().toImage();
    const auto &rawHoveredMarkers = env.area.axis().markers();
    check(!env.area.useDetents() && env.area.axis().markerCount() == 1 &&
              rawHoveredMarkers[0].velocity == env.hoveredPsgVelocity &&
              std::abs(rawHoveredMarkers[0].y -
                       env.area.axis().velocityToY(env.hoveredPsgVelocity)) < 0.001 &&
              !samePixels(hoveredVelocityImage.copy(velocityLabelBounds),
                          rawHoveredVelocityImage.copy(velocityLabelBounds)),
          "with PSG detents disabled, hovering MIDI velocity 74 must isolate raw MIDI 74");
    env.area.setUseDetents(true);
    QEvent velocityLeave(QEvent::Leave);
    QApplication::sendEvent(&env.area, &velocityLeave);
    QApplication::processEvents();
    const QImage restoredVelocityImage = env.area.grab().toImage();
    check(samePixels(velocityImage.copy(velocityLabelBounds),
                     restoredVelocityImage.copy(velocityLabelBounds)),
          "leaving a hovered velocity node must restore the graduation labels");
    const QRect stemBounds =
        toPixels(QRectF(paintNodeX + 8.0, unselectedY - 3.0, 16.0, 6.0), env.imageScale);
    const QPointF unselectedNodeCenter(paintNodeX * env.imageScale, unselectedY * env.imageScale);
    const qreal outlineRadius = env.expected.nodePaintRadius * env.imageScale;
    const qreal outlineWidth = env.expected.nodeOutlineDipWidth * env.imageScale;
    env.outlineRadius = outlineRadius;
    env.outlineWidth = outlineWidth;
    const QRect selectedRingBounds =
        toPixels(QRectF(paintNodeX - 6.0, selectedY - 6.0, 4.0, 12.0), env.imageScale);
    check(selectedLevel && unselectedLevel &&
              hasColorNear(velocityImage, stemBounds, expectedStem, 4),
          "unselected velocity duration stems must use the OKLab track shade");
    check(hasDarkOutlinePixel(velocityImage, unselectedNodeCenter,
                              std::max(0.0, env.outlineRadius - env.outlineWidth),
                              env.outlineRadius + env.outlineWidth),
          "unselected velocity nodes must retain black outlines");
    check(
        hasColorNear(velocityImage, selectedRingBounds, env.area.palette().highlight().color(), 16),
        "selected velocity nodes must retain selection rings");
    const QRect unselectedNodeFillBounds =
        toPixels(QRectF(paintNodeX - 3.0, unselectedY - 3.0, 6.0, 6.0), env.imageScale);
    check(hasColorNear(velocityImage, unselectedNodeFillBounds, env.live.trackColor, 4),
          "a single-node selection must preserve unselected velocity node colors");
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId, env.notes[2].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const QImage multiSelectionImage = env.area.grab().toImage();
    check(hasColorNear(multiSelectionImage, unselectedNodeFillBounds,
                       env.area.palette().mid().color(), 4),
          "nodes outside a multi-node velocity selection must turn gray");
    check(!hasDarkOutlinePixel(multiSelectionImage, unselectedNodeCenter,
                               std::max(0.0, env.outlineRadius - env.outlineWidth),
                               env.outlineRadius + env.outlineWidth),
          "nodes outside a multi-node velocity selection must omit their outlines");
    env.view.cancelVelocityGesture();
    QApplication::processEvents();
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    const QRect rulerAccentBounds =
        toPixels(QRectF(double(env.area.plotOrigin() - layout::singlePixel() -
                               3 * layout::space(layout::Space::Half) - 1),
                        selectedY - 2.0, double(3 * layout::space(layout::Space::Half) + 2), 4.0),
                 env.imageScale);
    check(
        hasColorNear(velocityImage, rulerAccentBounds, env.area.palette().highlight().color(), 16),
        "intrinsic ruler paint must preserve the emphasized accent tick");
    return failures;
}

int checkEditCursorRepaint(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const qreal imageScale = env.imageScale;
    env.live.editCursorTick = 12;
    env.area.refreshLiveState(env.live);
    const QImage firstEditCursor = env.area.grab().toImage();
    env.live.editCursorTick = 18;
    env.area.refreshLiveState(env.live);
    const QImage secondEditCursor = env.area.grab().toImage();
    const qreal cursorX = (double(env.area.plotOrigin()) +
                           18.0 * env.live.timeZoom / double(env.timeline->ticksPerBeat) -
                           env.live.horizontalScroll) *
                          env.imageScale;
    const QRect cursorBounds(qRound(cursorX) - 2, 0, 5, secondEditCursor.height());
    check(!samePixels(firstEditCursor, secondEditCursor),
          "moving the edit cursor must repaint the velocity lane");
    check(hasColorNear(secondEditCursor, cursorBounds,
                       themes::color(themes::Role::song_view_edit_cursor), 16),
          "velocity lane must paint the shared edit cursor");
    return failures;
}

int checkDrawerContextTickRounding(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.area.clearTrackHeaderSelection();
    check(env.view.selectionModel().noteSelection().empty(),
          "plain track-header clearing must clear shared NoteId selection");
    env.live.playback.playing = true;
    const std::array<double, 4> contextInputs = {-1.0, 0.49, 0.5, 0.51};
    const auto checkContextRounding = [&](const ToneData *tone, VelocityAxis::Mode expectedMode,
                                          const char *message) {
        env.voicegroup.voices[0] = *tone;
        env.view.setVoicegroup(&env.voicegroup);
        env.area.songChanged();
        ++env.live.editCursorTick;
        bool rounded = true;
        for (const double input : contextInputs) {
            env.live.playback.playheadTick = input;
            env.area.refreshLiveState(env.live);
            rounded = rounded && env.view.voiceContext(drawerContextTick(input)).voice ==
                                     &env.voicegroup.voices[0];
        }
        check(rounded && env.area.axis().mode() == expectedMode, message);
    };
    checkContextRounding(&env.directSound, VelocityAxis::Mode::Continuous,
                         "continuous context must use drawerContextTick");
    checkContextRounding(&env.square, VelocityAxis::Mode::Intrinsic,
                         "Square context must use drawerContextTick");
    checkContextRounding(&env.wave, VelocityAxis::Mode::Intrinsic,
                         "Wave context must use drawerContextTick");
    checkContextRounding(&env.noise, VelocityAxis::Mode::Intrinsic,
                         "Noise context must use drawerContextTick");
    return failures;
}

int checkRelativeDragDefersCommit(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const auto rebuildConnection =
        QObject::connect(&rig.env.document, &SongDocument::documentChanged, &rig.env.view, [&] {
            auto rebuilt = rig.env.document.buildTimeline(48000.0);
            if (!rebuilt)
                return;
            rig.env.timeline = std::move(rebuilt);
            rig.env.view.updateSong(rig.env.timeline.get());
        });
    rig.env.view.selectionModel().setNoteSelection(
        {rig.env.notes[0].noteId, rig.env.notes[1].noteId});
    rig.env.live.playback.playing = false;
    rig.env.live.editCursorTick++;
    rig.env.area.refreshLiveState(rig.env.live);
    const int undoDepth = rig.env.document.undoStack()->count();
    const uint64_t revisionBeforeGesture = rig.env.document.revision();
    const std::optional<std::size_t> selectedPsgLevel =
        rig.env.map.levelOf(rig.env.notes[0].velocity);
    const double nodeX = double(rig.env.area.plotOrigin()) +
                         double(rig.env.notes[0].tick) * rig.env.live.timeZoom /
                             double(rig.env.timeline->ticksPerBeat) -
                         rig.env.live.horizontalScroll;
    rig.nodeX = nodeX;
    const double nodeY = selectedPsgLevel
                             ? rig.env.area.axis().levelToY(int(*selectedPsgLevel))
                             : rig.env.area.axis().velocityToY(rig.env.notes[0].velocity);
    check(rig.env.area.axis().mode() == VelocityAxis::Mode::Intrinsic && selectedPsgLevel &&
              nodeY != rig.env.area.axis().velocityToY(rig.env.notes[0].velocity),
          "compatible intrinsic notes must use their categorical graduation");
    const QPointF node(rig.nodeX, nodeY);
    const double stemX = rig.nodeX + double(rig.env.notes[0].duration) * rig.env.live.timeZoom /
                                         double(rig.env.timeline->ticksPerBeat) * 0.5;
    const QPointF stem(stemX, nodeY);
    const QPointF firstDrag = stem + QPointF(0.0, double(rig.env.area.height()));
    const QPointF drag = stem + QPointF(0.0, -double(rig.env.area.height()));
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, stem, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseMove, firstDrag, Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
              std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[1].noteId}),
          "dragging selected velocity nodes must preserve their shared selection");
    const auto firstPreviewFirst = rig.env.view.previewVelocity(rig.env.notes[0].noteId);
    const auto firstPreviewSecond = rig.env.view.previewVelocity(rig.env.notes[1].noteId);
    DocNote draggedFirst;
    DocNote draggedSecond;
    check(
        rig.env.document.findNote(rig.env.notes[0].noteId, &draggedFirst) &&
            rig.env.document.findNote(rig.env.notes[1].noteId, &draggedSecond) &&
            draggedFirst.velocity == rig.env.notes[0].velocity &&
            draggedSecond.velocity == rig.env.notes[1].velocity && firstPreviewFirst &&
            firstPreviewSecond && *firstPreviewFirst != rig.env.notes[0].velocity &&
            *firstPreviewSecond != rig.env.notes[1].velocity &&
            rig.env.document.revision() == revisionBeforeGesture &&
            rig.env.document.undoStack()->count() == undoDepth,
        "velocity drag moves must update preview without changing document revision or undo depth");
    const QImage activeDrag = rig.env.area.grab().toImage();
    const uint8_t firstPreviewVelocity = firstPreviewFirst.value_or(rig.env.notes[0].velocity);
    const std::optional<std::size_t> firstDraggedLevel = rig.env.map.levelOf(firstPreviewVelocity);
    const double firstDraggedY = firstDraggedLevel
                                     ? rig.env.area.axis().levelToY(int(*firstDraggedLevel))
                                     : rig.env.area.axis().velocityToY(firstPreviewVelocity);
    const QRect activeDragRing = toPixels(QRectF(rig.nodeX - 6.0, firstDraggedY - 6.0, 4.0, 12.0),
                                          activeDrag.devicePixelRatio());
    check(hasColorNear(activeDrag, activeDragRing, rig.env.area.palette().highlight().color(), 16),
          "dragging a selected velocity node must retain its visible selection ring");
    checks::events::sendMouse(rig.env.area, QEvent::MouseMove, drag, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    const auto finalPreviewFirst = rig.env.view.previewVelocity(rig.env.notes[0].noteId);
    const auto finalPreviewSecond = rig.env.view.previewVelocity(rig.env.notes[1].noteId);
    check(finalPreviewFirst && finalPreviewSecond && firstPreviewFirst &&
              *finalPreviewFirst != *firstPreviewFirst &&
              rig.env.document.revision() == revisionBeforeGesture &&
              rig.env.document.undoStack()->count() == undoDepth,
          "successive velocity updates must remain deferred while the drag is held");
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, drag, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QObject::disconnect(rebuildConnection);
    DocNote committedFirst;
    DocNote committedSecond;
    check(rig.env.document.revision() == revisionBeforeGesture + 1 &&
              rig.env.document.undoStack()->count() == undoDepth + 1 &&
              !rig.env.view.previewVelocity(rig.env.notes[0].noteId) &&
              !rig.env.view.previewVelocity(rig.env.notes[1].noteId) && finalPreviewFirst &&
              finalPreviewSecond &&
              rig.env.document.findNote(rig.env.notes[0].noteId, &committedFirst) &&
              rig.env.document.findNote(rig.env.notes[1].noteId, &committedSecond) &&
              committedFirst.velocity == *finalPreviewFirst &&
              committedSecond.velocity == *finalPreviewSecond &&
              rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[1].noteId}),
          "relative drag must commit both final previews in one batch and preserve selection");
    const std::vector<NoteId> selectedBeforeUndo = rig.env.view.selectionModel().noteSelection();
    rig.env.document.undoStack()->undo();
    rig.env.area.documentChanged();
    rig.env.live.documentRevision = rig.env.document.revision();
    rig.env.area.refreshLiveState(rig.env.live);
    QApplication::processEvents();
    check(rig.env.view.selectionModel().noteSelection() == selectedBeforeUndo,
          "Undo must preserve the shared selection identities of surviving notes");
    DocNote restoredFirst;
    check(rig.env.document.findNote(rig.env.notes[0].noteId, &restoredFirst),
          "click-collapse fixture must resolve the restored velocity note");
    const std::optional<std::size_t> restoredLevel = rig.env.map.levelOf(restoredFirst.velocity);
    const QPointF restoredNode(
        rig.nodeX, restoredLevel ? rig.env.area.axis().levelToY(int(*restoredLevel))
                                 : rig.env.area.axis().velocityToY(restoredFirst.velocity));
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, restoredNode, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, restoredNode,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
              std::vector<NoteId>{rig.env.notes[0].noteId},
          "clicking one selected velocity node must collapse the other selected nodes");
    return failures;
}

int checkUngrabCancelsProvisionalSelection(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
    ++rig.env.live.editCursorTick;
    rig.env.area.refreshLiveState(rig.env.live);
    const std::optional<std::size_t> secondLevel = rig.env.map.levelOf(rig.env.notes[1].velocity);
    const QPointF secondNode(
        rig.nodeX, secondLevel ? rig.env.area.axis().levelToY(int(*secondLevel))
                               : rig.env.area.axis().velocityToY(rig.env.notes[1].velocity));
    const int undoDepthBeforeUngrab = rig.env.document.undoStack()->count();
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, secondNode, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    QEvent ungrabMouse(QEvent::UngrabMouse);
    QApplication::sendEvent(&rig.env.area, &ungrabMouse);
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId} &&
              rig.env.document.undoStack()->count() == undoDepthBeforeUngrab,
          "mouse ungrab must cancel a provisional selection without history residue");
    return failures;
}

int checkDragBandOverlay(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const QRect selectorProbe(rig.env.area.plotOrigin() + layout::space(layout::Space::One),
                              rig.env.area.height() / 3, 2 * layout::space(layout::Space::Eight),
                              layout::space(layout::Space::Eight));
    const auto grabSelectorProbe = [&rig, &selectorProbe] {
        const QImage image = rig.env.area.grab().toImage();
        const qreal dpr = image.devicePixelRatio();
        const int left = qFloor(selectorProbe.left() * dpr);
        const int top = qFloor(selectorProbe.top() * dpr);
        const int right = qCeil((selectorProbe.left() + selectorProbe.width()) * dpr);
        const int bottom = qCeil((selectorProbe.top() + selectorProbe.height()) * dpr);
        return image.copy(QRect(left, top, right - left, bottom - top));
    };
    const QPointF selectorStart(selectorProbe.left(), selectorProbe.top());
    const QPointF selectorEnd(selectorProbe.right(), selectorProbe.bottom());
    const QPointF selectorContractedEnd =
        selectorStart + QPointF(selectorProbe.width() / 2.0, selectorProbe.height() / 2.0);
    const auto abandonedCorner = [](const QImage &image) {
        return image.copy(QRect(image.width() * 3 / 4, image.height() * 3 / 4, image.width() / 4,
                                image.height() / 4));
    };
    const QImage bandBaseline = grabSelectorProbe();
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, selectorStart,
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseMove, selectorEnd, Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage activeBand = grabSelectorProbe();
    check(!samePixels(bandBaseline, activeBand),
          "drag-select must visibly paint its selector overlay");
    QColor selectionFill = themes::color(themes::Role::song_view_selection_fill);
    selectionFill.setAlpha(30);
    const auto blendedChannel = [&selectionFill](int background, int foreground) {
        return (foreground * selectionFill.alpha() + background * (255 - selectionFill.alpha()) +
                127) /
               255;
    };
    const auto channelDifference = [](int left, int right) { return std::abs(left - right); };
    const int interiorMargin = qCeil(2.0 * activeBand.devicePixelRatio());
    int sampledPixels = 0;
    int translucentPixels = 0;
    for (int y = interiorMargin; y < activeBand.height() - interiorMargin; ++y) {
        for (int x = interiorMargin; x < activeBand.width() - interiorMargin; ++x) {
            const QColor baselinePixel(bandBaseline.pixel(x, y));
            const QColor activePixel(activeBand.pixel(x, y));
            const QColor expectedPixel(blendedChannel(baselinePixel.red(), selectionFill.red()),
                                       blendedChannel(baselinePixel.green(), selectionFill.green()),
                                       blendedChannel(baselinePixel.blue(), selectionFill.blue()));
            ++sampledPixels;
            if (channelDifference(activePixel.red(), expectedPixel.red()) <= 1 &&
                channelDifference(activePixel.green(), expectedPixel.green()) <= 1 &&
                channelDifference(activePixel.blue(), expectedPixel.blue()) <= 1) {
                ++translucentPixels;
            }
        }
    }
    check(sampledPixels > 0 && translucentPixels * 2 >= sampledPixels,
          "drag-select must composite the translucent selection fill over velocity content");
    checks::events::sendMouse(rig.env.area, QEvent::MouseMove, selectorContractedEnd, Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage contractedBand = grabSelectorProbe();
    check(!samePixels(bandBaseline, contractedBand) &&
              samePixels(abandonedCorner(bandBaseline), abandonedCorner(contractedBand)),
          "contracting drag-select must clear the abandoned selector area");
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, selectorContractedEnd,
                              Qt::RightButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    check(samePixels(bandBaseline, grabSelectorProbe()),
          "completed drag-select must clear its selector overlay");

    rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
    ++rig.env.live.editCursorTick;
    rig.env.area.refreshLiveState(rig.env.live);
    QApplication::processEvents();
    const QImage cancelledBandBaseline = grabSelectorProbe();
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, selectorStart,
                              Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseMove, selectorEnd, Qt::NoButton,
                              Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    QEvent cancelBand(QEvent::UngrabMouse);
    QApplication::sendEvent(&rig.env.area, &cancelBand);
    QApplication::processEvents();
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId} &&
              samePixels(cancelledBandBaseline, grabSelectorProbe()),
          "cancelled drag-select must clear its selector overlay and restore selection");
    rig.env.live.documentRevision = rig.env.document.revision();
    rig.env.area.refreshLiveState(rig.env.live);
    QApplication::processEvents();
    return failures;
}

int checkStackedNodeHitPriority(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    DocNote currentFirst;
    DocNote currentSecond;
    check(rig.env.document.findNote(rig.env.notes[0].noteId, &currentFirst) &&
              rig.env.document.findNote(rig.env.notes[1].noteId, &currentSecond),
          "velocity node click fixture must resolve its notes");
    rig.env.document.setNotesVelocity({currentSecond}, currentFirst.velocity);
    rig.env.live.documentRevision = rig.env.document.revision();
    rig.env.area.refreshLiveState(rig.env.live);
    QApplication::processEvents();
    rig.currentMap = VelocityMap::resolve(&rig.env.noise, currentFirst.key);
    const std::optional<std::size_t> currentLevel = rig.currentMap.levelOf(currentFirst.velocity);
    const QPointF currentNode(double(rig.env.area.plotOrigin()) +
                                  double(currentFirst.tick) * rig.env.live.timeZoom /
                                      double(rig.env.timeline->ticksPerBeat) -
                                  rig.env.live.horizontalScroll,
                              currentLevel
                                  ? rig.env.area.axis().levelToY(int(*currentLevel))
                                  : rig.env.area.axis().velocityToY(currentFirst.velocity));
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, currentNode, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, currentNode, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
              std::vector<NoteId>{rig.env.notes[0].noteId},
          "selected velocity node must win a stacked-node click");
    rig.env.document.addNote(0, currentFirst.tick + 8, currentFirst.key, currentFirst.duration,
                             currentFirst.velocity);
    rig.env.live.documentRevision = rig.env.document.revision();
    rig.env.area.refreshLiveState(rig.env.live);
    QApplication::processEvents();
    const std::vector<DocNote> overlapFixtureNotes = rig.env.document.notesForTrack(0);
    rig.env.live.timeZoom = rig.env.view.pxPerBeat();
    rig.env.live.horizontalScroll = rig.env.view.viewState().scrollPx;
    const auto overlapIt = std::find_if(overlapFixtureNotes.cbegin(), overlapFixtureNotes.cend(),
                                        [&currentFirst](const DocNote &note) {
                                            return note.tick == currentFirst.tick + 8 &&
                                                   note.noteId != currentFirst.noteId;
                                        });
    check(overlapIt != overlapFixtureNotes.cend(),
          "velocity overlap fixture must add a circle candidate beside a duration stem");
    if (overlapIt != overlapFixtureNotes.cend()) {
        const DocNote overlapNote = *overlapIt;
        const auto velocityNode = [&rig](const DocNote &note) {
            const double x =
                double(rig.env.area.plotOrigin()) +
                double(note.tick) * rig.env.live.timeZoom / double(rig.env.timeline->ticksPerBeat) -
                rig.env.live.horizontalScroll;
            const std::optional<std::size_t> level = rig.currentMap.levelOf(note.velocity);
            const bool intrinsic = rig.env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
                                   rig.env.area.axis().map().compatibleWith(rig.currentMap);
            const double y = intrinsic && level ? rig.env.area.axis().levelToY(int(*level))
                                                : rig.env.area.axis().velocityToY(note.velocity);
            return QPointF(x, y);
        };
        rig.env.view.selectionModel().setNoteSelection({});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF stackedNode = velocityNode(currentFirst);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, stackedNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[1].noteId},
              "overlapping circles must resolve to one later-painted target");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, stackedNode,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[1].noteId},
              "overlapping-circle release must retain its frozen target");
        ++rig.env.live.editCursorTick;
        rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF selectedStackedNode = velocityNode(currentFirst);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, selectedStackedNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId},
              "selected overlapping velocity nodes must outrank unselected candidates");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, selectedStackedNode,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId},
              "selected-layer velocity click must keep its selected target");
        rig.env.view.selectionModel().setNoteSelection({});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF circleNode = velocityNode(overlapNote);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, circleNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage circleHeld = rig.env.area.grab().toImage();
        const QRect circleRingBounds = toPixels(
            QRectF(circleNode.x() - 6.0, circleNode.y() - 6.0, 4.0, 12.0), rig.env.imageScale);
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>{overlapNote.noteId} &&
                  hasColorNear(circleHeld, circleRingBounds,
                               rig.env.area.palette().highlight().color(), 16),
              "a circle hit must outrank stem-only overlap and paint one selected ring");
        const QPointF movedRelease = velocityNode(currentFirst);
        checks::events::sendMouse(rig.env.area, QEvent::MouseMove, movedRelease, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{overlapNote.noteId},
              "a velocity gesture must retain its frozen target while the cursor moves");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, movedRelease,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{overlapNote.noteId},
              "moving release away from a velocity node must not click through to another target");
        const DocNote rightTarget = rig.env.notes[2];
        rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF rightTargetNode = velocityNode(rightTarget);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, rightTargetNode,
                                  Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage rightNodeHeld = rig.env.area.grab().toImage();
        const QRect rightNodeRingBounds =
            toPixels(QRectF(rightTargetNode.x() - 6.0, rightTargetNode.y() - 6.0, 4.0, 12.0),
                     rig.env.imageScale);
        check(
            rig.env.view.selectionModel().noteSelection() ==
                    std::vector<NoteId>{rightTarget.noteId} &&
                hasColorNear(rightNodeHeld, rightNodeRingBounds,
                             rig.env.area.palette().highlight().color(), 16),
            "plain right press on an unselected velocity node must select and ring it immediately");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, rightTargetNode,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage rightNodeReleased = rig.env.area.grab().toImage();
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>{rightTarget.noteId} &&
                  hasColorNear(rightNodeReleased, rightNodeRingBounds,
                               rig.env.area.palette().highlight().color(), 16),
              "plain right release must retain its selected velocity node and ring");
        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rightTarget.noteId});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF selectedRightNode = velocityNode(currentFirst);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, selectedRightNode,
                                  Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage selectedRightHeld = rig.env.area.grab().toImage();
        const QRect selectedRightRingBounds =
            toPixels(QRectF(selectedRightNode.x() - 6.0, selectedRightNode.y() - 6.0, 4.0, 12.0),
                     rig.env.imageScale);
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({rig.env.notes[0].noteId, rightTarget.noteId}) &&
                  hasColorNear(selectedRightHeld, selectedRightRingBounds,
                               rig.env.area.palette().highlight().color(), 16),
              "plain right press on a selected velocity node must retain its visual group");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, selectedRightNode,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage selectedRightReleased = rig.env.area.grab().toImage();
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({rig.env.notes[0].noteId, rightTarget.noteId}) &&
                  hasColorNear(selectedRightReleased, selectedRightRingBounds,
                               rig.env.area.palette().highlight().color(), 16),
              "plain right release on a selected velocity node must retain its group ring");
        rig.env.document.deleteNotes({overlapNote});
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
    }
    return failures;
}

int checkPaintGestureDefersCommit(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    rig.env.view.selectionModel().setNoteSelection(
        {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
    rig.env.document.findNote(rig.env.notes[0].noteId, &rig.paintFirstBefore);
    rig.env.document.findNote(rig.env.notes[2].noteId, &rig.paintThirdBefore);
    const QPointF paintStart(rig.paintGestureX(rig.paintFirstBefore),
                             rig.env.area.axis().levelToY(0));
    const QPointF paintEnd(rig.paintGestureX(rig.paintThirdBefore),
                           rig.env.area.axis().levelToY(4));
    const uint64_t revisionBeforePaint = rig.env.document.revision();
    const int undoIndexBeforePaint = rig.env.document.undoStack()->index();
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, paintStart, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseMove, paintEnd, Qt::NoButton,
                              Qt::LeftButton, Qt::NoModifier);
    const auto paintPreviewFirst = rig.env.view.previewVelocity(rig.env.notes[0].noteId);
    const auto paintPreviewThird = rig.env.view.previewVelocity(rig.env.notes[2].noteId);
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[2].noteId}) &&
              rig.env.document.revision() == revisionBeforePaint &&
              rig.env.document.undoStack()->index() == undoIndexBeforePaint && paintPreviewFirst &&
              paintPreviewThird && *paintPreviewFirst == rig.currentMap.representative(0) &&
              *paintPreviewThird == rig.currentMap.representative(4),
          "holding velocity paint must update preview while deferring document changes");
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, paintEnd, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote paintedFirst;
    DocNote paintedThird;
    check(rig.env.document.revision() == revisionBeforePaint + 1 &&
              rig.env.document.undoStack()->index() == undoIndexBeforePaint + 1 &&
              !rig.env.view.previewVelocity(rig.env.notes[0].noteId) &&
              !rig.env.view.previewVelocity(rig.env.notes[2].noteId) &&
              rig.env.document.findNote(rig.env.notes[0].noteId, &paintedFirst) &&
              rig.env.document.findNote(rig.env.notes[2].noteId, &paintedThird) &&
              paintedFirst.velocity == rig.currentMap.representative(0) &&
              paintedThird.velocity == rig.currentMap.representative(4),
          "held velocity paint must commit one batch and clear its preview");
    return failures;
}

int checkRampGestureCommits(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    rig.env.document.addNote(0, 36, rig.paintFirstBefore.key, 12, rig.currentMap.representative(3));
    const std::vector<DocNote> rampFixtureNotes = rig.env.document.notesForTrack(0);
    const auto rampMiddleIt = std::find_if(rampFixtureNotes.cbegin(), rampFixtureNotes.cend(),
                                           [](const DocNote &note) { return note.tick == 36; });
    check(rampMiddleIt != rampFixtureNotes.cend(),
          "velocity ramp fixture must create its midpoint note");
    if (rampMiddleIt != rampFixtureNotes.cend()) {
        const DocNote rampMiddleBefore = *rampMiddleIt;
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rampMiddleBefore.noteId, rig.env.notes[2].noteId});
        const QPointF rampStart(rig.paintGestureX(rig.paintFirstBefore),
                                rig.env.area.axis().levelToY(0));
        const QPointF rampEnd(rig.paintGestureX(rig.paintThirdBefore),
                              rig.env.area.axis().levelToY(4));
        const uint64_t revisionBeforeRamp = rig.env.document.revision();
        const int undoIndexBeforeRamp = rig.env.document.undoStack()->index();
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, rampStart, Qt::LeftButton,
                                  Qt::LeftButton, Qt::ShiftModifier);
        checks::events::sendMouse(rig.env.area, QEvent::MouseMove, rampEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::ShiftModifier);
        const auto rampPreviewFirst = rig.env.view.previewVelocity(rig.env.notes[0].noteId);
        const auto rampPreviewMiddle = rig.env.view.previewVelocity(rampMiddleBefore.noteId);
        const auto rampPreviewThird = rig.env.view.previewVelocity(rig.env.notes[2].noteId);
        check(rig.env.document.revision() == revisionBeforeRamp &&
                  rig.env.document.undoStack()->index() == undoIndexBeforeRamp &&
                  rampPreviewFirst && rampPreviewMiddle && rampPreviewThird &&
                  *rampPreviewFirst == rig.currentMap.representative(0) &&
                  *rampPreviewMiddle == rig.currentMap.representative(2) &&
                  *rampPreviewThird == rig.currentMap.representative(4),
              "holding a velocity ramp must update preview while deferring document changes");
        const QPointF rampQuarter = rampStart + 0.25 * (rampEnd - rampStart);
        const QImage rampPreview = rig.env.area.grab().toImage();
        check(hasColorNear(rampPreview,
                           toPixels(QRectF(rampQuarter.x() - 2.0, rampQuarter.y() - 2.0, 5.0, 5.0),
                                    rig.env.imageScale),
                           themes::color(themes::Role::song_view_edit_preview_outline), 24),
              "velocity Shift-drag did not render its ramp line preview");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, rampEnd, Qt::LeftButton,
                                  Qt::NoButton, Qt::ShiftModifier);
        DocNote rampedFirst;
        DocNote rampedMiddle;
        DocNote rampedThird;
        check(rig.env.document.revision() == revisionBeforeRamp + 1 &&
                  rig.env.document.undoStack()->index() == undoIndexBeforeRamp + 1 &&
                  !rig.env.view.previewVelocity(rig.env.notes[0].noteId) &&
                  !rig.env.view.previewVelocity(rampMiddleBefore.noteId) &&
                  !rig.env.view.previewVelocity(rig.env.notes[2].noteId) &&
                  rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({rig.env.notes[0].noteId, rampMiddleBefore.noteId,
                                           rig.env.notes[2].noteId}) &&
                  rig.env.document.findNote(rig.env.notes[0].noteId, &rampedFirst) &&
                  rig.env.document.findNote(rampMiddleBefore.noteId, &rampedMiddle) &&
                  rig.env.document.findNote(rig.env.notes[2].noteId, &rampedThird) &&
                  rampedFirst.velocity == rig.currentMap.representative(0) &&
                  rampedMiddle.velocity == rig.currentMap.representative(2) &&
                  rampedThird.velocity == rig.currentMap.representative(4),
              "Shift-drag must commit one ramp batch and clear its preview");
        rig.env.document.deleteNotes({rampMiddleBefore});
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
    }
    return failures;
}

int checkBlankAndGraduationClicks(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const QPointF blankPoint(double(rig.env.area.plotOrigin() + rig.env.area.plotWidth() - 4),
                             rig.env.area.axis().levelToY(2));
    const uint64_t revisionBeforeBlankClick = rig.env.document.revision();
    const int undoDepthBeforeBlankClick = rig.env.document.undoStack()->count();
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, blankPoint, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
              std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[2].noteId}),
          "blank velocity press must retain selection until mouse-up");
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, blankPoint, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection().empty() &&
              rig.env.document.revision() == revisionBeforeBlankClick &&
              rig.env.document.undoStack()->count() == undoDepthBeforeBlankClick,
          "blank velocity click must deselect only on mouse-up");

    rig.env.view.selectionModel().setNoteSelection(
        {rig.env.notes[0].noteId, rig.env.notes[1].noteId});
    const VelocityAxisGraduation graduation = rig.env.area.axis().graduations()[2];
    const QPointF graduationPoint(graduation.x + graduation.width / 2.0, graduation.y);
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, graduationPoint,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, graduationPoint,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[1].noteId}) &&
              rig.env.document.findNote(rig.env.notes[0].noteId, &rig.graduatedFirst) &&
              rig.env.document.findNote(rig.env.notes[1].noteId, &rig.graduatedSecond) &&
              rig.graduatedFirst.velocity == graduation.velocity &&
              rig.graduatedSecond.velocity == graduation.velocity,
          "clicking a graduation must retain and move the selected nodes");
    return failures;
}

int checkRollVelocityDrag(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const qreal outlineRadius = rig.env.outlineRadius;
    const qreal outlineWidth = rig.env.outlineWidth;
    auto *roll = rig.env.view.findChild<QWidget *>(QStringLiteral("pianoRoll"));
    const auto velocityDragModifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    check(roll != nullptr && velocityDragModifiers != Qt::NoModifier,
          "velocity preview fixture must expose the piano roll drag shortcut");
    if (roll && velocityDragModifiers != Qt::NoModifier) {
        const int dragDelta = QApplication::startDragDistance() + 16;
        const QPointF rollNoteCenter(
            double(rig.env.expected.pianoKeyboardWidth) +
                double(rig.env.view.contentX(double(rig.graduatedFirst.tick) +
                                             double(rig.graduatedFirst.duration) / 2.0)),
            (127.5 - double(rig.graduatedFirst.key)) * rig.env.view.keyHeight() -
                rig.env.view.scrollY());
        const QPointF rollDragPosition = rollNoteCenter - QPointF(0.0, double(dragDelta));
        const auto stageRollVelocityPreview = [&]() {
            checks::events::sendMouse(*roll, QEvent::MouseButtonPress, rollNoteCenter,
                                      Qt::LeftButton, Qt::LeftButton, velocityDragModifiers);
            checks::events::sendMouse(*roll, QEvent::MouseMove, rollDragPosition, Qt::NoButton,
                                      Qt::LeftButton, velocityDragModifiers);
            QApplication::processEvents();
        };

        DocNote cancelledBefore;
        DocNote cancelledBeforeSecond;
        check(rig.env.document.findNote(rig.graduatedFirst.noteId, &cancelledBefore) &&
                  rig.env.document.findNote(rig.graduatedSecond.noteId, &cancelledBeforeSecond),
              "piano-roll cancellation fixture must retain its target notes");
        const uint64_t revisionBeforeRollCancel = rig.env.document.revision();
        const int undoIndexBeforeRollCancel = rig.env.document.undoStack()->index();
        const int undoCountBeforeRollCancel = rig.env.document.undoStack()->count();
        stageRollVelocityPreview();
        const auto cancellationPreview = rig.env.view.previewVelocity(rig.graduatedFirst.noteId);
        const auto cancellationPreviewSecond =
            rig.env.view.previewVelocity(rig.graduatedSecond.noteId);
        check(cancellationPreview && cancellationPreviewSecond &&
                  (*cancellationPreview != cancelledBefore.velocity ||
                   *cancellationPreviewSecond != cancelledBeforeSecond.velocity) &&
                  rig.env.document.revision() == revisionBeforeRollCancel &&
                  rig.env.document.undoStack()->index() == undoIndexBeforeRollCancel &&
                  rig.env.document.undoStack()->count() == undoCountBeforeRollCancel,
              "piano-roll cancellation must stage a changed deferred velocity preview");
        rig.env.view.cancelActiveInteractions();
        checks::events::sendMouse(*roll, QEvent::MouseMove, rollDragPosition, Qt::NoButton,
                                  Qt::LeftButton, velocityDragModifiers);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition,
                                  Qt::LeftButton, Qt::NoButton, velocityDragModifiers);
        QApplication::processEvents();
        DocNote cancelledAfter;
        DocNote cancelledAfterSecond;
        check(!rig.env.view.previewVelocity(rig.graduatedFirst.noteId) &&
                  !rig.env.view.previewVelocity(rig.graduatedSecond.noteId) &&
                  rig.env.document.revision() == revisionBeforeRollCancel &&
                  rig.env.document.undoStack()->index() == undoIndexBeforeRollCancel &&
                  rig.env.document.undoStack()->count() == undoCountBeforeRollCancel &&
                  rig.env.document.findNote(rig.graduatedFirst.noteId, &cancelledAfter) &&
                  rig.env.document.findNote(rig.graduatedSecond.noteId, &cancelledAfterSecond) &&
                  cancelledAfter.velocity == cancelledBefore.velocity &&
                  cancelledAfterSecond.velocity == cancelledBeforeSecond.velocity,
              "SongView cancellation must clear piano-roll local drag state and prevent commit");

        const uint64_t revisionBeforeRollDrag = rig.env.document.revision();
        const int undoBeforeRollDrag = rig.env.document.undoStack()->count();
        stageRollVelocityPreview();
        const uint8_t previewVelocity =
            uint8_t(std::clamp(int(rig.graduatedFirst.velocity) + dragDelta, 1, 127));
        const uint8_t secondPreviewVelocity =
            uint8_t(std::clamp(int(rig.graduatedSecond.velocity) + dragDelta, 1, 127));
        const auto rollPreviewValue = rig.env.view.previewVelocity(rig.graduatedFirst.noteId);
        const auto rollPreviewSecond = rig.env.view.previewVelocity(rig.graduatedSecond.noteId);
        const std::optional<std::size_t> previewLevel = rig.env.map.levelOf(previewVelocity);
        const QImage rollDragPreview = rig.env.area.grab().toImage();
        const QPointF previewNodeCenter(
            (double(rig.env.area.plotOrigin()) +
             double(rig.env.view.contentX(double(rig.graduatedFirst.tick)))) *
                rollDragPreview.devicePixelRatio(),
            (previewLevel ? rig.env.area.axis().levelToY(int(*previewLevel))
                          : rig.env.area.axis().velocityToY(previewVelocity)) *
                rollDragPreview.devicePixelRatio());
        check(rig.env.document.revision() == revisionBeforeRollDrag &&
                  rig.env.document.undoStack()->count() == undoBeforeRollDrag && rollPreviewValue &&
                  rollPreviewSecond && *rollPreviewValue == previewVelocity &&
                  *rollPreviewSecond == secondPreviewVelocity,
              "piano-roll velocity preview must stage both selected targets before release");
        check(previewLevel && rig.env.area.axis().graduations()[*previewLevel].active,
              "piano-roll velocity drag must update the velocity drawer's active graduation");
        check(hasDarkOutlinePixel(rollDragPreview, previewNodeCenter,
                                  std::max(0.0, rig.env.outlineRadius - rig.env.outlineWidth),
                                  rig.env.outlineRadius + rig.env.outlineWidth),
              "piano-roll velocity drag must move the velocity drawer node before release");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition,
                                  Qt::LeftButton, Qt::NoButton, velocityDragModifiers);
        DocNote committedFirst;
        DocNote committedSecond;
        check(rig.env.document.revision() == revisionBeforeRollDrag + 1 &&
                  rig.env.document.undoStack()->count() == undoBeforeRollDrag + 1 &&
                  !rig.env.view.previewVelocity(rig.graduatedFirst.noteId) &&
                  !rig.env.view.previewVelocity(rig.graduatedSecond.noteId) &&
                  rig.env.document.findNote(rig.graduatedFirst.noteId, &committedFirst) &&
                  rig.env.document.findNote(rig.graduatedSecond.noteId, &committedSecond) &&
                  committedFirst.velocity == previewVelocity &&
                  committedSecond.velocity == secondPreviewVelocity,
              "piano-roll velocity drag must commit both previews in one batch and clear them");
        rig.env.live.documentRevision = rig.env.document.revision();
    }
    return failures;
}

int checkClickBelowSelectedNode(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    rig.env.view.selectionModel().setNoteSelection({rig.env.notes[1].noteId});
    rig.env.voicegroup.voices[0] = rig.env.directSound;
    rig.env.view.setVoicegroup(&rig.env.voicegroup);
    rig.env.area.songChanged();
    DocNote axisFirstBefore;
    DocNote axisSecondBefore;
    rig.env.document.findNote(rig.env.notes[0].noteId, &axisFirstBefore);
    rig.env.document.findNote(rig.env.notes[1].noteId, &axisSecondBefore);
    rig.env.document.setNotesVelocity({axisFirstBefore}, 1);
    rig.env.document.findNote(rig.env.notes[0].noteId, &axisFirstBefore);
    rig.env.document.setNotesVelocity({axisSecondBefore}, 70);
    rig.env.document.findNote(rig.env.notes[1].noteId, &axisSecondBefore);
    rig.env.live.documentRevision = rig.env.document.revision();
    rig.env.live.playback.playing = false;
    ++rig.env.live.editCursorTick;
    rig.env.area.refreshLiveState(rig.env.live);
    const int axisVelocity = 40;
    const QPointF axisPoint(double(rig.env.area.plotOrigin()) +
                                double(axisSecondBefore.tick) * rig.env.live.timeZoom /
                                    double(rig.env.timeline->ticksPerBeat) -
                                rig.env.live.horizontalScroll,
                            rig.env.area.axis().velocityToY(axisVelocity));
    const uint64_t axisRevision = rig.env.document.revision();
    const int axisUndoDepth = rig.env.document.undoStack()->count();
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, axisPoint, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, axisPoint, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    DocNote axisFirstAfter;
    DocNote axisSecondAfter;
    check(rig.env.area.axis().mode() == VelocityAxis::Mode::Continuous &&
              rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[1].noteId} &&
              rig.env.document.revision() == axisRevision + 1 &&
              rig.env.document.undoStack()->count() == axisUndoDepth + 1 &&
              rig.env.document.findNote(rig.env.notes[0].noteId, &axisFirstAfter) &&
              rig.env.document.findNote(rig.env.notes[1].noteId, &axisSecondAfter) &&
              axisFirstAfter.velocity == axisFirstBefore.velocity &&
              axisSecondAfter.velocity == axisVelocity,
          "clicking below a selected node must set only that node to the clicked velocity");
    return failures;
}

int checkDetentUnlockGestures(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const Qt::KeyboardModifiers detentUnlockModifiers = Qt::ControlModifier;
    check(keymap::Registry::instance().modifierBinding(QStringLiteral("velocity.detent_unlock")) ==
              detentUnlockModifiers,
          "velocity detent unlock shortcut must retain its Ctrl default");
    // Earlier density checks resize the canvas directly. Restore container-owned
    // geometry before asserting sibling rig.env.drawer chrome.
    const int velocitySectionHeight = rig.env.view.drawerSectionHeight(EditorDrawerPage::Velocity);
    rig.env.view.setDrawerSectionHeight(EditorDrawerPage::Velocity, std::nullopt);
    rig.env.view.setDrawerSectionHeight(EditorDrawerPage::Velocity, velocitySectionHeight);
    QApplication::processEvents();
    rig.env.live.timeZoom = rig.env.view.pxPerBeat();
    rig.env.live.horizontalScroll = rig.env.view.viewState().scrollPx;
    if (detentUnlockModifiers != Qt::NoModifier) {
        rig.env.voicegroup.voices[0] = rig.env.wave;
        rig.env.view.setVoicegroup(&rig.env.voicegroup);
        rig.env.area.songChanged();
        rig.env.live.documentRevision = rig.env.document.revision();
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        const VelocityMap unlockedMap = VelocityMap::resolve(&rig.env.wave, rig.env.notes[0].key);
        const auto isOffDetent = [&unlockedMap](int velocity) {
            return unlockedMap.canonicalize(velocity) != velocity;
        };
        const auto setVelocity = [&rig](NoteId noteId, uint8_t velocity) {
            DocNote note;
            if (!rig.env.document.findNote(noteId, &note))
                return false;
            rig.env.document.setNotesVelocity({note}, velocity);
            return true;
        };

        const auto &psgGraduations = rig.env.area.axis().graduations();
        const VelocityAxisGraduation &vol1 = psgGraduations[0];
        const double labelLeft = double(layout::space(layout::Space::Two));
        const double labelRight =
            std::max(labelLeft, double(rig.env.area.plotOrigin() - layout::singlePixel() -
                                       layout::space(layout::Space::Two)));
        const double labelHeight = rig.env.area.axis().geometry().labelHeight;
        const QRectF vol1LabelBounds =
            QFontMetricsF(typography::noteName(rig.env.area.font()))
                .boundingRect(QRectF(labelLeft, vol1.y - labelHeight / 2.0, labelRight - labelLeft,
                                     labelHeight),
                              Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("Vol 1"));
        const QPoint areaOrigin = rig.env.area.mapTo(rig.env.drawer, QPoint());
        const QRect detentBounds =
            rig.env.detentToggle ? QRect(rig.env.detentToggle->mapTo(rig.env.drawer, QPoint()),
                                         rig.env.detentToggle->size())
                                 : QRect();
        const QRectF vol1LabelBoundsInDrawer =
            vol1LabelBounds.translated(areaOrigin.x(), areaOrigin.y());
        const QRect trackHeaderBounds(0, 0, areaOrigin.x(), rig.env.drawer->height());
        check(rig.env.detentToggle && rig.env.detentToggle->isVisible() &&
                  rig.env.detentToggle->isEnabled() && rig.env.detentToggle->isChecked() &&
                  detentBounds.left() == areaOrigin.x() &&
                  detentBounds.right() < areaOrigin.x() + rig.env.area.plotOrigin(),
              "velocity detent toggle must stay inside the PSG label gutter");
        check(detentBounds.bottom() == areaOrigin.y() + rig.env.area.height() - 1,
              "velocity detent toggle must stay flush with the PSG label gutter bottom");
        check(!detentBounds.intersects(trackHeaderBounds),
              "velocity detent toggle must not cover the track headers");
        check(rig.env.area.axis().graduationCount() > 0 && vol1.labelVisible &&
                  rig.env.detentToggle && !QRectF(detentBounds).intersects(vol1LabelBoundsInDrawer),
              "PSG detent toggle must not overlap the Vol 1 label");
        if (rig.env.detentToggle) {
            rig.env.voicegroup.voices[0] = rig.env.directSound;
            rig.env.view.selectionModel().setNoteSelection(
                {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
            check(!rig.env.detentToggle->isVisible() && !rig.env.detentToggle->isEnabled() &&
                      !rig.env.detentToggle->isChecked(),
                  "velocity detent toggle must hide and turn off for a DirectSound selection");
            check(setVelocity(rig.env.notes[0].noteId, 1) &&
                      setVelocity(rig.env.notes[2].noteId, 127),
                  "detent toggle fixture must reset its ruler values");
            rig.env.live.documentRevision = rig.env.document.revision();
            rig.env.area.refreshLiveState(rig.env.live);
            QApplication::processEvents();
            const QImage directSoundRuler = rig.env.area.grab().toImage();
            rig.env.voicegroup.voices[0] = rig.env.wave;
            rig.env.area.songChanged();
            check(rig.env.detentToggle->isVisible() && rig.env.detentToggle->isEnabled(),
                  "velocity detent toggle must reappear immediately for a PSG selection");
            rig.env.detentToggle->click();
            QApplication::processEvents();
            const QImage unlockedPsgRuler = rig.env.area.grab().toImage();
            const qreal rulerScale = unlockedPsgRuler.devicePixelRatio();
            const int rulerHeight =
                qFloor(double(detentBounds.top() - areaOrigin.y()) * rulerScale);
            const QRect rulerBounds(0, 0, qCeil(double(rig.env.area.plotOrigin()) * rulerScale),
                                    rulerHeight);
            check(
                samePixels(directSoundRuler.copy(rulerBounds), unlockedPsgRuler.copy(rulerBounds)),
                "disabled PSG detents must show the continuous sample-voice ruler");
            const int toggleUnlockedVelocity = 73;
            const QPointF toggleUnlockedRuler(
                double(rig.env.area.plotOrigin()) - 1.0,
                rig.env.area.axis().velocityToY(toggleUnlockedVelocity));
            checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, toggleUnlockedRuler,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, toggleUnlockedRuler,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            DocNote toggleUnlockedFirst;
            DocNote toggleUnlockedThird;
            check(!rig.env.detentToggle->isChecked() &&
                      rig.env.document.findNote(rig.env.notes[0].noteId, &toggleUnlockedFirst) &&
                      rig.env.document.findNote(rig.env.notes[2].noteId, &toggleUnlockedThird) &&
                      toggleUnlockedFirst.velocity == toggleUnlockedVelocity &&
                      toggleUnlockedThird.velocity == toggleUnlockedVelocity &&
                      isOffDetent(toggleUnlockedVelocity),
                  "disabled velocity detents must write exact PSG velocities without a modifier");
            const QImage unlockedNodeImage = rig.env.area.grab().toImage();
            const qreal unlockedNodeScale = unlockedNodeImage.devicePixelRatio();
            const QPointF unlockedNodeCenter(
                rig.paintGestureX(toggleUnlockedFirst) * unlockedNodeScale,
                rig.env.area.axis().velocityToY(toggleUnlockedVelocity) * unlockedNodeScale);
            check(hasDarkOutlinePixel(
                      unlockedNodeImage, unlockedNodeCenter,
                      std::max(0.0, rig.env.expected.nodePaintRadius * unlockedNodeScale -
                                        rig.env.expected.nodeOutlineDipWidth * unlockedNodeScale),
                      rig.env.expected.nodePaintRadius * unlockedNodeScale),
                  "disabled velocity detents must keep idle nodes at exact velocity positions");
            rig.env.detentToggle->click();
            check(rig.env.detentToggle->isChecked(),
                  "velocity detent toggle must restore snapped PSG editing");
        }

        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
        check(setVelocity(rig.env.notes[0].noteId, 1) && setVelocity(rig.env.notes[2].noteId, 127),
              "unlocked wave fixture must reset its ruler values");
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        const int lockedPaintVelocity = 73;
        const QPointF lockedPaintStart(rig.paintGestureX(rig.env.notes[0]),
                                       rig.env.area.axis().velocityToY(lockedPaintVelocity));
        const QPointF lockedPaintEnd(rig.paintGestureX(rig.env.notes[2]),
                                     rig.env.area.axis().velocityToY(lockedPaintVelocity));
        const uint64_t revisionBeforeLockedPaint = rig.env.document.revision();
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, lockedPaintStart,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(rig.env.area, QEvent::MouseMove, lockedPaintEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, lockedPaintEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote lockedPaintFirst;
        DocNote lockedPaintThird;
        check(rig.env.document.findNote(rig.env.notes[0].noteId, &lockedPaintFirst) &&
                  rig.env.document.findNote(rig.env.notes[2].noteId, &lockedPaintThird) &&
                  rig.env.document.revision() == revisionBeforeLockedPaint + 1 &&
                  lockedPaintFirst.velocity == unlockedMap.canonicalize(lockedPaintVelocity) &&
                  lockedPaintThird.velocity == unlockedMap.canonicalize(lockedPaintVelocity) &&
                  isOffDetent(lockedPaintVelocity),
              "no-modifier velocity paint must retain snapped PSG semantics");
        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
        check(setVelocity(rig.env.notes[0].noteId, 1) && setVelocity(rig.env.notes[2].noteId, 127),
              "unlocked wave fixture must reset its ruler values");
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        const int unlockedRulerVelocity = 73;
        const QPointF unlockedRuler(double(rig.env.area.plotOrigin()) - 1.0,
                                    rig.env.area.axis().velocityToY(unlockedRulerVelocity));
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, unlockedRuler,
                                  Qt::LeftButton, Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, unlockedRuler,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote rulerUnlockedFirst;
        DocNote rulerUnlockedThird;
        check(rig.env.document.findNote(rig.env.notes[0].noteId, &rulerUnlockedFirst) &&
                  rig.env.document.findNote(rig.env.notes[2].noteId, &rulerUnlockedThird) &&
                  rulerUnlockedFirst.velocity == unlockedRulerVelocity &&
                  rulerUnlockedThird.velocity == unlockedRulerVelocity &&
                  isOffDetent(unlockedRulerVelocity),
              "unlocked intrinsic ruler clicks must write exact off-detent values");

        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
        check(setVelocity(rig.env.notes[0].noteId, 1) && setVelocity(rig.env.notes[2].noteId, 127),
              "unlocked wave paint fixture must reset its endpoints");
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        DocNote paintUnlockedFirst;
        DocNote paintUnlockedThird;
        rig.env.document.findNote(rig.env.notes[0].noteId, &paintUnlockedFirst);
        rig.env.document.findNote(rig.env.notes[2].noteId, &paintUnlockedThird);
        const int unlockedPaintFirstVelocity = 37;
        const int unlockedPaintThirdVelocity = 91;
        const QPointF unlockedPaintStart(
            rig.paintGestureX(paintUnlockedFirst),
            rig.env.area.axis().velocityToY(unlockedPaintFirstVelocity));
        const QPointF unlockedPaintEnd(rig.paintGestureX(paintUnlockedThird),
                                       rig.env.area.axis().velocityToY(unlockedPaintThirdVelocity));
        const uint64_t revisionBeforeUnlockedPaint = rig.env.document.revision();
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, unlockedPaintStart,
                                  Qt::LeftButton, Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(rig.env.area, QEvent::MouseMove, unlockedPaintEnd, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        const QImage unlockedPaintPreview = rig.env.area.grab().toImage();
        const qreal unlockedPaintScale = unlockedPaintPreview.devicePixelRatio();
        const QPointF unlockedPaintCenter(
            rig.paintGestureX(paintUnlockedFirst) * unlockedPaintScale,
            rig.env.area.axis().velocityToY(unlockedPaintFirstVelocity) * unlockedPaintScale);
        check(rig.env.document.revision() == revisionBeforeUnlockedPaint &&
                  hasDarkOutlinePixel(
                      unlockedPaintPreview, unlockedPaintCenter,
                      std::max(0.0, rig.env.expected.nodePaintRadius * unlockedPaintScale -
                                        rig.env.expected.nodeOutlineDipWidth * unlockedPaintScale),
                      rig.env.expected.nodePaintRadius * unlockedPaintScale),
              "unlocked paint preview must remain at its continuous y position");
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, unlockedPaintEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote paintedUnlockedFirst;
        DocNote paintedUnlockedThird;
        check(rig.env.document.findNote(rig.env.notes[0].noteId, &paintedUnlockedFirst) &&
                  rig.env.document.findNote(rig.env.notes[2].noteId, &paintedUnlockedThird) &&
                  paintedUnlockedFirst.velocity == unlockedPaintFirstVelocity &&
                  paintedUnlockedThird.velocity == unlockedPaintThirdVelocity &&
                  isOffDetent(unlockedPaintFirstVelocity) &&
                  isOffDetent(unlockedPaintThirdVelocity),
              "unlocked paint must commit exact off-detent wave values");

        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
        check(setVelocity(rig.env.notes[0].noteId, 33) && setVelocity(rig.env.notes[2].noteId, 87),
              "unlocked wave relative fixture must reset its origins");
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        const int lockedRelativeOriginFirst = 33;
        const int lockedRelativeOriginThird = 87;
        const int lockedRelativeDelta = 20;
        const double lockedRelativeStartY = rig.env.area.axis().levelToY(
            int(unlockedMap.levelOf(lockedRelativeOriginFirst).value()));
        const double lockedRelativeEndY =
            rig.env.area.axis().velocityToY(lockedRelativeOriginFirst + lockedRelativeDelta);
        const QPointF lockedRelativeStart(rig.paintGestureX(rig.env.notes[0]),
                                          lockedRelativeStartY);
        const QPointF lockedRelativeEnd(lockedRelativeStart.x(), lockedRelativeEndY);
        const int lockedRelativeLevelDelta = rig.env.area.axis().yToLevel(lockedRelativeEndY) -
                                             rig.env.area.axis().yToLevel(lockedRelativeStartY);
        const int lockedProposedFirst = lockedRelativeOriginFirst + lockedRelativeDelta;
        const int lockedProposedThird = lockedRelativeOriginThird + lockedRelativeDelta;
        const uint8_t lockedExpectedFirst =
            unlockedMap.moveLevels(uint8_t(lockedRelativeOriginFirst), lockedRelativeLevelDelta);
        const uint8_t lockedExpectedThird =
            unlockedMap.moveLevels(uint8_t(lockedRelativeOriginThird), lockedRelativeLevelDelta);
        const uint64_t revisionBeforeLockedStart = rig.env.document.revision();
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, lockedRelativeStart,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(rig.env.area, QEvent::MouseMove, lockedRelativeEnd, Qt::NoButton,
                                  Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, lockedRelativeEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote lockedRelativeFirst;
        DocNote lockedRelativeThird;
        check(rig.env.document.findNote(rig.env.notes[0].noteId, &lockedRelativeFirst) &&
                  rig.env.document.findNote(rig.env.notes[2].noteId, &lockedRelativeThird) &&
                  rig.env.document.revision() == revisionBeforeLockedStart + 1 &&
                  lockedRelativeFirst.velocity == lockedExpectedFirst &&
                  lockedRelativeThird.velocity == lockedExpectedThird &&
                  lockedRelativeLevelDelta != 0 && isOffDetent(lockedProposedFirst) &&
                  isOffDetent(lockedProposedThird),
              "unlock added after a gesture starts must not bypass snapped PSG semantics");
        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rig.env.notes[2].noteId});
        check(setVelocity(rig.env.notes[0].noteId, lockedRelativeOriginFirst) &&
                  setVelocity(rig.env.notes[2].noteId, lockedRelativeOriginThird),
              "unlocked wave relative fixture must reset its origins");
        rig.env.live.documentRevision = rig.env.document.revision();
        rig.env.area.refreshLiveState(rig.env.live);
        DocNote relativeUnlockedFirst;
        DocNote relativeUnlockedThird;
        rig.env.document.findNote(rig.env.notes[0].noteId, &relativeUnlockedFirst);
        rig.env.document.findNote(rig.env.notes[2].noteId, &relativeUnlockedThird);
        const int unlockedRelativeDelta = 7;
        const QPointF unlockedRelativeStart(
            rig.paintGestureX(relativeUnlockedFirst),
            rig.env.area.axis().levelToY(
                int(unlockedMap.levelOf(relativeUnlockedFirst.velocity).value())));
        const QPointF unlockedRelativeEnd(
            unlockedRelativeStart.x(), rig.env.area.axis().velocityToY(
                                           relativeUnlockedFirst.velocity + unlockedRelativeDelta));
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, unlockedRelativeStart,
                                  Qt::LeftButton, Qt::LeftButton, detentUnlockModifiers);
        checks::events::sendMouse(rig.env.area, QEvent::MouseMove, unlockedRelativeEnd,
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, unlockedRelativeEnd,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        DocNote relativeUnlockedFirstAfter;
        DocNote relativeUnlockedThirdAfter;
        check(rig.env.document.findNote(rig.env.notes[0].noteId, &relativeUnlockedFirstAfter) &&
                  rig.env.document.findNote(rig.env.notes[2].noteId, &relativeUnlockedThirdAfter) &&
                  relativeUnlockedFirstAfter.velocity == 40 &&
                  relativeUnlockedThirdAfter.velocity == 94 &&
                  isOffDetent(relativeUnlockedFirstAfter.velocity) &&
                  isOffDetent(relativeUnlockedThirdAfter.velocity),
              "unlocked relative drag must preserve exact off-detent origins");

        rig.env.document.addNote(0, 36, relativeUnlockedFirst.key, 12, 56);
        const std::vector<DocNote> unlockedRampNotes = rig.env.document.notesForTrack(0);
        const auto unlockedRampMiddleIt =
            std::find_if(unlockedRampNotes.cbegin(), unlockedRampNotes.cend(),
                         [](const DocNote &note) { return note.tick == 36; });
        check(unlockedRampMiddleIt != unlockedRampNotes.cend(),
              "unlocked wave ramp fixture must create its midpoint note");
        if (unlockedRampMiddleIt != unlockedRampNotes.cend()) {
            const DocNote unlockedRampMiddleBefore = *unlockedRampMiddleIt;
            rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId,
                                                            unlockedRampMiddleBefore.noteId,
                                                            rig.env.notes[2].noteId});
            rig.env.live.documentRevision = rig.env.document.revision();
            rig.env.area.refreshLiveState(rig.env.live);
            const DocNote unlockedRampFirst = relativeUnlockedFirstAfter;
            const DocNote unlockedRampThird = relativeUnlockedThirdAfter;
            const double unlockedRampStartX = rig.paintGestureX(unlockedRampFirst);
            const double unlockedRampEndX = rig.paintGestureX(unlockedRampThird);
            const int unlockedRampFirstVelocity = 37;
            const int unlockedRampThirdVelocity = 93;
            const QPointF unlockedRampStart(
                unlockedRampStartX, rig.env.area.axis().velocityToY(unlockedRampFirstVelocity));
            const QPointF unlockedRampEnd(
                unlockedRampEndX, rig.env.area.axis().velocityToY(unlockedRampThirdVelocity));
            const double middleRatio =
                (rig.paintGestureX(unlockedRampMiddleBefore) - unlockedRampStartX) /
                (unlockedRampEndX - unlockedRampStartX);
            const int unlockedRampMiddleVelocity = rig.env.area.axis().yToVelocity(
                unlockedRampStart.y() +
                middleRatio * (unlockedRampEnd.y() - unlockedRampStart.y()));
            const uint64_t revisionBeforeUnlockedRamp = rig.env.document.revision();
            const Qt::KeyboardModifiers unlockedRampModifiers =
                detentUnlockModifiers | Qt::ShiftModifier;
            checks::events::sendMouse(rig.env.area, QEvent::MouseButtonPress, unlockedRampStart,
                                      Qt::LeftButton, Qt::LeftButton, unlockedRampModifiers);
            checks::events::sendMouse(rig.env.area, QEvent::MouseMove, unlockedRampEnd,
                                      Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
            check(rig.env.document.revision() == revisionBeforeUnlockedRamp,
                  "unlocked Shift-ramp must defer document changes");
            checks::events::sendMouse(rig.env.area, QEvent::MouseButtonRelease, unlockedRampEnd,
                                      Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            DocNote rampedUnlockedFirst;
            DocNote rampedUnlockedMiddle;
            DocNote rampedUnlockedThird;
            check(rig.env.document.findNote(rig.env.notes[0].noteId, &rampedUnlockedFirst) &&
                      rig.env.document.findNote(unlockedRampMiddleBefore.noteId,
                                                &rampedUnlockedMiddle) &&
                      rig.env.document.findNote(rig.env.notes[2].noteId, &rampedUnlockedThird) &&
                      rampedUnlockedFirst.velocity == unlockedRampFirstVelocity &&
                      rampedUnlockedMiddle.velocity == unlockedRampMiddleVelocity &&
                      rampedUnlockedThird.velocity == unlockedRampThirdVelocity &&
                      isOffDetent(rampedUnlockedFirst.velocity) &&
                      isOffDetent(rampedUnlockedMiddle.velocity) &&
                      isOffDetent(rampedUnlockedThird.velocity),
                  "unlocked Shift-ramp must commit exact continuous wave values");
            rig.env.document.deleteNotes({unlockedRampMiddleBefore});
            rig.env.live.documentRevision = rig.env.document.revision();
            rig.env.area.refreshLiveState(rig.env.live);
        }
    }
    return failures;
}

} // namespace

int runVelocityPageCheck(const QString &scratchProject, const QString &songLabel,
                         const QString &screenshotPath)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    if (scratchProject.isEmpty() || songLabel.isEmpty()) {
        std::fprintf(stderr, "velocity-page: FAIL: scratch project and song label are required\n");
        return 1;
    }

    QString fixtureError;
    auto fixtureSong = checks::LoadedSong::load(scratchProject, songLabel, fixtureError);
    if (!fixtureSong) {
        std::fprintf(stderr, "velocity-page: FAIL %s: could not load fixture song: %s\n",
                     qUtf8Printable(songLabel), qUtf8Printable(fixtureError));
        return 1;
    }
    SongDocument &fixtureDocument = fixtureSong->document();
    auto fixtureTimeline = fixtureDocument.buildTimeline(48000.0);
    if (!fixtureTimeline) {
        std::fprintf(stderr, "velocity-page: FAIL %s: could not build fixture timeline\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    LoadedVoiceGroup fixtureVoicegroup{};
    for (ToneData &tone : fixtureVoicegroup.voices)
        tone.type = VOICE_DIRECTSOUND;
    SongView fixtureView;
    fixtureView.resize(960, 480);
    fixtureView.setDocument(&fixtureDocument);
    fixtureView.setSong(fixtureTimeline.get(), &fixtureVoicegroup);
    fixtureView.setDrawerActivePage(EditorDrawerPage::Velocity);
    fixtureView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    fixtureView.show();
    QApplication::processEvents();
    auto *fixtureDrawer = fixtureView.editorDrawer();
    auto *fixtureArea = fixtureDrawer ? fixtureDrawer->velocityArea() : nullptr;
    if (!fixtureArea) {
        std::fprintf(stderr,
                     "velocity-page: FAIL %s: fixture SongView did not expose VelocityArea\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    const auto expected = expectedVelocityGeometry();
    fixtureArea->resize(expected.plotOrigin + layout::space(layout::Space::Eight),
                        expected.densityThresholdD4 + layout::space(layout::Space::Six));
    fixtureArea->songChanged();
    DrawerPageLiveState fixtureLive;
    fixtureLive.documentRevision = fixtureDocument.revision();
    fixtureLive.timeZoom = 48.0;
    fixtureView.setEditorTimeZoom(fixtureLive.timeZoom);
    fixtureLive.timeZoom = fixtureView.pxPerBeat();
    fixtureLive.horizontalScroll = fixtureView.viewState().scrollPx;
    fixtureArea->refreshLiveState(fixtureLive);
    fixtureArea->show();
    QApplication::processEvents();
    const qreal zoomAnchorContentX = std::max(1, fixtureArea->plotWidth() / 2);
    const QPoint zoomAnchor(fixtureArea->plotOrigin() + qRound(zoomAnchorContentX),
                            fixtureArea->height() / 2);
    const double tickBeforeZoom = fixtureView.tickAtContentX(zoomAnchorContentX);
    const double zoomBefore = fixtureView.pxPerBeat();
    checks::events::sendWheel(*fixtureArea, QPointF(zoomAnchor), QPoint(), QPoint(0, 120),
                              Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QApplication::processEvents();
    check(fixtureView.pxPerBeat() > zoomBefore, "plain wheel must change velocity-lane time zoom");
    check(std::abs(fixtureView.tickAtContentX(zoomAnchorContentX) - tickBeforeZoom) < 0.001,
          "velocity-lane time zoom must preserve the tick under the cursor");
    int fixtureTrack = -1;
    DocNote fixtureNote;
    for (int track = 0; track < std::min(fixtureDocument.engineTrackCount(), 16); ++track) {
        const auto notes = fixtureDocument.notesForTrack(track);
        const auto note = std::find_if(notes.begin(), notes.end(), [](const DocNote &candidate) {
            return candidate.noteId.isAssigned();
        });
        if (note != notes.end()) {
            fixtureTrack = track;
            fixtureNote = *note;
            break;
        }
    }
    if (fixtureTrack < 0) {
        std::fprintf(stderr,
                     "velocity-page: FAIL %s: fixture song has no real note on a usable track\n",
                     qUtf8Printable(songLabel));
        fixtureView.hide();
        return 1;
    }
    fixtureView.selectTrack(fixtureTrack);
    fixtureView.selectionModel().setNoteSelection({fixtureNote.noteId});
    ++fixtureLive.editCursorTick;
    fixtureArea->refreshLiveState(fixtureLive);
    DocNote resolvedFixtureNote;
    const auto &fixtureMarkers = fixtureArea->axis().markers();
    check(fixtureView.document() == &fixtureDocument &&
              fixtureView.selectionModel().primaryTrack() == fixtureTrack &&
              fixtureView.selectionModel().noteSelection() ==
                  std::vector<NoteId>{fixtureNote.noteId} &&
              fixtureDocument.findNote(fixtureNote.noteId, &resolvedFixtureNote) &&
              resolvedFixtureNote.noteId == fixtureNote.noteId &&
              resolvedFixtureNote.velocity == fixtureNote.velocity &&
              fixtureArea->axis().mode() == VelocityAxis::Mode::Continuous &&
              fixtureArea->axis().markerCount() == 1 &&
              fixtureMarkers[0].velocity == fixtureNote.velocity &&
              std::abs(fixtureMarkers[0].y -
                       fixtureArea->axis().velocityToY(fixtureNote.velocity)) < 0.001,
          "requested fixture note, velocity, and axis data must reach its concrete VelocityArea");
    fixtureView.hide();
    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {
        noteEvent(0xC0, 0, 0, 0),   noteEvent(0x90, 12, 60, 20), noteEvent(0x90, 12, 60, 70),
        noteEvent(0x80, 36, 60, 0), noteEvent(0x80, 36, 60, 0),  noteEvent(0x90, 60, 64, 70),
        noteEvent(0x80, 84, 64, 0),
    };
    track.endTick = 84;
    smf.tracks.push_back(track);
    const QString midiPath = temporary.path() + QStringLiteral("/velocity.mid");
    SongInfo song;
    song.label = QStringLiteral("velocity");
    song.midPath = midiPath;
    song.hasMid = true;
    SongDocument document;
    check(temporary.isValid() && smf.writeFile(midiPath, &error) && document.load(song, &error),
          "synthetic duplicate-note fixture should load");
    const std::vector<DocNote> notes = document.notesForTrack(0);
    check(notes.size() == 3 && notes[0].noteId != notes[1].noteId,
          "duplicate notes must keep distinct NoteId values");
    if (notes.size() != 3)
        return 1;

    ToneData directSound{};
    directSound.type = VOICE_DIRECTSOUND;
    ToneData square{};
    square.type = VOICE_SQUARE_1;
    ToneData wave{};
    wave.type = VOICE_PROGRAMMABLE_WAVE;
    ToneData noise{};
    noise.type = VOICE_NOISE;
    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[0] = directSound;
    auto timeline = document.buildTimeline(48000.0);
    check(timeline != nullptr, "concrete velocity fixture should build a timeline");
    if (!timeline)
        return 1;
    SongView view;
    view.resize(960, 480);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 320);
    view.show();
    QApplication::processEvents();
    auto *drawer = view.editorDrawer();
    auto *areaPtr = drawer ? drawer->velocityArea() : nullptr;
    check(drawer != nullptr && areaPtr != nullptr,
          "concrete SongView should expose its owned velocity area");
    if (!areaPtr)
        return 1;
    auto *drawerSections = drawer->findChild<QWidget *>(QStringLiteral("drawerSections"));
    auto *velToggle =
        drawerSections
            ? drawerSections->findChild<QToolButton *>(QStringLiteral("velocityDrawerToggle"))
            : nullptr;
    auto *automationBar =
        drawerSections ? drawerSections->findChild<QWidget *>(QStringLiteral("automationDrawerBar"))
                       : nullptr;
    auto *automationToggle =
        drawerSections
            ? drawerSections->findChild<QToolButton *>(QStringLiteral("automationDrawerToggle"))
            : nullptr;
    auto &area = *areaPtr;
    DrawerPageLiveState live;
    VelocityAreaEnv env{document, timeline,       voicegroup, directSound,   square,
                        wave,     noise,          notes,      view,          area,
                        drawer,   drawerSections, velToggle,  automationBar, automationToggle,
                        nullptr,  live,           expected};
    VelocityAreaRig rig{env, VelocityMap::resolve(&noise, notes[0].key)};
    failures += checkDrawerToggleGeometry(env);
    area.resize(expected.plotOrigin + layout::space(layout::Space::Eight),
                expected.densityThresholdD4 + layout::space(layout::Space::Six));
    area.songChanged();
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    live.trackColor = QColor(Qt::cyan);
    view.setEditorTimeZoom(live.timeZoom);
    view.setEditorHorizontalScroll(live.horizontalScroll);
    live.timeZoom = view.pxPerBeat();
    live.horizontalScroll = view.viewState().scrollPx;
    area.refreshLiveState(live);
    area.show();
    QApplication::processEvents();
    failures += checkDirectSoundChromeAndFocus(env);
    failures += checkGridContinuesPastSongEnd(env);
    failures += checkPanClampAtTickZero(env);
    failures += checkContinuousGraduationDensity(env);
    failures += checkPsgAxisContexts(env);
    failures += checkHoverAxisContext(env);
    failures += checkVelocityRendering(env);
    failures += checkEditCursorRepaint(env);
    failures += checkDrawerContextTickRounding(env);
    failures += checkRelativeDragDefersCommit(rig);
    failures += checkUngrabCancelsProvisionalSelection(rig);
    failures += checkDragBandOverlay(rig);
    failures += checkStackedNodeHitPriority(rig);
    failures += checkPaintGestureDefersCommit(rig);
    failures += checkRampGestureCommits(rig);
    failures += checkBlankAndGraduationClicks(rig);
    failures += checkRollVelocityDrag(rig);
    failures += checkClickBelowSelectedNode(rig);
    failures += checkDetentUnlockGestures(rig);

    live.playback.playing = true;
    live.playback.playheadTick = -1.0;
    area.refreshLiveState(live);
    QApplication::processEvents();
    const VelocityAreaDiagnostics warm = area.diagnostics();
    for (int update = 0; update < 120; ++update) {
        live.playback.playheadTick = double(update);
        area.refreshLiveState(live);
        QApplication::processEvents();
    }
    check(area.diagnostics().contentBuildCount == warm.contentBuildCount &&
              area.diagnostics().presentedPlayheadTick == 119.0 &&
              area.diagnostics().playheadPresentationCount == warm.playheadPresentationCount + 120,
          "120 playhead presentations must not rebuild velocity content");

    view.selectionModel().setNoteSelection({notes[0].noteId, notes[2].noteId});
    const std::vector<NoteId> selectedBeforeKeyboard = view.selectionModel().noteSelection();
    DocNote firstBeforeKeyboard;
    DocNote thirdBeforeKeyboard;
    check(document.findNote(notes[0].noteId, &firstBeforeKeyboard) &&
              document.findNote(notes[2].noteId, &thirdBeforeKeyboard),
          "focused velocity keyboard fixture must resolve its selected notes");
    const uint64_t revisionBeforeKeyboard = document.revision();
    area.setFocus(Qt::OtherFocusReason);
    checks::events::sendKey(area, QEvent::KeyPress, Qt::Key_Up, Qt::ShiftModifier, QString(), false,
                            1);
    DocNote firstAfterKeyboard;
    DocNote thirdAfterKeyboard;
    check(document.revision() == revisionBeforeKeyboard &&
              view.selectionModel().noteSelection() == selectedBeforeKeyboard &&
              document.findNote(notes[0].noteId, &firstAfterKeyboard) &&
              document.findNote(notes[2].noteId, &thirdAfterKeyboard) &&
              firstAfterKeyboard.key == firstBeforeKeyboard.key &&
              thirdAfterKeyboard.key == thirdBeforeKeyboard.key,
          "focused velocity keyboard pitch editing must leave selected notes unchanged");
    if (!screenshotPath.isEmpty())
        check(area.grab().save(screenshotPath), "optional velocity screenshot should save");
    area.hide();
    return failures == 0 ? 0 : 1;
}
