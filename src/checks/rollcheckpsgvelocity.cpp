#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"

#include "core/velocitymodel.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/velocityaxis.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <optional>
#include <vector>

#include <QApplication>
#include <QEvent>
#include <QFontMetricsF>
#include <QImage>
#include <QTemporaryDir>

#include "core/miditimeline.h"
#include "core/noteid.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

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

const std::optional<songview::TimelineBandGeometry> &velocityGeometry(const SongView &view)
{
    return view.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
}

QRect velocityBandRect(const SongView &view)
{
    return velocityGeometry(view) ? velocityGeometry(view)->rect : QRect{};
}

QRect velocityPlotRect(const SongView &view)
{
    return velocityGeometry(view) ? velocityGeometry(view)->plotRect : QRect{};
}

int velocityFixedSpan(const SongView &view)
{
    return velocityGeometry(view) ? std::max(0, velocityGeometry(view)->plotRect.x() -
                                                    velocityGeometry(view)->rect.x())
                                  : 0;
}

QImage captureVelocityBand(SongView &view)
{
    return checks::support::captureQuickBand(view, velocityBandRect(view));
}

struct ExpectedVelocityGeometry {
    int densityThresholdD2;
    int densityThresholdD4;
    qreal nodePaintRadius;
};

ExpectedVelocityGeometry expectedVelocityGeometry()
{
    return {
        layout::fontPx(25.0 / 3.0),
        layout::fontPx(24.0),
        layout::fontPxF(7.0 / 26.0),
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
    songview::TimelineInputItem *velocityInput = nullptr;
    songview::TimelineInputItem *velocityGutterInput = nullptr;
    DrawerChrome &chrome;
    songview::TimelineInputItem *barInput = nullptr;
    songview::TimelineInputItem *detentInput = nullptr;
    songview::TimelineQuickScene *quickScene = nullptr;
    songview::TimelineQuickView *quickView = nullptr;
    DrawerPageLiveState &live;
    ExpectedVelocityGeometry expected;
    VelocityMap map;
    uint8_t hoveredPsgVelocity = 0;
    std::size_t hoveredPsgLevel = 0;
    qreal imageScale = 1.0;
};

void velocityPress(VelocityAreaEnv &env, const QPointF &position, Qt::MouseButton button,
                   Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*env.velocityInput, QEvent::MouseButtonPress, position, button,
                              buttons, modifiers);
}

void velocityMove(VelocityAreaEnv &env, const QPointF &position, Qt::MouseButtons buttons,
                  Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*env.velocityInput, QEvent::MouseMove, position, Qt::NoButton,
                              buttons, modifiers);
}

void velocityRelease(VelocityAreaEnv &env, const QPointF &position, Qt::MouseButton button,
                     Qt::KeyboardModifiers modifiers)
{
    checks::events::sendMouse(*env.velocityInput, QEvent::MouseButtonRelease, position, button,
                              Qt::NoButton, modifiers);
}

void velocityLeave(VelocityAreaEnv &env)
{
    checks::events::sendMouse(*env.velocityInput, QEvent::Leave, QPointF{}, Qt::NoButton,
                              Qt::NoButton, Qt::NoModifier);
}

double velocityXForTick(const VelocityAreaEnv &env, double tick)
{
    return env.view.camera().displayX(tick, 0.0, env.velocityInput->devicePixelRatio());
}

bool colorsMatch(const QColor &actual, const QColor &expected)
{
    return actual == expected;
}

bool layerTouches(const songview::TimelineQuickScene *scene, songview::TimelineQuickLayer layer,
                  const QRectF &probe, const QColor &expected)
{
    if (!scene || probe.isEmpty())
        return false;
    const auto &data = scene->layer(layer);
    const auto rectMatches = [&probe, &expected](const songview::TimelineQuickRect &rect) {
        return rect.rect.intersects(probe) &&
               (colorsMatch(rect.topLeft, expected) || colorsMatch(rect.topRight, expected) ||
                colorsMatch(rect.bottomRight, expected) || colorsMatch(rect.bottomLeft, expected));
    };
    if (std::any_of(data.rects.cbegin(), data.rects.cend(), rectMatches))
        return true;
    const auto triangleMatches = [&probe,
                                  &expected](const songview::TimelineQuickTriangle &triangle) {
        const QRectF bounds = QRectF(triangle.first, triangle.second)
                                  .normalized()
                                  .united(QRectF(triangle.first, triangle.third).normalized())
                                  .united(QRectF(triangle.second, triangle.third).normalized());
        return bounds.intersects(probe) && (colorsMatch(triangle.firstColor, expected) ||
                                            colorsMatch(triangle.secondColor, expected) ||
                                            colorsMatch(triangle.thirdColor, expected));
    };
    return std::any_of(data.triangles.cbegin(), data.triangles.cend(), triangleMatches);
}
std::optional<QRectF> solidLayerRect(const songview::TimelineQuickScene *scene,
                                     songview::TimelineQuickLayer layer, const QColor &color)
{
    if (!scene)
        return std::nullopt;
    const auto &rects = scene->layer(layer).rects;
    const auto match = [&color](const songview::TimelineQuickRect &rect) {
        return colorsMatch(rect.topLeft, color) && colorsMatch(rect.topRight, color) &&
               colorsMatch(rect.bottomRight, color) && colorsMatch(rect.bottomLeft, color);
    };
    const auto found = std::find_if(rects.cbegin(), rects.cend(), match);
    return found == rects.cend() ? std::nullopt : std::optional<QRectF>{found->rect};
}

