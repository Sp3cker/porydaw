// ---------------------------------------------------------------- TimeRuler

#include "ui/songview/timeruler.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"

#include <QFontMetrics>
#include <QPainter>

#include <algorithm>
#include <cstdint>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;

void TimeRuler::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    const qreal dpr = p.device()->devicePixelRatioF();
    p.setFont(m_rulerFont);
    const QColor chrome = themes::color(themes::Role::song_view_timeline_chrome_background);
    p.fillRect(rect(), chrome);
    p.setPen(QPen(themes::color(themes::Role::song_view_separator), lyt::singlePixel()));
    p.drawLine(lyt::space(Space::Zero), rect().bottom(), width(), rect().bottom());

    const QRect area(m_geometry.plotOrigin, lyt::space(Space::Zero),
                     width() - m_geometry.plotOrigin, height());
    p.setClipRect(area);
    drawPreRoll(p, m_sv, area, m_geometry.plotOrigin, chrome);

    // Loop band, time-selection band, and edit cursor: drawOverlays
    // paints them only from loaded song state.
    drawOverlays(p, m_sv, area, m_geometry.plotOrigin, true);

    const qreal physicalPixel = logicalPhysicalPixel(dpr);
    const qreal roundingMargin = physicalPixel / 2.0;
    const double t0 =
        std::max(0.0, m_sv->tickAtContentX(area.left() - m_geometry.plotOrigin - roundingMargin));
    const double t1 = m_sv->tickAtContentX(area.x() + area.width() - physicalPixel -
                                           m_geometry.plotOrigin + roundingMargin) +
                      1;
    const auto indicatorColor = gridLineColor();
    // Beat labels recede a step past secondary text: blended a quarter of
    // the way into the ruler chrome so they read as texture next to the
    // bar numbers, in every theme.
    const QColor secondary = themes::color(themes::Role::song_view_secondary_text);
    const auto recede = [&](int fg, int bg) { return (191 * fg + 64 * bg + 127) / 255; };
    const QColor textColor(recede(secondary.red(), chrome.red()),
                           recede(secondary.green(), chrome.green()),
                           recede(secondary.blue(), chrome.blue()));

    const QRect ticks = tickRow();
    const int tickBottom = ticks.bottom();
    const QFontMetrics tickMetrics(p.font());
    const QFontMetrics beatMetrics(m_beatFont);
    const int tickBaseline = ticks.top() + tickMetrics.ascent();
    const auto barCapWidth = lyt::space(Space::Half);
    const auto indicatorRise = lyt::space(Space::Half);
    const auto labelGap = lyt::singlePixel();
    const auto beatDetailReserve = lyt::space(Space::Two);
    const bool drawBeatTicks = m_sv->pxPerBeat() >= m_geometry.timelineDetailMinimumPixelsPerBeat;

    // Short sub-beat ticks at the snap grid, mirroring the roll's grid.
    p.setPen(indicatorColor);
    forEachSubGridLine(
        m_sv, t0, t1, m_geometry.timelineDetailMinimumPixelsPerBeat, [&](uint64_t tick, int level) {
            const qreal x = m_sv->displayX(double(tick), m_geometry.plotOrigin, dpr);
            const int tickHeight = level == 1 ? lyt::space(Space::Half) : lyt::singlePixel();
            p.drawLine(QLineF(x, tickBottom - tickHeight + lyt::singlePixel(), x, tickBottom));
        });

    // Bar numbers are the primary labels; the in-between beats only earn
    // "bar.beat" labels once a beat spans several label-widths, so the
    // ruler stays sparse until the zoom genuinely has room for detail.
    // One decision per paint, sized to the widest label in view, so a
    // ruler never shows some beat labels while suppressing others.
    const QColor barTextColor = themes::color(themes::Role::song_view_primary_text);
    int widestDetailWidth = 0;
    m_sv->forEachGridLine(
        uint64_t(t0), uint64_t(t1), [&](uint64_t, bool, int barNumber, int beatNumber) {
            widestDetailWidth = std::max(
                widestDetailWidth, beatMetrics.horizontalAdvance(
                                       QStringLiteral("%1.%2").arg(barNumber).arg(beatNumber)));
        });
    const bool showBeatLabels = m_sv->pxPerBeat() >= m_geometry.timeRulerBeatLabelZoomFactor *
                                                         (barCapWidth + 2 * labelGap +
                                                          beatDetailReserve + widestDetailWidth);
    qreal lastLabelRight = area.left() - labelGap;
    m_sv->forEachGridLine(
        uint64_t(t0), uint64_t(t1), [&](uint64_t tick, bool isBar, int barNumber, int beatNumber) {
            const qreal x = m_sv->displayX(double(tick), m_geometry.plotOrigin, dpr);
            const auto detailedLabel = QStringLiteral("%1.%2").arg(barNumber).arg(beatNumber);
            if (!isBar && !showBeatLabels) {
                if (drawBeatTicks) {
                    p.setPen(indicatorColor);
                    p.drawLine(QLineF(x, ticks.center().y() - indicatorRise, x, tickBottom));
                }
                return;
            }
            const auto label = isBar ? QString::number(barNumber) : detailedLabel;
            const int labelWidth = (isBar ? tickMetrics : beatMetrics).horizontalAdvance(label);
            const qreal labelX = x + barCapWidth;
            if (labelX < lastLabelRight + labelGap) {
                if (!isBar && drawBeatTicks) {
                    p.setPen(indicatorColor);
                    p.drawLine(QLineF(x, ticks.center().y() - indicatorRise, x, tickBottom));
                }
                return;
            }
            p.setPen(indicatorColor);
            if (isBar) {
                const int indicatorTop = ticks.top() - indicatorRise;
                p.drawLine(QLineF(x, indicatorTop, x, tickBottom));
                p.drawLine(QLineF(x, indicatorTop, x + barCapWidth, indicatorTop));
            } else {
                p.drawLine(QLineF(x, ticks.center().y() - indicatorRise, x, tickBottom));
            }
            p.setPen(isBar ? barTextColor : textColor);
            p.setFont(isBar ? m_rulerFont : m_beatFont);
            p.drawText(QPointF(labelX, tickBaseline), label);
            p.setFont(m_rulerFont);
            lastLabelRight = labelX + labelWidth;
        });

    p.setFont(m_boldRulerFont);

    const QRect markers = markerRow();
    const int markerBaseline = textBaseline(markers, p.fontMetrics());

    // Time-signature chips in the marker row; the axis synthesizes the
    // opening 4/4 while no 0x58 meta governs the opening bars.
    for (const SigChip &chip : sigChips()) {
        if (chip.x > area.right() || chip.labelX + chip.labelW < area.left())
            continue;
        p.setPen(palette().color(chip.implicit ? QPalette::PlaceholderText : QPalette::WindowText));
        p.drawLine(QLineF(chip.x, markers.top(), chip.x, markers.bottom()));
        if (chip.labelW > 0)
            p.drawText(QPointF(chip.labelX, markerBaseline),
                       timeSigLabel(chip.numerator, chip.denomPow2));
    }

    // Loaded-song overlays: loop bracket glyphs, the marker /
    // time-signature drag preview, and time-selection edge handles.
    if (!m_sv->timeline())
        return;
    const TimeAxis &axis = m_sv->timeAxis();

    // Loop bracket glyphs above the band edges.
    p.setPen(loopEdge());
    if (axis.loopStartTick() != UINT64_MAX) {
        const qreal x = m_sv->displayX(double(axis.loopStartTick()), m_geometry.plotOrigin, dpr) +
                        lyt::space(Space::Half);
        p.drawText(QPointF(x, markerBaseline), QStringLiteral("["));
    }
    if (axis.loopEndTick() != UINT64_MAX) {
        const qreal x = m_sv->displayX(double(axis.loopEndTick()), m_geometry.plotOrigin, dpr) +
                        lyt::space(Space::Half);
        p.drawText(QPointF(x, markerBaseline), QStringLiteral("]"));
    }

    // Marker / time-signature drag preview.
    const auto markerStroke = lyt::space(Space::Half);
    if (m_dragMarker >= 0 || m_dragTimeSig) {
        const qreal x = m_sv->displayX(double(m_dragTick), m_geometry.plotOrigin, dpr);
        p.setPen(QPen(m_dragMarker >= 0 ? loopEdge() : palette().color(QPalette::WindowText),
                      markerStroke));
        p.drawLine(QLineF(x, lyt::space(Space::Zero), x, height()));
    }

    // Time-selection edge handles (the 1px band edges come from
    // drawOverlays); the marker row is their grab zone, while the tick
    // row stays scrub territory.
    const auto &tsel = m_sv->selectionModel().timeSelection();
    if (tsel.active()) {
        p.setPen(QPen(themes::color(themes::Role::song_view_selection_edge), markerStroke));
        const qreal sx0 = m_sv->displayX(double(tsel.startTick), m_geometry.plotOrigin, dpr);
        const qreal sx1 = m_sv->displayX(double(tsel.endTick), m_geometry.plotOrigin, dpr);
        p.drawLine(QLineF(sx0, markers.top(), sx0, markers.bottom()));
        p.drawLine(QLineF(sx1, markers.top(), sx1, markers.bottom()));
    }
}

} // namespace songview
