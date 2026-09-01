#include "ui/editordrawer/automationcanvas.h"

#include <algorithm>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

#include <QPalette>
#include <QScrollArea>
#include <QScrollBar>

#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/songview/quick/automationnodelanequick.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/quick/timelinequickview.h"
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

bool hasDirty(TimelineQuickDirtySet mask, TimelineQuickDirty dirty)
{
    return mask.testFlag(dirty);
}

QRect viewportRect(const QRect &content, int verticalScroll)
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
    if (separator) {
        addHorizontalLine(scene, TimelineQuickLayer::AutomationGrid, band.left(), band.right(),
                          band.bottom(), layout::singlePixel(),
                          themes::color(themes::Role::song_view_separator), viewport);
    }
    if (!arrow)
        return;
    const QRect &bounds = *arrow;
    const QColor color = themes::color(themes::Role::song_view_primary_text);
    if (expanded) {
        addClippedTriangle(scene, TimelineQuickLayer::AutomationGrid,
                           QPointF(bounds.left(), bounds.top()),
                           QPointF(bounds.right(), bounds.top()),
                           QPointF(bounds.center().x(), bounds.bottom()), color, textClip);
    } else {
        addClippedTriangle(scene, TimelineQuickLayer::AutomationGrid,
                           QPointF(bounds.left(), bounds.top()),
                           QPointF(bounds.right(), bounds.center().y()),
                           QPointF(bounds.left(), bounds.bottom()), color, textClip);
    }
}

} // namespace
} // namespace songview

