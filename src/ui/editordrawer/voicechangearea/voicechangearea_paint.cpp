#include "ui/editordrawer/voicechangearea/voicechangearea.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include <QFontMetrics>
#include <QPainter>
#include <QPen>

#include "core/miditimeline.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"

namespace {

// Horizontal plot coverage of one held program span, clamped to the visible
// plot; empty when the span is entirely off-camera.
QRectF heldSpanRect(uint64_t beginTick, uint64_t endTick, const SongView &owner, const QRect &plot)
{
    const qreal left =
        std::max<qreal>(plot.left(), owner.contentX(double(beginTick)) + plot.left());
    const qreal right =
        std::min<qreal>(plot.right() + 1, owner.contentX(double(endTick)) + plot.left());
    if (right <= left)
        return {};
    return QRectF(left, plot.top(), right - left, plot.height());
}

} // namespace

void VoiceChangeArea::paintContent(QPainter &painter)
{
    const QRect bounds = rect();
    if (bounds.isEmpty())
        return;
    painter.fillRect(bounds, themes::color(themes::Role::song_view_piano_roll_background));
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(bounds.left(), bounds.bottom(), bounds.right(), bounds.bottom());

    const int origin = plotOrigin();
    const int gutterMargin = layout::space(layout::Space::One);
    const QRect textBounds(gutterMargin, bounds.top(), std::max(0, origin - 2 * gutterMargin),
                           bounds.height());
    const layout::TwoLineTextLayout textLayout =
        layout::twoLineText(m_titleFont, m_titleFont, m_captionFont, layout::Space::Zero);
    const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
    SongDocument *document = m_owner.document();
    painter.save();
    painter.setClipRect(bounds, Qt::IntersectClip);
    painter.save();
    painter.setClipRect(textBoxes.primary.united(textBoxes.secondary), Qt::IntersectClip);
    painter.setFont(m_titleFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(textBoxes.primary, Qt::AlignLeft | Qt::AlignVCenter, tr("Voice"));
    painter.setFont(m_captionFont);
    if (document && m_engineTrack >= 0) {
        const int changeCount = int(m_voicePoints.size());
        if (m_changeCount != changeCount) {
            m_secondary = changeCount
                              ? tr("%n change(s) · double-click to edit", nullptr, changeCount)
                              : tr("no voice set · double-click to add");
            m_changeCount = changeCount;
        }
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter, m_secondary);
    }
    painter.restore();

    const QRect plot = plotRect();
    painter.setClipRect(plot, Qt::IntersectClip);
    painter.setFont(m_captionFont);
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    if (!document) {
        painter.drawText(plot, Qt::AlignCenter, tr("Voice changes are read-only"));
        painter.restore();
        return;
    }
    const auto *timeline = m_owner.timeline();
    if (!timeline || m_engineTrack < 0 || m_engineTrack >= 16) {
        painter.drawText(plot, Qt::AlignCenter, tr("No track selected"));
        painter.restore();
        return;
    }
    const int track = m_engineTrack;
    const qreal dpr =
        painter.device() ? painter.device()->devicePixelRatioF() : devicePixelRatioF();
    const bool previewing = voiceDragActive();
    if (previewing) {
        m_previewEntries.clear();
        m_previewEntries.reserve(m_voicePoints.size());
        for (const DocLanePoint &point : m_voicePoints) {
            const bool dragged = point.smfTrack == m_voiceDrag->point.smfTrack &&
                                 point.index == m_voiceDrag->point.index;
            m_previewEntries.push_back(
                {dragged ? m_voiceDrag->previewTick : point.tick, point.value});
        }
        std::stable_sort(m_previewEntries.begin(), m_previewEntries.end(),
                         [](const VoicePaintEntry &left, const VoicePaintEntry &right) {
                             return left.tick < right.tick;
                         });
    }
    const std::size_t paintEntryCount = previewing ? m_previewEntries.size() : m_voicePoints.size();
    const auto paintEntryAt = [&](std::size_t index) {
        if (previewing)
            return m_previewEntries[index];
        const DocLanePoint &point = m_voicePoints[index];
        return VoicePaintEntry{point.tick, point.value};
    };
    // SongView's grid always paints; there is no plain fallback here.
    m_owner.paintGrid(painter, plot, qreal(origin));

    // Held program spans: the track color from the governing program's start
    // (tick 0 under firstProgram) through each change to the song end. A tick-0
    // change governs immediately; deleting it reveals the initial span again.
    const QColor &trackColor =
        themes::trackIdentityColor(std::size_t(track % themes::trackIdentityColorCount));
    QColor heldColor = trackColor;
    heldColor.setAlpha(18);
    {
        int program = timeline->tracks[track].firstProgram;
        uint64_t spanStart = 0;
        for (std::size_t index = 0; index < paintEntryCount; ++index) {
            const VoicePaintEntry entry = paintEntryAt(index);
            if (program >= 0 && entry.tick > spanStart)
                painter.fillRect(heldSpanRect(spanStart, entry.tick, m_owner, plot), heldColor);
            program = entry.program;
            spanStart = entry.tick;
        }
        if (program >= 0 && timeline->lengthTicks > spanStart)
            painter.fillRect(heldSpanRect(spanStart, timeline->lengthTicks, m_owner, plot),
                             heldColor);
    }

    static const QString noVoiceText = tr("No voice");
    // Right-aligned current program: the playback tick while playing, the edit
    // cursor otherwise; "No voice" when the track has no resolvable program.
    const double contextTick =
        m_live.playback.playing ? m_live.playback.playheadTick : double(m_live.editCursorTick);
    const int contextSlot = voiceSlotAt(uint64_t(std::round(std::max(0.0, contextTick))));
    const QString &contextText = contextSlot >= 0 && contextSlot < VOICEGROUP_SIZE
                                     ? paintTextFor(contextSlot).label
                                     : noVoiceText;
    painter.drawText(
        plot.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                      -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
        Qt::AlignRight | Qt::AlignVCenter, contextText);

    // One marker and one label per change, stair-stepped apart when labels
    // collide, elided at the right edge. Geometry stays font-relative.
    const qreal pad = layout::space(layout::Space::One);
    const qreal gap =
        std::max<qreal>(m_geometry.hoverPaintPadding, layout::space(layout::Space::One));
    const QFontMetricsF fm(m_captionFont);
    const qreal labelH = fm.height();
    const qreal centerY = plot.center().y() - labelH / 2.0;
    const qreal stairStep = std::min<qreal>(layout::space(layout::Space::Four),
                                            (plot.height() - labelH - 2 * pad) / 2.0);
    const bool canStair = stairStep > 1.0;
    m_labelLayouts.resize(paintEntryCount);
    qreal lastXEnd = -std::numeric_limits<qreal>::infinity();
    bool stairUp = true;
    for (std::size_t index = 0; index < paintEntryCount; ++index) {
        const VoicePaintEntry entry = paintEntryAt(index);
        VoiceLabelLayout &labelLayout = m_labelLayouts[index];
        labelLayout.elidedText.clear();
        const QString &sourceText = paintTextFor(entry.program).label;
        labelLayout.text = sourceText.isEmpty() ? &noVoiceText : &sourceText;
        const qreal labelX = m_owner.displayX(double(entry.tick), origin, dpr) + pad;
        const qreal maxW = std::max<qreal>(0, plot.right() - labelX);
        if (fm.horizontalAdvance(*labelLayout.text) > maxW && maxW > 0) {
            labelLayout.elidedText =
                fm.elidedText(*labelLayout.text, Qt::ElideRight, int(std::floor(maxW)));
            labelLayout.text = &labelLayout.elidedText;
        }
        const qreal w = std::min(fm.horizontalAdvance(*labelLayout.text), maxW);
        labelLayout.offscreen = labelX + w < plot.left() || labelX > plot.right() || w <= 0;
        qreal labelY = centerY;
        if (!labelLayout.offscreen) {
            const bool close = labelX < lastXEnd + gap;
            if (close && canStair)
                stairUp = !stairUp;
            else
                stairUp = true;
            if (close && canStair)
                labelY = stairUp ? centerY - stairStep : centerY + stairStep;
            labelY =
                std::clamp(labelY, qreal(plot.top()) + pad, qreal(plot.bottom()) - labelH - pad);
            lastXEnd = labelX + w + gap;
        }
        labelLayout.rect = QRectF(labelX, labelY, w, labelH);
    }
    const qreal markerW = layout::singlePixel() + layout::singlePixel();
    painter.setPen(QPen(trackColor, markerW));
    for (const VoiceLabelLayout &labelLayout : m_labelLayouts) {
        const qreal markerX = labelLayout.rect.left() - pad;
        painter.drawLine(QPointF(markerX, plot.top() + pad), QPointF(markerX, plot.bottom() - pad));
    }
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    for (const VoiceLabelLayout &labelLayout : m_labelLayouts)
        if (!labelLayout.offscreen && labelLayout.text)
            painter.drawText(labelLayout.rect, Qt::AlignLeft | Qt::AlignVCenter, *labelLayout.text);

    // Dotted hover line plus the held label, suppressed directly over a
    // marker (updateHover leaves the label empty there). A non-empty label
    // implies the hover font cache is warm: only updateHover sets it, and
    // FontChange drops the whole hover state before the next paint.
    if (m_hoverActive) {
        painter.setPen(QPen(themes::color(themes::Role::song_view_secondary_text),
                            layout::singlePixel(), Qt::DotLine));
        painter.drawLine(QPointF(m_hoverX, plot.top()), QPointF(m_hoverX, plot.bottom()));
        if (!m_hoverLabel.isEmpty()) {
            painter.setFont(m_hoverLabelFont);
            painter.setPen(themes::color(themes::Role::song_view_primary_text));
            painter.drawText(m_hoverLabelRect, Qt::AlignLeft | Qt::AlignVCenter, m_hoverLabel);
        }
    }

    // Dashed edit cursor painted locally; the AutomationCanvas helper stays
    // owned by the automation page.
    const qreal cursorX = m_owner.displayX(double(m_live.editCursorTick), origin, dpr);
    painter.setPen(QPen(themes::color(themes::Role::song_view_edit_cursor), layout::singlePixel(),
                        Qt::DashLine));
    painter.drawLine(QPointF(cursorX, plot.top()), QPointF(cursorX, plot.bottom()));
    painter.restore();
}
