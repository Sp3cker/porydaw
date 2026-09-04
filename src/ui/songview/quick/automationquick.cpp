#include "ui/editordrawer/automationcanvas.h"

#include <QPalette>

#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/songview/quick/automationnodelanequick.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace songview {
namespace {

using timeline_quick::addClippedTriangle;
using timeline_quick::addHorizontalLine;
using timeline_quick::addRect;
using timeline_quick::addSelectionReticle;
using timeline_quick::composeBandedGrid;
using timeline_quick::resetLayer;

QRect translatedToViewport(const QRect &content, int verticalScroll)
{
    return content.translated(0, -verticalScroll);
}

QRectF rectF(const QRect &rect)
{
    return QRectF(rect.x(), rect.y(), rect.width(), rect.height());
}

void appendText(std::vector<TimelineQuickTextModel::Record> &records, TimelineQuickTextKeyKind kind,
                quint64 ordinal, const QRectF &rect, const QString &text, const QColor &color,
                const QFont &font, Qt::Alignment horizontal = Qt::AlignLeft, QRectF clip = {})
{
    if ((!clip.isNull() && !rect.intersects(clip)) || rect.width() <= 0.0 || rect.height() <= 0.0 ||
        text.isEmpty())
        return;
    records.push_back(
        {{kind, {}, ordinal}, rect, text, color, font, horizontal, Qt::AlignVCenter, clip});
}

void appendText(std::vector<TimelineQuickTextModel::Record> &records, TimelineQuickTextKeyKind kind,
                quint64 ordinal, const QRect &rect, const QString &text, const QColor &color,
                const QFont &font, Qt::Alignment horizontal = Qt::AlignLeft, QRectF clip = {})
{
    appendText(records, kind, ordinal, rectF(rect), text, color, font, horizontal, clip);
}

void addHeaderChrome(TimelineQuickScene &scene, const QRectF &band, const QRectF &textClip,
                     const std::optional<QRect> &arrow, bool expanded, bool separator,
                     const QRectF &viewport)
{
    constexpr TimelineQuickLayer chromeLayer = TimelineQuickLayer::AutomationGutterChrome;
    if (separator) {
        addHorizontalLine(scene, chromeLayer, band.left(), band.right(), band.bottom(),
                          layout::singlePixel(), themes::color(themes::Role::song_view_separator),
                          viewport);
    }
    if (!arrow)
        return;
    const QRect &bounds = *arrow;
    const QColor color = themes::color(themes::Role::song_view_primary_text);
    if (expanded) {
        addClippedTriangle(scene, chromeLayer, QPointF(bounds.left(), bounds.top()),
                           QPointF(bounds.right(), bounds.top()),
                           QPointF(bounds.center().x(), bounds.bottom()), color, textClip);
    } else {
        addClippedTriangle(scene, chromeLayer, QPointF(bounds.left(), bounds.top()),
                           QPointF(bounds.right(), bounds.center().y()),
                           QPointF(bounds.left(), bounds.bottom()), color, textClip);
    }
}

} // namespace
} // namespace songview

