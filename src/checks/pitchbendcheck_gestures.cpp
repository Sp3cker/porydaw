#include "pitchbendcheck_internal.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QPointer>
#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>

#include "ui/curvegraph/editablecurvegraph.hpp"
#include "ui/pitchbendeditor.hpp"

namespace pitchbendcheck {

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
    sendMouse(graph, QEvent::MouseButtonPress, targetPos, Qt::LeftButton, Qt::LeftButton);
    QCoreApplication::processEvents();
    const auto selected = graph->selectedX();
    if (!selected || uint64_t(std::llround(*selected)) != target.tick) {
        fail("automation vertex click did not select the expected node");
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
    const int dragUndo = m_document.undoStack()->index();
    sendMouse(graph, QEvent::MouseMove, movedPos, Qt::NoButton, Qt::LeftButton, Qt::AltModifier);
    sendMouse(graph, QEvent::MouseButtonRelease, movedPos, Qt::LeftButton, Qt::NoButton,
              Qt::AltModifier);
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != dragUndo + 1) {
        fail("automation vertex drag did not push one undo command");
        restoreBaseline();
        return;
    }
    const auto movedHit = graph->hitTest(QPointF(movedPos));
    DocLanePoint movedPoint;
    if (!movedHit || uint64_t(std::llround(movedHit->x)) == target.tick ||
        !m_document.findLanePoint(m_engineTrack, cc, uint64_t(std::llround(movedHit->x)),
                                  &movedPoint) ||
        movedPoint.value != qRound(movedHit->y) ||
        m_document.findLanePoint(m_engineTrack, cc, target.tick, nullptr) || !graph->isVisible()) {
        fail("automation vertex drag did not move the document node");
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
    sendMouse(graph, QEvent::MouseButtonPress, restoredPos, Qt::LeftButton, Qt::LeftButton);
    QCoreApplication::processEvents();
    const auto restoredSelected = graph->selectedX();
    if (!restoredSelected || uint64_t(std::llround(*restoredSelected)) != target.tick) {
        fail("automation vertex could not be reselected for deletion");
        restoreBaseline();
        return;
    }
    graph->cancelGesture();
    const int deleteUndo = m_document.undoStack()->index();
    const std::vector<DocLanePoint> beforeDelete = m_document.lanePoints(m_engineTrack, cc);
    sendKey(graph, Qt::Key_Delete, Qt::NoModifier);
    QCoreApplication::processEvents();
    const std::vector<DocLanePoint> afterDelete = m_document.lanePoints(m_engineTrack, cc);
    DocLanePoint startPoint;
    DocLanePoint endPoint;
    if (m_document.undoStack()->index() != deleteUndo + 1 ||
        afterDelete.size() + 1 != beforeDelete.size() ||
        m_document.findLanePoint(m_engineTrack, cc, target.tick, nullptr) ||
        !m_document.findLanePoint(m_engineTrack, cc, m_note.tick, &startPoint) ||
        !m_document.findLanePoint(m_engineTrack, cc, m_endTick, &endPoint)) {
        fail("automation vertex delete did not remove only the interior node");
        restoreBaseline();
        return;
    }
    m_document.undoStack()->undo();
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != deleteUndo ||
        !sameLanePoints(m_document.lanePoints(m_engineTrack, cc), beforeDelete)) {
        fail("undo did not restore the deleted automation vertex");
        restoreBaseline();
        return;
    }
    const auto endpointDelete = [this, graph, cc, &sameLanePoints](uint64_t tick, int value) {
        const int beforeUndo = m_document.undoStack()->index();
        const std::vector<DocLanePoint> before = m_document.lanePoints(m_engineTrack, cc);
        const QPoint position = graph->pointPosition({double(tick), double(value)});
        sendMouse(graph, QEvent::MouseButtonPress, position, Qt::LeftButton, Qt::LeftButton);
        QCoreApplication::processEvents();
        const auto selected = graph->selectedX();
        if (!selected || uint64_t(std::llround(*selected)) != tick) {
            fail("automation endpoint click did not select its node");
            graph->cancelGesture();
            return;
        }
        graph->cancelGesture();
        sendKey(graph, Qt::Key_Delete, Qt::NoModifier);
        QCoreApplication::processEvents();
        if (m_document.undoStack()->index() != beforeUndo ||
            !sameLanePoints(m_document.lanePoints(m_engineTrack, cc), before))
            fail("automation endpoint deletion changed the document");
    };
    endpointDelete(m_note.tick, startPoint.value);
    endpointDelete(m_endTick, endPoint.value);
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
    const auto sameCurvePoint = [](const songview::CurvePoint &lhs,
                                   const songview::CurvePoint &rhs) {
        return lhs.x == rhs.x && lhs.y == rhs.y;
    };
    const auto insertedCurvePoint =
        [&sameCurvePoint](
            const std::vector<songview::CurvePoint> &before,
            const std::vector<songview::CurvePoint> &after) -> std::optional<songview::CurvePoint> {
        auto beforeIt = before.cbegin();
        std::optional<songview::CurvePoint> inserted;
        for (const songview::CurvePoint &point : after) {
            if (beforeIt != before.cend() && sameCurvePoint(point, *beforeIt)) {
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
    const bool previewMatchesDocument =
        snappedPreview.size() >= 2 &&
        uint64_t(std::llround(snappedPreview.front().x)) == m_note.tick &&
        uint64_t(std::llround(snappedPreview.back().x)) == m_endTick &&
        snappedPreview.size() == boundedPoints.size() &&
        std::equal(snappedPreview.begin(), snappedPreview.end(), boundedPoints.begin(),
                   [](const songview::CurvePoint &previewPoint, const DocLanePoint &documentPoint) {
                       return uint64_t(std::llround(previewPoint.x)) == documentPoint.tick &&
                              qRound(previewPoint.y) == documentPoint.value;
                   });
    if (!previewMatchesDocument)
        fail("empty-canvas click bounded document curve disagreed with the preview");
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
    std::vector<songview::CurvePoint> previewRamp;
    for (const songview::CurvePoint &point : preview) {
        const uint64_t tick = uint64_t(std::llround(point.x));
        if (tick > m_note.tick && tick < m_endTick)
            previewRamp.push_back(point);
    }
    if (previewRamp.size() < 2 || previewRamp.front().x >= previewRamp.back().x) {
        fail("Shift mod-wheel line preview had no interior gesture ramp");
        dismissPopup(popup);
        return;
    }
    const uint64_t lowTick = uint64_t(std::llround(previewRamp.front().x));
    const uint64_t highTick = uint64_t(std::llround(previewRamp.back().x));
    sendMouse(graph.data(), QEvent::MouseButtonRelease, finish, Qt::LeftButton, Qt::NoButton,
              Qt::ShiftModifier);
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != beforeUndo + 1)
        fail("Shift mod-wheel line did not produce exactly one undo command");

    const std::vector<DocLanePoint> written = m_document.lanePoints(m_engineTrack, 1);
    std::vector<DocLanePoint> ramp;
    for (const DocLanePoint &point : written) {
        if (point.tick >= lowTick && point.tick <= highTick && point.tick > m_note.tick &&
            point.tick < m_endTick) {
            ramp.push_back(point);
        }
    }
    const bool previewMatchesDocument =
        ramp.size() == previewRamp.size() &&
        std::equal(previewRamp.begin(), previewRamp.end(), ramp.begin(),
                   [](const songview::CurvePoint &previewPoint, const DocLanePoint &documentPoint) {
                       return uint64_t(std::llround(previewPoint.x)) == documentPoint.tick &&
                              qRound(previewPoint.y) == documentPoint.value;
                   });
    if (!previewMatchesDocument)
        fail("Shift mod-wheel line interior document ramp disagreed with the preview");
    bool monotonic = ramp.size() >= 2;
    for (size_t i = 1; i < ramp.size(); i++) {
        if (ramp[i].tick <= ramp[i - 1].tick || ramp[i].value < ramp[i - 1].value)
            monotonic = false;
    }
    if (!monotonic || ramp.front().value >= ramp.back().value)
        fail("Shift mod-wheel line did not produce a monotonic ascending CC1 ramp");
    while (m_document.undoStack()->index() > beforeUndo && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    QCoreApplication::processEvents();
    if (m_document.undoStack()->index() != beforeUndo || m_document.smf().write() != before)
        fail("Shift mod-wheel line undo did not restore the document");
    dismissPopup(popup);
}

} // namespace pitchbendcheck
