#include "ui/editordrawer/automationpage.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <limits>
#include <vector>

#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPoint>
#include <QPointF>
#include <QQuickItem>
#include <QRect>
#include <QRectF>

extern "C" {
#include "voicegroup_loader.h"
}

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "core/timedefaults.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/cclanes.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/editordrawer/tempolane.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/editorselectionmodel.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

struct AutomationBandInput {
    AutomationPage &page;
    songview::TimelineInputItem &item;

    void mouse(QEvent::Type type, const QPointF &contentPosition, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers) const
    {
        checks::events::sendMouse(item, type, contentPosition - QPointF(0.0, page.verticalScroll()),
                                  button, buttons, modifiers);
    }

    void leave() const { mouse(QEvent::Leave, {}, Qt::NoButton, Qt::NoButton, Qt::NoModifier); }
};

struct LaneGeometry {
    LaneHandle handle;
    QRect body;
    QColor curveColor;
};

enum class LaneKind { Tempo, Cc };

struct LaneCase {
    LaneKind kind;
    const char *name;
};

constexpr LaneCase kLanes[] = {{LaneKind::Tempo, "Tempo"}, {LaneKind::Cc, "CC"}};
constexpr uint64_t kHeldTick = 0;
constexpr uint64_t kNodeTick = 96;
constexpr uint64_t kSecondTick = 144;
constexpr int kTempoHeld = 80;
constexpr int kTempoNode = 200;
constexpr int kTempoSecond = 160;
constexpr int kCcHeld = 24;
constexpr int kCcNode = 96;
constexpr int kCcSecond = 72;

songview::TimelineInputItem *automationInputItem(SongView &view, const QString &objectName)
{
    auto *quickCanvas =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    return quickCanvas && quickCanvas->rootObject()
               ? quickCanvas->rootObject()->findChild<songview::TimelineInputItem *>(objectName)
               : nullptr;
}

void pumpQuickEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

void refresh(AutomationPage &page, SongDocument &document, DrawerPageLiveState &live)
{
    live.documentRevision = document.revision();
    page.documentChanged();
    page.refreshLiveState(live);
    pumpQuickEvents();
}

void leaveCanvas(const AutomationBandInput &band)
{
    band.leave();
    pumpQuickEvents();
}

int panRowIndex(const AutomationPage &page)
{
    const auto &rows = page.canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id.controller == 10)
            return index;
    }
    return -1;
}

LaneGeometry laneGeometry(AutomationPage &page, LaneKind kind)
{
    LaneGeometry geometry;
    if (kind == LaneKind::Tempo) {
        geometry.handle = LaneHandle{0};
        geometry.curveColor = themes::color(themes::Role::song_view_automation_tempo_curve);
    } else {
        const int panRow = panRowIndex(page);
        if (panRow < 0)
            return geometry;
        geometry.handle = LaneHandle{panRow + 1};
        geometry.curveColor = themes::trackIdentityColor(0);
    }
    geometry.body = page.canvas()->laneBody(geometry.handle);
    return geometry;
}

QRect automationRowBody(const AutomationPage &page, const EditorAutomationRowId &id)
{
    const auto &rows = page.canvas()->rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id == id)
            return page.canvas()->laneBody(LaneHandle{index + 1});
    }
    return {};
}

