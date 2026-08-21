#include "pitchbendcheck_internal.hpp"

#include <QColor>
#include <QCoreApplication>
#include <QCursor>
#include <QImage>
#include <QPixmap>
#include <QPointer>
#include <algorithm>
#include <cmath>
#include <vector>

#include "ui/curvegraph/curvegraph.hpp"
#include "ui/pitchbendeditor.hpp"

namespace pitchbendcheck {

void PitchBendCheckContext::verifyShiftLinePreview(const RangePopupState &range)
{
    const QPoint start(range.graph.left() + range.graph.width() / 8,
                       range.graph.bottom() - range.graph.height() / 8);
    const QPoint finish(range.graph.right() - range.graph.width() / 8,
                        range.graph.top() + range.graph.height() / 8);
    const int undoIndex = m_document.undoStack()->index();
    sendMouse(range.graphWidget, QEvent::MouseButtonPress,
              range.graphWidget->mapFrom(range.popup, start), Qt::LeftButton, Qt::LeftButton,
              Qt::ShiftModifier);
    sendMouse(range.graphWidget, QEvent::MouseMove, range.graphWidget->mapFrom(range.popup, finish),
              Qt::NoButton, Qt::LeftButton, Qt::ShiftModifier);
    sendMouse(range.graphWidget, QEvent::MouseButtonRelease,
              range.graphWidget->mapFrom(range.popup, finish), Qt::LeftButton, Qt::NoButton,
              Qt::ShiftModifier);
    if (m_document.undoStack()->index() != undoIndex + 1)
        fail("Shift pitch-bend drag did not push one curve command");
    QCoreApplication::processEvents();
    const QPixmap linePixmap = range.popup->grab();
    const QImage lineImage = linePixmap.toImage();
    const qreal lineDpr = linePixmap.devicePixelRatio();
    const QColor curveColor = SongView::trackColor(m_engineTrack);
    int diagonalHits = 0;
    for (int i = 1; i < 8; i++) {
        const double fraction = double(i) / 8.0;
        const QPoint linePoint(
            qRound(double(start.x()) + fraction * double(finish.x() - start.x())),
            qRound(double(start.y()) + fraction * double(finish.y() - start.y())));
        if (persistedCurvePixelNear(lineImage, lineDpr, linePoint, curveColor))
            diagonalHits++;
    }
    if (diagonalHits < 4)
        fail("Shift pitch-bend drag did not draw an angled line");
    m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != undoIndex)
        fail("undo did not restore the document after the Shift line");
}