quint64 layerRevision(const VelocityAreaEnv &env, songview::TimelineQuickLayer layer)
{
    return env.quickScene ? env.quickScene->layer(layer).revision : quint64{0};
}

bool layerIsEmpty(const songview::TimelineQuickScene *scene, songview::TimelineQuickLayer layer)
{
    if (!scene)
        return false;
    const auto &data = scene->layer(layer);
    return data.rects.empty() && data.triangles.empty();
}

bool velocityNodeHasColor(const VelocityAreaEnv &env, const QPointF &center, const QColor &color)
{
    const qreal radius = env.expected.nodePaintRadius;
    return layerTouches(
        env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
        QRectF(center.x() - radius, center.y() - radius, 2.0 * radius, 2.0 * radius), color);
}

int checkDrawerToggleGeometry(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const QRectF voiceToggle = env.chrome.voiceChangesToggleRect();
    const QRectF automationToggle = env.chrome.automationToggleRect();
    const QRectF velocityToggle = env.chrome.velocityToggleRect();
    const QRectF toggleGroup = voiceToggle.united(automationToggle).united(velocityToggle);
    const int pianoKeysCenter = velocityBandRect(env.view).x() + velocityFixedSpan(env.view) / 2;
    check(env.barInput &&
              env.barInput->interaction() == &env.chrome.interaction(DrawerChromeTarget::Bar) &&
              env.barInput->isVisible() &&
              env.barInput->bounds() == QRectF(QPointF{}, env.chrome.barRect().size()) &&
              !env.chrome.barRect().isEmpty() && !voiceToggle.isEmpty() &&
              !automationToggle.isEmpty() && !velocityToggle.isEmpty() &&
              env.chrome.barRect().contains(voiceToggle) &&
              env.chrome.barRect().contains(automationToggle) &&
              env.chrome.barRect().contains(velocityToggle) &&
              automationToggle.x() ==
                  voiceToggle.x() + voiceToggle.width() + layout::space(layout::Space::One) &&
              velocityToggle.x() == automationToggle.x() + automationToggle.width() +
                                        layout::space(layout::Space::One) &&
              voiceToggle.y() == automationToggle.y() &&
              velocityToggle.y() == automationToggle.y() &&
              std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
          "drawer chrome toggles must sit together beneath the piano keys");
    return failures;
}

