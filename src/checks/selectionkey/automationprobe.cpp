#include "checks/selectionkey/automationprobe.h"

#include "checks/selectionkey/primitives.h"
#include "core/songdocument.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/automationprojection.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/nodelane/nodelane.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

#include <QQuickWindow>
#include <QtGlobal>
#include <QtTest>

#include <algorithm>
#include <array>

namespace {

QString describePoint(const QPointF &point)
{
    return QStringLiteral("(%1,%2)").arg(point.x(), 0, 'f', 2).arg(point.y(), 0, 'f', 2);
}

QString describeRect(const QRectF &rect)
{
    return QStringLiteral("(%1,%2 %3x%4)")
        .arg(rect.x(), 0, 'f', 2)
        .arg(rect.y(), 0, 'f', 2)
        .arg(rect.width(), 0, 'f', 2)
        .arg(rect.height(), 0, 'f', 2);
}

LaneHandle ccLaneHandle(const AutomationCanvas &canvas, int track, uint8_t controller)
{
    const auto &rows = canvas.rows();
    for (int index = 0; index < int(rows.size()); ++index) {
        if (rows[std::size_t(index)].id ==
            EditorAutomationRowId{EditorAutomationRowKind::ControlChange,
                                  static_cast<uint8_t>(track), controller}) {
            return {index + 1};
        }
    }
    return {};
}

} // namespace