void AutomationCanvas::rebuildQuickScene(songview::TimelineQuickScene &scene,
                                         songview::AutomationRefreshSet refresh)
{
    using namespace songview;
    const bool content = refresh.testFlag(AutomationRefresh::Content);
    const bool transient = refresh.testFlag(AutomationRefresh::Transient);
    const bool hover = refresh.testFlag(AutomationRefresh::Hover);
    if (content) {
        resetLayer(scene, TimelineQuickLayer::AutomationGutterChrome);
        resetLayer(scene, TimelineQuickLayer::AutomationGrid);
        resetLayer(scene, TimelineQuickLayer::AutomationCurves);
        resetLayer(scene, TimelineQuickLayer::AutomationNodes);
        resetLayer(scene, TimelineQuickLayer::AutomationSelection);
        scene.setAutomationTextRecords({});
    }
    if (transient) {
        resetLayer(scene, TimelineQuickLayer::AutomationTransient);
        scene.setAutomationTransientTextRecords({});
    }
    if (hover) {
        resetLayer(scene, TimelineQuickLayer::AutomationHover);
        scene.setAutomationHoverTextRecords({});
    }
    if (!m_inputHost || !m_page.document())
        return;

    const QRectF viewport = m_inputHost->bounds();
    if (viewport.height() <= 0.0)
        return;
    const auto &bandGeometry =
        m_page.m_owner.timelineBandLayout().geometry(TimelineBand::Automation);
    const QRect gutter = bandGeometry ? bandGeometry->gutterRect() : QRect{};
    const QRectF gutterViewport(0.0, 0.0, gutter.width(), gutter.height());
    const int gutterMargin = layout::space(layout::Space::One);
    const QRect labelGutter(gutterMargin, 0, std::max(0, gutter.width() - 2 * gutterMargin), 0);
    const auto gutterClipFor = [&gutterViewport](const QRect &band) {
        return QRectF(0.0, band.top(), gutterViewport.width(), band.height())
            .intersected(gutterViewport);
    };
    const int verticalScroll = m_page.verticalScroll();
    const qreal dpr = m_inputHost->devicePixelRatio();
    const AutomationProjection projection = this->projection();
    const auto selectedTickRange = [this]() -> std::optional<std::pair<uint64_t, uint64_t>> {
        if (m_band.active) {
            const uint64_t first = std::min(m_band.startTick, m_band.endTick);
            const uint64_t last = std::max(m_band.startTick, m_band.endTick);
            if (first != last)
                return std::pair{first, last};
            return std::nullopt;
        }
        return m_laneSelection.activeTickRange();
    }();
    const uint64_t bandFirst = std::min(m_band.startTick, m_band.endTick);
    const uint64_t bandLast = std::max(m_band.startTick, m_band.endTick);
    const NodeDragGesture *nodeDrag = nullptr;
    const PhantomGesture *phantomGesture = nullptr;
    const SweepGesture *sweep = nullptr;
    const PencilGesture *pencil = nullptr;
    if (m_activeGesture) {
        nodeDrag = std::get_if<NodeDragGesture>(&*m_activeGesture);
        phantomGesture = std::get_if<PhantomGesture>(&*m_activeGesture);
        sweep = std::get_if<SweepGesture>(&*m_activeGesture);
        pencil = std::get_if<PencilGesture>(&*m_activeGesture);
    }

    struct VisibleLane {
        LaneHandle handle;
        const NodeLaneSlot *slot = nullptr;
        QRect band;
        QRect body;
        QRectF clip;
        QRectF plot;
        QRectF overflow;
        bool tempo = false;
        bool selectedLane = false;
        bool selectedNodesLane = false;
        bool bandLane = false;
        bool needsPoints = false;
        std::vector<NodePoint> points;
    };

    const NodeLaneSlot *tempoSlot = nullptr;
    LaneHandle tempoHandle;
    for (int index = 0; index < int(m_nodeStack.size()); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[std::size_t(index)];
        if (!slot.lane || !slot.isTempo())
            continue;
        tempoSlot = &slot;
        tempoHandle = LaneHandle{index};
        break;
    }
    const bool tempoExpanded = m_tempoLane.expanded();
    const QRect tempoBandContent =
        tempoExpanded ? m_tempoLane.bodyRect() : m_tempoLane.headerRect();
    const QRect tempoBand = translatedToViewport(tempoBandContent, verticalScroll);
    const QRectF tempoClip = rectF(tempoBand).intersected(viewport);
    QRectF scrollableViewport = viewport;
    if (!tempoClip.isEmpty())
        scrollableViewport.setBottom(std::min(scrollableViewport.bottom(), tempoClip.top()));
    const auto localPlotFor = [&viewport](const QRect &body, const QRectF &clip) {
        return QRectF(0.0, body.top(), viewport.width(), body.height()).intersected(clip);
    };
    const auto localOverflowFor = [this, &viewport](const QRect &body, const QRectF &clip) {
        const QRect plot(0, body.top(), std::max(0, int(viewport.width())), body.height());
        return nodelane::nodeOverflowClip(plot, m_geometry).intersected(clip);
    };

    std::vector<VisibleLane> lanes;
    lanes.reserve(m_nodeStack.size() < 2 ? 2 : std::min<std::size_t>(m_nodeStack.size(), 8));
    for (int index = 0; index < int(m_nodeStack.size()); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[std::size_t(index)];
        if (!slot.lane || slot.isTempo())
            continue;
        const QRect body = translatedToViewport(slot.body, verticalScroll);
        const QRectF clip = rectF(body).intersected(scrollableViewport);
        if (clip.isEmpty())
            continue;
        const LaneHandle handle{index};
        const bool bandLane = bandPreviewContainsLane(handle);
        const bool selectedNodesLane = m_laneSelection.coversNodes(slot.id) || bandLane;
        const bool needsTransientPoints =
            transient && (m_band.active ||
                          (nodeDrag && nodeDrag->points.size() == 1 && nodeDrag->lane == handle) ||
                          (phantomGesture && phantomGesture->lane == handle) ||
                          (pencil && pencil->lane == handle));
        const bool needsHoverPoints = hover && m_hoverState.hover.lane == handle;
        lanes.push_back({.handle = handle,
                         .slot = &slot,
                         .band = body,
                         .body = body,
                         .clip = clip,
                         .plot = localPlotFor(body, clip),
                         .overflow = localOverflowFor(body, clip),
                         .tempo = false,
                         .selectedLane = m_laneSelection.coversLane(slot.id) || bandLane,
                         .selectedNodesLane = selectedNodesLane,
                         .bandLane = bandLane,
                         .needsPoints = content || needsTransientPoints || needsHoverPoints});
    }
    if (tempoSlot && !tempoClip.isEmpty()) {
        const QRect tempoBody = translatedToViewport(tempoSlot->body, verticalScroll);
        const LaneHandle handle = tempoHandle;
        const bool bandLane = bandPreviewContainsLane(handle);
        const bool selectedNodesLane = m_laneSelection.coversNodes(tempoSlot->id) || bandLane;
        const bool needsTransientPoints =
            transient && (m_band.active ||
                          (nodeDrag && nodeDrag->points.size() == 1 && nodeDrag->lane == handle) ||
                          (phantomGesture && phantomGesture->lane == handle) ||
                          (pencil && pencil->lane == handle));
        const bool needsHoverPoints = hover && m_hoverState.hover.lane == handle;
        lanes.push_back(
            {.handle = handle,
             .slot = tempoSlot,
             .band = tempoBand,
             .body = tempoBody,
             .clip = tempoClip,
             .plot = tempoExpanded ? localPlotFor(tempoBody, tempoClip) : QRectF{},
             .overflow = tempoExpanded ? localOverflowFor(tempoBody, tempoClip) : QRectF{},
             .tempo = true,
             .selectedLane = m_laneSelection.coversLane(tempoSlot->id) || bandLane,
             .selectedNodesLane = selectedNodesLane,
             .bandLane = bandLane,
             .needsPoints =
                 tempoExpanded && (content || needsTransientPoints || needsHoverPoints)});
    }

    for (VisibleLane &lane : lanes) {
        if (lane.needsPoints)
            lane.points = lane.slot->lane->points();
    }
    const bool multipleSelectedNodes = hasMultipleSelectedNodes(selectedTickRange);

    std::vector<TimelineQuickTextModel::Record> mainText;
    std::vector<TimelineQuickTextModel::Record> hoverTextRecords;
    std::vector<TimelineQuickTextModel::Record> transientTextRecords;
    if (content)
        mainText.reserve(2 * lanes.size() + 1);
    if (hover)
        hoverTextRecords.reserve(1);
    if (transient)
        transientTextRecords.reserve(1);
    // Gutter records use gutter-local label bounds; plot value labels retain
    // their pre-clip rectangles so clipping does not move centered glyphs.
    const NodeLaneQuickPaint::Outputs outputs;
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);
    const QColor primaryText = themes::color(themes::Role::song_view_primary_text);
    const QColor secondaryText = themes::color(themes::Role::song_view_secondary_text);
    if (content) {
        addRect(scene, TimelineQuickLayer::AutomationGrid, viewport, background, viewport);
        addRect(scene, TimelineQuickLayer::AutomationGutterChrome, gutterViewport, background,
                gutterViewport);
    }

    for (const VisibleLane &lane : lanes) {
        const QRectF gutterBand = gutterClipFor(lane.band);
        if (!lane.tempo && content) {
            composeBandedGrid(scene, TimelineQuickLayer::AutomationGrid, m_page.m_owner, lane.plot,
                              0.0, dpr);
            addHeaderChrome(scene, gutterBand, gutterBand, std::nullopt, true, true, gutterBand);
        }
        if (!lane.tempo && content && lane.slot->text) {
            CCLanes::RowTextCache &rowText = *lane.slot->text;
            const QRect textBounds(labelGutter.x(), lane.body.top(), labelGutter.width(),
                                   lane.body.height());
            const auto textBoxes =
                m_laneTextLayout.align(textBounds, layout::VerticalAlignment::Center);
            const QString &summary = refreshCcSummaryText(rowText, lane.points, *lane.slot->lane);
            appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                       quint64(2 * lane.handle.index), textBoxes.primary, rowText.title,
                       primaryText, m_laneTitleFont, Qt::AlignLeft, gutterBand);
            appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                       quint64(2 * lane.handle.index + 1), textBoxes.secondary, summary,
                       secondaryText, m_laneCaptionFont, Qt::AlignLeft, gutterBand);
        }
    }

    for (const VisibleLane &lane : lanes) {
        if (!lane.tempo)
            continue;
        const QRectF gutterBand = gutterClipFor(lane.band);
        if (content) {
            addRect(scene, TimelineQuickLayer::AutomationGutterChrome, gutterBand, background,
                    gutterBand);
            addHeaderChrome(
                scene, gutterBand, gutterBand,
                [&] {
                    const QRect strip(0, lane.band.top(), gutter.width(),
                                      m_geometry.addLaneStripHeight);
                    const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
                    return std::optional<QRect>{QRect(labelGutter.left(),
                                                      strip.center().y() - arrowSize / 2, arrowSize,
                                                      arrowSize)};
                }(),
                tempoExpanded, false, gutterBand);
            if (tempoExpanded) {
                composeBandedGrid(scene, TimelineQuickLayer::AutomationGrid, m_page.m_owner,
                                  lane.plot, 0.0, dpr);
            }
        }
        if (content) {
            const QRect strip(0, lane.band.top(), gutter.width(), m_geometry.addLaneStripHeight);
            const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
            const QRect primary(
                labelGutter.x() + arrowSize + layout::space(layout::Space::One), strip.top(),
                std::max(0, labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
                strip.height());
            const QRect secondary(primary.x(), strip.top() + strip.height(), primary.width(),
                                  strip.height());
            appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                       quint64(2 * lane.handle.index), primary, tr("Tempo (BPM)"), primaryText,
                       tempoExpanded ? m_laneTitleFont : m_laneCaptionFont, Qt::AlignLeft,
                       gutterBand);
            if (tempoExpanded) {
                appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                           quint64(2 * lane.handle.index + 1), secondary,
                           tr("%n point(s)", nullptr, int(lane.points.size())), secondaryText,
                           m_laneCaptionFont, Qt::AlignLeft, gutterBand);
            }
        }
    }
    for (const VisibleLane &lane : lanes) {
        if (!lane.tempo || tempoExpanded || !lane.selectedLane || !selectedTickRange)
            continue;
        const auto [firstTick, lastTick] = *selectedTickRange;
        const QRectF bounds(0.0, lane.band.top(), viewport.width(), lane.band.height());
        const QRectF reticle(projection.displayX(firstTick, dpr), bounds.top(),
                             projection.displayX(lastTick, dpr) -
                                 projection.displayX(firstTick, dpr),
                             bounds.height());
        if (content && !m_band.active) {
            addSelectionReticle(scene, TimelineQuickLayer::AutomationSelection, reticle, lane.clip);
        } else if (transient && m_band.active) {
            addSelectionReticle(scene, TimelineQuickLayer::AutomationTransient, reticle, lane.clip);
        }
    }

    if (content) {
        const QRect strip(0, addLaneStripTop() - verticalScroll, gutter.width(),
                          m_geometry.addLaneStripHeight);
        const QRectF stripClip = rectF(strip).intersected(gutterViewport);
        if (!stripClip.isEmpty()) {
            addRect(scene, TimelineQuickLayer::AutomationGutterChrome, rectF(strip), background,
                    stripClip);
            addHeaderChrome(scene, rectF(strip), stripClip, std::nullopt, true, true, stripClip);
        }
    }
    if (content) {
        const QRect strip(0, addLaneStripTop() - verticalScroll, gutter.width(),
                          m_geometry.addLaneStripHeight);
        const QRectF stripClip = rectF(strip).intersected(gutterViewport);
        if (!stripClip.isEmpty()) {
            appendText(mainText, TimelineQuickTextKeyKind::AutomationAddLane, 0,
                       QRect(labelGutter.x(), strip.top(), labelGutter.width(), strip.height()),
                       tr("Add automation lane"),
                       themes::color(themes::Role::song_view_add_automation_lane_action),
                       m_laneCaptionFont, Qt::AlignLeft, stripClip);
        }
    }

    for (const VisibleLane &lane : lanes) {
        if (!lane.tempo || !tempoExpanded)
            continue;
        const QColor color = themes::color(themes::Role::song_view_automation_tempo_curve);
        std::optional<OriginPhantom> phantom;
        if (phantomGesture && phantomGesture->lane == lane.handle) {
            phantom = OriginPhantom{lane.handle, phantomGesture->point.current,
                                    phantomGesture->point.minimumValue,
                                    phantomGesture->point.maximumValue};
        } else if (lane.needsPoints) {
            phantom = originPhantom(lane.handle, projection, lane.points);
        }
        NodeLaneQuickPaint::Context context{
            .scene = scene,
            .lane = *lane.slot->lane,
            .points = lane.points,
            .body = tempoExpanded ? lane.body : lane.band,
            .plot = tempoExpanded
                        ? lane.plot
                        : QRectF(0.0, lane.band.top(), viewport.width(), lane.band.height())
                              .intersected(lane.clip),
            .contentYOffset = static_cast<qreal>(verticalScroll),
            .overflow = tempoExpanded ? lane.overflow : lane.clip,
            .geometry = m_geometry,
            .projection = projection,
            .hoverState = m_hoverState,
            .handle = lane.handle,
            .color = color,
            .selectedColor = m_inputHost->palette().highlight().color(),
            .dimmedColor = m_inputHost->palette().mid().color(),
            .devicePixelRatio = dpr,
            .selectedTickRange = selectedTickRange,
            .selectedLane = lane.selectedLane,
            .selectedNodesLane = lane.selectedNodesLane,
            .bandLane = lane.bandLane,
            .bandFirstTick = bandFirst,
            .bandLastTick = bandLast,
            .multipleSelectedNodes = multipleSelectedNodes,
            .pencilMode = m_pencilMode,
            .nodeDrag = nodeDrag,
            .phantomGesture = phantomGesture,
            .sweep = sweep,
            .pencil = pencil,
            .phantom = phantom,
        };
        NodeLaneQuickPaint::Context staticContext = context;
        if (m_band.active) {
            staticContext.selectedTickRange = std::nullopt;
            staticContext.selectedLane = false;
            staticContext.selectedNodesLane = false;
            staticContext.bandLane = false;
            staticContext.multipleSelectedNodes = false;
        }
        NodeLaneQuickPaint::composeStatic(staticContext, content, content,
                                          content && !m_band.active);
        NodeLaneQuickPaint::composeTransient(context, transient, m_band.active, outputs);
        NodeLaneQuickPaint::composeHover(context, hover, outputs);
    }
    for (const VisibleLane &lane : lanes) {
        if (lane.tempo)
            continue;
        const QColor color =
            themes::trackIdentityColor(lane.slot->id.track % themes::trackIdentityColorCount);
        std::optional<OriginPhantom> phantom;
        if (phantomGesture && phantomGesture->lane == lane.handle) {
            phantom = OriginPhantom{lane.handle, phantomGesture->point.current,
                                    phantomGesture->point.minimumValue,
                                    phantomGesture->point.maximumValue};
        } else if (lane.needsPoints) {
            phantom = originPhantom(lane.handle, projection, lane.points);
        }
        NodeLaneQuickPaint::Context context{
            .scene = scene,
            .lane = *lane.slot->lane,
            .points = lane.points,
            .body = lane.body,
            .plot = lane.plot,
            .contentYOffset = static_cast<qreal>(verticalScroll),
            .overflow = lane.overflow,
            .geometry = m_geometry,
            .projection = projection,
            .hoverState = m_hoverState,
            .handle = lane.handle,
            .color = color,
            .selectedColor = m_inputHost->palette().highlight().color(),
            .dimmedColor = m_inputHost->palette().mid().color(),
            .devicePixelRatio = dpr,
            .selectedTickRange = selectedTickRange,
            .selectedLane = lane.selectedLane,
            .selectedNodesLane = lane.selectedNodesLane,
            .bandLane = lane.bandLane,
            .bandFirstTick = bandFirst,
            .bandLastTick = bandLast,
            .multipleSelectedNodes = multipleSelectedNodes,
            .pencilMode = m_pencilMode,
            .nodeDrag = nodeDrag,
            .phantomGesture = phantomGesture,
            .sweep = sweep,
            .pencil = pencil,
            .phantom = phantom,
        };
        NodeLaneQuickPaint::Context staticContext = context;
        if (m_band.active) {
            staticContext.selectedTickRange = std::nullopt;
            staticContext.selectedLane = false;
            staticContext.selectedNodesLane = false;
            staticContext.bandLane = false;
            staticContext.multipleSelectedNodes = false;
        }
        NodeLaneQuickPaint::composeStatic(staticContext, content, content,
                                          content && !m_band.active);
        NodeLaneQuickPaint::composeTransient(context, transient, m_band.active, outputs);
        NodeLaneQuickPaint::composeHover(context, hover, outputs);
    }
    const auto appendValueLabel = [&lanes, verticalScroll](
                                      std::vector<TimelineQuickTextModel::Record> &records,
                                      TimelineQuickTextKeyKind kind,
                                      const NodeLaneHoverState::ValueLabelCache &label) {
        if (!label.valid || label.text.isEmpty())
            return;
        const auto lane =
            std::find_if(lanes.cbegin(), lanes.cend(),
                         [&label](const VisibleLane &item) { return item.handle == label.lane; });
        if (lane == lanes.cend())
            return;
        appendText(records, kind, quint64(label.lane.index),
                   QRectF(label.rect).translated(0.0, -verticalScroll), label.text,
                   themes::color(themes::Role::song_view_primary_text), label.font,
                   Qt::AlignHCenter, lane->overflow);
    };
    if (hover)
        appendValueLabel(hoverTextRecords, TimelineQuickTextKeyKind::AutomationHover,
                         m_hoverState.hoverValueLabel);
    if (transient && m_activeGesture)
        appendValueLabel(transientTextRecords, TimelineQuickTextKeyKind::AutomationTransient,
                         m_hoverState.previewValueLabel);
    if (content)
        scene.setAutomationTextRecords(mainText);
    if (hover)
        scene.setAutomationHoverTextRecords(hoverTextRecords);
    if (transient)
        scene.setAutomationTransientTextRecords(transientTextRecords);
}
