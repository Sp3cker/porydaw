#include "ui/editordrawer/velocityarea/velocityarea.h"

#include <algorithm>
#include <cmath>

#include <QColor>
#include <QPainter>
#include <QPen>

#include "ui/editordrawer/velocityarea/detail.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"

using velocityarea::detail::contains;

void VelocityArea::paintContent(QPainter &painter)
{
    painter.setRenderHint(QPainter::Antialiasing, false);
    painter.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    const int origin = plotOrigin();
    const int width = plotWidth();
    const int separatorX = origin - layout::singlePixel();
    const double labelLeft = double(layout::space(layout::Space::Two));
    const double labelRight =
        std::max(labelLeft, double(separatorX - layout::space(layout::Space::Two)));
    const double labelWidth = labelRight - labelLeft;
    const double labelHeight = double(m_captionFontHeight);
    painter.fillRect(QRect(layout::space(layout::Space::Zero), layout::space(layout::Space::Zero),
                           std::min(origin, this->width()), height()),
                     palette().alternateBase());
    painter.setPen(QPen(palette().mid().color(), layout::singlePixel()));
    painter.drawLine(separatorX, 0, separatorX, height());
    const QColor trackColor =
        m_live.trackColor.isValid() ? m_live.trackColor : palette().highlight().color();
    const QColor stemColor = songview::mixTowardOklab(trackColor, Qt::black, 1.0 / 3.0);
    const QColor selectedColor = palette().highlight().color();
    VelocityAxisPaintStyle axisStyle;
    axisStyle.labelColor = themes::color(themes::Role::song_view_primary_text);
    axisStyle.accentColor = selectedColor;
    axisStyle.labelFont = m_captionFont;
    axisStyle.emphasizedFont = m_boldCaptionFont;
    axisStyle.separatorX = double(separatorX);
    axisStyle.labelLeft = labelLeft;
    axisStyle.labelWidth = labelWidth;
    axisStyle.labelHeight = labelHeight;
    axisStyle.tickWidth = double(layout::singlePixel());
    axisStyle.emphasizedWidth = 1.5;
    axisStyle.markerWidth = 1.5;
    axisStyle.minorTickLength = double(layout::space(layout::Space::One));
    axisStyle.majorTickLength = double(3 * layout::space(layout::Space::Half));
    axisStyle.markerTickLength = double(layout::space(layout::Space::Two));
    axisStyle.graduationTickLength = double(3 * layout::space(layout::Space::Half));
    axisStyle.contentClip = QRectF(double(origin), double(layout::space(layout::Space::Zero)),
                                   double(width), double(height()));
    axisStyle.continuousRuler = detentsDisabled();
    std::optional<DocNote> hoveredNote;
    if (m_hoveredNote) {
        DocNote note;
        const SongDocument *document = m_owner.document();
        if (document && document->findNote(*m_hoveredNote, &note))
            hoveredNote = note;
    }
    axisStyle.relativeGesture = m_relativeActivated ||
                                m_owner.selectionModel().noteSelection().size() > 1 ||
                                hoveredNote.has_value();
    m_axis.paintRuler(painter, axisStyle);
    painter.save();
    painter.setClipRect(axisStyle.contentClip, Qt::IntersectClip);
    m_owner.paintGrid(painter, QRect(origin, 0, width, height()), origin);
    const MidiTimeline *timeline = m_owner.timeline();
    if (timeline) {
        const double ticksPerBeat = double(std::max(1u, timeline->ticksPerBeat));
        const double ticksPerPixel = ticksPerBeat / pxPerBeat();
        const uint64_t firstTick =
            uint64_t(std::max(0.0, std::floor(m_live.horizontalScroll * ticksPerPixel)));
        const uint64_t lastTick = std::max(
            firstTick + 1,
            uint64_t(std::ceil((m_live.horizontalScroll + double(width)) * ticksPerPixel)));
        uint64_t sectionTick = firstTick;
        painter.setPen(QPen(themes::color(themes::Role::song_view_psg_velocity_levels),
                            layout::singlePixel()));
        while (sectionTick < lastTick) {
            const DrawerPageVoiceContext context = m_owner.voiceContext(sectionTick);
            const uint64_t sectionEnd = std::min(lastTick, context.endTick);
            if (sectionEnd <= sectionTick)
                break;
            const VelocityMap map = VelocityMap::resolve(context.voice, std::nullopt);
            if (map.isPsg()) {
                const double left =
                    std::clamp(xForTick(sectionTick), double(origin), double(origin + width));
                const double right =
                    std::clamp(xForTick(sectionEnd), double(origin), double(origin + width));
                for (std::size_t level = 0; level + 1 < map.levelCount(); ++level) {
                    const double y = levelBoundaryY(map, int(level));
                    painter.drawLine(QPointF(left, y), QPointF(right, y));
                }
            }
            sectionTick = sectionEnd;
        }
    }
    const std::vector<NoteId> &selection = m_owner.selectionModel().noteSelection();
    const std::vector<DocNote> notes = primaryTrackNotes();
    const auto selected = [&selection, this](const DocNote &note) {
        return contains(selection, note.noteId) || contains(m_bandPreview, note.noteId);
    };
    const auto selectedCount = std::count_if(notes.begin(), notes.end(), selected);
    const bool dimUnselectedNodes = selectedCount > 1;
    const QColor unselectedNodeColor = dimUnselectedNodes ? palette().mid().color() : trackColor;
    const double stemWidth = m_geometry.stemDipWidth / devicePixelRatioF();
    painter.setPen(QPen(stemColor, stemWidth, Qt::SolidLine, Qt::FlatCap));
    for (const DocNote &note : notes) {
        if (selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const double start = xForTick(note.tick);
        const double end = std::max(start + 1.0, xForTick(note.tick + note.duration));
        painter.drawLine(QPointF(start, yForNote(note, velocity)),
                         QPointF(end, yForNote(note, velocity)));
    }
    painter.setPen(QPen(selectedColor, m_geometry.selectedStemDipWidth / devicePixelRatioF(),
                        Qt::SolidLine, Qt::FlatCap));
    for (const DocNote &note : notes) {
        if (!selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const double start = xForTick(note.tick);
        const double end = std::max(start + 1.0, xForTick(note.tick + note.duration));
        painter.drawLine(QPointF(start, yForNote(note, velocity)),
                         QPointF(end, yForNote(note, velocity)));
    }
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(dimUnselectedNodes ? QPen(Qt::NoPen)
                                      : QPen(Qt::black, m_geometry.nodeOutlineDipWidth));
    painter.setBrush(unselectedNodeColor);
    for (const DocNote &note : notes) {
        if (selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        painter.drawEllipse(QPointF(xForTick(note.tick), yForNote(note, velocity)),
                            m_geometry.nodePaintRadius, m_geometry.nodePaintRadius);
    }
    for (const DocNote &note : notes) {
        if (!selected(note))
            continue;
        const uint8_t velocity = displayedVelocity(note);
        const QPointF center(xForTick(note.tick), yForNote(note, velocity));
        painter.setPen(QPen(selectedColor, m_geometry.selectedNodeRingDipWidth));
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(center, m_geometry.selectedNodeRingRadius,
                            m_geometry.selectedNodeRingRadius);
        painter.setPen(QPen(Qt::black, m_geometry.nodeOutlineDipWidth));
        painter.setBrush(trackColor);
        painter.drawEllipse(center, m_geometry.nodePaintRadius, m_geometry.nodePaintRadius);
    }
    if (m_interaction == Interaction::Ramp) {
        painter.setPen(QPen(themes::color(themes::Role::song_view_edit_preview_outline),
                            layout::singlePixel()));
        painter.drawLine(m_pressPosition, m_previousPosition);
    }
    if (m_interaction == Interaction::Band)
        songview::paintSelectionReticle(painter, m_bandRect);
    painter.setRenderHint(QPainter::Antialiasing, false);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                        Qt::DashLine));
    painter.drawLine(QPointF(xForTick(m_live.editCursorTick), 0),
                     QPointF(xForTick(m_live.editCursorTick), height()));
    painter.restore();
}