int checkDrawerToggleInput(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const bool velocityWasVisible = env.view.drawerSectionVisible(EditorDrawerPage::Velocity);
    const int heightBefore = env.view.drawerSectionHeight(EditorDrawerPage::Velocity);
    check(velocityWasVisible && env.barInput && !env.chrome.velocityToggleRect().isEmpty(),
          "velocity chrome toggle fixture was not visible");
    if (!velocityWasVisible || !env.barInput || env.chrome.velocityToggleRect().isEmpty())
        return failures;

    const auto clickVelocityToggle = [&env] {
        const QPointF localCenter =
            env.chrome.velocityToggleRect().center() - env.chrome.barRect().topLeft();
        checks::events::sendMouse(*env.barInput, QEvent::MouseButtonPress, localCenter,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*env.barInput, QEvent::MouseButtonRelease, localCenter,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    };
    clickVelocityToggle();
    QApplication::processEvents();
    check(!env.view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              !env.chrome.velocityChecked() && !env.view.editorViewState().velocity.visible &&
              env.view.drawerSectionHeight(EditorDrawerPage::Velocity) == heightBefore,
          "drawerBarInput did not hide velocity without losing its retained height");
    clickVelocityToggle();
    QApplication::processEvents();
    check(env.view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              env.chrome.velocityChecked() && env.view.editorViewState().velocity.visible &&
              env.view.drawerSectionHeight(EditorDrawerPage::Velocity) == heightBefore,
          "drawerBarInput did not reopen velocity with its retained height");
    return failures;
}

int checkDirectSoundChromeAndFocus(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    check(env.detentInput &&
              env.detentInput->interaction() ==
                  &env.chrome.interaction(DrawerChromeTarget::Detent) &&
              !env.detentInput->isVisible() && !env.chrome.detentVisible() &&
              !env.chrome.detentEnabled() && !env.chrome.detentChecked() &&
              env.chrome.detentRect().isEmpty(),
          "DrawerChrome detent must hide for DirectSound");
    check(env.area.axis().mode() == VelocityAxis::Mode::Continuous &&
              env.velocityInput->accessibilityDescription() == QStringLiteral("Velocity"),
          "DirectSound with no selection should publish the continuous accessible axis");
    check(!VelocityAxis::nodesFocusable() && !VelocityAxis::graduationLabelsFocusable(),
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
    env.view.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                    env.expected.densityThresholdD2 +
                                        layout::space(layout::Space::One));
    QApplication::processEvents();
    env.area.refreshLiveState(env.live);
    const auto &directSoundLabels = env.area.axis().labels();
    check(env.area.axis().tickCount() == 9 && env.area.axis().labelCount() == 5 &&
              directSoundLabels[0].velocity == 127 && directSoundLabels[1].velocity == 96 &&
              directSoundLabels[2].velocity == 64 && directSoundLabels[3].velocity == 32 &&
              directSoundLabels[4].velocity == 1,
          "DirectSound must retain the original medium-height continuous graduations");
    env.view.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                    env.expected.densityThresholdD4 +
                                        layout::space(layout::Space::Six));
    QApplication::processEvents();
    env.area.refreshLiveState(env.live);
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
    // Retained scene geometry is local to the plot-side VelocityGrid item.
    // Match the renderer's snapped, camera-relative plot-local x.
    const qreal dpr = env.velocityInput->devicePixelRatio();
    const auto gridX = [&env, dpr](uint64_t tick) {
        return env.view.camera().displayX(double(tick), 0.0, dpr);
    };
    const qreal firstBarPastSongEndX = gridX(firstBarPastSongEnd);
    const std::array gridColors = {
        songview::detail::gridLineColor(125), songview::detail::gridLineColor(100),
        songview::detail::gridLineColor(75),  songview::detail::gridLineColor(160),
        songview::detail::gridLineColor(200), songview::detail::gridLineColor(),
    };
    const QRectF gridProbe(firstBarPastSongEndX - 2.0, 0.0, 4.0,
                           qreal(velocityBandRect(env.view).height()));
    check(std::any_of(gridColors.cbegin(), gridColors.cend(),
                      [&](const QColor &color) {
                          return layerTouches(env.quickScene,
                                              songview::TimelineQuickLayer::VelocityGrid, gridProbe,
                                              color);
                      }),
          "velocity grid must continue to the piano grid beyond the song end");
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
    env.live.timeZoom = env.view.camera().pxPerBeat();
    env.live.horizontalScroll = env.view.camera().scrollX();
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const auto beforePanPastZero = captureVelocityBand(env.view);
    const auto panStart =
        QPointF(layout::space(layout::Space::Two), velocityPlotRect(env.view).height() / 2.0);
    const auto panLeftPastZero = panStart + QPointF(layout::space(layout::Space::Eight), 0.0);
    velocityPress(env, panStart, Qt::MiddleButton, Qt::MiddleButton, Qt::NoModifier);
    velocityMove(env, panLeftPastZero, Qt::MiddleButton, Qt::NoModifier);
    velocityRelease(env, panLeftPastZero, Qt::MiddleButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto afterPanPastZero = captureVelocityBand(env.view);
    check(env.view.camera().scrollX() == env.live.horizontalScroll &&
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
              env.velocityInput->accessibilityDescription() ==
                  QStringLiteral("Velocity. Square 1 has 16 volume levels."),
          "compatible Square selection should publish intrinsic graduations");
    env.voicegroup.voices[0] = env.wave;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              env.area.axis().graduationCount() == 5 &&
              env.velocityInput->accessibilityDescription() ==
                  QStringLiteral("Velocity. Programmable Wave has 5 volume levels."),
          "Wave selection should publish five intrinsic graduations");
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              env.area.axis().graduationCount() == 16 &&
              env.velocityInput->accessibilityDescription() ==
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
    env.map = VelocityMap::resolve(&env.noise, env.notes[0].key);
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
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
    velocityMove(env,
                 QPointF(velocityXForTick(env, double(env.notes[1].tick)),
                         hoveredNoiseProjection.levelToY(int(env.hoveredPsgLevel))),
                 Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto &contextGraduations = env.area.axis().graduations();
    check(env.area.axis().map() == env.map &&
              env.area.axis().graduationCount() == env.map.levelCount() &&
              contextGraduations[env.hoveredPsgLevel].active,
          "hovered PSG node must replace an incompatible selected-note axis context");
    velocityLeave(env);
    env.view.cancelVelocityGesture();
    QApplication::processEvents();
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
    env.map = VelocityMap::resolve(&env.noise, env.notes[0].key);
    env.hoveredPsgVelocity = 74;
    env.hoveredPsgLevel = 9;
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    check(env.view.beginVelocityGesture({env.notes[1]}) &&
              env.view.updateVelocityGesture({{env.notes[1].noteId, env.hoveredPsgVelocity}}),
          "velocity rendering fixture must stage its hovered PSG preview");
    QApplication::processEvents();
    const std::optional<std::size_t> selectedLevel = env.map.levelOf(env.notes[0].velocity);
    const std::optional<std::size_t> unselectedLevel = env.map.levelOf(env.notes[1].velocity);
    const double paintNodeX = velocityXForTick(env, double(env.notes[0].tick));
    const double selectedY = selectedLevel ? env.area.axis().levelToY(int(*selectedLevel))
                                           : env.area.axis().velocityToY(env.notes[0].velocity);
    const double unselectedY = env.area.axis().levelToY(int(env.hoveredPsgLevel));
    const QImage velocityImage = captureVelocityBand(env.view);
    const qreal imageScale = velocityImage.devicePixelRatio();
    env.imageScale = imageScale;
    const QColor expectedStem = songview::mixTowardOklab(env.live.trackColor, Qt::black, 1.0 / 3.0);
    const int fixedSpan = velocityFixedSpan(env.view);
    const QRect velocityLabelBounds =
        toPixels(QRectF(double(layout::space(layout::Space::Two)), 0.0,
                        double(fixedSpan - 2 * layout::space(layout::Space::Two)),
                        velocityBandRect(env.view).height()),
                 env.imageScale);
    const quint64 axisBeforeHover = layerRevision(env, songview::TimelineQuickLayer::VelocityAxis);
    velocityMove(env, QPointF(paintNodeX, unselectedY), Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage hoveredVelocityImage = captureVelocityBand(env.view);
    const auto &hoveredGraduations = env.area.axis().graduations();
    const auto activeHoveredGraduationCount = std::count_if(
        hoveredGraduations.begin(), hoveredGraduations.begin() + env.area.axis().graduationCount(),
        [](const VelocityAxisGraduation &graduation) { return graduation.active; });
    const auto hoveredPreview = env.view.previewVelocity(env.notes[1].noteId);
    check(env.area.useDetents() && env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              hoveredPreview && *hoveredPreview == env.hoveredPsgVelocity &&
              env.map.representative(int(env.hoveredPsgLevel)) == 76 &&
              hoveredGraduations[env.hoveredPsgLevel].active && activeHoveredGraduationCount == 1 &&
              layerRevision(env, songview::TimelineQuickLayer::VelocityAxis) > axisBeforeHover &&
              !velocityImage.isNull() && !hoveredVelocityImage.isNull() &&
              !samePixels(velocityImage.copy(velocityLabelBounds),
                          hoveredVelocityImage.copy(velocityLabelBounds)),
          "with PSG detents enabled, hovering MIDI velocity 74 must isolate Noise Vol 10 "
          "instead of raw MIDI 74");
    env.area.setUseDetents(false);
    const quint64 axisBeforeRawHover =
        layerRevision(env, songview::TimelineQuickLayer::VelocityAxis);
    QApplication::processEvents();
    const QImage rawHoveredVelocityImage = captureVelocityBand(env.view);
    const auto &rawHoveredMarkers = env.area.axis().markers();
    check(!env.area.useDetents() && env.area.axis().markerCount() == 1 &&
              rawHoveredMarkers[0].velocity == env.hoveredPsgVelocity &&
              std::abs(rawHoveredMarkers[0].y -
                       env.area.axis().velocityToY(env.hoveredPsgVelocity)) < 0.001 &&
              layerRevision(env, songview::TimelineQuickLayer::VelocityAxis) > axisBeforeRawHover &&
              !rawHoveredVelocityImage.isNull() &&
              !samePixels(hoveredVelocityImage.copy(velocityLabelBounds),
                          rawHoveredVelocityImage.copy(velocityLabelBounds)),
          "with PSG detents disabled, hovering MIDI velocity 74 must isolate raw MIDI 74");
    env.area.setUseDetents(true);
    const quint64 axisBeforeLeave = layerRevision(env, songview::TimelineQuickLayer::VelocityAxis);
    velocityLeave(env);
    QApplication::processEvents();
    const QImage restoredVelocityImage = captureVelocityBand(env.view);
    check(layerRevision(env, songview::TimelineQuickLayer::VelocityAxis) > axisBeforeLeave &&
              !restoredVelocityImage.isNull() &&
              samePixels(velocityImage.copy(velocityLabelBounds),
                         restoredVelocityImage.copy(velocityLabelBounds)),
          "leaving a hovered velocity node must restore the graduation labels");
    const QRectF selectedNodeProbe(
        paintNodeX - env.expected.nodePaintRadius, selectedY - env.expected.nodePaintRadius,
        2.0 * env.expected.nodePaintRadius, 2.0 * env.expected.nodePaintRadius);
    const QRectF unselectedNodeProbe(
        paintNodeX - env.expected.nodePaintRadius, unselectedY - env.expected.nodePaintRadius,
        2.0 * env.expected.nodePaintRadius, 2.0 * env.expected.nodePaintRadius);
    check(selectedLevel && unselectedLevel && !velocityImage.isNull() &&
              layerTouches(
                  env.quickScene, songview::TimelineQuickLayer::VelocityStems,
                  QRectF(paintNodeX, unselectedY - layout::singlePixel(),
                         velocityXForTick(env, double(env.notes[1].tick + env.notes[1].duration)) -
                             paintNodeX,
                         2.0 * layout::singlePixel()),
                  expectedStem),
          "unselected velocity duration stems must use the OKLab track shade");
    check(layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                       unselectedNodeProbe, Qt::black),
          "unselected velocity nodes must retain black outlines");
    check(layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                       selectedNodeProbe, env.velocityInput->palette().highlight().color()),
          "selected velocity nodes must retain selection rings");
    check(layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                       unselectedNodeProbe, env.live.trackColor),
          "a single-node selection must preserve unselected velocity node colors");
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId, env.notes[2].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const QImage multiSelectionImage = captureVelocityBand(env.view);
    check(!multiSelectionImage.isNull() &&
              layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                           unselectedNodeProbe, env.velocityInput->palette().mid().color()),
          "nodes outside a multi-node velocity selection must turn gray");
    check(!layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                        unselectedNodeProbe, Qt::black),
          "nodes outside a multi-node velocity selection must omit their outlines");
    env.view.cancelVelocityGesture();
    QApplication::processEvents();
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    const QRectF rulerAccentBounds(
        double(fixedSpan - layout::singlePixel() - 3 * layout::space(layout::Space::Half) - 1),
        selectedY - 2.0, double(3 * layout::space(layout::Space::Half) + 2), 4.0);
    const QImage rulerImage = captureVelocityBand(env.view);
    check(!rulerImage.isNull() &&
              layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityAxis,
                           rulerAccentBounds,
                           env.velocityGutterInput->palette().highlight().color()),
          "intrinsic ruler paint must preserve the emphasized accent tick");
    return failures;
}

