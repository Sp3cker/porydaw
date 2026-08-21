#include "ui/editordrawer/voicechangelane.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

#include <QAction>
#include <QFontMetrics>
#include <QMouseEvent>
#include <QPainter>
#include <QPen>
#include <QRegion>
#include <vector>

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "ui/contextmenu.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/layout.h"
#include "ui/m4asemantics.h"
#include "ui/theme/themeruntime.h"
#include "ui/theme/trackidentitycolors.h"
#include "ui/typography.h"

bool VoiceChangeLane::voiceMarkerAt(const AutomationCanvas &area, qreal x,
                                    const AutomationGeometry &geometry, DocLanePoint *out) const
{
    if (!m_page || !m_page->document() || m_engineTrack < 0 || !out)
        return false;
    const auto points = m_page->document()->lanePoints(m_engineTrack, DOC_CC_VOICE);
    const qreal dpr = area.devicePixelRatioF();
    const DocLanePoint *marker = nullptr;
    qreal distance = geometry.deleteTimeRadius + 1;
    for (const auto &point : points) {
        const qreal candidate =
            std::abs(m_page->displayX(point.tick, geometry.plotOrigin, dpr) - x);
        if (candidate <= geometry.deleteTimeRadius && (!marker || candidate <= distance)) {
            marker = &point;
            distance = candidate;
        }
    }
    if (!marker)
        return false;
    *out = *marker;
    return true;
}

VoiceChangeLane::VoiceChangeLane(AutomationPage *page) noexcept : m_page(page) {}

void VoiceChangeLane::invalidateFontCache()
{
    m_hoverLabelFontValid = false;
}

void VoiceChangeLane::ensureHoverLabelFontCache(const QFont &font)
{
    if (m_hoverLabelFontValid)
        return;
    m_hoverLabelFont = typography::noteName(font);
    m_hoverLabelMetrics = QFontMetrics(m_hoverLabelFont);
    m_hoverLabelFontValid = true;
}

void VoiceChangeLane::rebuild(int engineTrack, int width, int top,
                              const AutomationGeometry &geometry)
{
    m_engineTrack = engineTrack;
    m_changeCount = -1;
    m_secondary.clear();
    m_hoverActive = false;
    m_hoverX = 0;
    m_hoverTick = 0;
    m_hoverLabel.clear();
    m_hoverLabelRect = {};
    m_hoverLabelBounds = {};
    m_hoverDirtyBounds = {};
    if (engineTrack < 0) {
        m_bounds = {};
        return;
    }
    const int requestedHeight = m_page && m_page->m_viewState.laneHeight > 0
                                    ? m_page->m_viewState.laneHeight
                                    : geometry.rowDefaultHeight;
    m_bounds =
        QRect(layout::space(layout::Space::Zero), top, width,
              std::clamp(requestedHeight, geometry.rowMinimumHeight, geometry.rowMaximumHeight));
}

void VoiceChangeLane::cancel()
{
    m_hoverActive = false;
    m_hoverX = 0;
    m_hoverTick = 0;
    m_hoverLabel.clear();
    m_hoverLabelRect = {};
    m_hoverLabelBounds = {};
    m_hoverDirtyBounds = {};
}

void VoiceChangeLane::clearHover(AutomationCanvas &area)
{
    if (!m_hoverActive && m_hoverDirtyBounds.isEmpty())
        return;
    const QRect previousBounds = m_hoverDirtyBounds;
    m_hoverActive = false;
    m_hoverX = 0;
    m_hoverTick = 0;
    m_hoverLabel.clear();
    m_hoverLabelRect = {};
    m_hoverLabelBounds = {};
    m_hoverDirtyBounds = {};
    if (!previousBounds.isEmpty())
        area.invalidateContent(previousBounds);
}

bool VoiceChangeLane::contains(const QPoint &position) const noexcept
{
    return m_bounds.contains(position);
}

