#include "ui/editordrawer/velocityarea/velocityarea.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <span>
#include <string_view>
#include <vector>

#include <QPalette>

#include "ui/editordrawer/velocityarea/detail.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/songview/timecamera.h"
#include "ui/theme/themeruntime.h"

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using timeline_quick::addEllipse;
using timeline_quick::addEllipseRing;
using timeline_quick::addHorizontalLine;
using timeline_quick::addLine;
using timeline_quick::addRect;
using timeline_quick::addSelectionReticle;
using timeline_quick::addVerticalLine;
using timeline_quick::resetLayer;

namespace {

void appendAxisText(std::vector<TimelineQuickTextModel::Record> &records, quint64 ordinal,
                    const QRectF &rect, const QString &text, const QColor &color, const QFont &font)
{
    if (rect.width() <= 0.0 || rect.height() <= 0.0)
        return;
    records.push_back({{TimelineQuickTextKeyKind::VelocityAxis, {}, ordinal},
                       rect,
                       text,
                       color,
                       font,
                       Qt::AlignRight,
                       Qt::AlignVCenter});
}

} // namespace

} // namespace songview

void VelocityArea::rebuildQuickChrome(songview::TimelineQuickScene &scene, const QRectF &plot,
                                      const QRectF &gutter, qreal separatorX)
{
    using namespace songview;
    constexpr TimelineQuickLayer gutterLayer = TimelineQuickLayer::VelocityGutterChrome;
    constexpr TimelineQuickLayer chromeLayer = TimelineQuickLayer::VelocityChrome;
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);
    const QColor gutterColor = m_inputHost->palette().alternateBase().color();
    const QColor separator = m_inputHost->palette().mid().color();
    addRect(scene, chromeLayer, plot, background, plot);
    addRect(scene, gutterLayer, gutter, gutterColor, gutter);
    addVerticalLine(scene, gutterLayer, separatorX, 0, gutter.height(), lyt::singlePixel(),
                    separator, gutter);
}

void VelocityArea::rebuildQuickAxis(songview::TimelineQuickScene &scene, const QRectF &gutter,
                                    qreal separatorX)
{
    using namespace songview;
    constexpr TimelineQuickLayer axisLayer = TimelineQuickLayer::VelocityAxis;
    const qreal labelLeft = lyt::space(Space::Two);
    const qreal labelRight = std::max(labelLeft, qreal(separatorX - lyt::space(Space::Two)));
    const qreal labelWidth = labelRight - labelLeft;
    const qreal labelHeight = m_captionFontHeight;
    const QColor selectedColor = m_inputHost->palette().highlight().color();
    const QColor labelColor = themes::color(themes::Role::song_view_primary_text);
    const bool hasHoveredNote = [this] {
        if (!m_hoveredNote)
            return false;
        DocNote note;
        const SongDocument *document = m_owner.document();
        return document && document->findNote(*m_hoveredNote, &note);
    }();
    const bool relativeGesture = m_relativeActivated ||
                                 m_owner.selectionModel().noteSelection().size() > 1 ||
                                 hasHoveredNote;
    std::vector<TimelineQuickTextModel::Record> axisText;
    if (m_axis.mode() == VelocityAxis::Mode::Intrinsic && !detentsDisabled()) {
        for (std::size_t index = 0; index < m_axis.graduationCount(); ++index) {
            const VelocityAxisGraduation &graduation = m_axis.graduations()[index];
            const bool emphasizeLabel =
                graduation.active && (relativeGesture || !graduation.labelVisible);
            addHorizontalLine(scene, axisLayer, separatorX - 3.0 * lyt::space(Space::Half),
                              separatorX, graduation.y,
                              graduation.active ? 1.5 : lyt::singlePixel(),
                              graduation.active ? selectedColor : labelColor, gutter);
            if ((!relativeGesture && graduation.labelVisible) || emphasizeLabel) {
                appendAxisText(
                    axisText, index,
                    QRectF(labelLeft, graduation.y - labelHeight / 2.0, labelWidth, labelHeight),
                    QStringLiteral("Vol %1").arg(unsigned(graduation.level) + 1), labelColor,
                    emphasizeLabel ? m_boldCaptionFont : m_captionFont);
            }
        }
    } else {
        for (std::size_t index = 0; index < m_axis.tickCount(); ++index) {
            const VelocityAxisTick &tick = m_axis.ticks()[index];
            const qreal length = m_axis.hasLabel(tick.velocity) ? 3.0 * lyt::space(Space::Half)
                                                                : lyt::space(Space::One);
            addHorizontalLine(scene, axisLayer, separatorX - length, separatorX, tick.y,
                              lyt::singlePixel(), labelColor, gutter);
        }
        if (!relativeGesture) {
            for (std::size_t index = 0; index < m_axis.labelCount(); ++index) {
                const VelocityAxisLabel &label = m_axis.labels()[index];
                const std::string_view text = label.labelText();
                appendAxisText(
                    axisText, index,
                    QRectF(labelLeft, label.y - labelHeight / 2.0, labelWidth, labelHeight),
                    QString::fromLatin1(text.data(), int(text.size())), labelColor, m_captionFont);
            }
        }
        for (std::size_t index = 0; index < m_axis.markerCount(); ++index) {
            const VelocityAxisMarker &marker = m_axis.markers()[index];
            addHorizontalLine(scene, axisLayer, separatorX - lyt::space(Space::Two), separatorX,
                              marker.y, 1.5, selectedColor, gutter);
            if (relativeGesture) {
                appendAxisText(
                    axisText, index,
                    QRectF(labelLeft, marker.y - labelHeight / 2.0, labelWidth, labelHeight),
                    QString::number(marker.velocity), labelColor, m_boldCaptionFont);
            }
        }
    }
    scene.setVelocityTextRecords(axisText);
}

