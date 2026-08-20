#include "pitchbendcheck_internal.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QPointer>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <optional>
#include <vector>

#include "ui/curvegraph/editablecurvegraph.hpp"
#include "ui/pitchbendeditor.hpp"

namespace pitchbendcheck {

namespace {

int curveValueAt(const std::vector<songview::CurvePoint> &points, uint64_t tick, int minimum,
                 int maximum)
{
    if (points.empty())
        return 0;
    const auto next = std::lower_bound(
        points.begin(), points.end(), double(tick),
        [](const songview::CurvePoint &point, double value) { return point.x < value; });
    if (next == points.begin())
        return qRound(next->y);
    if (next == points.end())
        return qRound(points.back().y);
    const songview::CurvePoint &previous = *std::prev(next);
    const double fraction = (double(tick) - previous.x) / (next->x - previous.x);
    return qRound(std::clamp(previous.y + fraction * (next->y - previous.y), double(minimum),
                             double(maximum)));
}

std::vector<DocLanePoint> fixedCurveSamples(const std::vector<songview::CurvePoint> &points,
                                            uint64_t start, uint64_t end, uint64_t division,
                                            int minimum, int maximum, bool collapseBend)
{
    std::vector<DocLanePoint> result;
    const auto append = [&](uint64_t tick, bool endpoint) {
        const int value = curveValueAt(points, tick, minimum, maximum);
        if (!result.empty() && result.back().tick == tick) {
            result.back().value = value;
            return;
        }
        const int effective = (std::clamp(value, -8192, 8191) + 8192) >> 7;
        if (!endpoint && collapseBend && !result.empty() &&
            effective == (std::clamp(result.back().value, -8192, 8191) + 8192) >> 7)
            return;
        result.push_back({-1, 0, tick, value});
    };
    append(start, true);
    if (division != 0) {
        using WideTick = unsigned __int128;
        for (WideTick boundary = WideTick(start) * 16 / division + 1;; boundary++) {
            const WideTick tick = (boundary * division + 8) / 16;
            if (tick >= end)
                break;
            append(uint64_t(tick), false);
        }
    }
    append(end, true);
    return result;
}

bool sameLanePointValues(const std::vector<DocLanePoint> &lhs, const std::vector<DocLanePoint> &rhs)
{
    return lhs.size() == rhs.size() &&
           std::equal(lhs.begin(), lhs.end(), rhs.begin(),
                      [](const DocLanePoint &left, const DocLanePoint &right) {
                          return left.tick == right.tick && left.value == right.value;
                      });
}

} // namespace

bool PitchBendCheckContext::driveRangeFreehand(const RangePopupState &range)
{
    m_curveUndoIndex = m_document.undoStack()->index();
    m_beforeCurve = m_document.smf().write();
    const QPoint start(range.graph.left() + range.graph.width() / 3, range.graph.center().y());
    const QPoint finish(range.graph.left() + 2 * range.graph.width() / 3,
                        range.graph.top() + range.graph.height() / 3);
    sendMouse(range.graphWidget, QEvent::MouseButtonPress,
              range.graphWidget->mapFrom(range.popup, start), Qt::LeftButton, Qt::LeftButton);
    sendMouse(range.graphWidget, QEvent::MouseMove, range.graphWidget->mapFrom(range.popup, finish),
              Qt::NoButton, Qt::LeftButton);
    sendMouse(range.graphWidget, QEvent::MouseButtonRelease,
              range.graphWidget->mapFrom(range.popup, finish), Qt::LeftButton, Qt::NoButton);
    if (!range.popup->isVisible())
        fail("pitch-bend popup dismissed after its freehand stroke");
    sendKey(range.popup, Qt::Key_Enter, Qt::NoModifier);
    if (!range.popup->isVisible())
        fail("Enter dismissed the pitch-bend popup");
    if (m_document.undoStack()->index() != m_curveUndoIndex + 1) {
        fail("pitch-bend stroke did not push exactly one undo command");
        return false;
    }
    return true;
}
bool PitchBendCheckContext::verifyPopupUndo(const RangePopupState &range)
{
    range.graphWidget->setFocus(Qt::ShortcutFocusReason);
    QCoreApplication::processEvents();
    if (QApplication::focusWidget() != range.graphWidget) {
        fail("pitch-bend graph did not hold focus for Undo");
        return false;
    }
    if (!sendStandardUndo(range.graphWidget)) {
        fail("pitch-bend popup did not claim the standard Undo shortcut");
        return false;
    }
    if (!range.popup->isVisible()) {
        fail("Undo dismissed the pitch-bend popup");
        return false;
    }
    if (m_document.undoStack()->index() != m_curveUndoIndex ||
        m_document.smf().write() != m_beforeCurve) {
        fail("Undo inside the pitch-bend popup did not restore the drawn curve");
        return false;
    }
    return true;
}
bool PitchBendCheckContext::verifyKeyboardControlsIgnored(const RangePopupState &range)
{
    const int undoIndex = m_document.undoStack()->index();
    const QByteArray curve = m_document.smf().write();
    sendKey(range.graphWidget, Qt::Key_Left, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_Right, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_Home, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_End, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_Up, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_Down, Qt::ShiftModifier);
    sendKey(range.graphWidget, Qt::Key_PageUp, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_PageDown, Qt::NoModifier);
    sendKey(range.graphWidget, Qt::Key_0, Qt::NoModifier);
    if (m_document.undoStack()->index() != undoIndex || m_document.smf().write() != curve) {
        fail("pitch-bend keyboard controls changed the curve");
        return false;
    }
    return true;
}
void PitchBendCheckContext::verifyStackedCurveUndo(const RangePopupState &range)
{
    const int firstUndoIndex = m_document.undoStack()->index();
    const QByteArray firstCurve = m_document.smf().write();
    const QPoint strokeStart(range.graph.left() + range.graph.width() / 5,
                             range.graph.bottom() - range.graph.height() / 5);
    const QPoint strokeFinish(range.graph.left() + 2 * range.graph.width() / 5,
                              range.graph.bottom() - range.graph.height() / 3);
    sendMouse(range.graphWidget, QEvent::MouseButtonPress,
              range.graphWidget->mapFrom(range.popup, strokeStart), Qt::LeftButton, Qt::LeftButton);
    sendMouse(range.graphWidget, QEvent::MouseMove,
              range.graphWidget->mapFrom(range.popup, strokeFinish), Qt::NoButton, Qt::LeftButton);
    sendMouse(range.graphWidget, QEvent::MouseButtonRelease,
              range.graphWidget->mapFrom(range.popup, strokeFinish), Qt::LeftButton, Qt::NoButton);
    bool stacked = true;
    if (m_document.undoStack()->index() != firstUndoIndex + 1) {
        fail("a second pitch-bend stroke did not push its own undo command");
        stacked = false;
    }
    const QByteArray secondCurve = m_document.smf().write();
    if (secondCurve == firstCurve) {
        fail("the second pitch-bend stroke did not change the curve");
        stacked = false;
    }
    if (stacked && m_document.undoStack()->index() == firstUndoIndex + 1) {
        m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != firstUndoIndex ||
            m_document.smf().write() != firstCurve)
            fail("undo did not preserve the preceding pitch-bend stroke");
    }
    while (m_document.undoStack()->index() > firstUndoIndex && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != firstUndoIndex || m_document.smf().write() != firstCurve)
        fail("stacked pitch-bend undo did not restore the initial stroke");
}
void PitchBendCheckContext::runVertexEditing()
{
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!popup || !popup->isVisible()) {
        fail("pitch-bend popup was not visible for vertex editing");
        return;
    }
    auto *bendGraph = dynamic_cast<songview::EditableCurveGraph *>(
        popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")));
    auto *modGraph = dynamic_cast<songview::EditableCurveGraph *>(
        popup->findChild<QWidget *>(QStringLiteral("modWheelGraph")));
    if (!bendGraph)
        fail("pitch-bend popup had no EditableCurveGraph pitchBendGraph child for vertex editing");
    else
        runVertexEditingGraph(bendGraph, DOC_CC_BEND);
    if (!modGraph)
        fail("pitch-bend popup had no EditableCurveGraph modWheelGraph child for vertex editing");
    else
        runVertexEditingGraph(modGraph, 1);
}
void PitchBendCheckContext::runVertexEditingGraph(songview::EditableCurveGraph *graph, uint8_t cc)
{
    if (graph->cursor().shape() != Qt::ArrowCursor)
        fail("editable curve graph did not use the regular arrow cursor");
    const int baselineUndo = m_document.undoStack()->index();
    const QByteArray baselineSmf = m_document.smf().write();
    const QRect canvas = graph->canvasRect();
    const auto sameLanePoints = [](const std::vector<DocLanePoint> &lhs,
                                   const std::vector<DocLanePoint> &rhs) {
        return lhs.size() == rhs.size() &&
               std::equal(lhs.begin(), lhs.end(), rhs.begin(),
                          [](const DocLanePoint &left, const DocLanePoint &right) {
                              return left.tick == right.tick && left.value == right.value;
                          });
    };
    const auto restoreBaseline = [this, graph, baselineUndo] {
        graph->cancelGesture();
        while (m_document.undoStack()->index() > baselineUndo &&
               m_document.undoStack()->canUndo()) {
            m_document.undoStack()->undo();
            QCoreApplication::processEvents();
        }
    };
    const bool isModWheel = graph->objectName() == QStringLiteral("modWheelGraph");
    const QPoint strokeStart(canvas.left() + canvas.width() / 5,
                             isModWheel ? canvas.bottom() - canvas.height() / 4
                                        : canvas.center().y() + canvas.height() / 4);
    const QPoint strokeFinish(canvas.left() + 4 * canvas.width() / 5,
                              isModWheel ? canvas.top() + canvas.height() / 4
                                         : canvas.center().y() - canvas.height() / 4);
    sendMouse(graph, QEvent::MouseButtonPress, strokeStart, Qt::LeftButton, Qt::LeftButton);
    sendMouse(graph, QEvent::MouseMove, strokeFinish, Qt::NoButton, Qt::LeftButton);
    sendMouse(graph, QEvent::MouseButtonRelease, strokeFinish, Qt::LeftButton, Qt::NoButton);
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != baselineUndo + 1) {
        fail("vertex fixture stroke did not push one automation command");
        restoreBaseline();
        return;
    }
    const std::vector<DocLanePoint> written = m_document.lanePoints(m_engineTrack, cc);
    std::vector<DocLanePoint> interior;
    for (const DocLanePoint &point : written) {
        if (point.tick > m_note.tick && point.tick < m_endTick)
            interior.push_back(point);
    }
    if (interior.empty()) {
        fail("vertex fixture stroke produced no interior automation node");
        restoreBaseline();
        return;
    }
    const DocLanePoint target = interior[interior.size() / 2];
    const QPoint targetPos = graph->pointPosition({double(target.tick), double(target.value)});
    const auto hit = graph->hitTest(QPointF(targetPos));
    if (!hit || uint64_t(std::llround(hit->x)) != target.tick || qRound(hit->y) != target.value) {
        fail("automation vertex center did not hit the expected node");
        restoreBaseline();
        return;
    }
    const int dragUndo = m_document.undoStack()->index();
    sendMouse(graph, QEvent::MouseButtonPress, targetPos, Qt::LeftButton, Qt::LeftButton);
    QCoreApplication::processEvents();
    const auto selected = graph->selectedX();
    if (!selected || uint64_t(std::llround(*selected)) != target.tick) {
        fail("automation vertex press did not select the expected node");
        restoreBaseline();
        return;
    }
    QPoint movedPos = targetPos + QPoint(20, -10);
    movedPos.setX(std::clamp(movedPos.x(), canvas.left() + 2, canvas.right() - 2));
    movedPos.setY(std::clamp(movedPos.y(), canvas.top() + 2, canvas.bottom() - 2));
    if (movedPos == targetPos) {
        fail("automation vertex had no usable drag destination");
        restoreBaseline();
        return;
    }
    sendMouse(graph, QEvent::MouseMove, movedPos, Qt::NoButton, Qt::LeftButton, Qt::AltModifier);
    const auto movedX = graph->selectedX();
    const std::vector<songview::CurvePoint> movedPreview = graph->points();
    sendMouse(graph, QEvent::MouseButtonRelease, movedPos, Qt::LeftButton, Qt::NoButton,
              Qt::AltModifier);
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != dragUndo + 1 || !movedX ||
        uint64_t(std::llround(*movedX)) == target.tick || !graph->isVisible()) {
        fail("automation vertex drag did not move its graph control point");
        restoreBaseline();
        return;
    }
    std::vector<DocLanePoint> movedDocument;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, cc)) {
        if (point.tick >= m_note.tick && point.tick <= m_endTick)
            movedDocument.push_back(point);
    }
    const std::vector<DocLanePoint> movedExpected = fixedCurveSamples(
        movedPreview, m_note.tick, m_endTick, m_document.smf().division,
        cc == DOC_CC_BEND ? -8192 : 0, cc == DOC_CC_BEND ? 8191 : 127, cc == DOC_CC_BEND);
    if (!sameLanePoints(movedDocument, movedExpected)) {
        fail("automation vertex drag did not write its independently resampled curve");
        restoreBaseline();
        return;
    }
    m_document.undoStack()->undo();
    QCoreApplication::processEvents();
    const std::vector<DocLanePoint> restoredAfterDrag = m_document.lanePoints(m_engineTrack, cc);
    if (m_document.undoStack()->index() != dragUndo ||
        !sameLanePoints(restoredAfterDrag, written)) {
        fail("undo did not restore the automation vertex after dragging");
        restoreBaseline();
        return;
    }
    DocLanePoint restoredTarget;
    if (!m_document.findLanePoint(m_engineTrack, cc, target.tick, &restoredTarget)) {
        fail("drag undo did not restore the original automation node");
        restoreBaseline();
        return;
    }
    const QPoint restoredPos =
        graph->pointPosition({double(target.tick), double(restoredTarget.value)});
    const int deleteUndo = m_document.undoStack()->index();
    const std::vector<DocLanePoint> beforeDelete = m_document.lanePoints(m_engineTrack, cc);
    const QByteArray beforeDeleteBytes = m_document.smf().write();
    sendMouse(graph, QEvent::MouseButtonPress, restoredPos, Qt::LeftButton, Qt::LeftButton);
    sendMouse(graph, QEvent::MouseButtonRelease, restoredPos, Qt::LeftButton, Qt::NoButton);
    QCoreApplication::processEvents();
    DocLanePoint startPoint;
    DocLanePoint endPoint;
    if (m_document.undoStack()->index() != deleteUndo + 1 ||
        m_document.smf().write() == beforeDeleteBytes ||
        !m_document.findLanePoint(m_engineTrack, cc, m_note.tick, &startPoint) ||
        !m_document.findLanePoint(m_engineTrack, cc, m_endTick, &endPoint)) {
        fail("automation vertex click did not delete its interior graph control point");
        restoreBaseline();
        return;
    }
    m_document.undoStack()->undo();
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != deleteUndo ||
        !sameLanePoints(m_document.lanePoints(m_engineTrack, cc), beforeDelete)) {
        fail("undo did not restore the click-deleted automation vertex");
        restoreBaseline();
        return;
    }
    const auto endpointClick = [this, graph, cc, &sameLanePoints](uint64_t tick, int value) {
        const std::vector<DocLanePoint> before = m_document.lanePoints(m_engineTrack, cc);
        const QPoint position = graph->pointPosition({double(tick), double(value)});
        sendMouse(graph, QEvent::MouseButtonPress, position, Qt::LeftButton, Qt::LeftButton);
        sendMouse(graph, QEvent::MouseButtonRelease, position, Qt::LeftButton, Qt::NoButton);
        QCoreApplication::processEvents();
        if (!sameLanePoints(m_document.lanePoints(m_engineTrack, cc), before))
            fail("automation endpoint click removed or moved the document node");
    };
    endpointClick(m_note.tick, startPoint.value);
    endpointClick(m_endTick, endPoint.value);
    restoreBaseline();
    if (m_document.undoStack()->index() != baselineUndo || m_document.smf().write() != baselineSmf)
        fail("vertex checks did not restore the document");
}
void PitchBendCheckContext::runModWheelEditing()
{
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    auto *graphWidget = popup ? dynamic_cast<songview::EditableCurveGraph *>(
                                    popup->findChild<QWidget *>(QStringLiteral("modWheelGraph")))
                              : nullptr;
    if (!popup || !popup->isVisible() || !graphWidget) {
        fail("pitch-bend popup did not expose its EditableCurveGraph modWheelGraph child");
        return;
    }
    const QRect graph = popup->modGraphRect();
    if (graph.isEmpty()) {
        fail("mod-wheel graph has no editable canvas");
        return;
    }
    const int undoIndex = m_document.undoStack()->index();
    const QByteArray before = m_document.smf().write();
    int endValue = 0;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, 1)) {
        if (point.tick <= m_endTick)
            endValue = point.value;
    }
    const QPoint start(graph.left() + graph.width() / 4, graph.bottom() - graph.height() / 5);
    const QPoint finish(graph.right() - graph.width() / 4, graph.top() + graph.height() / 5);
    sendMouse(graphWidget, QEvent::MouseButtonPress, graphWidget->mapFrom(popup, start),
              Qt::LeftButton, Qt::LeftButton);
    sendMouse(graphWidget, QEvent::MouseMove, graphWidget->mapFrom(popup, finish), Qt::NoButton,
              Qt::LeftButton);
    sendMouse(graphWidget, QEvent::MouseButtonRelease, graphWidget->mapFrom(popup, finish),
              Qt::LeftButton, Qt::NoButton);
    if (m_document.undoStack()->index() != undoIndex + 1)
        fail("mod-wheel stroke did not push exactly one undo command");
    bool wroteInside = false;
    bool restoredAtEnd = false;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, 1)) {
        if (point.tick >= m_note.tick && point.tick < m_endTick && point.value > 0)
            wroteInside = true;
        if (point.tick == m_endTick && point.value == endValue)
            restoredAtEnd = true;
    }
    if (!wroteInside)
        fail("mod-wheel stroke wrote no CC1 automation inside the note");
    if (!restoredAtEnd)
        fail("mod-wheel stroke did not restore CC1 at note-off");
    if (!sendStandardUndo(graphWidget))
        fail("mod-wheel graph did not claim the standard Undo shortcut");
    if (!popup->isVisible())
        fail("Undo dismissed the popup from the mod-wheel graph");
    if (m_document.undoStack()->index() != undoIndex || m_document.smf().write() != before)
        fail("Undo did not restore the document after mod-wheel drawing");
}
void PitchBendCheckContext::runPointClickAndEscape()
{
    QPointer<songview::PitchBendEditor> popup = dynamic_cast<songview::PitchBendEditor *>(
        m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
    dismissPopup(popup);
    const RangePopupState range = openRangePopup();
    popup = range.popup;
    if (!popup) {
        popup = dynamic_cast<songview::PitchBendEditor *>(
            m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
        dismissPopup(popup);
        return;
    }
    QPointer<songview::EditableCurveGraph> graph = range.graphWidget;
    if (!graph) {
        fail("pitch-bend popup had no EditableCurveGraph pitchBendGraph child");
        dismissPopup(popup);
        return;
    }
    const QRect canvas = graph->canvasRect();
    const auto insertedCurvePoint =
        [](const std::vector<songview::CurvePoint> &before,
           const std::vector<songview::CurvePoint> &after) -> std::optional<songview::CurvePoint> {
        auto beforeIt = before.cbegin();
        std::optional<songview::CurvePoint> inserted;
        for (const songview::CurvePoint &point : after) {
            if (beforeIt != before.cend() && point.x == beforeIt->x && point.y == beforeIt->y) {
                ++beforeIt;
                continue;
            }
            if (inserted)
                return std::nullopt;
            inserted = point;
        }
        return beforeIt == before.cend() ? inserted : std::nullopt;
    };
    const int beforeUndo = m_document.undoStack()->index();
    const QByteArray before = m_document.smf().write();
    const std::vector<songview::CurvePoint> beforePreview = graph->points();
    std::vector<songview::CurvePoint> snappedPreview;
    std::optional<songview::CurvePoint> insertedPreviewPoint;
    QPoint click;
    const int xStep = std::max(1, canvas.width() / 10);
    for (int x = canvas.left() + canvas.width() / 5; x <= canvas.left() + 4 * canvas.width() / 5;
         x += xStep) {
        const QPoint candidate(x, canvas.top() + canvas.height() / 5);
        sendMouse(graph.data(), QEvent::MouseButtonPress, candidate, Qt::LeftButton,
                  Qt::LeftButton);
        QCoreApplication::processEvents();
        if (!popup || !graph) {
            fail("empty-canvas click dismissed the pitch-bend popup");
            dismissPopup(popup);
            return;
        }
        const std::vector<songview::CurvePoint> preview = graph->points();
        const auto inserted = insertedCurvePoint(beforePreview, preview);
        if (inserted && graph->hasGesture() && uint64_t(std::llround(inserted->x)) > m_note.tick &&
            uint64_t(std::llround(inserted->x)) < m_endTick) {
            click = candidate;
            insertedPreviewPoint = *inserted;
            snappedPreview = preview;
            break;
        }
        graph->cancelGesture();
        QCoreApplication::processEvents();
    }
    if (!insertedPreviewPoint) {
        fail("empty-canvas click did not create one interior preview point");
        dismissPopup(popup);
        return;
    }
    sendMouse(graph.data(), QEvent::MouseButtonRelease, click, Qt::LeftButton, Qt::NoButton);
    QCoreApplication::processEvents();
    const bool clickCompleted = popup && popup->isVisible() && graph && !graph->hasGesture();
    if (!clickCompleted)
        fail("empty-canvas click did not leave the popup open with no active gesture");
    if (m_document.undoStack()->index() != beforeUndo + 1)
        fail("empty-canvas click did not produce exactly one undo command");
    const std::vector<DocLanePoint> afterPoints = m_document.lanePoints(m_engineTrack, DOC_CC_BEND);
    std::vector<DocLanePoint> boundedPoints;
    for (const DocLanePoint &point : afterPoints) {
        if (point.tick >= m_note.tick && point.tick <= m_endTick)
            boundedPoints.push_back(point);
    }
    const std::vector<DocLanePoint> expected = fixedCurveSamples(
        snappedPreview, m_note.tick, m_endTick, m_document.smf().division, -8192, 8191, true);
    if (!sameLanePointValues(boundedPoints, expected))
        fail("empty-canvas click did not persist its independently resampled 1/64 curve");
    while (m_document.undoStack()->index() > beforeUndo && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != beforeUndo || m_document.smf().write() != before)
        fail("empty-canvas click undo did not restore the document");
    if (!clickCompleted) {
        dismissPopup(popup);
        return;
    }

    const int cancelUndo = m_document.undoStack()->index();
    const QByteArray cancelBefore = m_document.smf().write();
    const QPoint gestureStart(canvas.left() + canvas.width() / 3, canvas.center().y());
    const QPoint gestureFinish(canvas.left() + 2 * canvas.width() / 3,
                               canvas.top() + canvas.height() / 3);
    sendMouse(graph.data(), QEvent::MouseButtonPress, gestureStart, Qt::LeftButton, Qt::LeftButton);
    sendMouse(graph.data(), QEvent::MouseMove, gestureFinish, Qt::NoButton, Qt::LeftButton);
    QCoreApplication::processEvents();
    if (!graph->hasGesture())
        fail("pitch-bend graph did not retain its in-flight gesture");
    dismissPopup(popup);
    if (popup || graph || m_document.undoStack()->index() != cancelUndo ||
        m_document.smf().write() != cancelBefore) {
        fail("Escape during a pitch-bend gesture mutated the document or undo stack");
    }
}
void PitchBendCheckContext::runModWheelShiftLine()
{
    QPointer<songview::PitchBendEditor> popup = dynamic_cast<songview::PitchBendEditor *>(
        m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
    dismissPopup(popup);
    const RangePopupState range = openRangePopup();
    popup = range.popup;
    if (!popup) {
        popup = dynamic_cast<songview::PitchBendEditor *>(
            m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
        dismissPopup(popup);
        return;
    }
    QPointer<songview::EditableCurveGraph> graph = dynamic_cast<songview::EditableCurveGraph *>(
        popup->findChild<QWidget *>(QStringLiteral("modWheelGraph")));
    if (!graph) {
        fail("pitch-bend popup had no EditableCurveGraph modWheelGraph child");
        dismissPopup(popup);
        return;
    }
    const QRect canvas = graph->canvasRect();
    const QPoint start(canvas.left() + canvas.width() / 12, canvas.bottom() - canvas.height() / 8);
    const QPoint finish(canvas.right() - canvas.width() / 12, canvas.top() + canvas.height() / 8);
    const int beforeUndo = m_document.undoStack()->index();
    const QByteArray before = m_document.smf().write();
    sendMouse(graph.data(), QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton,
              Qt::ShiftModifier);
    sendMouse(graph.data(), QEvent::MouseMove, finish, Qt::NoButton, Qt::LeftButton,
              Qt::ShiftModifier);
    QCoreApplication::processEvents();
    if (!popup || !graph) {
        fail("Shift mod-wheel line dismissed the pitch-bend popup");
        dismissPopup(popup);
        return;
    }
    const std::vector<songview::CurvePoint> preview = graph->points();
    if (!graph->hasGesture() || preview.size() < 2) {
        fail("Shift mod-wheel line did not retain an in-flight gesture");
        dismissPopup(popup);
        return;
    }
    const bool previewHasInterior =
        std::any_of(preview.begin(), preview.end(), [this](const songview::CurvePoint &point) {
            const uint64_t tick = uint64_t(std::llround(point.x));
            return tick > m_note.tick && tick < m_endTick;
        });
    if (!previewHasInterior) {
        fail("Shift mod-wheel line preview had no interior gesture ramp");
        dismissPopup(popup);
        return;
    }
    const std::vector<DocLanePoint> expected = fixedCurveSamples(
        preview, m_note.tick, m_endTick, m_document.smf().division, 0, 127, false);
    sendMouse(graph.data(), QEvent::MouseButtonRelease, finish, Qt::LeftButton, Qt::NoButton,
              Qt::ShiftModifier);
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != beforeUndo + 1)
        fail("Shift mod-wheel line did not produce exactly one undo command");
    std::vector<DocLanePoint> ramp;
    std::vector<DocLanePoint> expectedRamp;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, 1)) {
        if (point.tick > m_note.tick && point.tick < m_endTick)
            ramp.push_back(point);
    }
    for (const DocLanePoint &point : expected) {
        if (point.tick > m_note.tick && point.tick < m_endTick)
            expectedRamp.push_back(point);
    }
    const bool fixedSamplesMatch =
        ramp.size() == expectedRamp.size() &&
        std::equal(ramp.begin(), ramp.end(), expectedRamp.begin(),
                   [](const DocLanePoint &actual, const DocLanePoint &expectedPoint) {
                       return actual.tick == expectedPoint.tick &&
                              actual.value == expectedPoint.value;
                   });
    if (!fixedSamplesMatch)
        fail("Shift mod-wheel line did not persist its independently resampled 1/64 ramp");
    std::vector<songview::CurvePoint> gestureRamp;
    for (const songview::CurvePoint &point : preview) {
        const int x = graph->pointPosition(point).x();
        if (x >= start.x() && x <= finish.x())
            gestureRamp.push_back(point);
    }
    bool monotonic = gestureRamp.size() >= 2;
    for (size_t i = 1; i < gestureRamp.size(); i++) {
        if (gestureRamp[i].x <= gestureRamp[i - 1].x || gestureRamp[i].y < gestureRamp[i - 1].y)
            monotonic = false;
    }
    if (!monotonic || gestureRamp.front().y >= gestureRamp.back().y)
        fail("Shift mod-wheel line did not produce a monotonic ascending CC1 ramp");
    while (m_document.undoStack()->index() > beforeUndo && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != beforeUndo || m_document.smf().write() != before)
        fail("Shift mod-wheel line undo did not restore the document");
    dismissPopup(popup);
}

} // namespace pitchbendcheck