const VoiceChangeLane::VoicePaintText &VoiceChangeLane::paintTextFor(int program) const
{
    static const VoicePaintText invalid;
    if (program < 0 || program >= VOICEGROUP_SIZE)
        return invalid;
    auto &cache = m_paintTexts[std::size_t(program)];
    const auto *voicegroup = m_page ? m_page->voicegroup() : nullptr;
    const int type = voicegroup ? int(voicegroup->voices[program].type) : -1;
    const char *sourceName = voicegroup ? voicegroup->voiceNames[program] : "";
    if (cache.group == voicegroup && cache.type == type &&
        std::strncmp(cache.sourceName.data(), sourceName, VG_VOICE_NAME_LEN) == 0 &&
        !cache.label.isEmpty())
        return cache;
    cache.group = voicegroup;
    cache.type = type;
    std::strncpy(cache.sourceName.data(), sourceName, cache.sourceName.size() - 1);
    cache.sourceName.back() = '\0';
    QString name;
    QString typeName;
    if (voicegroup) {
        name = QString::fromUtf8(cache.sourceName.data()).trimmed();
        typeName = m4aVoiceTypeName(voicegroup->voices[program].type);
    }
    const QString shortName = name.isEmpty()
                                  ? (typeName.isEmpty() ? AutomationCanvas::tr("Voice") : typeName)
                                  : QStringLiteral("%1 (%2)").arg(name, typeName);
    cache.label = QStringLiteral("%1 %2").arg(program, 3, 10, QLatin1Char('0')).arg(shortName);
    cache.hoverLabel =
        QStringLiteral("→ %1 %2").arg(program, 3, 10, QLatin1Char('0')).arg(shortName);
    return cache;
}

int VoiceChangeLane::voiceSlotAt(uint64_t tick) const
{
    if (!m_page || m_engineTrack < 0 || m_engineTrack >= 16)
        return -1;
    const auto *timeline = m_page->timeline();
    if (!timeline || !m_page->voicegroup())
        return -1;
    int program = timeline->tracks[m_engineTrack].firstProgram;
    for (const VoiceChange &change : m_page->model().voices) {
        if (change.track != m_engineTrack)
            continue;
        if (change.tick > tick)
            break;
        program = change.program;
    }
    return program;
}

QRect VoiceChangeLane::plotRect(const AutomationGeometry &geometry) const
{
    return QRect(geometry.plotOrigin, m_bounds.top(),
                 std::max(0, m_bounds.width() - geometry.plotOrigin), m_bounds.height());
}

bool VoiceChangeLane::mousePress(AutomationCanvas &area, QMouseEvent *event,
                                 const AutomationGeometry &geometry)
{
    if (event->button() == Qt::RightButton) {
        if (event->position().x() >= geometry.plotOrigin)
            showContextMenu(area, event->globalPosition().toPoint(), geometry);
        return true;
    }
    if (event->button() != Qt::LeftButton)
        return true;
    if (event->position().x() < geometry.plotOrigin)
        return true;
    return true;
}

bool VoiceChangeLane::mouseDoubleClick(AutomationCanvas &area, QMouseEvent *event,
                                       const AutomationGeometry &geometry)
{
    if (event->button() != Qt::LeftButton || event->position().x() < geometry.plotOrigin)
        return true;
    showPicker(area, event->globalPosition().toPoint(), geometry);
    return true;
}

void VoiceChangeLane::showPicker(AutomationCanvas &area, const QPoint &globalPosition,
                                 const AutomationGeometry &geometry)
{
    if (!m_page || !m_page->document() || m_engineTrack < 0)
        return;
    const int track = m_engineTrack;
    const qreal x = area.mapFromGlobal(globalPosition).x();
    const auto points = m_page->document()->lanePoints(track, DOC_CC_VOICE);
    DocLanePoint markerPoint;
    const DocLanePoint *marker =
        voiceMarkerAt(area, x, geometry, &markerPoint) ? &markerPoint : nullptr;
    const double rawTick = std::max(
        0.0, m_page->tickAtContentX(std::max(qreal(geometry.plotOrigin), x) - geometry.plotOrigin));
    const uint64_t tick = marker ? marker->tick : m_page->snapTick(rawTick, false);
    int current = marker ? marker->value : 0;
    if (!marker)
        current = voiceSlotAt(tick);
    if (!marker) {
        for (const auto &point : points) {
            if (point.tick > tick)
                break;
            current = point.value;
        }
    }
    int selectedVoice = 0;
    if (!m_page->pickVoice(marker ? AutomationCanvas::tr("Change voice")
                                  : AutomationCanvas::tr("Insert voice change"),
                           std::max(0, current), &selectedVoice))
        return;
    DocLanePoint existing;
    bool changed = false;
    if (m_page->document()->findLanePoint(track, DOC_CC_VOICE, tick, &existing)) {
        if (existing.value != selectedVoice) {
            m_page->document()->moveLanePoints(
                {{track, DOC_CC_VOICE, existing, tick, selectedVoice}});
            changed = true;
        }
    } else {
        m_page->document()->addLanePoint(track, DOC_CC_VOICE, tick, selectedVoice);
        changed = true;
    }
    if (changed)
        m_page->requestRefresh();
}