void AutomationCanvas::rebuildQuickScene(songview::TimelineQuickScene &scene,
                                         songview::TimelineQuickDirtySet mask)
{
    using namespace songview;
    const bool grid = hasDirty(mask, TimelineQuickDirty::AutomationGrid);
    const bool curves = hasDirty(mask, TimelineQuickDirty::AutomationCurves);
    const bool nodes = hasDirty(mask, TimelineQuickDirty::AutomationNodes);
    const bool selection = hasDirty(mask, TimelineQuickDirty::AutomationSelection);
    const bool transient = hasDirty(mask, TimelineQuickDirty::AutomationTransient);
    const bool hover = hasDirty(mask, TimelineQuickDirty::AutomationHover);
    const bool text = hasDirty(mask, TimelineQuickDirty::AutomationText);
    const bool hoverText = hasDirty(mask, TimelineQuickDirty::AutomationHoverText);
    const bool transientText = hasDirty(mask, TimelineQuickDirty::AutomationTransientText);
    if (grid)
        resetLayer(scene, TimelineQuickLayer::AutomationGrid);
    if (curves)
        resetLayer(scene, TimelineQuickLayer::AutomationCurves);
    if (nodes)
        resetLayer(scene, TimelineQuickLayer::AutomationNodes);
    if (selection)
        resetLayer(scene, TimelineQuickLayer::AutomationSelection);
    if (transient)
        resetLayer(scene, TimelineQuickLayer::AutomationTransient);
    if (hover)
        resetLayer(scene, TimelineQuickLayer::AutomationHover);
    if (text)
        scene.setAutomationTextRecords({});
    if (hoverText)
        scene.setAutomationHoverTextRecords({});
    if (transientText)
        scene.setAutomationTransientTextRecords({});
    if (!m_page || !m_scroll || !m_scroll->viewport() || !m_page->document())
        return;

    const QWidget *viewportWidget = m_scroll->viewport();
    const QRectF viewport(0, 0, viewportWidget->width(), viewportWidget->height());
    if (viewport.width() <= 0.0 || viewport.height() <= 0.0)
        return;
    const QScrollBar *verticalBar = m_scroll->verticalScrollBar();
    const int verticalScroll = verticalBar ? verticalBar->value() : 0;
    const qreal dpr = devicePixelRatioF();
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
    const QRect tempoBand = viewportRect(tempoBandContent, verticalScroll);
    const QRectF tempoClip = rectF(tempoBand).intersected(viewport);
    QRectF scrollableViewport = viewport;
    if (!tempoClip.isEmpty())
        scrollableViewport.setBottom(std::min(scrollableViewport.bottom(), tempoClip.top()));

    std::vector<VisibleLane> lanes;
    lanes.reserve(m_nodeStack.size() < 2 ? 2 : std::min<std::size_t>(m_nodeStack.size(), 8));
    for (int index = 0; index < int(m_nodeStack.size()); ++index) {
        const NodeLaneSlot &slot = m_nodeStack[std::size_t(index)];
        if (!slot.lane || slot.isTempo())
            continue;
        const QRect body = viewportRect(slot.body, verticalScroll);
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
        lanes.push_back(
            {.handle = handle,
             .slot = &slot,
             .band = body,
             .body = body,
             .clip = clip,
             .plot = rectF(nodelane::plotRect(body, m_geometry)).intersected(clip),
             .overflow =
                 nodelane::nodeOverflowClip(nodelane::plotRect(body, m_geometry), m_geometry)
                     .intersected(clip),
             .tempo = false,
             .selectedLane = m_laneSelection.coversLane(slot.id) || bandLane,
             .selectedNodesLane = selectedNodesLane,
             .bandLane = bandLane,
             .needsPoints = curves || nodes || text || needsTransientPoints || needsHoverPoints});
    }
    if (tempoSlot && !tempoClip.isEmpty()) {
        const QRect tempoBody = viewportRect(tempoSlot->body, verticalScroll);
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
             .plot = tempoExpanded
                         ? rectF(nodelane::plotRect(tempoBody, m_geometry)).intersected(tempoClip)
                         : QRectF{},
             .overflow = tempoExpanded ? nodelane::nodeOverflowClip(
                                             nodelane::plotRect(tempoBody, m_geometry), m_geometry)
                                             .intersected(tempoClip)
                                       : QRectF{},
             .tempo = true,
             .selectedLane = m_laneSelection.coversLane(tempoSlot->id) || bandLane,
             .selectedNodesLane = selectedNodesLane,
             .bandLane = bandLane,
             .needsPoints = tempoExpanded &&
                            (curves || nodes || text || needsTransientPoints || needsHoverPoints)});
    }

    for (VisibleLane &lane : lanes) {
        if (lane.needsPoints)
            lane.points = lane.slot->lane->points();
    }
    const bool multipleSelectedNodes = hasMultipleSelectedNodes(selectedTickRange);

    std::vector<TimelineQuickTextModel::Record> mainText;
    std::vector<TimelineQuickTextModel::Record> hoverTextRecords;
    std::vector<TimelineQuickTextModel::Record> transientTextRecords;
    if (text)
        mainText.reserve(2 * lanes.size() + 1);
    if (hoverText)
        hoverTextRecords.reserve(1);
    if (transientText)
        transientTextRecords.reserve(1);
    // Text must retain its pre-clip rectangle: the QML automation band clips
    // viewport-local glyphs without changing their alignment origin.
    const NodeLaneQuickPaint::Outputs outputs;
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);
    const QColor primaryText = themes::color(themes::Role::song_view_primary_text);
    const QColor secondaryText = themes::color(themes::Role::song_view_secondary_text);
    const QRectF gutterClip(m_labelGutter.x(), 0, m_labelGutter.width(), viewport.height());
    if (grid)
        addRect(scene, TimelineQuickLayer::AutomationGrid, viewport, background, viewport);

    for (const VisibleLane &lane : lanes) {
        if (!lane.tempo && grid) {
            composeBandedGrid(scene, TimelineQuickLayer::AutomationGrid, m_page->m_owner, lane.plot,
                              m_geometry.plotOrigin, dpr);
            addHeaderChrome(scene, rectF(lane.band), rectF(lane.band), std::nullopt, true, true,
                            lane.clip);
        }
        if (!lane.tempo && text && lane.slot->text && m_laneTextLayout) {
            CCLanes::RowTextCache &rowText = *lane.slot->text;
            const QRect textBounds(m_labelGutter.x(), lane.body.top(), m_labelGutter.width(),
                                   lane.body.height());
            const auto textBoxes =
                m_laneTextLayout->align(textBounds, layout::VerticalAlignment::Center);
            const QString &summary = refreshCcSummaryText(rowText, lane.points, *lane.slot->lane);
            appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                       quint64(2 * lane.handle.index), textBoxes.primary, rowText.title,
                       primaryText, m_laneTitleFont, Qt::AlignLeft, lane.clip);
            appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                       quint64(2 * lane.handle.index + 1), textBoxes.secondary, summary,
                       secondaryText, m_laneCaptionFont, Qt::AlignLeft, lane.clip);
        }
    }

    for (const VisibleLane &lane : lanes) {
        if (!lane.tempo)
            continue;
        if (grid) {
            addRect(scene, TimelineQuickLayer::AutomationGrid, rectF(lane.band), background,
                    lane.clip);
            addHorizontalLine(scene, TimelineQuickLayer::AutomationGrid, lane.band.left(),
                              lane.band.right(), lane.band.bottom(), layout::singlePixel(),
                              themes::color(themes::Role::song_view_separator), lane.clip);
            addHeaderChrome(
                scene, rectF(lane.band), gutterClip,
                [&] {
                    const QRect strip(lane.band.left(), lane.band.top(), lane.band.width(),
                                      m_geometry.addLaneStripHeight);
                    const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
                    return std::optional<QRect>{QRect(m_labelGutter.left(),
                                                      strip.center().y() - arrowSize / 2, arrowSize,
                                                      arrowSize)};
                }(),
                tempoExpanded, false, lane.clip);
            if (tempoExpanded) {
                composeBandedGrid(scene, TimelineQuickLayer::AutomationGrid, m_page->m_owner,
                                  lane.plot, m_geometry.plotOrigin, dpr);
            }
        }
        if (text) {
            const QRect strip(lane.band.left(), lane.band.top(), lane.band.width(),
                              m_geometry.addLaneStripHeight);
            const int arrowSize = std::max(layout::fontPx(0.5), strip.height() / 3);
            const QRect primary(
                m_labelGutter.x() + arrowSize + layout::space(layout::Space::One), strip.top(),
                std::max(0, m_labelGutter.width() - arrowSize - layout::space(layout::Space::One)),
                strip.height());
            const QRect secondary(primary.x(), strip.top() + strip.height(), primary.width(),
                                  strip.height());
            appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                       quint64(2 * lane.handle.index), primary, tr("Tempo (BPM)"), primaryText,
                       tempoExpanded ? m_laneTitleFont : m_laneCaptionFont, Qt::AlignLeft,
                       lane.clip);
            if (tempoExpanded) {
                appendText(mainText, TimelineQuickTextKeyKind::AutomationHeader,
                           quint64(2 * lane.handle.index + 1), secondary,
                           tr("%n point(s)", nullptr, int(lane.points.size())), secondaryText,
                           m_laneCaptionFont, Qt::AlignLeft, lane.clip);
            }
        }
    }
    for (const VisibleLane &lane : lanes) {
        if (!lane.tempo || tempoExpanded || !lane.selectedLane || !selectedTickRange)
            continue;
        const auto [firstTick, lastTick] = *selectedTickRange;
        const QRectF bounds = rectF(lane.band);
        const QRectF reticle(projection.displayX(firstTick, dpr), bounds.top(),
                             projection.displayX(lastTick, dpr) -
                                 projection.displayX(firstTick, dpr),
                             bounds.height());
        if (selection && !m_band.active) {
            addSelectionReticle(scene, TimelineQuickLayer::AutomationSelection, reticle, lane.clip);
        } else if (transient && m_band.active) {
            addSelectionReticle(scene, TimelineQuickLayer::AutomationTransient, reticle, lane.clip);
        }
    }

    if (grid) {
        const QRect strip =
            viewportRect(QRect(layout::space(layout::Space::Zero), addLaneStripTop(), width(),
                               m_geometry.addLaneStripHeight),
                         verticalScroll);
        const QRectF stripClip = rectF(strip).intersected(scrollableViewport);
        if (!stripClip.isEmpty()) {
            addRect(scene, TimelineQuickLayer::AutomationGrid, rectF(strip), background, stripClip);
            addHeaderChrome(scene, rectF(strip), rectF(strip), std::nullopt, true, true, stripClip);
        }
    }
    if (text) {
        const QRect strip =
            viewportRect(QRect(layout::space(layout::Space::Zero), addLaneStripTop(), width(),
                               m_geometry.addLaneStripHeight),
                         verticalScroll);
        const QRectF stripClip = rectF(strip).intersected(scrollableViewport);
        if (!stripClip.isEmpty()) {
            appendText(mainText, TimelineQuickTextKeyKind::AutomationAddLane, 0,
                       QRect(m_labelGutter.x(), strip.top(), m_labelGutter.width(), strip.height()),
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
            .plot = tempoExpanded ? lane.plot : rectF(lane.band).intersected(lane.clip),
            .contentYOffset = static_cast<qreal>(verticalScroll),
            .overflow = tempoExpanded ? lane.overflow : lane.clip,
            .geometry = m_geometry,
            .projection = projection,
            .hoverState = m_hoverState,
            .handle = lane.handle,
            .color = color,
            .selectedColor = palette().highlight().color(),
            .dimmedColor = palette().mid().color(),
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
        NodeLaneQuickPaint::composeStatic(staticContext, curves, nodes,
                                          selection && !m_band.active);
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
            .selectedColor = palette().highlight().color(),
            .dimmedColor = palette().mid().color(),
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
        NodeLaneQuickPaint::composeStatic(staticContext, curves, nodes,
                                          selection && !m_band.active);
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
    if (hover && hoverText)
        appendValueLabel(hoverTextRecords, TimelineQuickTextKeyKind::AutomationHover,
                         m_hoverState.hoverValueLabel);
    if (transient && transientText && m_activeGesture)
        appendValueLabel(transientTextRecords, TimelineQuickTextKeyKind::AutomationTransient,
                         m_hoverState.previewValueLabel);
    if (text)
        scene.setAutomationTextRecords(mainText);
    if (hoverText)
        scene.setAutomationHoverTextRecords(hoverTextRecords);
    if (transientText)
        scene.setAutomationTransientTextRecords(transientTextRecords);
}
