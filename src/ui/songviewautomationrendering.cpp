#include "ui/songviewautomationarea_p.hpp"
#include "ui/songviewtimeruler.hpp"

#include <QPaintEvent>
#include <QPainter>

#include <algorithm>

#include "ui/songview.h"

namespace songview {

void AutomationArea::State::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.fillRect(rect(), palette().color(QPalette::Window));
    if (!m_sv->timeline())
        return;

    int rowY = 0;
    for (size_t i = 0; i < m_rows.size(); i++) {
        const int h = rowHeight(m_rows[i]);
        paintRow(p, m_rows[i], QRect(0, rowY, width(), h));
        rowY += h;
    }

    if (m_sv->document()) {
        const QRect strip = addLaneRect();
        p.setPen(palette().color(QPalette::Highlight));
        p.drawText(strip.adjusted(8, 0, -8, 0), Qt::AlignLeft | Qt::AlignVCenter,
                   SongView::tr("+ Add lane"));
    }

    // Drag preview: the pending stream (sweep) or ramp (line), plus a
    // marker with the value the gesture will commit at the cursor.
    if (m_dragRow >= 0 && m_dragRow < int(m_rows.size())) {
        int minV, maxV;
        rowRange(m_rows[m_dragRow], &minV, &maxV);
        const int top = rowTop(m_dragRow) + 5;
        const int bottom = rowBottom(m_dragRow) - 1 - 4;
        auto valueY = [&](int v) {
            return bottom - (v - minV) * (bottom - top) / std::max(1, maxV - minV);
        };
        auto tickX = [&](uint64_t t) {
            return kGutterW + m_sv->contentX(double(t));
        };
        p.setClipRect(QRect(kGutterW, rowTop(m_dragRow), width() - kGutterW,
                            rowHeight(m_rows[m_dragRow])));
        p.setPen(QPen(palette().color(QPalette::WindowText), 1));
        p.setBrush(Qt::NoBrush);
        if (m_gesture == Gesture::Sweep && m_sweep.size() > 1) {
            // Hold-value steps, like paintCurve draws committed points.
            for (size_t i = 0; i + 1 < m_sweep.size(); i++) {
                const int y = valueY(m_sweep[i].second);
                p.drawLine(tickX(m_sweep[i].first), y,
                           tickX(m_sweep[i + 1].first), y);
                p.drawLine(tickX(m_sweep[i + 1].first), y,
                           tickX(m_sweep[i + 1].first),
                           valueY(m_sweep[i + 1].second));
            }
        } else if (m_gesture == Gesture::Line) {
            p.drawLine(tickX(m_lineStartTick), valueY(m_lineStartValue),
                       tickX(m_dragTick), valueY(m_dragValue));
        }
        const int x = tickX(m_dragTick);
        const int y = valueY(m_dragValue);
        p.drawEllipse(QPoint(x, y), 3, 3);
        p.drawText(QPoint(x + 6, y - 4),
                   formatRowValue(m_rows[m_dragRow], m_dragValue));
        p.setClipping(false);
    }

    paintHoverReadout(p);
}

void AutomationArea::State::paintHoverReadout(QPainter &p)
{
    if (m_dragRow >= 0 || m_selSweep || m_hoverRow < 0
        || m_hoverRow >= int(m_rows.size()))
        return;
    const Row &row = m_rows[m_hoverRow];
    const std::vector<LanePoint> *points = rowPoints(row);
    if (!points || points->empty())
        return;
    const auto it = std::upper_bound(
        points->begin(), points->end(), m_hoverTick,
        [](double t, const LanePoint &pt) { return t < double(pt.tick); });
    if (it == points->begin())
        return; // before the first point: no value in effect yet
    const int value = (it - 1)->value;
    int minV, maxV;
    rowRange(row, &minV, &maxV);
    const int top = rowTop(m_hoverRow) + 5;
    const int bottom = rowBottom(m_hoverRow) - 1 - 4;
    const int x = kGutterW + m_sv->contentX(m_hoverTick);
    const int y =
        bottom - (value - minV) * (bottom - top) / std::max(1, maxV - minV);
    p.setClipRect(
        QRect(kGutterW, rowTop(m_hoverRow), width() - kGutterW, rowHeight(row)));
    p.setPen(QPen(palette().color(QPalette::WindowText), 1));
    p.setBrush(Qt::NoBrush);
    p.drawEllipse(QPoint(x, y), 3, 3);
    const QString text = formatRowValue(row, value);
    // Keep the label inside the row: flip left of the cursor at the right
    // edge, and keep the baseline below the row top when the curve is high.
    const int tw = fontMetrics().horizontalAdvance(text);
    const int tx = x + 6 + tw > width() ? x - 6 - tw : x + 6;
    const int ty = std::max(y - 4, rowTop(m_hoverRow) + fontMetrics().ascent() + 2);
    p.drawText(QPoint(tx, ty), text);
    p.setClipping(false);
}