void VoiceChangeLane::showContextMenu(AutomationCanvas &area, const QPoint &globalPosition,
                                      const AutomationGeometry &geometry)
{
    if (!m_page || !m_page->document() || m_engineTrack < 0)
        return;
    const int track = m_engineTrack;
    const qreal x = area.mapFromGlobal(globalPosition).x();
    DocLanePoint markerPoint;
    const bool hasMarker = voiceMarkerAt(area, x, geometry, &markerPoint);
    ui::ContextMenu menu(&area);
    QAction *change = nullptr;
    QAction *insert = nullptr;
    QAction *remove = nullptr;
    if (hasMarker) {
        change = menu.addAction(AutomationCanvas::tr("Change voice"));
        remove = menu.addAction(AutomationCanvas::tr("Delete"));
    } else {
        insert = menu.addAction(AutomationCanvas::tr("Insert voice change"));
    }
    QAction *chosen = menu.exec(globalPosition);
    if (!chosen)
        return;
    if (chosen == change || chosen == insert) {
        showPicker(area, globalPosition, geometry);
        return;
    }
    if (chosen == remove) {
        m_page->document()->deleteLanePoints(track, DOC_CC_VOICE, {markerPoint});
        m_page->requestRefresh();
    }
}

void VoiceChangeLane::updateHover(AutomationCanvas &area, const AutomationGeometry &geometry,
                                  qreal x, int y)
{
    Q_UNUSED(y);
    if (!m_page || !m_page->ready() || m_bounds.isEmpty() || x < geometry.plotOrigin) {
        clearHover(area);
        return;
    }
    const qreal dpr = area.devicePixelRatioF();
    const double tick = std::max(
        0.0, m_page->tickAtContentX(std::max(qreal(geometry.plotOrigin), x) - geometry.plotOrigin));
    const uint64_t snapped = m_page->snapTick(tick, true);
    DocLanePoint markerPoint;
    const bool atMarker = voiceMarkerAt(area, x, geometry, &markerPoint);
    const uint64_t hoverTick = atMarker ? markerPoint.tick : snapped;
    const qreal lineX = m_page->displayX(hoverTick, geometry.plotOrigin, dpr);
    QString hoverLabel;
    if (!voiceMarkerAt(area, lineX, geometry, &markerPoint)) {
        const int slot = voiceSlotAt(hoverTick);
        if (slot >= 0 && slot < VOICEGROUP_SIZE)
            hoverLabel = paintTextFor(slot).hoverLabel;
    }
    const QRect plot = plotRect(geometry);
    QRectF labelRect;
    QRect labelBounds;
    if (!hoverLabel.isEmpty()) {
        ensureHoverLabelFontCache(area.font());
        labelRect = QRectF(lineX + layout::space(layout::Space::One), plot.top(),
                           std::max<qreal>(0, plot.right() - lineX), plot.height());
        labelBounds = m_hoverLabelMetrics.boundingRect(
            labelRect.toAlignedRect(), Qt::AlignLeft | Qt::AlignVCenter, hoverLabel);
    }
    if (m_hoverActive && m_hoverX == lineX && m_hoverTick == hoverTick &&
        m_hoverLabel == hoverLabel && m_hoverLabelRect == labelRect &&
        m_hoverLabelBounds == labelBounds)
        return;
    const QRect previousBounds = m_hoverDirtyBounds;
    m_hoverActive = true;
    m_hoverX = lineX;
    m_hoverTick = hoverTick;
    m_hoverLabel = std::move(hoverLabel);
    m_hoverLabelRect = labelRect;
    m_hoverLabelBounds = labelBounds;
    const int paintPadding = geometry.hoverPaintPadding;
    QRect dirty =
        QRectF(lineX - paintPadding, plot.top(), 2 * paintPadding, plot.height()).toAlignedRect();
    if (!m_hoverLabel.isEmpty())
        dirty = dirty.united(
            m_hoverLabelBounds.adjusted(-paintPadding, -paintPadding, paintPadding, paintPadding));
    m_hoverDirtyBounds = dirty.intersected(area.rect());
    QRegion region(previousBounds);
    region += m_hoverDirtyBounds;
    if (!region.isEmpty())
        area.invalidateContent(region);
}