int checkEditCursorRepaint(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const uint64_t viewCursorBefore = env.view.editCursorTick();
    const auto quickCursorAt = [&env](uint64_t tick) {
        return env.view.timelineSplitX() +
               env.view.camera().displayX(double(tick), 0.0, env.velocityInput->devicePixelRatio());
    };
    env.live.editCursorTick = 12;
    env.view.setEditCursorTick(env.live.editCursorTick);
    QApplication::processEvents();
    env.area.refreshLiveState(env.live);
    const qreal firstQuickCursor = env.quickView->editRootContentX();
    env.live.editCursorTick = 18;
    env.view.setEditCursorTick(env.live.editCursorTick);
    QApplication::processEvents();
    env.area.refreshLiveState(env.live);
    const qreal secondQuickCursor = env.quickView->editRootContentX();
    check(env.quickView->editVisible() && std::abs(firstQuickCursor - quickCursorAt(12)) < 0.001 &&
              std::abs(secondQuickCursor - quickCursorAt(18)) < 0.001 &&
              std::abs(secondQuickCursor - firstQuickCursor) > 0.001,
          "moving the edit cursor must repaint the velocity lane");
    env.view.setEditCursorTick(viewCursorBefore);
    QApplication::processEvents();
    env.area.refreshLiveState(env.live);
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

int checkBandOverlayRendering(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const QRectF selectorProbe(
        layout::space(layout::Space::One), velocityPlotRect(env.view).height() / 3.0,
        2 * layout::space(layout::Space::Eight), layout::space(layout::Space::Eight));
    const QPointF selectorStart = selectorProbe.topLeft();
    const QPointF selectorEnd = selectorProbe.bottomRight();
    QColor selectionFill = themes::color(themes::Role::song_view_selection_fill);
    selectionFill.setAlpha(30);
    const QColor selectionEdge = themes::color(themes::Role::song_view_selection_edge);
    const auto selectionRect = [&env, &selectionFill] {
        return solidLayerRect(env.quickScene, songview::TimelineQuickLayer::VelocityTransient,
                              selectionFill);
    };
    const quint64 transientBefore =
        layerRevision(env, songview::TimelineQuickLayer::VelocityTransient);
    velocityPress(env, selectorStart, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    velocityMove(env, selectorEnd, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto activeSelectionRect = selectionRect();
    check(layerRevision(env, songview::TimelineQuickLayer::VelocityTransient) > transientBefore &&
              activeSelectionRect && activeSelectionRect->contains(selectorProbe.center()) &&
              layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityTransient,
                           selectorProbe, selectionEdge),
          "velocity band selection must paint its translucent fill and edge");
    velocityRelease(env, selectorEnd, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    check(layerIsEmpty(env.quickScene, songview::TimelineQuickLayer::VelocityTransient),
          "releasing velocity band selection must clear its rendered overlay");
    return failures;
}

int checkStackedNodeRendering(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    DocNote first;
    check(env.document.findNote(env.notes[0].noteId, &first),
          "stacked-node rendering fixture must resolve its first note");
    if (!env.document.findNote(env.notes[0].noteId, &first))
        return failures;
    env.document.addNote(0, first.tick + 8, first.key, first.duration, first.velocity);
    env.live.documentRevision = env.document.revision();
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const std::vector<DocNote> fixtureNotes = env.document.notesForTrack(0);
    const auto overlap =
        std::find_if(fixtureNotes.cbegin(), fixtureNotes.cend(), [&first](const DocNote &note) {
            return note.tick == first.tick + 8 && note.noteId != first.noteId;
        });
    check(overlap != fixtureNotes.cend(),
          "stacked-node rendering fixture must add an overlapping circle");
    if (overlap == fixtureNotes.cend())
        return failures;
    env.map = VelocityMap::resolve(&env.noise, overlap->key);
    const auto nodeFor = [&env](const DocNote &note) {
        const std::optional<std::size_t> level = env.map.levelOf(note.velocity);
        const double y = level ? env.area.axis().levelToY(int(*level))
                               : env.area.axis().velocityToY(note.velocity);
        return QPointF(velocityXForTick(env, double(note.tick)), y);
    };
    const QPointF overlapNode = nodeFor(*overlap);
    velocityPress(env, overlapNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage overlapImage = captureVelocityBand(env.view);
    check(!overlapImage.isNull() &&
              velocityNodeHasColor(env, overlapNode,
                                   env.velocityInput->palette().highlight().color()),
          "a velocity circle over a duration stem must render its selected ring");
    velocityRelease(env, overlapNode, Qt::LeftButton, Qt::NoModifier);

    env.view.selectionModel().setNoteSelection({env.notes[0].noteId, env.notes[2].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const QPointF selectedNode = nodeFor(first);
    velocityPress(env, selectedNode, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const QImage selectedImage = captureVelocityBand(env.view);
    check(!selectedImage.isNull() &&
              velocityNodeHasColor(env, selectedNode,
                                   env.velocityInput->palette().highlight().color()),
          "a selected velocity-node group must retain its rendered ring");
    velocityRelease(env, selectedNode, Qt::RightButton, Qt::NoModifier);
    env.document.deleteNotes({*overlap});
    env.live.documentRevision = env.document.revision();
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    return failures;
}

int checkRampPreviewRendering(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.map = VelocityMap::resolve(&env.noise, env.notes[0].key);
    DocNote first;
    DocNote third;
    check(env.document.findNote(env.notes[0].noteId, &first) &&
              env.document.findNote(env.notes[2].noteId, &third),
          "ramp-preview rendering fixture must resolve its endpoint notes");
    if (!env.document.findNote(env.notes[0].noteId, &first) ||
        !env.document.findNote(env.notes[2].noteId, &third))
        return failures;
    env.document.setNotesVelocity({first}, env.map.representative(0));
    env.document.setNotesVelocity({third}, env.map.representative(4));
    env.document.addNote(0, 36, first.key, 12, env.map.representative(3));
    const std::vector<DocNote> fixtureNotes = env.document.notesForTrack(0);
    const auto middle = std::find_if(fixtureNotes.cbegin(), fixtureNotes.cend(),
                                     [](const DocNote &note) { return note.tick == 36; });
    check(middle != fixtureNotes.cend(), "ramp-preview rendering fixture must add a midpoint");
    if (middle == fixtureNotes.cend())
        return failures;
    env.view.selectionModel().setNoteSelection(
        {env.notes[0].noteId, middle->noteId, env.notes[2].noteId});
    env.area.songChanged();
    env.live.documentRevision = env.document.revision();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const QPointF start(velocityXForTick(env, double(first.tick)), env.area.axis().levelToY(0));
    const QPointF end(velocityXForTick(env, double(third.tick)), env.area.axis().levelToY(4));
    velocityPress(env, start, Qt::LeftButton, Qt::LeftButton, Qt::ShiftModifier);
    velocityMove(env, end, Qt::LeftButton, Qt::ShiftModifier);
    QApplication::processEvents();
    const QPointF quarter = start + 0.25 * (end - start);
    const QImage preview = captureVelocityBand(env.view);
    check(!preview.isNull() &&
              layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityTransient,
                           QRectF(quarter.x() - 2.0, quarter.y() - 2.0, 5.0, 5.0),
                           themes::color(themes::Role::song_view_edit_preview_outline)),
          "Shift-ramp preview must retain its rendered outline");
    velocityRelease(env, end, Qt::LeftButton, Qt::ShiftModifier);
    env.document.deleteNotes({*middle});
    env.live.documentRevision = env.document.revision();
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    return failures;
}

int checkRollVelocityPreviewRendering(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    auto *roll = env.quickView && env.quickView->rootObject()
                     ? env.quickView->rootObject()->findChild<songview::TimelineInputItem *>(
                           QStringLiteral("timelineRollInput"))
                     : nullptr;
    const auto modifiers =
        keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
    check(roll && modifiers != Qt::NoModifier,
          "roll-preview rendering fixture must expose the velocity drag input");
    if (!roll || modifiers == Qt::NoModifier)
        return failures;
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId, env.notes[1].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    DocNote first;
    check(env.document.findNote(env.notes[0].noteId, &first),
          "roll-preview rendering fixture must resolve its first note");
    if (!env.document.findNote(env.notes[0].noteId, &first))
        return failures;
    env.map = VelocityMap::resolve(&env.noise, first.key);
    const QPointF center(
        env.view.camera().displayX(double(first.tick) + double(first.duration) / 2.0, 0.0,
                                   roll->devicePixelRatio()),
        (127.5 - double(first.key)) * env.view.camera().keyHeight() - env.view.camera().scrollY());
    const int delta = QApplication::startDragDistance() + 16;
    const QPointF dragged = center - QPointF(0.0, double(delta));
    checks::events::sendMouse(*roll, QEvent::MouseButtonPress, center, Qt::LeftButton,
                              Qt::LeftButton, modifiers);
    checks::events::sendMouse(*roll, QEvent::MouseMove, dragged, Qt::NoButton, Qt::LeftButton,
                              modifiers);
    QApplication::processEvents();
    const auto previewVelocity = env.view.previewVelocity(first.noteId);
    const std::optional<std::size_t> previewLevel =
        previewVelocity ? env.map.levelOf(*previewVelocity) : std::nullopt;
    const QPointF previewNode(velocityXForTick(env, double(first.tick)),
                              previewVelocity && previewLevel
                                  ? env.area.axis().levelToY(int(*previewLevel))
                                  : env.area.axis().velocityToY(first.velocity));
    const QImage preview = captureVelocityBand(env.view);
    check(previewVelocity && !preview.isNull() && velocityNodeHasColor(env, previewNode, Qt::black),
          "piano-roll velocity preview must move the drawer node before release");
    checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, dragged, Qt::LeftButton,
                              Qt::NoButton, modifiers);
    env.live.documentRevision = env.document.revision();
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    return failures;
}

int checkDetentChromeRendering(VelocityAreaEnv &env)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    env.voicegroup.voices[0] = env.wave;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const auto &graduations = env.area.axis().graduations();
    const VelocityAxisGraduation &vol1 = graduations[0];
    const QPoint areaOrigin = velocityBandRect(env.view).topLeft();
    const QRect detentBounds = env.chrome.detentRect().toAlignedRect();
    const double labelLeft = double(layout::space(layout::Space::Two));
    const double labelRight =
        std::max(labelLeft, double(velocityFixedSpan(env.view) - layout::singlePixel() -
                                   layout::space(layout::Space::Two)));
    const double labelHeight = env.area.axis().geometry().labelHeight;
    const QRectF labelBounds =
        QFontMetricsF(typography::noteName(env.velocityGutterInput->font()))
            .boundingRect(
                QRectF(labelLeft, vol1.y - labelHeight / 2.0, labelRight - labelLeft, labelHeight),
                Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("Vol 1"))
            .translated(areaOrigin.x(), areaOrigin.y());
    const QRect trackHeaderBounds(0, 0, areaOrigin.x(), env.view.height());
    check(env.detentInput &&
              env.detentInput->interaction() ==
                  &env.chrome.interaction(DrawerChromeTarget::Detent) &&
              env.detentInput->isVisible() &&
              env.detentInput->bounds() == QRectF(QPointF{}, env.chrome.detentRect().size()) &&
              env.chrome.detentVisible() && env.chrome.detentEnabled() &&
              env.chrome.detentChecked() && !detentBounds.isEmpty() &&
              detentBounds.left() == areaOrigin.x() &&
              detentBounds.right() < areaOrigin.x() + velocityFixedSpan(env.view) &&
              detentBounds.bottom() == velocityBandRect(env.view).bottom() &&
              !detentBounds.intersects(trackHeaderBounds) && vol1.labelVisible &&
              !QRectF(detentBounds).intersects(labelBounds),
          "PSG detent chrome must stay in the label gutter without covering Vol 1");

    env.voicegroup.voices[0] = env.directSound;
    env.view.setVoicegroup(&env.voicegroup);
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId, env.notes[2].noteId});
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const QImage directSoundRuler = captureVelocityBand(env.view);
    const quint64 directAxisRevision =
        layerRevision(env, songview::TimelineQuickLayer::VelocityAxis);
    check(!env.detentInput->isVisible() && !env.chrome.detentVisible() &&
              !env.chrome.detentEnabled() && !env.chrome.detentChecked() &&
              env.chrome.detentRect().isEmpty(),
          "detent chrome must hide for a DirectSound selection");

    env.voicegroup.voices[0] = env.wave;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const int checkedIconRevision = env.chrome.iconRevision();
    env.chrome.setDetentChecked(false);
    QApplication::processEvents();
    const QImage unlockedRuler = captureVelocityBand(env.view);
    const qreal scale = unlockedRuler.devicePixelRatio();
    const QRect rulerBounds(0, 0, qCeil(double(velocityFixedSpan(env.view)) * scale),
                            qFloor(double(detentBounds.top() - areaOrigin.y()) * scale));
    check(env.detentInput->isVisible() && env.chrome.detentVisible() &&
              env.chrome.detentEnabled() && !env.chrome.detentChecked() && !env.area.useDetents() &&
              env.chrome.iconRevision() > checkedIconRevision && !directSoundRuler.isNull() &&
              !unlockedRuler.isNull() &&
              layerRevision(env, songview::TimelineQuickLayer::VelocityAxis) > directAxisRevision &&
              samePixels(directSoundRuler.copy(rulerBounds), unlockedRuler.copy(rulerBounds)),
          "disabling PSG detents must redraw the continuous sample-voice ruler");
    const int uncheckedIconRevision = env.chrome.iconRevision();
    const QPointF detentCenter = env.detentInput->bounds().center();
    checks::events::sendMouse(*env.detentInput, QEvent::MouseButtonPress, detentCenter,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*env.detentInput, QEvent::MouseButtonRelease, detentCenter,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    check(env.chrome.detentChecked() && env.area.useDetents() &&
              env.chrome.iconRevision() > uncheckedIconRevision,
          "drawer detent input must restore the snapped ruler");
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
    auto *fixtureQuickView =
        fixtureView.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *fixtureQuickRoot = fixtureQuickView ? fixtureQuickView->rootObject() : nullptr;
    auto *fixtureInput = fixtureQuickRoot
                             ? fixtureQuickRoot->findChild<songview::TimelineInputItem *>(
                                   QStringLiteral("timelineVelocityInput"))
                             : nullptr;
    if (!fixtureArea || !fixtureInput) {
        std::fprintf(stderr,
                     "velocity-page: FAIL %s: fixture SongView did not expose its physical "
                     "velocity input\n",
                     qUtf8Printable(songLabel));
        return 1;
    }
    const auto expected = expectedVelocityGeometry();
    fixtureView.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                       expected.densityThresholdD4 +
                                           layout::space(layout::Space::Six));
    fixtureArea->songChanged();
    DrawerPageLiveState fixtureLive;
    fixtureLive.documentRevision = fixtureDocument.revision();
    fixtureLive.timeZoom = 48.0;
    fixtureView.setEditorTimeZoom(fixtureLive.timeZoom);
    fixtureLive.timeZoom = fixtureView.camera().pxPerBeat();
    fixtureLive.horizontalScroll = fixtureView.camera().scrollX();
    fixtureArea->refreshLiveState(fixtureLive);
    QApplication::processEvents();
    const qreal zoomAnchorContentX = std::max<qreal>(1.0, fixtureInput->bounds().width() / 2.0);
    const QPointF zoomAnchor(qRound(zoomAnchorContentX),
                             velocityPlotRect(fixtureView).height() / 2.0);
    const double tickBeforeZoom = fixtureView.camera().tickAtContentX(zoomAnchor.x());
    const double zoomBefore = fixtureView.camera().pxPerBeat();
    checks::events::sendWheel(*fixtureInput, zoomAnchor, QPoint(), QPoint(0, 120), Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false);
    QApplication::processEvents();
    check(fixtureView.camera().pxPerBeat() > zoomBefore,
          "plain wheel must change velocity-lane time zoom");
    check(std::abs(fixtureView.camera().tickAtContentX(zoomAnchor.x()) - tickBeforeZoom) < 0.001,
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
    if (!drawer || !areaPtr)
        return 1;
    DrawerChrome &chrome = drawer->chrome();
    auto *quickView =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    auto *quickRoot = quickView ? quickView->rootObject() : nullptr;
    auto *velocityInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                          QStringLiteral("timelineVelocityInput"))
                                    : nullptr;
    auto *velocityGutterInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                                QStringLiteral("timelineVelocityGutterInput"))
                                          : nullptr;
    auto *barInput =
        quickRoot
            ? quickRoot->findChild<songview::TimelineInputItem *>(QStringLiteral("drawerBarInput"))
            : nullptr;
    auto *detentInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                        QStringLiteral("drawerDetentInput"))
                                  : nullptr;
    check(quickView && quickScene && quickRoot && velocityInput && velocityGutterInput &&
              barInput && detentInput,
          "concrete SongView should expose physical velocity plot/gutter and drawer inputs");
    if (!quickView || !quickScene || !quickRoot || !velocityInput || !velocityGutterInput ||
        !barInput || !detentInput)
        return 1;
    check(
        velocityInput->bounds() == QRectF(QPointF{}, QSizeF(velocityPlotRect(view).width(),
                                                            velocityPlotRect(view).height())) &&
            velocityGutterInput->bounds() ==
                QRectF(QPointF{}, QSizeF(velocityFixedSpan(view), velocityBandRect(view).height())),
        "velocity physical plot/gutter input bounds must start at local x=0");
    auto &area = *areaPtr;
    DrawerPageLiveState live;
    VelocityAreaEnv env{document,  timeline, voicegroup,    directSound,
                        square,    wave,     noise,         notes,
                        view,      area,     velocityInput, velocityGutterInput,
                        chrome,    barInput, detentInput,   quickScene,
                        quickView, live,     expected};
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                expected.densityThresholdD4 + layout::space(layout::Space::Six));
    area.songChanged();
    live.documentRevision = document.revision();
    live.timeZoom = 48.0;
    live.trackColor = QColor(Qt::cyan);
    view.setEditorTimeZoom(live.timeZoom);
    view.setEditorHorizontalScroll(live.horizontalScroll);
    live.timeZoom = view.camera().pxPerBeat();
    live.horizontalScroll = view.camera().scrollX();
    area.refreshLiveState(live);
    QApplication::processEvents();
    failures += checkDrawerToggleGeometry(env);
    failures += checkDrawerToggleInput(env);
    failures += checkDirectSoundChromeAndFocus(env);
    failures += checkGridContinuesPastSongEnd(env);
    failures += checkPanClampAtTickZero(env);
    failures += checkContinuousGraduationDensity(env);
    failures += checkPsgAxisContexts(env);
    failures += checkHoverAxisContext(env);
    failures += checkVelocityRendering(env);
    failures += checkEditCursorRepaint(env);
    failures += checkDrawerContextTickRounding(env);
    failures += checkBandOverlayRendering(env);
    failures += checkStackedNodeRendering(env);
    failures += checkRampPreviewRendering(env);
    failures += checkRollVelocityPreviewRendering(env);
    failures += checkDetentChromeRendering(env);

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

    if (!screenshotPath.isEmpty())
        check(captureVelocityBand(view).save(screenshotPath),
              "optional velocity screenshot should save");
    return failures == 0 ? 0 : 1;
}