void VelocityArea::rebuildQuickGrid(songview::TimelineQuickScene &scene, const QRectF &plot,
                                    int origin, qreal dpr)
{
    songview::timeline_quick::composeBandedGrid(scene, songview::TimelineQuickLayer::VelocityGrid,
                                                m_owner, plot, origin, dpr);
}

void VelocityArea::rebuildQuickPsgBands(songview::TimelineQuickScene &scene, const QRectF &plot)
{
    using namespace songview;
    constexpr TimelineQuickLayer bandsLayer = TimelineQuickLayer::VelocityBands;
    if (m_owner.timeline()) {
        const uint64_t firstTick =
            uint64_t(std::max(0.0, std::floor(m_camera.tickAtContentX(plot.left()))));
        const uint64_t lastTick =
            std::max(firstTick + 1,
                     uint64_t(std::max(0.0, std::ceil(m_camera.tickAtContentX(plot.right())))));
        uint64_t sectionTick = firstTick;
        while (sectionTick < lastTick) {
            const DrawerPageVoiceContext context = m_owner.voiceContext(sectionTick);
            const uint64_t sectionEnd = std::min(lastTick, context.endTick);
            if (sectionEnd <= sectionTick)
                break;
            const VelocityMap map = VelocityMap::resolve(context.voice, std::nullopt);
            if (map.isPsg()) {
                const qreal left =
                    std::clamp<qreal>(xForTick(sectionTick), plot.left(), plot.right());
                const qreal right =
                    std::clamp<qreal>(xForTick(sectionEnd), plot.left(), plot.right());
                for (std::size_t level = 0; level + 1 < map.levelCount(); ++level) {
                    addHorizontalLine(scene, bandsLayer, left, right,
                                      levelBoundaryY(map, int(level)), lyt::singlePixel(),
                                      themes::color(themes::Role::song_view_psg_velocity_levels),
                                      plot);
                }
            }
            sectionTick = sectionEnd;
        }
    }
}