bool PitchBendCheckContext::openPersistedAltPopup(PersistedAltPopupState *state)
{
    QPointer<songview::PitchBendEditor> popup = dynamic_cast<songview::PitchBendEditor *>(
        m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
    dismissPopup(popup);
    QCursor::setPos(m_roll->mapToGlobal(m_noteCenter));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    popup = dynamic_cast<songview::PitchBendEditor *>(
        m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
    if (!popup || !popup->isVisible()) {
        fail("G did not open the pitch-bend popup for its Alt line");
        dismissPopup(popup);
        return false;
    }
    state->popup = popup;
    state->graph = popup->graphRect();
    state->graphWidget = dynamic_cast<songview::CurveGraph *>(
        popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")));
    if (!state->graphWidget) {
        fail("pitch-bend popup has no CurveGraph pitchBendGraph child for its Alt line");
        dismissPopup(popup);
        return false;
    }
    return true;
}

void PitchBendCheckContext::drivePersistedAltRamp(const PersistedAltPopupState &state)
{
    const QPoint lineStart(state.graph.left() + state.graph.width() / 16,
                           state.graph.bottom() - state.graph.height() / 12);
    const QPoint lineFinish(state.graph.right() - state.graph.width() / 16,
                            state.graph.top() + state.graph.height() / 12);
    sendMouse(state.graphWidget, QEvent::MouseButtonPress,
              state.graphWidget->mapFrom(state.popup, lineStart), Qt::LeftButton, Qt::LeftButton,
              Qt::AltModifier);
    sendMouse(state.graphWidget, QEvent::MouseMove,
              state.graphWidget->mapFrom(state.popup, lineFinish), Qt::NoButton, Qt::LeftButton,
              Qt::AltModifier);
    sendMouse(state.graphWidget, QEvent::MouseButtonRelease,
              state.graphWidget->mapFrom(state.popup, lineFinish), Qt::LeftButton, Qt::NoButton,
              Qt::AltModifier);
    if (!state.popup->isVisible())
        fail("pitch-bend popup dismissed after its Alt line");
    if (m_document.undoStack()->index() != m_curveUndoIndex + 1)
        fail("Alt line did not push exactly one pitch-bend edit");
    std::vector<DocLanePoint> angled;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, DOC_CC_BEND)) {
        if (point.tick > m_note.tick && point.tick < m_endTick)
            angled.push_back(point);
    }
    bool risingRamp = angled.size() >= 3;
    for (size_t i = 1; i < angled.size(); i++) {
        if (angled[i].value <= angled[i - 1].value) {
            risingRamp = false;
            break;
        }
    }
    if (!risingRamp)
        fail("Alt drag did not write a rising pitch-bend ramp");
}

bool PitchBendCheckContext::reopenPersistedAltPopup(PersistedAltPopupState *state)
{
    QCursor::setPos(m_roll->mapToGlobal(m_noteCenter));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    QPointer<songview::PitchBendEditor> popup = dynamic_cast<songview::PitchBendEditor *>(
        m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup")));
    if (!popup || !popup->isVisible()) {
        fail("G did not reopen the pitch-bend popup after the Alt line");
        dismissPopup(popup);
        return false;
    }
    state->popup = popup;
    state->graph = popup->graphRect();
    state->graphWidget = dynamic_cast<songview::CurveGraph *>(
        popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")));
    if (!state->graphWidget) {
        fail("reopened pitch-bend popup has no CurveGraph pitchBendGraph child");
        dismissPopup(popup);
        return false;
    }
    return true;
}

bool PitchBendCheckContext::persistedCurvePixelNear(const QImage &image, qreal dpr, QPoint logical,
                                                    const QColor &curveColor)
{
    for (int y = logical.y() - 1; y <= logical.y() + 1; y++) {
        for (int x = logical.x() - 1; x <= logical.x() + 1; x++) {
            const int px = qRound(double(x) * dpr);
            const int py = qRound(double(y) * dpr);
            if (px < 0 || px >= image.width() || py < 0 || py >= image.height())
                continue;
            const QColor pixel = image.pixelColor(px, py);
            if (std::abs(pixel.red() - curveColor.red()) <= 40 &&
                std::abs(pixel.green() - curveColor.green()) <= 40 &&
                std::abs(pixel.blue() - curveColor.blue()) <= 40)
                return true;
        }
    }
    return false;
}

void PitchBendCheckContext::verifyPersistedAltDiagonal(const PersistedAltPopupState &state)
{
    const QPixmap angledPixmap = state.popup->grab();
    const QImage angledImage = angledPixmap.toImage();
    const qreal angledDpr = angledPixmap.devicePixelRatio();
    const QColor curveColor = SongView::trackColor(m_engineTrack);
    const QPoint visualStart(state.graph.left() + state.graph.width() / 16,
                             state.graph.bottom() - state.graph.height() / 12);
    const QPoint visualFinish(state.graph.right() - state.graph.width() / 16,
                              state.graph.top() + state.graph.height() / 12);
    int diagonalHits = 0;
    for (int i = 1; i < 8; i++) {
        const double fraction = double(i) / 8.0;
        const QPoint visualPoint(
            qRound(double(visualStart.x()) + fraction * double(visualFinish.x() - visualStart.x())),
            qRound(double(visualStart.y()) +
                   fraction * double(visualFinish.y() - visualStart.y())));
        if (persistedCurvePixelNear(angledImage, angledDpr, visualPoint, curveColor))
            diagonalHits++;
    }
    if (diagonalHits < 4)
        fail("Alt pitch-bend ramp painted as stair steps instead of diagonal segments");
}

void PitchBendCheckContext::restorePersistedAltCurve()
{
    drainPopupDeletes();
    m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != m_curveUndoIndex ||
        m_document.smf().write() != m_beforeCurve)
        fail("undo did not restore the document after the Alt pitch-bend line");
}

void PitchBendCheckContext::runPersistedAltRendering()
{
    PersistedAltPopupState current;
    if (!openPersistedAltPopup(&current))
        return;
    drivePersistedAltRamp(current);
    QPointer<songview::PitchBendEditor> currentPopup = current.popup;
    sendKey(currentPopup.data(), Qt::Key_Escape, Qt::NoModifier);
    if (currentPopup && currentPopup->isVisible()) {
        fail("Escape did not dismiss the pitch-bend popup");
        dismissPopup(currentPopup);
    } else {
        drainPopupDeletes();
    }
    PersistedAltPopupState reopened;
    if (reopenPersistedAltPopup(&reopened)) {
        if (reopened.graphWidget)
            verifyPersistedAltDiagonal(reopened);
        QPointer<songview::PitchBendEditor> reopenedPopup = reopened.popup;
        sendKey(reopenedPopup.data(), Qt::Key_Escape, Qt::NoModifier);
        if (reopenedPopup && reopenedPopup->isVisible()) {
            fail("Escape did not dismiss the reopened pitch-bend popup");
            dismissPopup(reopenedPopup);
        } else {
            drainPopupDeletes();
        }
    }
    restorePersistedAltCurve();
}

void PitchBendCheckContext::runFocusHandoff()
{
    drainPopupDeletes();
    QCursor::setPos(m_roll->mapToGlobal(m_noteCenter));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    QPointer<songview::PitchBendEditor> popup =
        dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!popup || !popup->isVisible()) {
        fail("G did not reopen the pitch-bend popup for focus handoff");
        return;
    }
    sendMouse(m_roll, QEvent::MouseButtonPress, m_noteCenter, Qt::LeftButton, Qt::LeftButton);
    QCoreApplication::processEvents();
    if (popup && popup->isVisible())
        fail("clicking the selected note did not dismiss the pitch-bend popup");
    if (m_view.selectionModel().noteSelection().size() != 1 ||
        m_view.selectionModel().noteSelection().front() != m_note.noteId)
        fail("clicking the selected note did not preserve note focus");
    drainPopupDeletes();
    QPoint edgeHandle;
    bool foundEdge = false;
    for (int x = 0; x < m_roll->width(); ++x) {
        const QPoint candidate(x, m_noteCenter.y());
        sendMouse(m_roll, QEvent::MouseMove, candidate, Qt::NoButton, Qt::NoButton);
        if (!m_roll->cursor().pixmap().isNull()) {
            edgeHandle = candidate;
            foundEdge = true;
            break;
        }
    }
    if (!foundEdge) {
        fail("cursor handoff fixture did not find a note edge");
        return;
    }
    sendMouse(m_roll, QEvent::MouseMove, QPoint(1, m_noteCenter.y()), Qt::NoButton, Qt::NoButton);
    if (m_roll->cursor().shape() != Qt::ArrowCursor)
        fail("piano-roll cursor stopped tracking after pitch-bend click-away dismissal");
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!popup || !popup->isVisible()) {
        fail("G did not reopen the pitch-bend popup for cursor handoff");
        return;
    }
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    drainPopupDeletes();
    popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    auto *replacementGraph =
        popup ? dynamic_cast<songview::CurveGraph *>(
                    popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")))
              : nullptr;
    if (!popup || !popup->isVisible() || !replacementGraph || !replacementGraph->hasFocus()) {
        fail("replacing the pitch-bend popup did not retain graph focus");
        return;
    }
    const QPoint edgeGlobal = m_roll->mapToGlobal(edgeHandle);
    QCursor::setPos(edgeGlobal);
    QCoreApplication::processEvents();
    const bool cursorWarped = QCursor::pos() == edgeGlobal;
    sendKey(popup, Qt::Key_Escape, Qt::NoModifier);
    drainPopupDeletes();
    QCoreApplication::processEvents();
    if (cursorWarped && m_roll->cursor().pixmap().isNull())
        fail("dismissing the pitch-bend popup did not restore the note-edge cursor");
}

void PitchBendCheckContext::runActiveGridBoundary()
{
    BoundaryFixtureState fixture;
    bool ready = createBoundaryFixture(&fixture);
    if (ready)
        ready = inspectBoundaryFixturePopup(&fixture);
    if (ready)
        ready = driveBoundaryFreehand(&fixture);
    if (ready)
        verifyBoundarySamples(fixture);
    restoreBoundaryFixture(fixture);
}

void PitchBendCheckContext::restoreBoundaryFixture(const BoundaryFixtureState &fixture)
{
    drainPopupDeletes();
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (popup && popup->isVisible()) {
        sendKey(popup, Qt::Key_Escape, Qt::NoModifier);
        drainPopupDeletes();
    }
    while (m_document.undoStack()->index() > fixture.beforeUndoIndex &&
           m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != fixture.beforeUndoIndex ||
        m_document.smf().write() != fixture.beforeSmf)
        fail("active-grid fixture did not restore exact SMF bytes and undo index");
    m_view.applyViewState(fixture.beforeViewState);
    m_view.selectionModel().setNoteSelection(fixture.beforeSelection);
    QCoreApplication::processEvents();
    if (m_view.gridFeel() != (fixture.beforeViewState.gridTriplet ? SongView::GridFeel::Triplet
                                                                  : SongView::GridFeel::Straight) ||
        m_view.gridMinDenom() != fixture.beforeViewState.gridMinDenom ||
        m_view.selectionModel().noteSelection() != fixture.beforeSelection)
        fail("active-grid fixture did not restore view grid settings and selection");
    if (!m_document.containsNoteSpan(m_engineTrack, m_note, m_endTick))
        fail("active-grid fixture changed the original note span");
}

bool PitchBendCheckContext::createBoundaryFixture(BoundaryFixtureState *fixture)
{
    fixture->beforeSmf = m_document.smf().write();
    fixture->beforeUndoIndex = m_document.undoStack()->index();
    fixture->beforeSelection = m_view.selectionModel().noteSelection();
    fixture->beforeViewState = m_view.viewState();
    const uint64_t clock = std::max<uint64_t>(1, m_document.ticksPerClock());
    uint64_t fixtureEnd = 0;
    for (const SmfTrack &track : m_document.smf().tracks)
        fixtureEnd = std::max(fixtureEnd, track.endTick);
    const uint64_t margin = std::max<uint64_t>(clock * 8, 96);
    if (fixtureEnd > UINT64_MAX - margin) {
        fail("fixed-granularity fixture tick overflowed");
        return false;
    }
    fixture->fixtureTick = fixtureEnd + margin;
    fixture->span = std::max<uint64_t>(clock * 96, 192);
    if (fixture->fixtureTick > UINT64_MAX - fixture->span) {
        fail("fixed-granularity fixture span overflowed");
        return false;
    }
    fixture->fixtureEndTick = fixture->fixtureTick + fixture->span;
    fixture->fixtureKey = m_note.key == 127 ? 126 : uint8_t(m_note.key + 1);
    m_document.addNote(m_engineTrack, fixture->fixtureTick, fixture->fixtureKey,
                       uint32_t(fixture->span), 100);
    QCoreApplication::processEvents();
    if (!m_document.findNote(m_engineTrack, fixture->fixtureTick, fixture->fixtureKey,
                             &fixture->fixtureNote)) {
        fail("fixed-granularity fixture note was not created");
        return false;
    }
    return true;
}

songview::PitchBendEditor *
PitchBendCheckContext::openBoundaryPopup(const BoundaryFixtureState &fixture, const char *failure)
{
    m_view.selectTrack(m_engineTrack);
    m_view.selectionModel().setNoteSelection({fixture.fixtureNote.noteId});
    QCursor::setPos(m_roll->mapToGlobal(m_noteCenter));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!popup || !popup->isVisible()) {
        fail(failure);
        return nullptr;
    }
    return popup;
}

