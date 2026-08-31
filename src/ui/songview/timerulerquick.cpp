#include "ui/songview/timeruler.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/theme/themeruntime.h"

#include <QFontMetrics>
#include <QPalette>

#include <algorithm>
#include <cstdint>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
namespace {

void resetLayer(TimelineQuickScene &scene, TimelineQuickLayer layer)
{
    TimelineQuickLayerData &data = scene.layer(layer);
    data.rects.clear();
    data.triangles.clear();
    ++data.revision;
}

void addRect(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
             const QColor &color, const QRectF &clip)
{
    const QRectF clipped = rect.normalized().intersected(clip);
    if (clipped.isEmpty())
        return;
    scene.layer(layer).rects.push_back({clipped, color, color, color, color});
}

void addHorizontalGradient(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                           const QColor &left, const QColor &right, const QRectF &clip)
{
    const QRectF clipped = rect.normalized().intersected(clip);
    if (clipped.isEmpty())
        return;
    const qreal denominator = std::max<qreal>(rect.width(), 1.0);
    const auto sample = [&](const QColor &first, const QColor &last, qreal x) {
        const qreal t = std::clamp((x - rect.left()) / denominator, 0.0, 1.0);
        return QColor::fromRgbF(first.redF() + (last.redF() - first.redF()) * t,
                                first.greenF() + (last.greenF() - first.greenF()) * t,
                                first.blueF() + (last.blueF() - first.blueF()) * t,
                                first.alphaF() + (last.alphaF() - first.alphaF()) * t);
    };
    const QColor clippedLeft = sample(left, right, clipped.left());
    const QColor clippedRight = sample(left, right, clipped.right());
    scene.layer(layer).rects.push_back(
        {clipped, clippedLeft, clippedRight, clippedRight, clippedLeft});
}

void addHorizontalLine(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x0, qreal x1,
                       qreal y, qreal width, const QColor &color, const QRectF &clip)
{
    addRect(scene, layer, QRectF(x0, y - width / 2.0, x1 - x0, width), color, clip);
}

void addVerticalLine(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x, qreal y0,
                     qreal y1, qreal width, const QColor &color, const QRectF &clip)
{
    addRect(scene, layer, QRectF(x - width / 2.0, y0, width, y1 - y0), color, clip);
}

void addDashedVertical(TimelineQuickScene &scene, TimelineQuickLayer layer, qreal x, qreal y0,
                       qreal y1, qreal width, qreal dash, qreal gap, const QColor &color,
                       const QRectF &clip)
{
    for (qreal y = y0; y < y1; y += dash + gap)
        addVerticalLine(scene, layer, x, y, std::min(y + dash, y1), width, color, clip);
}

void appendTextRecord(std::vector<TimelineQuickTextModel::Record> &records, quint64 ordinal,
                      const QRectF &rect, const QString &text, const QFont &font,
                      const QColor &color)
{
    records.push_back({{TimelineQuickTextKeyKind::Ruler, {}, ordinal},
                       rect,
                       text,
                       color,
                       font,
                       Qt::AlignLeft,
                       Qt::AlignVCenter});
}

} // namespace