void AutomationArea::State::paintRow(QPainter &p, const Row &row, const QRect &r)
{
    const QRect plot(kGutterW, r.top(), width() - kGutterW, r.height());
    p.setClipRect(r);
    p.setPen(palette().color(QPalette::Mid));
    p.drawLine(r.left(), r.bottom(), r.right(), r.bottom());

    // Gutter label.
    const QString name = rowTitle(row);
    int minV = 0, maxV = 127;
    const std::vector<LanePoint> *points = nullptr;
    QColor curve = palette().color(QPalette::Highlight);
    rowRange(row, &minV, &maxV);
    switch (row.kind) {
    case Row::Tempo:
        points = &m_sv->model().tempoLane;
        curve = QColor(0xb0, 0x60, 0xd0);
        break;
    case Row::Voice:
        break;
    case Row::Lane:
        points = &row.lane->points;
        curve = SongView::trackColor(row.lane->track);
        break;
    }

    p.setPen(palette().color(QPalette::WindowText));
    QFont f = p.font();
    f.setBold(true);
    p.setFont(f);
    p.drawText(QRect(8, r.top() + 4, kGutterW - 16, 14), Qt::AlignLeft, name);
    f.setBold(false);
    p.setFont(f);
    if (points && !points->empty()) {
        p.setPen(palette().color(QPalette::PlaceholderText));
        p.drawText(QRect(8, r.top() + 20, kGutterW - 16, 14), Qt::AlignLeft,
                   SongView::tr("%1 points · %2..%3")
                       .arg(points->size())
                       .arg(minV)
                       .arg(maxV));
    } else if (points && row.kind == Row::Lane) {
        p.setPen(palette().color(QPalette::PlaceholderText));
        p.drawText(QRect(8, r.top() + 20, kGutterW - 16, 14), Qt::AlignLeft,
                   SongView::tr("empty · click to add points"));
    } else if (row.kind == Row::Voice && m_sv->document()) {
        int count = 0;
        for (const VoiceChange &vc : m_sv->model().voices)
            if (vc.track == m_sv->selectedTrack())
                count++;
        p.setPen(palette().color(QPalette::PlaceholderText));
        p.drawText(QRect(8, r.top() + 20, kGutterW - 16, 14), Qt::AlignLeft,
                   count ? SongView::tr("%n change(s) · click to edit", nullptr, count)
                         : SongView::tr("no voice set · click to add"));
    }

    p.setClipRect(plot);
    m_sv->drawGrid(p, plot, kGutterW);

    if (row.kind == Row::Voice)
        paintVoiceRow(p, plot);
    else if (points)
        paintCurve(p, plot, *points, minV, maxV, curve,
                   row.kind == Row::Lane && row.lane->cc == LANE_CC_BEND);

    const std::pair<int, uint8_t> id = rowIdentity(row);
    time_ruler_detail::drawOverlays(p, m_sv, plot, kGutterW,
                                    m_sv->timeSelectionCoversRow(id.first, id.second));
    p.setClipping(false);
}

void AutomationArea::State::paintCurve(QPainter &p, const QRect &plot, const std::vector<LanePoint> &points,
                int minV, int maxV, const QColor &color, bool centerLine)
{
    const int top = plot.top() + 5;
    const int bottom = plot.bottom() - 4;
    auto valueY = [&](int v) {
        return bottom - (v - minV) * (bottom - top) / std::max(1, maxV - minV);
    };
    if (centerLine) {
        p.setPen(QPen(palette().color(QPalette::Mid), 1, Qt::DashLine));
        p.drawLine(plot.left(), valueY(0), plot.right(), valueY(0));
    }
    p.setPen(QPen(color, 2));
    for (size_t i = 0; i < points.size(); i++) {
        const int x0 = kGutterW + m_sv->contentX(double(points[i].tick));
        const int x1 = i + 1 < points.size()
                           ? kGutterW + m_sv->contentX(double(points[i + 1].tick))
                           : plot.right();
        if (x1 < plot.left() || x0 > plot.right())
            continue;
        const int y = valueY(points[i].value);
        p.drawLine(x0, y, x1, y); // hold value until the next point
        if (i + 1 < points.size())
            p.drawLine(x1, y, x1, valueY(points[i + 1].value));
        if (m_sv->pxPerBeat() >= 24.0)
            p.fillRect(x0 - 1, y - 1, 3, 3, color);
    }
}

void AutomationArea::State::paintVoiceRow(QPainter &p, const QRect &plot)
{
    const SongViewModel &model = m_sv->model();
    const int selected = m_sv->selectedTrack();
    std::vector<const VoiceChange *> changes;
    for (const VoiceChange &vc : model.voices)
        if (vc.track == selected)
            changes.push_back(&vc);

    const QColor color = SongView::trackColor(selected);
    for (size_t i = 0; i < changes.size(); i++) {
        const int x = kGutterW + m_sv->contentX(double(changes[i]->tick));
        const int xEnd = i + 1 < changes.size()
                             ? kGutterW + m_sv->contentX(double(changes[i + 1]->tick))
                             : plot.right();
        if (xEnd < plot.left() || x > plot.right())
            continue;
        p.setPen(QPen(color, 2));
        p.drawLine(x, plot.top() + 4, x, plot.bottom() - 4);
        p.setPen(palette().color(QPalette::WindowText));
        const QString text = QStringLiteral("%1 %2")
                                 .arg(int(changes[i]->program), 3, 10, QLatin1Char('0'))
                                 .arg(m_sv->voiceShortName(changes[i]->program));
        // Keep the label readable while its voice region is scrolled
        // partially off the left edge.
        const int textX = std::max(x + 4, plot.left() + 4);
        const int textW = std::max(10, xEnd - textX - 4);
        p.drawText(QRect(textX, plot.top() + 4, textW, plot.height() - 8),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   fontMetrics().elidedText(text, Qt::ElideRight, textW));
    }
}

} // namespace songview