bool PitchBendCheckContext::inspectBoundaryFixturePopup(BoundaryFixtureState *fixture)
{
    m_view.setGridFeel(SongView::GridFeel::Straight);
    m_view.setGridMinDenom(4);
    QCoreApplication::processEvents();
    auto *popup = openBoundaryPopup(
        *fixture, "fixed-granularity fixture note did not open its pitch-bend popup");
    if (!popup)
        return false;
    const QRect graph = popup->graphRect();
    fixture->pixelsPerTick = double(graph.width()) / double(fixture->span);
    fixture->editingCell = m_view.gridTicksAtScale(fixture->fixtureTick, fixture->pixelsPerTick);
    sendKey(popup, Qt::Key_Escape, Qt::NoModifier);
    drainPopupDeletes();
    if (fixture->editingCell == 0) {
        fail("fixed-granularity fixture produced no coarse editing cell");
        return false;
    }
    return true;
}

bool PitchBendCheckContext::driveBoundaryFreehand(BoundaryFixtureState *fixture)
{
    auto *popup = openBoundaryPopup(
        *fixture, "fixed-granularity fixture could not reopen its pitch-bend popup");
    if (!popup)
        return false;
    auto *graphWidget = dynamic_cast<songview::CurveGraph *>(
        popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")));
    if (!graphWidget) {
        fail("fixed-granularity popup has no CurveGraph pitchBendGraph child");
        sendKey(popup, Qt::Key_Escape, Qt::NoModifier);
        return false;
    }
    if (!m_document.findNote(m_engineTrack, fixture->fixtureTick, fixture->fixtureKey,
                             &fixture->fixtureNote) ||
        !m_document.containsNoteSpan(m_engineTrack, fixture->fixtureNote, fixture->fixtureEndTick))
        fail("fixed-granularity fixture note span was not preserved");
    const QRect graph = popup->graphRect();
    const QPoint lineStart(graph.left() + graph.width() / 12, graph.bottom() - graph.height() / 10);
    const QPoint lineFinish(graph.right() - graph.width() / 12, graph.top() + graph.height() / 10);
    const int curveUndoIndex = m_document.undoStack()->index();
    sendMouse(graphWidget, QEvent::MouseButtonPress, graphWidget->mapFrom(popup, lineStart),
              Qt::LeftButton, Qt::LeftButton);
    sendMouse(graphWidget, QEvent::MouseMove, graphWidget->mapFrom(popup, lineFinish), Qt::NoButton,
              Qt::LeftButton);
    sendMouse(graphWidget, QEvent::MouseButtonRelease, graphWidget->mapFrom(popup, lineFinish),
              Qt::LeftButton, Qt::NoButton);
    if (!popup->isVisible())
        fail("fixed-granularity freehand drag dismissed the pitch-bend popup");
    if (m_document.undoStack()->index() != curveUndoIndex + 1)
        fail("fixed-granularity freehand drag did not push exactly one curve command");
    return true;
}

void PitchBendCheckContext::verifyBoundarySamples(const BoundaryFixtureState &fixture)
{
    const uint64_t division = m_document.smf().division;
    if (division == 0) {
        fail("fixed-granularity fixture had no musical division");
        return;
    }
    const auto boundaryAt = [division](uint64_t index) {
        return uint64_t((__uint128_t(index) * division + 8) / 16);
    };
    std::vector<uint64_t> boundaries;
    uint64_t index = (fixture.fixtureTick / division) * 16;
    while (boundaryAt(index) <= fixture.fixtureTick)
        index++;
    while (boundaryAt(index) < fixture.fixtureEndTick) {
        boundaries.push_back(boundaryAt(index));
        index++;
    }
    std::vector<DocLanePoint> points;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, DOC_CC_BEND)) {
        if (point.tick >= fixture.fixtureTick && point.tick <= fixture.fixtureEndTick)
            points.push_back(point);
    }
    if (points.size() < 3 || points.front().tick != fixture.fixtureTick ||
        points.front().value != 0 || points.back().tick != fixture.fixtureEndTick ||
        points.back().value != 0) {
        fail("fixed-granularity ramp did not retain exact zero-reset endpoints");
        return;
    }
    int fixedInteriorSamples = 0;
    bool sawOffGridBoundary = false;
    for (size_t i = 1; i + 1 < points.size(); i++) {
        const DocLanePoint &point = points[i];
        if (!std::binary_search(boundaries.begin(), boundaries.end(), point.tick)) {
            fail("pitch-bend persistence wrote an interior point off the 1/64-note grid");
            return;
        }
        fixedInteriorSamples++;
        const SongView::GridSeg segment = m_view.gridSegAt(point.tick);
        const uint64_t cell = m_view.gridTicksAtScale(point.tick, fixture.pixelsPerTick);
        if (cell > 0 && point.tick >= segment.start && (point.tick - segment.start) % cell != 0)
            sawOffGridBoundary = true;
        const int previousEffective = (std::clamp(points[i - 1].value, -8192, 8191) + 8192) >> 7;
        const int currentEffective = (std::clamp(point.value, -8192, 8191) + 8192) >> 7;
        if (previousEffective == currentEffective && points[i - 1].tick != fixture.fixtureTick) {
            fail("pitch-bend persistence retained consecutive equal M4A bend samples");
            return;
        }
    }
    if (fixedInteriorSamples < 16)
        fail("pitch-bend persistence did not resample its ramp at fixed 1/64-note density");
    if (!sawOffGridBoundary)
        fail("pitch-bend persistence followed the coarse editing grid instead of the 1/64 grid");
}

} // namespace pitchbendcheck
