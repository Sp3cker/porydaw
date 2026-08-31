#include "ui/songview/otherstrip.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/theme/themeruntime.h"

#include <algorithm>
#include <array>
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

struct ClippedPolygon {
    std::array<QPointF, 6> points;
    int size = 0;
};

ClippedPolygon clipToVerticalEdge(const ClippedPolygon &input, qreal edge, bool keepRight)
{
    ClippedPolygon output;
    if (input.size == 0)
        return output;
    const auto inside = [edge, keepRight](const QPointF &point) {
        return keepRight ? point.x() >= edge : point.x() <= edge;
    };
    const auto intersection = [edge](const QPointF &from, const QPointF &to) {
        const qreal fraction = (edge - from.x()) / (to.x() - from.x());
        return QPointF(edge, from.y() + fraction * (to.y() - from.y()));
    };
    QPointF previous = input.points[static_cast<std::size_t>(input.size - 1)];
    bool previousInside = inside(previous);
    for (int i = 0; i < input.size; ++i) {
        const QPointF current = input.points[static_cast<std::size_t>(i)];
        const bool currentInside = inside(current);
        if (currentInside != previousInside)
            output.points[static_cast<std::size_t>(output.size++)] =
                intersection(previous, current);
        if (currentInside)
            output.points[static_cast<std::size_t>(output.size++)] = current;
        previous = current;
        previousInside = currentInside;
    }
    return output;
}

void addTriangle(TimelineQuickLayerData &layer, const QPointF &first, const QPointF &second,
                 const QPointF &third, const QColor &color, const QRectF &clip)
{
    ClippedPolygon polygon{{first, second, third}, 3};
    polygon = clipToVerticalEdge(polygon, clip.left(), true);
    polygon = clipToVerticalEdge(polygon, clip.right(), false);
    for (int i = 1; i + 1 < polygon.size; ++i) {
        layer.triangles.push_back({polygon.points[0], polygon.points[static_cast<std::size_t>(i)],
                                   polygon.points[static_cast<std::size_t>(i + 1)], color, color,
                                   color});
    }
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

void addEditCursor(TimelineQuickScene &scene, TimelineQuickLayer layer, const SongView &songView,
                   const QRectF &area, qreal origin, qreal dpr)
{
    if (!songView.timeline())
        return;
    const qreal cursorX = songView.displayX(double(songView.editCursorTick()), origin, dpr);
    if (cursorX >= area.left() && cursorX <= area.right()) {
        addDashedVertical(scene, layer, cursorX, area.top(), area.bottom(), lyt::singlePixel(),
                          lyt::space(Space::One), lyt::space(Space::One),
                          themes::color(themes::Role::song_view_edit_cursor), area);
    }
}

} // namespace

void OtherStrip::rebuildQuickScene(TimelineQuickScene &scene)
{
    constexpr TimelineQuickLayer chromeLayer = TimelineQuickLayer::OtherEventsChrome;
    constexpr TimelineQuickLayer markersLayer = TimelineQuickLayer::OtherEventsMarkers;
    resetLayer(scene, chromeLayer);
    resetLayer(scene, markersLayer);

    const qreal dpr = devicePixelRatioF();
    const QRectF full(0, 0, width(), height());
    const QColor chrome = themes::color(themes::Role::song_view_timeline_chrome_background);
    addRect(scene, chromeLayer, full, chrome, full);
    addRect(scene, chromeLayer, QRectF(0, 0, width(), lyt::singlePixel()),
            themes::color(themes::Role::song_view_separator), full);

    const QRectF area(m_geometry.plotOrigin, 0, std::max(0, width() - m_geometry.plotOrigin),
                      height());
    const SongViewModel &model = m_sv->model();
    const int textInset = lyt::space(Space::Two);
    std::vector<TimelineQuickTextModel::Record> labels;
    labels.push_back({{TimelineQuickTextKeyKind::OtherEvents, {}, 0},
                      QRectF(textInset, 0, m_geometry.plotOrigin - 2 * textInset, height()),
                      SongView::tr("Other events (%1)").arg(model.strip.size()),
                      themes::color(themes::Role::song_view_primary_text),
                      font(),
                      Qt::AlignLeft,
                      Qt::AlignVCenter});
    scene.setOtherEventsTextRecords(labels);
    if (!m_sv->timeline())
        return;

    const qreal tickZero = m_sv->displayX(0.0, m_geometry.plotOrigin, dpr);
    if (tickZero > area.left()) {
        addRect(scene, chromeLayer,
                QRectF(area.left(), area.top(), tickZero - area.left(), area.height()),
                mixTowardOklab(chrome, detail::gridLineColor(), 0.15), area);
    }
    addEditCursor(scene, chromeLayer, *m_sv, area, m_geometry.plotOrigin, dpr);

    const int markerY = height() / 2;
    for (const StripItem &item : model.strip) {
        const qreal x = m_sv->displayX(double(item.tick), m_geometry.plotOrigin, dpr);
        if (x < area.left() - m_geometry.otherEventHitSlop ||
            x > area.right() + m_geometry.otherEventHitSlop) {
            continue;
        }
        const QColor color = item.track >= 0
                                 ? SongView::trackColor(item.track)
                                 : themes::color(themes::Role::song_view_file_event_marker);
        TimelineQuickLayerData &markers = scene.layer(markersLayer);
        const QPointF left(x - m_geometry.otherEventMarkerHalfWidth, markerY);
        const QPointF top(x, markerY - m_geometry.otherEventMarkerHalfHeight);
        const QPointF right(x + m_geometry.otherEventMarkerHalfWidth, markerY);
        const QPointF bottom(x, markerY + m_geometry.otherEventMarkerHalfHeight);
        addTriangle(markers, left, right, top, color, area);
        addTriangle(markers, left, bottom, right, color, area);
    }
}

} // namespace songview