namespace selectionkey {

AutomationProbe::AutomationProbe(SongView &view, AutomationPage &page, AutomationCanvas &canvas,
                                 songview::TimelineInputItem &input, int track,
                                 uint8_t controller) noexcept
    : m_view(&view)
    , m_page(&page)
    , m_canvas(&canvas)
    , m_input(&input)
    , m_track(track)
    , m_controller(controller)
{}

std::optional<AutomationProbe> AutomationProbe::locate(SongView &view,
                                                       songview::TimelineInputItem *input,
                                                       int track, uint8_t controller,
                                                       QString *diagnostics)
{
    QPointer<SongView> liveView(&view);
    EditorDrawer *const drawer = view.editorDrawer();
    QPointer<AutomationPage> page(drawer ? drawer->automationPage() : nullptr);
    QPointer<AutomationCanvas> canvas(page ? page->canvas() : nullptr);
    QPointer<songview::TimelineInputItem> quickInput(input);
    LaneHandle handle;
    QRect body;
    if (!liveView || !page || !canvas || !quickInput || !QTest::qWaitFor([&] {
            if (!liveView || !page || !canvas || !quickInput)
                return false;
            handle = ccLaneHandle(*canvas, track, controller);
            body = handle.valid() ? canvas->laneBody(handle) : QRect{};
            return quickInput->window() != nullptr && !quickInput->bounds().isEmpty() &&
                   handle.valid() && !body.isEmpty();
        })) {
        if (diagnostics) {
            const QString condition =
                !liveView     ? QStringLiteral("SongView was destroyed")
                : !page       ? QStringLiteral("automation page missing")
                : !canvas     ? QStringLiteral("automation canvas missing")
                : !quickInput ? QStringLiteral("automation input missing")
                : quickInput->window() == nullptr
                    ? QStringLiteral("automation input is not attached to a Quick window")
                : quickInput->bounds().isEmpty()
                    ? QStringLiteral("automation input bounds are empty")
                : !handle.valid() ? QStringLiteral("CC lane handle is invalid")
                                  : QStringLiteral("CC lane body is empty");
            *diagnostics =
                QStringLiteral("condition=%1; input-bounds=%2; lane-handle=%3; "
                               "lane-body=%4; vertical-scroll=%5")
                    .arg(condition,
                         quickInput ? describeRect(quickInput->bounds())
                                    : QStringLiteral("missing"),
                         handle.valid() ? QString::number(handle.index) : QStringLiteral("invalid"),
                         describeRect(body))
                    .arg(page ? page->verticalScroll() : -1);
        }
        return std::nullopt;
    }
    return AutomationProbe(*liveView, *page, *canvas, *quickInput, track, controller);
}

bool AutomationProbe::project(std::span<const AutomationProbePoint> points,
                              std::span<QPoint> projected, QString *diagnostics) const
{
    if (points.empty() || projected.size() != points.size()) {
        if (diagnostics) {
            *diagnostics =
                points.empty()
                    ? QStringLiteral("no automation points were requested")
                    : QStringLiteral("automation output span does not match input points");
        }
        return false;
    }
    if (!m_view || !m_page || !m_canvas || !m_input) {
        if (diagnostics)
            *diagnostics = QStringLiteral("the automation probe surface was destroyed");
        return false;
    }
    LaneHandle handle = ccLaneHandle(*m_canvas, m_track, m_controller);
    QRect body = handle.valid() ? m_canvas->laneBody(handle) : QRect{};
    if (body.isEmpty() || m_input->bounds().isEmpty() || m_input->window() == nullptr) {
        if (diagnostics) {
            *diagnostics = QStringLiteral("condition=%1; input-bounds=%2; lane-body=%3")
                               .arg(body.isEmpty() ? QStringLiteral("CC lane body is empty")
                                    : m_input->bounds().isEmpty()
                                        ? QStringLiteral("automation input bounds are empty")
                                        : QStringLiteral("automation input is detached"),
                                    describeRect(m_input->bounds()), describeRect(body));
        }
        return false;
    }

    const AutomationGeometry geometry = AutomationGeometry::resolve();
    uint64_t firstTick = points.front().tick;
    uint64_t lastTick = firstTick;
    qreal targetY = 0.0;
    for (const AutomationProbePoint &point : points) {
        firstTick = std::min(firstTick, point.tick);
        lastTick = std::max(lastTick, point.tick);
        targetY += AutomationProjection::valueY(body, geometry, 0, 127, point.value);
    }

    // Reveal the entire set before mapping any endpoint. Range endpoints are
    // intentionally projected only after this one final camera state exists.
    if (points.size() == 1)
        m_view->ensureTickVisible(firstTick);
    else
        m_view->ensureRangeVisible(firstTick, lastTick, true);
    const int viewportHeight = m_page->automationViewportSize().height();
    m_page->setVerticalScroll(qBound(0, qRound(targetY / qreal(points.size())) - viewportHeight / 2,
                                     qMax(0, m_page->automationContentHeight() - viewportHeight)));
    settle();
    if (!m_view || !m_page || !m_canvas || !m_input) {
        if (diagnostics)
            *diagnostics =
                QStringLiteral("the automation probe surface was destroyed while settling");
        return false;
    }
    handle = ccLaneHandle(*m_canvas, m_track, m_controller);
    body = handle.valid() ? m_canvas->laneBody(handle) : QRect{};
    if (body.isEmpty() || m_input->bounds().isEmpty() || m_input->window() == nullptr) {
        if (diagnostics)
            *diagnostics = QStringLiteral("the automation probe surface changed while settling");
        return false;
    }

    for (std::size_t index = 0; index < points.size(); ++index) {
        const AutomationProbePoint &point = points[index];
        const QPointF contentPoint(
            m_view->camera().displayX(point.tick, 0.0, m_input->devicePixelRatio()),
            AutomationProjection::valueY(body, geometry, 0, 127, point.value));
        const QPointF inputPoint = contentPoint - QPointF(0.0, qreal(m_page->verticalScroll()));
        const QPoint windowPoint = m_input->mapToScene(inputPoint).toPoint();
        const QString chosen =
            QStringLiteral("index=%1,tick=%2,value=%3,content=%4,input=%5,window=%6")
                .arg(index)
                .arg(point.tick)
                .arg(point.value)
                .arg(describePoint(contentPoint))
                .arg(describePoint(inputPoint))
                .arg(describePoint(windowPoint));
        if (!m_input->bounds().contains(inputPoint) ||
            !m_input->bounds().contains(m_input->mapFromScene(QPointF(windowPoint)))) {
            if (diagnostics) {
                *diagnostics =
                    QStringLiteral("condition=%1; input-bounds=%2; lane-body=%3; chosen={%4}")
                        .arg(!m_input->bounds().contains(inputPoint)
                                 ? QStringLiteral("chosen point is outside automation input bounds")
                                 : QStringLiteral(
                                       "rounded window point maps outside automation input"),
                             describeRect(m_input->bounds()), describeRect(body), chosen);
            }
            return false;
        }
        projected[index] = windowPoint;
        if (diagnostics)
            *diagnostics =
                QStringLiteral("condition=ready; input-bounds=%1; lane-body=%2; chosen={%3}")
                    .arg(describeRect(m_input->bounds()), describeRect(body), chosen);
    }
    return true;
}

bool AutomationProbe::emptyNodePoint(int value, QPoint &point, QString *diagnostics) const
{
    if (!m_view || !m_page || !m_input) {
        if (diagnostics)
            *diagnostics = QStringLiteral("the automation probe surface was destroyed");
        return false;
    }
    SongDocument *const document = m_view->document();
    if (!document) {
        if (diagnostics)
            *diagnostics = QStringLiteral("the automation probe has no live SongDocument");
        return false;
    }
    const AutomationGeometry geometry = AutomationGeometry::resolve();
    const AutomationProjection projection(geometry, m_page);
    const QRectF bounds = m_input->bounds();
    const qreal firstVisibleTick = qMax(0.0, projection.rawTickAt(bounds.left()));
    const qreal lastVisibleTick = qMax(0.0, projection.rawTickAt(bounds.right()));
    const qreal clearance = qreal(geometry.pointHitRadius) * 4.0 + 8.0;
    const std::vector<DocLanePoint> lanePoints = document->lanePoints(m_track, m_controller);
    std::optional<uint64_t> tick;
    for (const int permille : {500, 350, 650, 250, 750, 150, 850}) {
        const qreal x = bounds.left() + bounds.width() * (qreal(permille) / 1000.0);
        const bool clear = std::none_of(
            lanePoints.cbegin(), lanePoints.cend(), [&](const DocLanePoint &candidate) {
                return qAbs(projection.displayX(candidate.tick, m_input->devicePixelRatio()) - x) <
                       clearance;
            });
        if (x > bounds.left() + clearance && x < bounds.right() - clearance && clear) {
            tick = uint64_t(qMax(0.0, projection.rawTickAt(x)));
            break;
        }
    }
    if (!tick) {
        if (diagnostics) {
            *diagnostics =
                QStringLiteral("visible-ticks=[%1,%2]; input-bounds=%3; no node-free point")
                    .arg(firstVisibleTick)
                    .arg(lastVisibleTick)
                    .arg(describeRect(bounds));
        }
        return false;
    }
    const std::array requested{AutomationProbePoint{*tick, value}};
    std::array<QPoint, 1> projected;
    QString projectionState;
    const bool mapped = project(requested, projected, &projectionState);
    if (diagnostics) {
        *diagnostics = QStringLiteral("visible-ticks=[%1,%2]; input-bounds=%3; chosen-tick=%4; %5")
                           .arg(firstVisibleTick)
                           .arg(lastVisibleTick)
                           .arg(describeRect(bounds))
                           .arg(*tick)
                           .arg(projectionState);
    }
    if (mapped)
        point = projected.front();
    return mapped;
}

} // namespace selectionkey