void VoiceChangeLane::paint(QPainter &painter, AutomationCanvas &area,
                            const AutomationGeometry &geometry, const QRect &labelGutter,
                            const QFont &titleFont, const QFont &captionFont,
                            const layout::TwoLineTextLayout &textLayout, qreal captionHeight)
{
    if (m_bounds.isEmpty() || !m_page || !m_page->ready() || !m_page->timeline())
        return;
    const QRect bounds = m_bounds;
    const QRect plot = plotRect(geometry);
    const QRect textBounds(labelGutter.x(), bounds.top(), labelGutter.width(), bounds.height());
    const auto textBoxes = textLayout.align(textBounds, layout::VerticalAlignment::Center);
    painter.save();
    painter.setClipRect(bounds, Qt::IntersectClip);
    painter.setPen(themes::color(themes::Role::song_view_separator));
    painter.drawLine(bounds.left(), bounds.bottom(), bounds.right(), bounds.bottom());
    painter.save();
    painter.setClipRect(textBoxes.primary.united(textBoxes.secondary), Qt::IntersectClip);
    painter.setFont(titleFont);
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(textBoxes.primary, Qt::AlignLeft | Qt::AlignVCenter,
                     AutomationCanvas::tr("Voice"));
    painter.setFont(captionFont);
    if (m_page->document()) {
        const int changeCount = int(std::count_if(
            m_page->model().voices.cbegin(), m_page->model().voices.cend(),
            [this](const VoiceChange &change) { return change.track == m_engineTrack; }));
        if (m_changeCount != changeCount) {
            m_secondary = changeCount ? AutomationCanvas::tr("%n change(s) · click to edit",
                                                             nullptr, changeCount)
                                      : AutomationCanvas::tr("no voice set · click to add");
            m_changeCount = changeCount;
        }
        painter.setPen(themes::color(themes::Role::song_view_secondary_text));
        painter.drawText(textBoxes.secondary, Qt::AlignLeft | Qt::AlignVCenter, m_secondary);
    }
    painter.restore();
    painter.setClipRect(plot, Qt::IntersectClip);
    const qreal dpr = painter.device()->devicePixelRatioF();
    const bool hostPaintedGrid = m_page->paintGrid(painter, plot, geometry.plotOrigin);
    if (!hostPaintedGrid) {
        const uint64_t length = m_page->timeline()->lengthTicks;
        const double pxPerTick =
            m_page->pxPerBeat() / double(std::max(1u, m_page->timeline()->ticksPerBeat));
        if (m_page->ready()) {
            QColor subdivision = themes::color(themes::Role::song_view_grid);
            subdivision.setAlpha((subdivision.alpha() * 125 + 127) / 255);
            painter.setPen(QPen(subdivision, layout::singlePixel()));
            const double firstVisibleTick =
                std::max(0.0, m_page->tickAtContentX(layout::space(layout::Space::Zero)));
            for (uint64_t tick = m_page->snapTick(firstVisibleTick, false);;) {
                const auto state = m_page->gridState(tick, false);
                const qreal x = m_page->displayX(tick, geometry.plotOrigin, dpr);
                if (x > plot.right())
                    break;
                if (state.snapTicks < state.gridTicks &&
                    pxPerTick * double(state.snapTicks) >= geometry.gridMinimumCellWidth &&
                    x >= plot.left())
                    painter.drawLine(QPointF(x, plot.top()), QPointF(x, plot.bottom()));
                if (tick >= length)
                    break;
                const uint64_t next = m_page->snapTick(
                    double(tick) + double(std::max<uint64_t>(1, state.snapTicks)) * 0.75, false);
                if (next <= tick)
                    break;
                tick = std::min(next, length);
            }
        }
        AutomationCanvas::paintPlainGridFallback(painter, plot, *m_page, geometry.plotOrigin, dpr);
    }
    painter.setFont(captionFont);
    const int track = m_engineTrack;
    const auto &live = m_page->liveState();
    const double contextTick =
        live.playback.playing ? live.playback.playheadTick : double(live.editCursorTick);
    const int contextSlot =
        voiceSlotAt(static_cast<uint64_t>(std::round(std::max(0.0, contextTick))));
    const QString contextText = contextSlot >= 0 && contextSlot < VOICEGROUP_SIZE
                                    ? paintTextFor(contextSlot).label
                                    : AutomationCanvas::tr("No voice");
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    painter.drawText(
        plot.adjusted(layout::space(layout::Space::One), layout::space(layout::Space::Zero),
                      -layout::space(layout::Space::One), layout::space(layout::Space::Zero)),
        Qt::AlignRight | Qt::AlignVCenter, contextText);
    const qreal pad = layout::space(layout::Space::One);
    const qreal gap =
        std::max<qreal>(geometry.hoverPaintPadding, layout::space(layout::Space::One));
    const QFontMetricsF fm(captionFont);
    const qreal labelH = captionHeight;
    const qreal centerY = plot.center().y() - labelH / 2.0;
    const qreal stairStep = std::min<qreal>(layout::space(layout::Space::Four),
                                            (plot.height() - labelH - 2 * pad) / 2.0);
    const bool canStair = stairStep > 1.0;
    auto displayX = [&](uint32_t tick) { return m_page->displayX(tick, geometry.plotOrigin, dpr); };
    struct VoiceLabelLayout {
        QString text;
        QRectF rect;
        bool offscreen = true;
    };
    std::vector<VoiceLabelLayout> layouts;
    layouts.reserve(m_page->model().voices.size());
    qreal lastXEnd = -std::numeric_limits<qreal>::infinity();
    bool stairUp = true;
    for (const auto &change : m_page->model().voices) {
        if (change.track != track)
            continue;
        const qreal labelX = displayX(change.tick) + pad;
        QString text = paintTextFor(change.program).label;
        if (text.isEmpty())
            text = AutomationCanvas::tr("No voice");
        const qreal maxW = std::max<qreal>(0, plot.right() - labelX);
        if (fm.horizontalAdvance(text) > maxW && maxW > 0)
            text = fm.elidedText(text, Qt::ElideRight, int(std::floor(maxW)));
        const qreal w = std::min(fm.horizontalAdvance(text), maxW);
        const bool offscreen = labelX + w < plot.left() || labelX > plot.right() || w <= 0;
        qreal labelY = centerY;
        if (!offscreen) {
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
        layouts.push_back({std::move(text), QRectF(labelX, labelY, w, labelH), offscreen});
    }
    const QColor trackColor = themes::trackIdentityColor(track % themes::trackIdentityColorCount);
    const qreal markerW = layout::singlePixel() + layout::singlePixel();
    for (const auto &lt : layouts) {
        const qreal markerX = lt.rect.left() - pad;
        painter.setPen(QPen(trackColor, markerW));
        painter.drawLine(QPointF(markerX, plot.top() + pad), QPointF(markerX, plot.bottom() - pad));
    }
    const QColor primary = themes::color(themes::Role::song_view_primary_text);
    painter.setPen(primary);
    for (const auto &lt : layouts)
        if (!lt.offscreen)
            painter.drawText(lt.rect, Qt::AlignLeft | Qt::AlignVCenter, lt.text);
    if (m_hoverActive && !m_hoverLabel.isEmpty() && !m_hoverLabelFontValid) {
        ensureHoverLabelFontCache(area.font());
        m_hoverLabelBounds = m_hoverLabelMetrics.boundingRect(
            m_hoverLabelRect.toAlignedRect(), Qt::AlignLeft | Qt::AlignVCenter, m_hoverLabel);
        const int paintPadding = geometry.hoverPaintPadding;
        QRect dirty = QRectF(m_hoverX - paintPadding, plot.top(), 2 * paintPadding, plot.height())
                          .toAlignedRect();
        dirty = dirty.united(
            m_hoverLabelBounds.adjusted(-paintPadding, -paintPadding, paintPadding, paintPadding));
        m_hoverDirtyBounds = dirty.intersected(area.rect());
    }
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
    const qreal cursorX =
        m_page->displayX(m_page->liveState().editCursorTick, geometry.plotOrigin, dpr);
    AutomationCanvas::paintEditCursor(painter, plot, cursorX);
    painter.restore();
    Q_UNUSED(area);
}