void VelocityArea::rebuildQuickNotes(songview::TimelineQuickScene &scene, const QRectF &plot,
                                     qreal dpr)
{
    using namespace songview;
    constexpr TimelineQuickLayer stemsLayer = TimelineQuickLayer::VelocityStems;
    constexpr TimelineQuickLayer nodesLayer = TimelineQuickLayer::VelocityNodes;
    const QColor trackColor = m_live.trackColor.isValid()
                                  ? m_live.trackColor
                                  : m_inputHost->palette().highlight().color();
    const QColor stemColor = mixTowardOklab(trackColor, Qt::black, 1.0 / 3.0);
    const QColor selectedColor = m_inputHost->palette().highlight().color();
    const std::vector<NoteId> &selection = m_owner.selectionModel().noteSelection();
    const std::vector<DocNote> notes = primaryTrackNotes();
    const auto selected = [&selection, this](const DocNote &note) {
        return velocityarea::detail::contains(selection, note.noteId) ||
               velocityarea::detail::contains(m_bandPreview, note.noteId);
    };
    const auto selectedCount = std::count_if(notes.begin(), notes.end(), selected);
    const bool dimUnselectedNodes = selectedCount > 1;
    const QColor unselectedNodeColor =
        dimUnselectedNodes ? m_inputHost->palette().mid().color() : trackColor;
    const qreal stemWidth = m_geometry.stemDipWidth / dpr;
    for (const DocNote &note : notes) {
        const bool isSelected = selected(note);
        const uint8_t velocity = displayedVelocity(note);
        const qreal start = xForTick(note.tick);
        const qreal end = std::max(start + 1.0, qreal(xForTick(note.tick + note.duration)));
        addLine(scene, stemsLayer, QPointF(start, yForNote(note, velocity)),
                QPointF(end, yForNote(note, velocity)),
                isSelected ? m_geometry.selectedStemDipWidth / dpr : stemWidth,
                isSelected ? selectedColor : stemColor, plot);
    }
    for (const DocNote &note : notes) {
        const uint8_t velocity = displayedVelocity(note);
        const QPointF center(xForTick(note.tick), yForNote(note, velocity));
        const bool isSelected = selected(note);
        if (isSelected) {
            addEllipseRing(scene, nodesLayer, center, m_geometry.selectedNodeRingRadius,
                           m_geometry.selectedNodeRingRadius, m_geometry.selectedNodeRingDipWidth,
                           selectedColor, plot);
            addEllipse(scene, nodesLayer, center, m_geometry.nodePaintRadius,
                       m_geometry.nodePaintRadius, trackColor, plot);
            addEllipseRing(scene, nodesLayer, center, m_geometry.nodePaintRadius,
                           m_geometry.nodePaintRadius, m_geometry.nodeOutlineDipWidth, Qt::black,
                           plot);
        } else {
            addEllipse(scene, nodesLayer, center, m_geometry.nodePaintRadius,
                       m_geometry.nodePaintRadius, unselectedNodeColor, plot);
            if (!dimUnselectedNodes) {
                addEllipseRing(scene, nodesLayer, center, m_geometry.nodePaintRadius,
                               m_geometry.nodePaintRadius, m_geometry.nodeOutlineDipWidth,
                               Qt::black, plot);
            }
        }
    }
}

void VelocityArea::rebuildQuickTransient(songview::TimelineQuickScene &scene, const QRectF &plot)
{
    using namespace songview;
    constexpr TimelineQuickLayer transientLayer = TimelineQuickLayer::VelocityTransient;
    if (m_interaction == Interaction::Ramp) {
        addLine(scene, transientLayer, m_pressPosition, m_previousPosition, lyt::singlePixel(),
                themes::color(themes::Role::song_view_edit_preview_outline), plot);
    }
    if (m_interaction == Interaction::Band)
        addSelectionReticle(scene, transientLayer, m_bandRect, plot);
}

void VelocityArea::rebuildQuickScene(songview::TimelineQuickScene &scene)
{
    if (!m_inputHost)
        return;
    using namespace songview;
    constexpr std::array layers = {
        TimelineQuickLayer::VelocityGutterChrome, TimelineQuickLayer::VelocityChrome,
        TimelineQuickLayer::VelocityAxis,         TimelineQuickLayer::VelocityGrid,
        TimelineQuickLayer::VelocityBands,        TimelineQuickLayer::VelocityStems,
        TimelineQuickLayer::VelocityNodes,        TimelineQuickLayer::VelocityTransient,
    };
    for (const TimelineQuickLayer layer : layers)
        resetLayer(scene, layer);
    scene.setVelocityTextRecords(std::span<const TimelineQuickTextModel::Record>{});
    ++m_diagnostics.contentBuildCount;
    const QRectF bounds = m_inputHost->bounds();
    const QRectF plot(QPointF{}, bounds.size());
    if (plot.width() <= 0.0 || plot.height() <= 0.0)
        return;
    const std::optional<songview::TimelineBandGeometry> &band =
        m_owner.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
    if (!band)
        return;
    const QRect gutterRect = band->gutterRect();
    const QRectF gutter(0.0, 0.0, gutterRect.width(), gutterRect.height());
    const qreal dpr = m_inputHost->devicePixelRatio();
    const qreal separatorX = gutter.right() - lyt::singlePixel();
    rebuildQuickChrome(scene, plot, gutter, separatorX);
    rebuildQuickAxis(scene, gutter, separatorX);
    rebuildQuickGrid(scene, plot, 0, dpr);
    rebuildQuickPsgBands(scene, plot);
    rebuildQuickNotes(scene, plot, dpr);
    rebuildQuickTransient(scene, plot);
}
