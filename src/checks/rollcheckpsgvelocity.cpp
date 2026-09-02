#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
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
#include <QTemporaryDir>
#include <QToolButton>

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

QRect velocityBandRect(const SongView &view)
{
    const auto &geometry = view.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
    return geometry ? geometry->rect : QRect{};
}

QImage captureVelocityBand(SongView &view)
{
    return checks::support::captureQuickBand(view, velocityBandRect(view));
}

// In-memory TimelineInputHost for this check: it services the velocity band's
// host queries from SongView state, records the accessibility description the
// area publishes, and swaps out the production QML input item wiring while the
// check drives normalized interaction calls directly.
class VelocityInputHost final : public songview::TimelineInputHost
{
  public:
    VelocityInputHost(SongView &view, VelocityArea &area) : m_view(view), m_area(area) {}
    ~VelocityInputHost() override { Q_ASSERT(!m_attached); }

    void attach()
    {
        Q_ASSERT(!m_attached);
        auto *quickView =
            m_view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        m_productionItem = quickView && quickView->rootObject()
                               ? quickView->rootObject()->findChild<songview::TimelineInputItem *>(
                                     QStringLiteral("timelineVelocityInput"))
                               : nullptr;
        m_productionInteraction = m_productionItem ? m_productionItem->interaction() : nullptr;
        if (m_productionItem && m_productionInteraction)
            m_productionItem->setInteraction(nullptr);
        m_area.attachInputHost(*this);
        m_attached = true;
    }

    void detach()
    {
        Q_ASSERT(m_attached);
        m_attached = false;
        m_area.detachInputHost(*this);
        if (m_productionItem && m_productionInteraction)
            m_productionItem->setInteraction(m_productionInteraction);
        m_productionItem = nullptr;
        m_productionInteraction = nullptr;
    }

    QString accessibilityDescription() const { return m_accessibilityDescription; }

    // TimelineInputHost
    QRectF bounds() const override
    {
        const QRect band = velocityBandRect(m_view);
        return QRectF(0.0, 0.0, band.width(), band.height());
    }
    qreal devicePixelRatio() const override { return m_view.devicePixelRatioF(); }
    QFont font() const override { return m_view.font(); }
    QPalette palette() const override { return m_view.palette(); }
    QPointF mapFromGlobal(QPointF position) const override
    {
        return QPointF(m_view.mapFromGlobal(position.toPoint())) -
               QPointF(velocityBandRect(m_view).topLeft());
    }
    QPointF mapToGlobal(QPointF position) const override
    {
        return QPointF(
            m_view.mapToGlobal((QPointF(velocityBandRect(m_view).topLeft()) + position).toPoint()));
    }
    void requestFocus(Qt::FocusReason reason) override { m_view.setFocus(reason); }
    void setCursor(const QCursor &cursor) override { m_view.setCursor(cursor); }
    void clearCursor() override { m_view.unsetCursor(); }
    void releasePointerGrab() override {}
    void setAccessibilityDescription(const QString &description) override
    {
        m_accessibilityDescription = description;
    }

  private:
    SongView &m_view;
    VelocityArea &m_area;
    songview::TimelineInputItem *m_productionItem = nullptr;
    songview::TimelineBandInteraction *m_productionInteraction = nullptr;
    QString m_accessibilityDescription;
    bool m_attached = false;
};

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
    VelocityInputHost *host = nullptr;
    QWidget *drawer = nullptr;
    QWidget *drawerSections = nullptr;
    QToolButton *velToggle = nullptr;
    QWidget *automationBar = nullptr;
    QToolButton *automationToggle = nullptr;
    QToolButton *detentToggle = nullptr;
    songview::TimelineQuickScene *quickScene = nullptr;
    songview::TimelineQuickView *quickView = nullptr;
    DrawerPageLiveState &live;
    ExpectedVelocityGeometry expected;
    VelocityMap map;
    uint8_t hoveredPsgVelocity = 0;
    std::size_t hoveredPsgLevel = 0;
    qreal imageScale = 1.0;
};

QPointF velocityGlobalPosition(VelocityAreaEnv &env, const QPointF &position)
{
    return env.host->mapToGlobal(position);
}

void velocityPress(VelocityAreaEnv &env, const QPointF &position, Qt::MouseButton button,
                   Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    env.area.pointerPress(
        {position, velocityGlobalPosition(env, position), button, buttons, modifiers});
}

void velocityMove(VelocityAreaEnv &env, const QPointF &position, Qt::MouseButtons buttons,
                  Qt::KeyboardModifiers modifiers)
{
    env.area.pointerMove(
        {position, velocityGlobalPosition(env, position), Qt::NoButton, buttons, modifiers});
}

void velocityRelease(VelocityAreaEnv &env, const QPointF &position, Qt::MouseButton button,
                     Qt::KeyboardModifiers modifiers)
{
    env.area.pointerRelease(
        {position, velocityGlobalPosition(env, position), button, Qt::NoButton, modifiers});
}

void velocityLeave(VelocityAreaEnv &env)
{
    env.area.pointerLeave();
}

