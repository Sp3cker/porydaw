#include "ui/songview/otherstrip.h"

#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/timelinequickscene.h"
#include "ui/theme/themeruntime.h"

#include <algorithm>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using timeline_quick::addClippedTriangle;
using timeline_quick::addDashedVertical;
using timeline_quick::addRect;
using timeline_quick::resetLayer;

namespace {

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
        const QPointF left(x - m_geometry.otherEventMarkerHalfWidth, markerY);
        const QPointF top(x, markerY - m_geometry.otherEventMarkerHalfHeight);
        const QPointF right(x + m_geometry.otherEventMarkerHalfWidth, markerY);
        const QPointF bottom(x, markerY + m_geometry.otherEventMarkerHalfHeight);
        addClippedTriangle(scene, markersLayer, left, right, top, color, area);
        addClippedTriangle(scene, markersLayer, left, bottom, right, color, area);
    }
}

} // namespace songview