void TimeRuler::rebuildQuickScene(TimelineQuickScene &scene)
{
    constexpr TimelineQuickLayer chromeLayer = TimelineQuickLayer::RulerChrome;
    constexpr TimelineQuickLayer marksLayer = TimelineQuickLayer::RulerMarks;
    resetLayer(scene, chromeLayer);
    resetLayer(scene, marksLayer);

    const qreal dpr = devicePixelRatioF();
    const qreal physicalPixel = detail::logicalPhysicalPixel(dpr);
    const QRectF full(0, 0, width(), height());
    const QColor chrome = themes::color(themes::Role::song_view_timeline_chrome_background);
    addRect(scene, chromeLayer, full, chrome, full);
    addHorizontalLine(scene, chromeLayer, 0, width(), height() - lyt::singlePixel() / 2.0,
                      lyt::singlePixel(), themes::color(themes::Role::song_view_separator), full);

    const QRectF area(m_geometry.plotOrigin, 0, std::max(0, width() - m_geometry.plotOrigin),
                      height());
    const qreal tickZero = m_sv->displayX(0.0, m_geometry.plotOrigin, dpr);
    if (tickZero > area.left()) {
        addRect(scene, chromeLayer,
                QRectF(area.left(), area.top(), tickZero - area.left(), area.height()),
                mixTowardOklab(chrome, detail::gridLineColor(), 0.15), area);
    }

    if (const MidiTimeline *timeline = m_sv->timeline()) {
        const auto &selection = m_sv->selectionModel().timeSelection();
        if (selection.active()) {
            const qreal x0 =
                m_sv->displayX(double(selection.startTick), m_geometry.plotOrigin, dpr);
            const qreal x1 = m_sv->displayX(double(selection.endTick), m_geometry.plotOrigin, dpr);
            if (x1 > area.left() && x0 < area.right()) {
                QColor fill = themes::color(themes::Role::song_view_selection_fill);
                fill.setAlpha(30);
                addRect(scene, chromeLayer, QRectF(x0, area.top(), x1 - x0, area.height()), fill,
                        area);
                const QColor edge = themes::color(themes::Role::song_view_selection_edge);
                addVerticalLine(scene, chromeLayer, x0, area.top(), area.bottom(),
                                lyt::singlePixel(), edge, area);
                addVerticalLine(scene, chromeLayer, x1, area.top(), area.bottom(),
                                lyt::singlePixel(), edge, area);
            }
        }

        const bool hasLoopStart = timeline->loopStartTick != UINT64_MAX;
        const bool hasLoopEnd = timeline->loopEndTick != UINT64_MAX;
        if (hasLoopStart || hasLoopEnd) {
            const qreal x0 = hasLoopStart ? m_sv->displayX(double(timeline->loopStartTick),
                                                           m_geometry.plotOrigin, dpr)
                                          : area.left();
            const qreal x1 = hasLoopEnd ? m_sv->displayX(double(timeline->loopEndTick),
                                                         m_geometry.plotOrigin, dpr)
                                        : area.right();
            if (x1 > area.left() && x0 < area.right()) {
                const qreal glowWidth = std::min<qreal>(lyt::space(Space::Eight), x1 - x0);
                QColor strong = detail::loopEdge();
                strong.setAlpha(150);
                QColor middle = strong;
                middle.setAlpha(18);
                QColor transparent = strong;
                transparent.setAlpha(0);
                if (hasLoopStart && glowWidth > 0) {
                    const qreal knee = glowWidth * 0.2;
                    addHorizontalGradient(scene, chromeLayer,
                                          QRectF(x0, area.top(), knee, area.height()), strong,
                                          middle, area);
                    addHorizontalGradient(
                        scene, chromeLayer,
                        QRectF(x0 + knee, area.top(), glowWidth - knee, area.height()), middle,
                        transparent, area);
                }
                if (hasLoopEnd && glowWidth > 0) {
                    const qreal knee = glowWidth * 0.2;
                    addHorizontalGradient(scene, chromeLayer,
                                          QRectF(x1 - knee, area.top(), knee, area.height()),
                                          middle, strong, area);
                    addHorizontalGradient(
                        scene, chromeLayer,
                        QRectF(x1 - glowWidth, area.top(), glowWidth - knee, area.height()),
                        transparent, middle, area);
                }
                if (hasLoopStart)
                    addVerticalLine(scene, chromeLayer, x0, area.top(), area.bottom(),
                                    lyt::singlePixel(), detail::loopEdge(), area);
                if (hasLoopEnd)
                    addVerticalLine(scene, chromeLayer, x1, area.top(), area.bottom(),
                                    lyt::singlePixel(), detail::loopEdge(), area);
            }
        }

        const qreal cursorX =
            m_sv->displayX(double(m_sv->editCursorTick()), m_geometry.plotOrigin, dpr);
        if (cursorX >= area.left() && cursorX <= area.right()) {
            addDashedVertical(scene, chromeLayer, cursorX, area.top(), area.bottom(),
                              lyt::singlePixel(), lyt::space(Space::One), lyt::space(Space::One),
                              themes::color(themes::Role::song_view_edit_cursor), area);
        }
    }

    const qreal roundingMargin = physicalPixel / 2.0;
    const double t0 =
        std::max(0.0, m_sv->tickAtContentX(area.left() - m_geometry.plotOrigin - roundingMargin));
    const double t1 = m_sv->tickAtContentX(area.x() + area.width() - physicalPixel -
                                           m_geometry.plotOrigin + roundingMargin) +
                      1;
    const QColor indicatorColor = detail::gridLineColor();
    const QColor secondary = themes::color(themes::Role::song_view_secondary_text);
    const auto recede = [](int foreground, int background) {
        return (191 * foreground + 64 * background + 127) / 255;
    };
    const QColor detailText(recede(secondary.red(), chrome.red()),
                            recede(secondary.green(), chrome.green()),
                            recede(secondary.blue(), chrome.blue()));
    const QRect ticks = tickRow();
    const int tickBottom = ticks.bottom();
    const QFontMetrics tickMetrics(m_rulerFont);
    const QFontMetrics beatMetrics(m_beatFont);
    const int tickBaseline = ticks.top() + tickMetrics.ascent();
    const int barCapWidth = lyt::space(Space::Half);
    const int indicatorRise = lyt::space(Space::Half);
    const int labelGap = lyt::singlePixel();
    const int beatDetailReserve = lyt::space(Space::Two);
    const bool drawBeatTicks = m_sv->pxPerBeat() >= m_geometry.timelineDetailMinimumPixelsPerBeat;

    detail::forEachSubGridLine(
        m_sv, t0, t1, m_geometry.timelineDetailMinimumPixelsPerBeat, [&](uint64_t tick, int level) {
            const qreal x = m_sv->displayX(double(tick), m_geometry.plotOrigin, dpr);
            const int tickHeight = level == 1 ? lyt::space(Space::Half) : lyt::singlePixel();
            addVerticalLine(scene, marksLayer, x, tickBottom - tickHeight + lyt::singlePixel(),
                            tickBottom, lyt::singlePixel(), indicatorColor, area);
        });

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
    std::vector<TimelineQuickTextModel::Record> labels;
    qreal lastLabelRight = area.left() - labelGap;
    m_sv->forEachGridLine(
        uint64_t(t0), uint64_t(t1), [&](uint64_t tick, bool isBar, int barNumber, int beatNumber) {
            const qreal x = m_sv->displayX(double(tick), m_geometry.plotOrigin, dpr);
            const QString detailLabel = QStringLiteral("%1.%2").arg(barNumber).arg(beatNumber);
            if (!isBar && !showBeatLabels) {
                if (drawBeatTicks) {
                    addVerticalLine(scene, marksLayer, x, ticks.center().y() - indicatorRise,
                                    tickBottom, lyt::singlePixel(), indicatorColor, area);
                }
                return;
            }
            const QString label = isBar ? QString::number(barNumber) : detailLabel;
            const QFont &font = isBar ? m_rulerFont : m_beatFont;
            const int labelWidth = (isBar ? tickMetrics : beatMetrics).horizontalAdvance(label);
            const qreal labelX = x + barCapWidth;
            if (labelX < lastLabelRight + labelGap) {
                if (!isBar && drawBeatTicks) {
                    addVerticalLine(scene, marksLayer, x, ticks.center().y() - indicatorRise,
                                    tickBottom, lyt::singlePixel(), indicatorColor, area);
                }
                return;
            }
            if (isBar) {
                const int indicatorTop = ticks.top() - indicatorRise;
                addVerticalLine(scene, marksLayer, x, indicatorTop, tickBottom, lyt::singlePixel(),
                                indicatorColor, area);
                addHorizontalLine(scene, marksLayer, x, x + barCapWidth, indicatorTop,
                                  lyt::singlePixel(), indicatorColor, area);
            } else {
                addVerticalLine(scene, marksLayer, x, ticks.center().y() - indicatorRise,
                                tickBottom, lyt::singlePixel(), indicatorColor, area);
            }
            const QFontMetrics metrics(font);
            appendTextRecord(
                labels, tick,
                QRectF(labelX, tickBaseline - metrics.ascent(), labelWidth, metrics.height()),
                label, font,
                isBar ? themes::color(themes::Role::song_view_primary_text) : detailText);
            lastLabelRight = labelX + labelWidth;
        });

    const QRect markers = markerRow();
    const QFontMetrics markerMetrics(m_boldRulerFont);
    const int markerBaseline = textBaseline(markers, markerMetrics);
    for (const SigChip &chip : sigChips()) {
        if (chip.x > area.right() || chip.labelX + chip.labelW < area.left())
            continue;
        const QColor color =
            palette().color(chip.implicit ? QPalette::PlaceholderText : QPalette::WindowText);
        addVerticalLine(scene, marksLayer, chip.x, markers.top(), markers.bottom(),
                        lyt::singlePixel(), color, area);
        if (chip.labelW > 0) {
            const QString label = detail::timeSigLabel(chip.numerator, chip.denomPow2);
            appendTextRecord(labels, (quint64(1) << 63) | chip.tick,
                             QRectF(chip.labelX, markerBaseline - markerMetrics.ascent(),
                                    chip.labelW, markerMetrics.height()),
                             label, m_boldRulerFont, color);
        }
    }

    if (m_sv->timeline()) {
        const TimeAxis &axis = m_sv->timeAxis();
        if (axis.loopStartTick() != UINT64_MAX) {
            const QString label = QStringLiteral("[");
            const qreal x =
                m_sv->displayX(double(axis.loopStartTick()), m_geometry.plotOrigin, dpr) +
                lyt::space(Space::Half);
            appendTextRecord(labels, (quint64(3) << 62),
                             QRectF(x, markerBaseline - markerMetrics.ascent(),
                                    markerMetrics.horizontalAdvance(label), markerMetrics.height()),
                             label, m_boldRulerFont, detail::loopEdge());
        }
        if (axis.loopEndTick() != UINT64_MAX) {
            const QString label = QStringLiteral("]");
            const qreal x = m_sv->displayX(double(axis.loopEndTick()), m_geometry.plotOrigin, dpr) +
                            lyt::space(Space::Half);
            appendTextRecord(labels, (quint64(3) << 62) | 1,
                             QRectF(x, markerBaseline - markerMetrics.ascent(),
                                    markerMetrics.horizontalAdvance(label), markerMetrics.height()),
                             label, m_boldRulerFont, detail::loopEdge());
        }
        const int markerStroke = lyt::space(Space::Half);
        if (m_dragMarker >= 0 || m_dragTimeSig) {
            const qreal x = m_sv->displayX(double(m_dragTick), m_geometry.plotOrigin, dpr);
            addVerticalLine(scene, marksLayer, x, 0, height(), markerStroke,
                            m_dragMarker >= 0 ? detail::loopEdge()
                                              : palette().color(QPalette::WindowText),
                            area);
        }
        const auto &selection = m_sv->selectionModel().timeSelection();
        if (selection.active()) {
            const QColor edge = themes::color(themes::Role::song_view_selection_edge);
            const qreal x0 =
                m_sv->displayX(double(selection.startTick), m_geometry.plotOrigin, dpr);
            const qreal x1 = m_sv->displayX(double(selection.endTick), m_geometry.plotOrigin, dpr);
            addVerticalLine(scene, marksLayer, x0, markers.top(), markers.bottom(), markerStroke,
                            edge, area);
            addVerticalLine(scene, marksLayer, x1, markers.top(), markers.bottom(), markerStroke,
                            edge, area);
        }
    }
    scene.setRulerTextRecords(labels);
}

} // namespace songview