void velocityUngrab(VelocityAreaEnv &env)
{
    env.area.inputCancelled(songview::TimelineInputCancelReason::PointerUngrabbed);
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
    auto *voiceToggle = env.drawerSections ? env.drawerSections->findChild<QToolButton *>(
                                                 QStringLiteral("voiceChangesDrawerToggle"))
                                           : nullptr;
    const auto toggleRect = [&env](QWidget *widget) {
        return QRect(widget->mapTo(&env.view, QPoint()), widget->size());
    };
    const QRect toggleGroup = voiceToggle && env.automationToggle && env.velToggle
                                  ? toggleRect(voiceToggle)
                                        .united(toggleRect(env.automationToggle))
                                        .united(toggleRect(env.velToggle))
                                  : QRect{};
    const int pianoKeysCenter = velocityBandRect(env.view).x() + env.area.plotOrigin() / 2;
    check(voiceToggle && env.velToggle && env.automationBar && env.automationToggle &&
              env.automationBar->geometry().contains(voiceToggle->geometry()) &&
              env.automationBar->geometry().contains(env.velToggle->geometry()) &&
              env.automationToggle->x() ==
                  voiceToggle->x() + voiceToggle->width() + layout::space(layout::Space::One) &&
              env.velToggle->x() == env.automationToggle->x() + env.automationToggle->width() +
                                        layout::space(layout::Space::One) &&
              voiceToggle->y() == env.automationToggle->y() &&
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
              env.host->accessibilityDescription() == QStringLiteral("Velocity"),
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
    // Retained scene geometry is local to the VelocityGrid QQuickItem, not the native
    // QQuickView window. Match the renderer's snapped, camera-relative local x.
    const qreal dpr = env.host->devicePixelRatio();
    const auto gridX = [&env, dpr](uint64_t tick) {
        return env.view.displayX(double(tick), env.area.plotOrigin(), dpr);
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
    env.live.timeZoom = env.view.pxPerBeat();
    env.live.horizontalScroll = env.view.viewState().scrollPx;
    env.area.refreshLiveState(env.live);
    QApplication::processEvents();
    const auto beforePanPastZero = captureVelocityBand(env.view);
    const auto panStart = QPointF(env.area.plotOrigin() + layout::space(layout::Space::Two),
                                  velocityBandRect(env.view).height() / 2.0);
    const auto panLeftPastZero = panStart + QPointF(layout::space(layout::Space::Eight), 0.0);
    velocityPress(env, panStart, Qt::MiddleButton, Qt::MiddleButton, Qt::NoModifier);
    velocityMove(env, panLeftPastZero, Qt::MiddleButton, Qt::NoModifier);
    velocityRelease(env, panLeftPastZero, Qt::MiddleButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto afterPanPastZero = captureVelocityBand(env.view);
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
              env.host->accessibilityDescription() ==
                  QStringLiteral("Velocity. Square 1 has 16 volume levels."),
          "compatible Square selection should publish intrinsic graduations");
    env.voicegroup.voices[0] = env.wave;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              env.area.axis().graduationCount() == 5 &&
              env.host->accessibilityDescription() ==
                  QStringLiteral("Velocity. Programmable Wave has 5 volume levels."),
          "Wave selection should publish five intrinsic graduations");
    env.voicegroup.voices[0] = env.noise;
    env.view.setVoicegroup(&env.voicegroup);
    env.area.songChanged();
    env.live.editCursorTick++;
    env.area.refreshLiveState(env.live);
    check(env.area.axis().mode() == VelocityAxis::Mode::Intrinsic &&
              env.area.axis().graduationCount() == 16 &&
              env.host->accessibilityDescription() ==
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
                 QPointF(double(env.area.plotOrigin()) +
                             double(env.notes[1].tick) * env.live.timeZoom /
                                 double(env.timeline->ticksPerBeat) -
                             env.live.horizontalScroll,
                         hoveredNoiseProjection.levelToY(int(env.hoveredPsgLevel))),
                 Qt::NoButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto &contextGraduations = env.area.axis().graduations();
    check(env.area.axis().map() == env.map &&
              env.area.axis().graduationCount() == env.map.levelCount() &&
              contextGraduations[env.hoveredPsgLevel].active,
          "hovered PSG node must replace an incompatible selected-note axis context");
    velocityLeave(env);
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
    const QImage velocityImage = captureVelocityBand(env.view);
    const qreal imageScale = velocityImage.devicePixelRatio();
    env.imageScale = imageScale;
    const QColor expectedStem = songview::mixTowardOklab(env.live.trackColor, Qt::black, 1.0 / 3.0);
    const QRect velocityLabelBounds =
        toPixels(QRectF(double(layout::space(layout::Space::Two)), 0.0,
                        double(env.area.plotOrigin() - 2 * layout::space(layout::Space::Two)),
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
              layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityStems,
                           QRectF(paintNodeX, unselectedY - layout::singlePixel(),
                                  env.notes[1].duration * env.live.timeZoom /
                                      double(env.timeline->ticksPerBeat),
                                  2.0 * layout::singlePixel()),
                           expectedStem),
          "unselected velocity duration stems must use the OKLab track shade");
    check(layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                       unselectedNodeProbe, Qt::black),
          "unselected velocity nodes must retain black outlines");
    check(layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                       selectedNodeProbe, env.host->palette().highlight().color()),
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
                           unselectedNodeProbe, env.host->palette().mid().color()),
          "nodes outside a multi-node velocity selection must turn gray");
    check(!layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                        unselectedNodeProbe, Qt::black),
          "nodes outside a multi-node velocity selection must omit their outlines");
    env.view.cancelVelocityGesture();
    QApplication::processEvents();
    env.view.selectionModel().setNoteSelection({env.notes[0].noteId});
    ++env.live.editCursorTick;
    env.area.refreshLiveState(env.live);
    const QRectF rulerAccentBounds(double(env.area.plotOrigin() - layout::singlePixel() -
                                          3 * layout::space(layout::Space::Half) - 1),
                                   selectedY - 2.0,
                                   double(3 * layout::space(layout::Space::Half) + 2), 4.0);
    const QImage rulerImage = captureVelocityBand(env.view);
    check(!rulerImage.isNull() &&
              layerTouches(env.quickScene, songview::TimelineQuickLayer::VelocityAxis,
                           rulerAccentBounds, env.host->palette().highlight().color()),
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
        return env.view.timelinePlotOrigin() + qreal(env.view.contentX(double(tick)));
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
    const QPointF firstDrag = stem + QPointF(0.0, double(velocityBandRect(rig.env.view).height()));
    const QPointF drag = stem + QPointF(0.0, -double(velocityBandRect(rig.env.view).height()));
    velocityPress(rig.env, stem, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityMove(rig.env, firstDrag, Qt::LeftButton, Qt::NoModifier);
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
    const QImage activeDrag = captureVelocityBand(rig.env.view);
    const uint8_t firstPreviewVelocity = firstPreviewFirst.value_or(rig.env.notes[0].velocity);
    const std::optional<std::size_t> firstDraggedLevel = rig.env.map.levelOf(firstPreviewVelocity);
    const double firstDraggedY = firstDraggedLevel
                                     ? rig.env.area.axis().levelToY(int(*firstDraggedLevel))
                                     : rig.env.area.axis().velocityToY(firstPreviewVelocity);
    const QRectF activeDragRing(rig.nodeX - rig.env.expected.nodePaintRadius,
                                firstDraggedY - rig.env.expected.nodePaintRadius,
                                2.0 * rig.env.expected.nodePaintRadius,
                                2.0 * rig.env.expected.nodePaintRadius);
    check(!activeDrag.isNull() &&
              layerTouches(rig.env.quickScene, songview::TimelineQuickLayer::VelocityNodes,
                           activeDragRing, rig.env.host->palette().highlight().color()),
          "dragging a selected velocity node must retain its visible selection ring");
    velocityMove(rig.env, drag, Qt::LeftButton, Qt::NoModifier);
    const auto finalPreviewFirst = rig.env.view.previewVelocity(rig.env.notes[0].noteId);
    const auto finalPreviewSecond = rig.env.view.previewVelocity(rig.env.notes[1].noteId);
    check(finalPreviewFirst && finalPreviewSecond && firstPreviewFirst &&
              *finalPreviewFirst != *firstPreviewFirst &&
              rig.env.document.revision() == revisionBeforeGesture &&
              rig.env.document.undoStack()->count() == undoDepth,
          "successive velocity updates must remain deferred while the drag is held");
    velocityRelease(rig.env, drag, Qt::LeftButton, Qt::NoModifier);
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
    velocityPress(rig.env, restoredNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityRelease(rig.env, restoredNode, Qt::LeftButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
              std::vector<NoteId>{rig.env.notes[0].noteId},
          "clicking one selected velocity node must collapse the other selected nodes");
    return failures;
}

int checkPointerUngrabCancelsProvisionalSelection(VelocityAreaRig &rig)
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
    velocityPress(rig.env, secondNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityUngrab(rig.env);
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId} &&
              rig.env.document.undoStack()->count() == undoDepthBeforeUngrab,
          "pointer ungrab must cancel a provisional selection without history residue");
    return failures;
}