QRectF bounds(const songview::TimelineQuickTriangle &triangle)
{
    const qreal left = std::min({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal right = std::max({triangle.first.x(), triangle.second.x(), triangle.third.x()});
    const qreal top = std::min({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    const qreal bottom = std::max({triangle.first.y(), triangle.second.y(), triangle.third.y()});
    return QRectF(QPointF(left, top), QPointF(right, bottom));
}

bool layerHasColorIn(const songview::TimelineQuickLayerData &layer, const QRectF &contentProbe,
                     const QPoint &contentOrigin, const QColor &color)
{
    const QRectF probe = contentProbe.translated(contentOrigin);
    for (const songview::TimelineQuickRect &rect : layer.rects) {
        if (rect.rect.intersects(probe) &&
            (rect.topLeft == color || rect.topRight == color || rect.bottomRight == color ||
             rect.bottomLeft == color)) {
            return true;
        }
    }
    for (const songview::TimelineQuickTriangle &triangle : layer.triangles) {
        if (bounds(triangle).intersects(probe) &&
            (triangle.firstColor == color || triangle.secondColor == color ||
             triangle.thirdColor == color)) {
            return true;
        }
    }
    return false;
}

QRectF nodeProbe(qreal x, qreal y, qreal radius)
{
    return {x - radius, y - radius, 2 * radius, 2 * radius};
}

QRectF lineProbe(qreal x, qreal y, qreal halfWidth, qreal halfHeight)
{
    return {x - halfWidth, y - halfHeight, 2 * halfWidth, 2 * halfHeight};
}

bool framebufferHasColorNear(const QImage &framebuffer, const QPointF &point,
                             const QColor &expected)
{
    if (framebuffer.isNull())
        return false;
    const qreal dpr = framebuffer.devicePixelRatio();
    if (dpr <= 0.0)
        return false;

    constexpr int kColorTolerance = 64;
    const int radius = qCeil(2 * dpr);
    const int centerX = qRound(point.x() * dpr);
    const int centerY = qRound(point.y() * dpr);
    for (int y = std::max(0, centerY - radius);
         y <= std::min(framebuffer.height() - 1, centerY + radius); ++y) {
        for (int x = std::max(0, centerX - radius);
             x <= std::min(framebuffer.width() - 1, centerX + radius); ++x) {
            const QColor pixel = framebuffer.pixelColor(x, y);
            if (pixel.alpha() >= 32 && std::abs(pixel.red() - expected.red()) <= kColorTolerance &&
                std::abs(pixel.green() - expected.green()) <= kColorTolerance &&
                std::abs(pixel.blue() - expected.blue()) <= kColorTolerance) {
                return true;
            }
        }
    }
    return false;
}

bool hasRenderedSelectionRing(const QImage &framebuffer, const QPoint &contentPoint,
                              const AutomationPage &page, int automationGutterWidth,
                              qreal ringRadius, qreal ringWidth, const QColor &selectionColor)
{
    if (framebuffer.isNull())
        return false;
    const qreal framebufferDpr = framebuffer.devicePixelRatio();
    if (framebufferDpr <= 0.0)
        return false;

    const QPointF center =
        QPointF(contentPoint) + QPointF(automationGutterWidth, -page.verticalScroll());
    const qreal tolerance = 2 * layout::singlePixel();
    const qreal inner = std::max<qreal>(0.0, ringRadius - ringWidth / 2.0 - tolerance);
    const qreal outer = ringRadius + ringWidth / 2.0 + tolerance;
    const qreal innerSquared = inner * inner;
    const qreal outerSquared = outer * outer;
    const int left = std::max(0, qFloor((center.x() - outer) * framebufferDpr));
    const int top = std::max(0, qFloor((center.y() - outer) * framebufferDpr));
    const int right =
        std::min(framebuffer.width() - 1, qCeil((center.x() + outer) * framebufferDpr));
    const int bottom =
        std::min(framebuffer.height() - 1, qCeil((center.y() + outer) * framebufferDpr));
    for (int y = top; y <= bottom; ++y) {
        for (int x = left; x <= right; ++x) {
            const QPointF delta((x + 0.5) / framebufferDpr - center.x(),
                                (y + 0.5) / framebufferDpr - center.y());
            const qreal distanceSquared = delta.x() * delta.x() + delta.y() * delta.y();
            const QColor pixel = framebuffer.pixelColor(x, y);
            if (distanceSquared >= innerSquared && distanceSquared <= outerSquared &&
                pixel.alpha() >= 32 && std::abs(pixel.red() - selectionColor.red()) <= 64 &&
                std::abs(pixel.green() - selectionColor.green()) <= 64 &&
                std::abs(pixel.blue() - selectionColor.blue()) <= 64) {
                return true;
            }
        }
    }
    return false;
}

int runPaintRaster(const QString &project, const QString &song)
{
    QString error;
    auto loadedSong = checks::LoadedSong::load(project, song, error);
    if (!loadedSong) {
        std::fprintf(stderr, "automation-raster: %s\n", qUtf8Printable(error));
        return 1;
    }

    SongDocument &document = loadedSong->document();
    if (document.engineTrackCount() == 0) {
        std::fprintf(stderr, "automation-raster: %s has no engine tracks\n", qUtf8Printable(song));
        return 1;
    }

    document.addLanePoint(0, 7, 24, 32);
    document.writeLanePoints(0, 21, 96, 96, {{96, 32}, {96, 96}});
    document.addLanePoint(0, LANE_CC_BEND, 72, 8191);
    document.addLanePoint(0, DOC_CC_VOICE, 24, 3);
    auto timeline = document.buildTimeline(48000.0);
    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[3].type = VOICE_NOISE;
    std::strncpy(voicegroup.voiceNames[3], "automation-voice",
                 sizeof(voicegroup.voiceNames[3]) - 1);

    SongView view;
    view.resize(960, 720);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    const EditorAutomationRowId volume{EditorAutomationRowKind::ControlChange, 0, 7};
    const EditorAutomationRowId pan{EditorAutomationRowKind::ControlChange, 0, 10};
    const EditorAutomationRowId lfo{EditorAutomationRowKind::ControlChange, 0, 21};
    EditorViewState state;
    state.hideLane(volume);
    state.emptyLanes.insert(pan);
    state.laneHeights[lfo] = layout::fontPx(4.0) + 5;
    state.laneRanges[lfo] = 91;
    view.applyEditorViewState(state);
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Automations, 360);
    view.show();
    pumpQuickEvents();

    auto *drawer = view.editorDrawer();
    auto *pagePtr = drawer ? drawer->automationPage() : nullptr;
    if (!pagePtr) {
        std::fprintf(stderr,
                     "automation-raster: concrete SongView did not expose AutomationPage\n");
        return 1;
    }
    AutomationPage &page = *pagePtr;
    page.songChanged();
    DrawerPageLiveState live;
    live.documentRevision = document.revision();
    live.timeZoom = 96.0;
    view.setEditorTimeZoom(live.timeZoom);
    live.horizontalScroll = view.camera().scrollX();
    view.setEditCursorTick(24);
    page.refreshLiveState(live);
    pumpQuickEvents();

    int failures = 0;
    const auto check = [&](bool condition, const QString &message) {
        if (condition)
            return;
        std::fprintf(stderr, "automation-raster: FAIL %s: %s\n", qUtf8Printable(song),
                     qUtf8Printable(message));
        ++failures;
    };
    const auto automationBandRect = [&] {
        const auto band = view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
        return band ? band->rect : QRect{};
    };
    const auto captureAutomationViewport = [&] {
        pumpQuickEvents();
        QString captureError;
        const QImage image =
            checks::support::captureQuickBand(view, automationBandRect(), &captureError);
        check(
            !image.isNull(),
            QStringLiteral("automation viewport framebuffer capture failed: %1").arg(captureError));
        return image;
    };

    auto *automationInput = automationInputItem(view, QStringLiteral("timelineAutomationInput"));
    auto *automationGutterInput =
        automationInputItem(view, QStringLiteral("timelineAutomationGutterInput"));
    auto *quickScene = view.findChild<songview::TimelineQuickScene *>();
    check(automationInput && automationGutterInput && quickScene,
          QStringLiteral("automation page did not expose its native raster dependencies"));
    if (!automationInput || !automationGutterInput || !quickScene)
        return 1;

    const AutomationBandInput band{page, *automationInput};
    const AutomationBandInput gutterBand{page, *automationGutterInput};
    const auto bandGeometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
    const int automationGutterWidth =
        bandGeometry ? std::max(0, bandGeometry->plotRect.x() - bandGeometry->rect.x()) : 0;
    const qreal dpr = automationInput->devicePixelRatio();

    // The row-resize boundary must clear both hover paths before its pixel baseline.
    page.cancelInteraction();
    band.leave();
    gutterBand.leave();
    QCoreApplication::processEvents();
    const QRect lfoBody = automationRowBody(page, lfo);
    const QPoint boundaryPoint(layout::space(layout::Space::One), lfoBody.top() + lfoBody.height());
    const QImage boundaryBaseline = captureAutomationViewport();
    gutterBand.mouse(QEvent::MouseMove, boundaryPoint, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::processEvents();
    const QImage boundaryHover = captureAutomationViewport();
    check(automationGutterInput->cursor().shape() == Qt::SplitVCursor,
          QStringLiteral("automation row boundary did not advertise its resize action"));
    check(!boundaryBaseline.isNull() && boundaryHover == boundaryBaseline,
          QStringLiteral("automation row boundary painted an insertion preview"));

    // Curves and nodes: retain the original Tempo/CC preparation, state clearing, and pixel probes.
    view.setEditCursorTick(480);
    live.timeZoom = 96.0;
    live.horizontalScroll = 0.0;
    view.setEditorTimeZoom(live.timeZoom);
    view.setEditorHorizontalScroll(live.horizontalScroll);
    view.selectionModel().clearTimeSelection();
    refresh(page, document, live);
    TempoLane tempoLane(document);
    CCLaneAdapter ccLane(document, 0, uint8_t{10});
    if (page.canvas()->laneBody(LaneHandle{0}).isEmpty()) {
        const QRect tempo = page.canvas()->pinnedTempoRect();
        const QPointF tempoHeaderPoint(layout::space(layout::Space::One), tempo.center().y());
        gutterBand.mouse(QEvent::MouseButtonPress, tempoHeaderPoint, Qt::LeftButton, Qt::LeftButton,
                         Qt::NoModifier);
        gutterBand.mouse(QEvent::MouseButtonRelease, tempoHeaderPoint, Qt::LeftButton, Qt::NoButton,
                         Qt::NoModifier);
        pumpQuickEvents();
    }
    const bool tempoExpanded = !page.canvas()->laneBody(LaneHandle{0}).isEmpty();
    check(tempoExpanded, QStringLiteral("Tempo header did not expose the expanded body"));
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const qreal radius = nodelane::hoverRingRadius(geometry);
    const qreal lineHalf =
        std::max(qreal(layout::singlePixel()), qreal(geometry.hoverPaintPadding + 1));
    const QPoint plotContentOrigin(0, -page.verticalScroll());
    const QPoint plotFramebufferOrigin = plotContentOrigin + QPoint(automationGutterWidth, 0);
    const auto tickX = [&](uint64_t tick) {
        return view.camera().displayX(double(tick), 0.0, dpr);
    };
    const auto layerRevision = [&](songview::TimelineQuickLayer layer) {
        return quickScene->layer(layer).revision;
    };
    const auto layerHas = [&](songview::TimelineQuickLayer layer, const QRectF &contentProbe,
                              const QColor &color) {
        return layerHasColorIn(quickScene->layer(layer), contentProbe, plotContentOrigin, color);
    };

    for (const LaneCase &row : kLanes) {
        const quint64 curvesRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationCurves);
        const quint64 nodesRevision = layerRevision(songview::TimelineQuickLayer::AutomationNodes);
        NodeLane &lane = row.kind == LaneKind::Tempo ? static_cast<NodeLane &>(tempoLane)
                                                     : static_cast<NodeLane &>(ccLane);
        if (row.kind == LaneKind::Tempo) {
            TempoEdit edit;
            edit.remove = document.tempoPoints();
            edit.add = {
                {kHeldTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoHeld)},
                {kNodeTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoNode)},
                {kSecondTick, CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(kTempoSecond)}};
            document.applyTempoEdit(edit);
        } else {
            document.writeLanePoints(
                0, uint8_t{10}, 0, std::numeric_limits<uint64_t>::max(),
                {{kHeldTick, kCcHeld}, {kNodeTick, kCcNode}, {kSecondTick, kCcSecond}});
        }
        refresh(page, document, live);
        const LaneGeometry geom = laneGeometry(page, row.kind);
        if (!geom.handle.valid() || geom.body.isEmpty()) {
            check(false, QStringLiteral("%1: lane body is missing from the canvas stack")
                             .arg(QLatin1String(row.name)));
            continue;
        }
        const int held = row.kind == LaneKind::Tempo ? kTempoHeld : kCcHeld;
        const int node = row.kind == LaneKind::Tempo ? kTempoNode : kCcNode;
        const qreal heldY = nodelane::valueY(lane, geom.body, geometry, held);
        const qreal nodeY = nodelane::valueY(lane, geom.body, geometry, node);
        const qreal nodeX = tickX(kNodeTick);
        const qreal midX = tickX(48);
        leaveCanvas(band);
        check(layerRevision(songview::TimelineQuickLayer::AutomationCurves) > curvesRevision &&
                  layerRevision(songview::TimelineQuickLayer::AutomationNodes) > nodesRevision,
              QStringLiteral("%1: document refresh did not rebuild the Quick curves and nodes")
                  .arg(QLatin1String(row.name)));
        check(layerHas(songview::TimelineQuickLayer::AutomationCurves,
                       lineProbe(midX, heldY, 8, lineHalf), geom.curveColor),
              QStringLiteral("%1: normal step curve is missing from the retained Quick layer")
                  .arg(QLatin1String(row.name)));
        check(layerHas(songview::TimelineQuickLayer::AutomationNodes,
                       nodeProbe(nodeX, nodeY, radius), geom.curveColor),
              QStringLiteral("%1: normal node is missing from the retained Quick layer")
                  .arg(QLatin1String(row.name)));
        const QImage normalFramebuffer = captureAutomationViewport();
        check(framebufferHasColorNear(normalFramebuffer,
                                      QPointF(plotFramebufferOrigin) + QPointF(midX, heldY),
                                      geom.curveColor) &&
                  framebufferHasColorNear(normalFramebuffer,
                                          QPointF(plotFramebufferOrigin) + QPointF(nodeX, nodeY),
                                          geom.curveColor),
              QStringLiteral("%1: normal step curve or node did not render at its Quick position")
                  .arg(QLatin1String(row.name)));

        const quint64 selectionRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationSelection);
        const quint64 selectedNodesRevision =
            layerRevision(songview::TimelineQuickLayer::AutomationNodes);
        songview::EditorSelectionModel::TimeSelection selection;
        selection.startTick = kNodeTick;
        selection.endTick = kNodeTick + 1;
        selection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
        if (row.kind == LaneKind::Tempo)
            selection.tempo = true;
        else
            selection.lanes = {{0, 10}};
        view.selectionModel().setTimeSelection(selection);
        refresh(page, document, live);
        leaveCanvas(band);
        const qreal ringOuter = geometry.selectedNodeRingRadius + layout::singlePixel();
        check(layerHas(songview::TimelineQuickLayer::AutomationNodes,
                       nodeProbe(nodeX, nodeY, ringOuter), band.item.palette().highlight().color()),
              QStringLiteral("%1: selected ring is missing from the retained Quick node layer")
                  .arg(QLatin1String(row.name)));
        const QImage selectedFramebuffer = captureAutomationViewport();
        check(framebufferHasColorNear(selectedFramebuffer,
                                      QPointF(plotFramebufferOrigin) +
                                          QPointF(nodeX, nodeY - geometry.selectedNodeRingRadius),
                                      band.item.palette().highlight().color()),
              QStringLiteral("%1: selected ring did not render at its Quick node position")
                  .arg(QLatin1String(row.name)));
        check(layerRevision(songview::TimelineQuickLayer::AutomationSelection) >
                      selectionRevision &&
                  layerRevision(songview::TimelineQuickLayer::AutomationNodes) >
                      selectedNodesRevision,
              QStringLiteral("%1: selected-node change did not rebuild the retained Quick layers")
                  .arg(QLatin1String(row.name)));
        view.selectionModel().clearTimeSelection();
        refresh(page, document, live);
    }

    // Half-open time selection: preserve layer guards and the legacy framebuffer ring probes.
    page.cancelInteraction();
    live.timeZoom = 96.0;
    view.setEditorTimeZoom(live.timeZoom);
    live.horizontalScroll = 0.0;
    view.setEditorHorizontalScroll(live.horizontalScroll);
    const uint64_t groupA = view.grid().snapTick(48.0, false);
    const uint64_t groupB = view.grid().snapTick(72.0, false);
    const uint64_t groupC = view.grid().snapTick(120.0, false);
    constexpr int groupAValue = 40;
    constexpr int groupBValue = 80;
    constexpr int groupCValue = 55;
    document.writeLanePoints(0, pan.controller, 0, timeline->lengthTicks,
                             {{groupA, groupAValue}, {groupB, groupBValue}, {groupC, groupCValue}});
    page.documentChanged();
    live.documentRevision = document.revision();
    page.refreshLiveState(live);
    QCoreApplication::processEvents();
    const QRect groupPanBody = automationRowBody(page, pan);
    const int valuePlotPadding =
        qRound(std::max(layout::fontPxF(7.0 / 24.0) * 0.75 + layout::fontPxF(1.0 / 12.0),
                        layout::fontPxF(3.0 / 8.0) * 0.75 + layout::fontPxF(1.0 / 6.0) * 0.5));
    const int groupPlotTop = groupPanBody.top() + valuePlotPadding;
    const int groupPlotBottom = groupPanBody.bottom() + 1 - valuePlotPadding;
    const auto groupPointAt = [&](uint64_t tick, int value) {
        return QPoint(qRound(view.camera().displayX(double(tick), 0.0, dpr)),
                      groupPlotBottom - value * (groupPlotBottom - groupPlotTop) / 127);
    };
    const QPoint groupAPoint = groupPointAt(groupA, groupAValue);
    const QPoint groupBPoint = groupPointAt(groupB, groupBValue);
    const QPoint groupCPoint = groupPointAt(groupC, groupCValue);
    const auto setTrackRange = [&](uint64_t endTick) {
        songview::EditorSelectionModel::TimeSelection selection;
        selection.startTick = groupA;
        selection.endTick = endTick;
        view.selectionModel().setTimeSelection(selection);
        live.horizontalScroll = 0.0;
        view.setEditorHorizontalScroll(live.horizontalScroll);
        page.refreshLiveState(live);
        pumpQuickEvents();
    };
    const quint64 nodesRevisionBefore =
        layerRevision(songview::TimelineQuickLayer::AutomationNodes);
    setTrackRange(groupB);
    const songview::TimelineQuickLayerData excludedNodes =
        quickScene->layer(songview::TimelineQuickLayer::AutomationNodes);
    const QImage excludedNodesFramebuffer = captureAutomationViewport();
    setTrackRange(groupB + 1);
    const songview::TimelineQuickLayerData includedNodes =
        quickScene->layer(songview::TimelineQuickLayer::AutomationNodes);
    const QImage includedNodesFramebuffer = captureAutomationViewport();
    const QColor selectionColor = automationInput->palette().highlight().color();
    const qreal ringRadius = geometry.selectedNodeRingRadius;
    const qreal ringWidth = geometry.selectedNodeRingDipWidth;
    const auto hasSelectionRing = [&](const songview::TimelineQuickLayerData &layer,
                                      const QPoint &contentPoint) {
        const QPointF center = QPointF(contentPoint) - QPointF(0.0, page.verticalScroll());
        const qreal tolerance = layout::singlePixel();
        const qreal inner = std::max<qreal>(0.0, ringRadius - ringWidth / 2.0 - tolerance);
        const qreal outer = ringRadius + ringWidth / 2.0 + tolerance;
        const qreal innerSquared = inner * inner;
        const qreal outerSquared = outer * outer;
        return std::count_if(layer.triangles.cbegin(), layer.triangles.cend(),
                             [&](const songview::TimelineQuickTriangle &triangle) {
                                 const auto onRing = [&](const QPointF &point) {
                                     const QPointF delta = point - center;
                                     const qreal distanceSquared =
                                         delta.x() * delta.x() + delta.y() * delta.y();
                                     return distanceSquared >= innerSquared &&
                                            distanceSquared <= outerSquared;
                                 };
                                 return triangle.firstColor == selectionColor &&
                                        triangle.secondColor == selectionColor &&
                                        triangle.thirdColor == selectionColor &&
                                        onRing(triangle.first) && onRing(triangle.second) &&
                                        onRing(triangle.third);
                             }) >= 4;
    };
    check(excludedNodes.revision > nodesRevisionBefore &&
              includedNodes.revision > excludedNodes.revision &&
              hasSelectionRing(excludedNodes, groupAPoint) &&
              !hasSelectionRing(excludedNodes, groupBPoint) &&
              !hasSelectionRing(excludedNodes, groupCPoint) &&
              hasSelectionRing(includedNodes, groupAPoint) &&
              hasSelectionRing(includedNodes, groupBPoint) &&
              !hasSelectionRing(includedNodes, groupCPoint) &&
              hasRenderedSelectionRing(excludedNodesFramebuffer, groupAPoint, page,
                                       automationGutterWidth, ringRadius, ringWidth,
                                       selectionColor) &&
              hasRenderedSelectionRing(includedNodesFramebuffer, groupAPoint, page,
                                       automationGutterWidth, ringRadius, ringWidth,
                                       selectionColor) &&
              hasRenderedSelectionRing(includedNodesFramebuffer, groupBPoint, page,
                                       automationGutterWidth, ringRadius, ringWidth,
                                       selectionColor),
          QStringLiteral("track time selection did not retain or render half-open Quick node rings "
                         "in the automation nodes layer"));

    if (failures == 0)
        std::printf("automation-raster: PASS %s\n", qUtf8Printable(song));
    return failures == 0 ? 0 : 1;
}

} // namespace

int runAutomationPaintRasterCheck(const QString &project, const QString &song)
{
    return runPaintRaster(project, song);
}