int checkDragBandOverlay(VelocityAreaRig &rig)
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *message) {
        velocityFail(failures, condition, message);
    };
    const QRectF selectorProbe(rig.env.area.plotOrigin() + layout::space(layout::Space::One),
                               velocityBandRect(rig.env.view).height() / 3,
                               2 * layout::space(layout::Space::Eight),
                               layout::space(layout::Space::Eight));
    const QPointF selectorStart = selectorProbe.topLeft();
    const QPointF selectorEnd = selectorProbe.bottomRight();
    const QPointF selectorContractedEnd =
        selectorStart + QPointF(selectorProbe.width() / 2.0, selectorProbe.height() / 2.0);
    QColor selectionFill = themes::color(themes::Role::song_view_selection_fill);
    selectionFill.setAlpha(30);
    const QColor selectionEdge = themes::color(themes::Role::song_view_selection_edge);
    const auto selectionRect = [&rig, &selectionFill] {
        return solidLayerRect(rig.env.quickScene, songview::TimelineQuickLayer::VelocityTransient,
                              selectionFill);
    };
    const quint64 transientBeforeBand =
        layerRevision(rig.env, songview::TimelineQuickLayer::VelocityTransient);
    velocityPress(rig.env, selectorStart, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    velocityMove(rig.env, selectorEnd, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto activeSelectionRect = selectionRect();
    check(layerRevision(rig.env, songview::TimelineQuickLayer::VelocityTransient) >
                  transientBeforeBand &&
              activeSelectionRect && activeSelectionRect->contains(selectorProbe.center()) &&
              layerTouches(rig.env.quickScene, songview::TimelineQuickLayer::VelocityTransient,
                           selectorProbe, selectionEdge),
          "drag-select must visibly paint its selector overlay");
    check(activeSelectionRect && activeSelectionRect->contains(selectorProbe.center()),
          "drag-select must composite the translucent selection fill over velocity content");
    velocityMove(rig.env, selectorContractedEnd, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    const auto contractedSelectionRect = selectionRect();
    const QPointF abandonedPoint = (selectorEnd + selectorContractedEnd) / 2.0;
    const QPointF contractedInterior = (selectorStart + selectorContractedEnd) / 2.0;
    check(activeSelectionRect && contractedSelectionRect &&
              activeSelectionRect->contains(abandonedPoint) &&
              !contractedSelectionRect->contains(abandonedPoint) &&
              contractedSelectionRect->contains(contractedInterior) &&
              contractedSelectionRect->width() < activeSelectionRect->width() &&
              contractedSelectionRect->height() < activeSelectionRect->height(),
          "contracting drag-select must clear the abandoned selector area");
    velocityRelease(rig.env, selectorContractedEnd, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    check(layerIsEmpty(rig.env.quickScene, songview::TimelineQuickLayer::VelocityTransient),
          "completed drag-select must clear its selector overlay");

    rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
    ++rig.env.live.editCursorTick;
    rig.env.area.refreshLiveState(rig.env.live);
    QApplication::processEvents();
    velocityPress(rig.env, selectorStart, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
    velocityMove(rig.env, selectorEnd, Qt::RightButton, Qt::NoModifier);
    QApplication::processEvents();
    velocityUngrab(rig.env);
    QApplication::processEvents();
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId} &&
              layerIsEmpty(rig.env.quickScene, songview::TimelineQuickLayer::VelocityTransient),
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
    velocityPress(rig.env, currentNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityRelease(rig.env, currentNode, Qt::LeftButton, Qt::NoModifier);
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
        velocityPress(rig.env, stackedNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[1].noteId},
              "overlapping circles must resolve to one later-painted target");
        velocityRelease(rig.env, stackedNode, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[1].noteId},
              "overlapping-circle release must retain its frozen target");
        ++rig.env.live.editCursorTick;
        rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF selectedStackedNode = velocityNode(currentFirst);
        velocityPress(rig.env, selectedStackedNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId},
              "selected overlapping velocity nodes must outrank unselected candidates");
        velocityRelease(rig.env, selectedStackedNode, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{rig.env.notes[0].noteId},
              "selected-layer velocity click must keep its selected target");
        rig.env.view.selectionModel().setNoteSelection({});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF circleNode = velocityNode(overlapNote);
        velocityPress(rig.env, circleNode, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage circleHeld = captureVelocityBand(rig.env.view);
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>{overlapNote.noteId} &&
                  !circleHeld.isNull() &&
                  velocityNodeHasColor(rig.env, circleNode,
                                       rig.env.host->palette().highlight().color()),
              "a circle hit must outrank stem-only overlap and paint one selected ring");
        const QPointF movedRelease = velocityNode(currentFirst);
        velocityMove(rig.env, movedRelease, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{overlapNote.noteId},
              "a velocity gesture must retain its frozen target while the cursor moves");
        velocityRelease(rig.env, movedRelease, Qt::LeftButton, Qt::NoModifier);
        check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>{overlapNote.noteId},
              "moving release away from a velocity node must not click through to another target");
        const DocNote rightTarget = rig.env.notes[2];
        rig.env.view.selectionModel().setNoteSelection({rig.env.notes[0].noteId});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF rightTargetNode = velocityNode(rightTarget);
        velocityPress(rig.env, rightTargetNode, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage rightNodeHeld = captureVelocityBand(rig.env.view);
        check(
            rig.env.view.selectionModel().noteSelection() ==
                    std::vector<NoteId>{rightTarget.noteId} &&
                !rightNodeHeld.isNull() &&
                velocityNodeHasColor(rig.env, rightTargetNode,
                                     rig.env.host->palette().highlight().color()),
            "plain right press on an unselected velocity node must select and ring it immediately");
        velocityRelease(rig.env, rightTargetNode, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage rightNodeReleased = captureVelocityBand(rig.env.view);
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>{rightTarget.noteId} &&
                  !rightNodeReleased.isNull() &&
                  velocityNodeHasColor(rig.env, rightTargetNode,
                                       rig.env.host->palette().highlight().color()),
              "plain right release must retain its selected velocity node and ring");
        rig.env.view.selectionModel().setNoteSelection(
            {rig.env.notes[0].noteId, rightTarget.noteId});
        ++rig.env.live.editCursorTick;
        rig.env.area.refreshLiveState(rig.env.live);
        QApplication::processEvents();
        const QPointF selectedRightNode = velocityNode(currentFirst);
        velocityPress(rig.env, selectedRightNode, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage selectedRightHeld = captureVelocityBand(rig.env.view);
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({rig.env.notes[0].noteId, rightTarget.noteId}) &&
                  !selectedRightHeld.isNull() &&
                  velocityNodeHasColor(rig.env, selectedRightNode,
                                       rig.env.host->palette().highlight().color()),
              "plain right press on a selected velocity node must retain its visual group");
        velocityRelease(rig.env, selectedRightNode, Qt::RightButton, Qt::NoModifier);
        QApplication::processEvents();
        const QImage selectedRightReleased = captureVelocityBand(rig.env.view);
        check(rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({rig.env.notes[0].noteId, rightTarget.noteId}) &&
                  !selectedRightReleased.isNull() &&
                  velocityNodeHasColor(rig.env, selectedRightNode,
                                       rig.env.host->palette().highlight().color()),
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
    velocityPress(rig.env, paintStart, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityMove(rig.env, paintEnd, Qt::LeftButton, Qt::NoModifier);
    const auto paintPreviewFirst = rig.env.view.previewVelocity(rig.env.notes[0].noteId);
    const auto paintPreviewThird = rig.env.view.previewVelocity(rig.env.notes[2].noteId);
    check(rig.env.view.selectionModel().noteSelection() ==
                  std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[2].noteId}) &&
              rig.env.document.revision() == revisionBeforePaint &&
              rig.env.document.undoStack()->index() == undoIndexBeforePaint && paintPreviewFirst &&
              paintPreviewThird && *paintPreviewFirst == rig.currentMap.representative(0) &&
              *paintPreviewThird == rig.currentMap.representative(4),
          "holding velocity paint must update preview while deferring document changes");
    velocityRelease(rig.env, paintEnd, Qt::LeftButton, Qt::NoModifier);
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
        velocityPress(rig.env, rampStart, Qt::LeftButton, Qt::LeftButton, Qt::ShiftModifier);
        velocityMove(rig.env, rampEnd, Qt::LeftButton, Qt::ShiftModifier);
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
        const QImage rampPreview = captureVelocityBand(rig.env.view);
        check(!rampPreview.isNull() &&
                  layerTouches(rig.env.quickScene, songview::TimelineQuickLayer::VelocityTransient,
                               QRectF(rampQuarter.x() - 2.0, rampQuarter.y() - 2.0, 5.0, 5.0),
                               themes::color(themes::Role::song_view_edit_preview_outline)),
              "velocity Shift-drag did not render its ramp line preview");
        velocityRelease(rig.env, rampEnd, Qt::LeftButton, Qt::ShiftModifier);
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
    velocityPress(rig.env, blankPoint, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection() ==
              std::vector<NoteId>({rig.env.notes[0].noteId, rig.env.notes[2].noteId}),
          "blank velocity press must retain selection until mouse-up");
    velocityRelease(rig.env, blankPoint, Qt::LeftButton, Qt::NoModifier);
    check(rig.env.view.selectionModel().noteSelection().empty() &&
              rig.env.document.revision() == revisionBeforeBlankClick &&
              rig.env.document.undoStack()->count() == undoDepthBeforeBlankClick,
          "blank velocity click must deselect only on mouse-up");

    rig.env.view.selectionModel().setNoteSelection(
        {rig.env.notes[0].noteId, rig.env.notes[1].noteId});
    const VelocityAxisGraduation graduation = rig.env.area.axis().graduations()[2];
    const QPointF graduationPoint(graduation.x + graduation.width / 2.0, graduation.y);
    velocityPress(rig.env, graduationPoint, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityRelease(rig.env, graduationPoint, Qt::LeftButton, Qt::NoModifier);
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
        DocNote beforeFirst{};
        DocNote beforeSecond{};
        check(rig.env.document.findNote(rig.graduatedFirst.noteId, &beforeFirst) &&
                  rig.env.document.findNote(rig.graduatedSecond.noteId, &beforeSecond),
              "piano-roll cancellation fixture must retain both selected notes");
        const uint64_t revisionBeforeRollCancel = rig.env.document.revision();
        const int undoIndexBeforeRollCancel = rig.env.document.undoStack()->index();
        const int undoCountBeforeRollCancel = rig.env.document.undoStack()->count();
        stageRollVelocityPreview();
        const auto cancellationFirstPreview = rig.env.view.previewVelocity(beforeFirst.noteId);
        const auto cancellationSecondPreview = rig.env.view.previewVelocity(beforeSecond.noteId);
        check(
            cancellationFirstPreview && *cancellationFirstPreview != beforeFirst.velocity &&
                cancellationSecondPreview && *cancellationSecondPreview != beforeSecond.velocity &&
                rig.env.view.selectionModel().noteSelection() ==
                    std::vector<NoteId>({rig.graduatedFirst.noteId, rig.graduatedSecond.noteId}) &&
                rig.env.document.revision() == revisionBeforeRollCancel &&
                rig.env.document.undoStack()->index() == undoIndexBeforeRollCancel &&
                rig.env.document.undoStack()->count() == undoCountBeforeRollCancel,
            "piano-roll cancellation must stage both selected velocity previews");
        rig.env.view.cancelActiveInteractions();
        checks::events::sendMouse(*roll, QEvent::MouseMove, rollDragPosition, Qt::NoButton,
                                  Qt::LeftButton, velocityDragModifiers);
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition,
                                  Qt::LeftButton, Qt::NoButton, velocityDragModifiers);
        QApplication::processEvents();
        DocNote cancelledAfterFirst;
        DocNote cancelledAfterSecond;
        check(!rig.env.view.previewVelocity(beforeFirst.noteId) &&
                  !rig.env.view.previewVelocity(beforeSecond.noteId) &&
                  rig.env.document.revision() == revisionBeforeRollCancel &&
                  rig.env.document.undoStack()->index() == undoIndexBeforeRollCancel &&
                  rig.env.document.undoStack()->count() == undoCountBeforeRollCancel &&
                  rig.env.document.findNote(beforeFirst.noteId, &cancelledAfterFirst) &&
                  rig.env.document.findNote(beforeSecond.noteId, &cancelledAfterSecond) &&
                  cancelledAfterFirst.velocity == beforeFirst.velocity &&
                  cancelledAfterSecond.velocity == beforeSecond.velocity,
              "SongView cancellation must clear both piano-roll previews and prevent commit");

        const uint64_t revisionBeforeRollDrag = rig.env.document.revision();
        const int undoBeforeRollDrag = rig.env.document.undoStack()->count();
        DocNote dragBeforeFirst{};
        DocNote dragBeforeSecond{};
        check(rig.env.document.findNote(rig.graduatedFirst.noteId, &dragBeforeFirst) &&
                  rig.env.document.findNote(rig.graduatedSecond.noteId, &dragBeforeSecond),
              "piano-roll drag fixture must retain both selected notes");
        stageRollVelocityPreview();
        const auto firstPreviewVelocity =
            uint8_t(std::clamp(int(dragBeforeFirst.velocity) + dragDelta, 1, 127));
        const auto secondPreviewVelocity =
            uint8_t(std::clamp(int(dragBeforeSecond.velocity) + dragDelta, 1, 127));
        const auto firstRollPreview = rig.env.view.previewVelocity(dragBeforeFirst.noteId);
        const auto secondRollPreview = rig.env.view.previewVelocity(dragBeforeSecond.noteId);
        const std::optional<std::size_t> previewLevel = rig.env.map.levelOf(firstPreviewVelocity);
        const QImage rollDragPreview = captureVelocityBand(rig.env.view);
        const QPointF previewNodeCenter(
            double(rig.env.area.plotOrigin()) +
                double(rig.env.view.contentX(double(dragBeforeFirst.tick))),
            previewLevel ? rig.env.area.axis().levelToY(int(*previewLevel))
                         : rig.env.area.axis().velocityToY(firstPreviewVelocity));
        check(rig.env.document.revision() == revisionBeforeRollDrag &&
                  rig.env.document.undoStack()->count() == undoBeforeRollDrag && firstRollPreview &&
                  *firstRollPreview == firstPreviewVelocity && secondRollPreview &&
                  *secondRollPreview == secondPreviewVelocity &&
                  rig.env.view.selectionModel().noteSelection() ==
                      std::vector<NoteId>({rig.graduatedFirst.noteId, rig.graduatedSecond.noteId}),
              "piano-roll velocity preview must stage every selected note before release");
        check(previewLevel && rig.env.area.axis().graduations()[*previewLevel].active,
              "piano-roll velocity drag must update the velocity drawer's active graduation");
        check(!rollDragPreview.isNull() &&
                  velocityNodeHasColor(rig.env, previewNodeCenter, Qt::black),
              "piano-roll velocity drag must move the velocity drawer node before release");
        checks::events::sendMouse(*roll, QEvent::MouseButtonRelease, rollDragPosition,
                                  Qt::LeftButton, Qt::NoButton, velocityDragModifiers);
        DocNote committedFirst;
        DocNote committedSecond;
        check(rig.env.document.revision() == revisionBeforeRollDrag + 1 &&
                  rig.env.document.undoStack()->count() == undoBeforeRollDrag + 1 &&
                  !rig.env.view.previewVelocity(dragBeforeFirst.noteId) &&
                  !rig.env.view.previewVelocity(dragBeforeSecond.noteId) &&
                  rig.env.document.findNote(dragBeforeFirst.noteId, &committedFirst) &&
                  rig.env.document.findNote(dragBeforeSecond.noteId, &committedSecond) &&
                  committedFirst.velocity == firstPreviewVelocity &&
                  committedSecond.velocity == secondPreviewVelocity,
              "piano-roll velocity drag must commit every selected note in one command and "
              "clear previews");
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
    velocityPress(rig.env, axisPoint, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    velocityRelease(rig.env, axisPoint, Qt::LeftButton, Qt::NoModifier);
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
            QFontMetricsF(typography::noteName(rig.env.host->font()))
                .boundingRect(QRectF(labelLeft, vol1.y - labelHeight / 2.0, labelRight - labelLeft,
                                     labelHeight),
                              Qt::AlignRight | Qt::AlignVCenter, QStringLiteral("Vol 1"));
        const QPoint areaOrigin = velocityBandRect(rig.env.view).topLeft();
        const QRect detentBounds = rig.env.detentToggle
                                       ? QRect(rig.env.detentToggle->mapTo(&rig.env.view, QPoint()),
                                               rig.env.detentToggle->size())
                                       : QRect();
        const QRectF vol1LabelBoundsInDrawer =
            vol1LabelBounds.translated(areaOrigin.x(), areaOrigin.y());
        const QRect trackHeaderBounds(0, 0, areaOrigin.x(), rig.env.view.height());
        check(rig.env.detentToggle && rig.env.detentToggle->isVisible() &&
                  rig.env.detentToggle->isEnabled() && rig.env.detentToggle->isChecked() &&
                  detentBounds.left() == areaOrigin.x() &&
                  detentBounds.right() < areaOrigin.x() + rig.env.area.plotOrigin(),
              "velocity detent toggle must stay inside the PSG label gutter");
        check(detentBounds.bottom() == velocityBandRect(rig.env.view).bottom(),
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
            const QImage directSoundRuler = captureVelocityBand(rig.env.view);
            const quint64 directAxisRevision =
                layerRevision(rig.env, songview::TimelineQuickLayer::VelocityAxis);
            rig.env.voicegroup.voices[0] = rig.env.wave;
            rig.env.area.songChanged();
            check(rig.env.detentToggle->isVisible() && rig.env.detentToggle->isEnabled(),
                  "velocity detent toggle must reappear immediately for a PSG selection");
            rig.env.detentToggle->click();
            QApplication::processEvents();
            const QImage unlockedPsgRuler = captureVelocityBand(rig.env.view);
            const qreal rulerScale = unlockedPsgRuler.devicePixelRatio();
            const int rulerHeight =
                qFloor(double(detentBounds.top() - areaOrigin.y()) * rulerScale);
            const QRect rulerBounds(0, 0, qCeil(double(rig.env.area.plotOrigin()) * rulerScale),
                                    rulerHeight);
            check(!directSoundRuler.isNull() && !unlockedPsgRuler.isNull() &&
                      layerRevision(rig.env, songview::TimelineQuickLayer::VelocityAxis) >
                          directAxisRevision &&
                      samePixels(directSoundRuler.copy(rulerBounds),
                                 unlockedPsgRuler.copy(rulerBounds)),
                  "disabled PSG detents must show the continuous sample-voice ruler");
            const int toggleUnlockedVelocity = 73;
            const QPointF toggleUnlockedRuler(
                double(rig.env.area.plotOrigin()) - 1.0,
                rig.env.area.axis().velocityToY(toggleUnlockedVelocity));
            velocityPress(rig.env, toggleUnlockedRuler, Qt::LeftButton, Qt::LeftButton,
                          Qt::NoModifier);
            velocityRelease(rig.env, toggleUnlockedRuler, Qt::LeftButton, Qt::NoModifier);
            DocNote toggleUnlockedFirst;
            DocNote toggleUnlockedThird;
            check(!rig.env.detentToggle->isChecked() &&
                      rig.env.document.findNote(rig.env.notes[0].noteId, &toggleUnlockedFirst) &&
                      rig.env.document.findNote(rig.env.notes[2].noteId, &toggleUnlockedThird) &&
                      toggleUnlockedFirst.velocity == toggleUnlockedVelocity &&
                      toggleUnlockedThird.velocity == toggleUnlockedVelocity &&
                      isOffDetent(toggleUnlockedVelocity),
                  "disabled velocity detents must write exact PSG velocities without a modifier");
            const QImage unlockedNodeImage = captureVelocityBand(rig.env.view);
            const QPointF unlockedNodeCenter(
                rig.paintGestureX(toggleUnlockedFirst),
                rig.env.area.axis().velocityToY(toggleUnlockedVelocity));
            check(!unlockedNodeImage.isNull() &&
                      velocityNodeHasColor(rig.env, unlockedNodeCenter, Qt::black),
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
        velocityPress(rig.env, lockedPaintStart, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        velocityMove(rig.env, lockedPaintEnd, Qt::LeftButton, Qt::NoModifier);
        velocityRelease(rig.env, lockedPaintEnd, Qt::LeftButton, Qt::NoModifier);
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
        velocityPress(rig.env, unlockedRuler, Qt::LeftButton, Qt::LeftButton,
                      detentUnlockModifiers);
        velocityRelease(rig.env, unlockedRuler, Qt::LeftButton, Qt::NoModifier);
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
        velocityPress(rig.env, unlockedPaintStart, Qt::LeftButton, Qt::LeftButton,
                      detentUnlockModifiers);
        velocityMove(rig.env, unlockedPaintEnd, Qt::LeftButton, Qt::NoModifier);
        const QImage unlockedPaintPreview = captureVelocityBand(rig.env.view);
        const QPointF unlockedPaintCenter(
            rig.paintGestureX(paintUnlockedFirst),
            rig.env.area.axis().velocityToY(unlockedPaintFirstVelocity));
        check(rig.env.document.revision() == revisionBeforeUnlockedPaint &&
                  !unlockedPaintPreview.isNull() &&
                  velocityNodeHasColor(rig.env, unlockedPaintCenter, Qt::black),
              "unlocked paint preview must remain at its continuous y position");
        velocityRelease(rig.env, unlockedPaintEnd, Qt::LeftButton, Qt::NoModifier);
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
        velocityPress(rig.env, lockedRelativeStart, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        velocityMove(rig.env, lockedRelativeEnd, Qt::LeftButton, detentUnlockModifiers);
        velocityRelease(rig.env, lockedRelativeEnd, Qt::LeftButton, Qt::NoModifier);
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
        velocityPress(rig.env, unlockedRelativeStart, Qt::LeftButton, Qt::LeftButton,
                      detentUnlockModifiers);
        velocityMove(rig.env, unlockedRelativeEnd, Qt::LeftButton, Qt::NoModifier);
        velocityRelease(rig.env, unlockedRelativeEnd, Qt::LeftButton, Qt::NoModifier);
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
            velocityPress(rig.env, unlockedRampStart, Qt::LeftButton, Qt::LeftButton,
                          unlockedRampModifiers);
            velocityMove(rig.env, unlockedRampEnd, Qt::LeftButton, Qt::NoModifier);
            check(rig.env.document.revision() == revisionBeforeUnlockedRamp,
                  "unlocked Shift-ramp must defer document changes");
            velocityRelease(rig.env, unlockedRampEnd, Qt::LeftButton, Qt::NoModifier);
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
    fixtureView.setDrawerSectionHeight(EditorDrawerPage::Velocity,
                                       expected.densityThresholdD4 +
                                           layout::space(layout::Space::Six));
    VelocityInputHost fixtureHost{fixtureView, *fixtureArea};
    fixtureHost.attach();
    fixtureArea->songChanged();
    DrawerPageLiveState fixtureLive;
    fixtureLive.documentRevision = fixtureDocument.revision();
    fixtureLive.timeZoom = 48.0;
    fixtureView.setEditorTimeZoom(fixtureLive.timeZoom);
    fixtureLive.timeZoom = fixtureView.pxPerBeat();
    fixtureLive.horizontalScroll = fixtureView.viewState().scrollPx;
    fixtureArea->refreshLiveState(fixtureLive);
    QApplication::processEvents();
    const qreal zoomAnchorContentX = std::max(1, fixtureArea->plotWidth() / 2);
    const QPointF zoomAnchor(fixtureArea->plotOrigin() + qRound(zoomAnchorContentX),
                             velocityBandRect(fixtureView).height() / 2.0);
    const double tickBeforeZoom = fixtureView.tickAtContentX(zoomAnchorContentX);
    const double zoomBefore = fixtureView.pxPerBeat();
    fixtureArea->wheel({zoomAnchor, fixtureHost.mapToGlobal(zoomAnchor), QPoint(), QPoint(0, 120),
                        Qt::NoModifier, Qt::NoScrollPhase, false});
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
        fixtureHost.detach();
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
    fixtureHost.detach();
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
    auto *quickView =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    check(quickView && quickScene,
          "concrete SongView should expose its retained Quick velocity renderer");
    if (!quickView || !quickScene)
        return 1;
    auto &area = *areaPtr;
    VelocityInputHost host{view, area};
    host.attach();
    DrawerPageLiveState live;
    VelocityAreaEnv env{document,       timeline,   voicegroup,    directSound,
                        square,         wave,       noise,         notes,
                        view,           area,       &host,         drawer,
                        drawerSections, velToggle,  automationBar, automationToggle,
                        nullptr,        quickScene, quickView,     live,
                        expected};
    VelocityAreaRig rig{env, VelocityMap::resolve(&noise, notes[0].key)};
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity,
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
    QApplication::processEvents();
    failures += checkDrawerToggleGeometry(env);
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
    failures += checkPointerUngrabCancelsProvisionalSelection(rig);
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
    host.requestFocus(Qt::OtherFocusReason);
    area.keyPress({Qt::Key_Up, Qt::ShiftModifier, QString(), false});
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
        check(captureVelocityBand(view).save(screenshotPath),
              "optional velocity screenshot should save");
    host.detach();
    return failures == 0 ? 0 : 1;
}
