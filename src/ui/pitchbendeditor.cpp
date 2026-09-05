#include "pitchbendeditor.hpp"

#include "layout.h"
#include "m4asemantics.h"

#include "songview.h"
#include "theme/themeruntime.h"
#include "typography.h"

#include <QApplication>
#include <QFont>
#include <QUndoStack>
#include <QVariant>
#include <QWindow>
#include <algorithm>
#include <map>
#include <utility>

namespace {
QFont chromeFont(const QPointer<::SongView> &songView)
{
    if (songView && songView->window())
        return songView->window()->font();
    return QApplication::font();
}

qreal chromeDpr(const QPointer<::SongView> &songView)
{
    if (songView && songView->window() && songView->window()->windowHandle())
        return songView->window()->windowHandle()->devicePixelRatio();
    return qApp->devicePixelRatio();
}

struct CurveSnapshot {
    std::map<uint64_t, int> points;
    int endValue = 0;
};

CurveSnapshot readCurveSnapshot(const SongDocument *document, int engineTrack, uint8_t cc,
                                uint64_t startTick, uint64_t endTick)
{
    CurveSnapshot snapshot;
    int enteringValue = 0;
    for (const DocLanePoint &point : document->lanePoints(engineTrack, cc)) {
        if (point.tick <= startTick)
            enteringValue = point.value;
        if (point.tick > endTick)
            break;
        snapshot.endValue = point.value;
        if (point.tick > startTick && point.tick < endTick)
            snapshot.points[point.tick] = point.value;
    }
    snapshot.points[startTick] = enteringValue;
    snapshot.points[endTick] = snapshot.endValue;
    return snapshot;
}

} // namespace

namespace songview {

PitchBendEditor::PitchBendEditor(::SongView *songView, SongDocument *document, const DocNote &note,
                                 std::function<bool(QPointF)> focusNoteUnderCursor)
    : QObject(songView)
    , m_songView(songView)
    , m_document(document)
    , m_noteSnapshot(note)
    , m_engineTrack(note.engineTrack)
    , m_startTick(note.tick)
    , m_unterminated(note.unterminated())
{
    setObjectName(QStringLiteral("pitchBendPopup"));
    m_endTick = m_document->noteEndTick(m_noteSnapshot);
    snapshotControllerValues();
    resolveChromeGeometry();
    rebuildCachedChrome();
    updateDescription();
    connect(m_document->undoStack(), &QUndoStack::indexChanged, this, [this] {
        snapshotCurves();
        updateDescription();
    });
    connect(m_document, &SongDocument::documentChanged, this, [this] {
        if (!noteSpanStillPresent())
            close(DismissAction::Cancel, CloseFocus::Restore);
    });
    installCloseController(std::move(focusNoteUnderCursor));
}

void PitchBendEditor::setBendRange(int range)
{
    range = std::clamp(range, 0, 127);
    if (range == m_bendRange)
        return;
    if (!writeController(0x14, range, m_endRange)) {
        // Rejected by the document: notify so a QML field resyncs to the
        // still-committed value instead of showing the rejected edit.
        emit controllerValuesChanged();
        return;
    }
    m_bendRange = range;
    if (m_pitchGraph)
        m_pitchGraph->setBendRange(range);
    updateDescription();
    emit controllerValuesChanged();
}

void PitchBendEditor::setLfoSpeed(int speed)
{
    speed = std::clamp(speed, 0, 127);
    if (speed == m_lfoSpeed)
        return;
    if (!writeController(0x15, speed, m_endLfoSpeed)) {
        emit controllerValuesChanged();
        return;
    }
    m_lfoSpeed = speed;
    updateDescription();
    emit controllerValuesChanged();
}

void PitchBendEditor::resetCurve(PitchBendGraph *graph)
{
    if (!graph)
        return;
    graph->resetCurve();
    commitCurve();
    // Reset returns focus to its graph.
    graph->forceActiveFocus(Qt::MouseFocusReason);
}

void PitchBendEditor::resetPitchCurve()
{
    resetCurve(m_pitchGraph.data());
}

void PitchBendEditor::resetModCurve()
{
    resetCurve(m_modGraph.data());
}

PitchBendGraph *PitchBendEditor::focusedGraph() const
{
    return (m_modGraph && m_modGraph->hasActiveFocus()) ? m_modGraph.data() : m_pitchGraph.data();
}

void PitchBendEditor::onGrabLost()
{
    // A lost grab is not an Escape-close: resolve only the unsettled preview
    // while the session is still open. commitCurve() settles exactly once, so
    // a normal release (or teardown) cannot double-commit here.
    if (m_lifecycle == Lifecycle::Open)
        commitCurve();
}

void PitchBendEditor::undoCurve()
{
    if (m_pitchGraph)
        m_pitchGraph->cancelGesture();
    if (m_modGraph)
        m_modGraph->cancelGesture();
    cancelCurve();
    if (!m_document || !m_document->undoStack()->canUndo())
        return;
    m_document->undoStack()->undo();
}

void PitchBendEditor::updateRange(int steps)
{
    setBendRange(std::clamp(m_bendRange + steps, 0, 127));
}

void PitchBendEditor::snapshotControllerValues()
{
    if (!m_document)
        return;
    const auto snapshotController = [this](uint8_t cc, int defaultValue, int *startValue,
                                           int *endValue) {
        *startValue = defaultValue;
        *endValue = defaultValue;
        for (const DocLanePoint &point : m_document->lanePoints(m_engineTrack, cc)) {
            if (point.tick <= m_startTick)
                *startValue = std::clamp(point.value, 0, 127);
            if (point.tick <= m_endTick)
                *endValue = std::clamp(point.value, 0, 127);
            if (point.tick > m_endTick)
                break;
        }
    };
    snapshotController(0x14, 2, &m_bendRange, &m_endRange);
    snapshotController(0x15, 22, &m_lfoSpeed, &m_endLfoSpeed);
}

void PitchBendEditor::snapshotCurves()
{
    if ((m_pitchGraph && m_pitchGraph->hasGesture()) || (m_modGraph && m_modGraph->hasGesture()))
        return;
    snapshotControllerValues();
    if (m_pitchGraph) {
        m_pitchGraph->setBendRange(m_bendRange);
        snapshotCurve(m_pitchGraph.data(), DOC_CC_BEND);
    }
    if (m_modGraph)
        snapshotCurve(m_modGraph.data(), 1);
    emit controllerValuesChanged();
}

void PitchBendEditor::snapshotCurve(PitchBendGraph *graph, uint8_t cc)
{
    CurveSnapshot snapshot =
        readCurveSnapshot(m_document, m_engineTrack, cc, m_startTick, m_endTick);
    graph->setCurve(snapshot.points, snapshot.endValue);
}

bool PitchBendEditor::writeController(uint8_t cc, int value, int endValue)
{
    if (!noteSpanStillPresent())
        return false;
    m_document->writeLanePoints(m_engineTrack, cc, m_startTick, m_endTick,
                                {{m_startTick, value}, {m_endTick, endValue}});
    return true;
}

void PitchBendEditor::writeCurve(PitchBendGraph *graph)
{
    if (!noteSpanStillPresent())
        return;
    m_document->writeLanePoints(m_engineTrack, ccForGraph(graph), m_startTick, m_endTick,
                                graph->curvePoints());
}

void PitchBendEditor::markCurvePending(PitchBendGraph *graph)
{
    m_pendingGraph = graph;
    m_pending = PendingEdit::Curve;
}

void PitchBendEditor::commitCurve()
{
    if (m_pending != PendingEdit::Curve || m_pendingGraph.isNull())
        return;
    PitchBendGraph *graph = m_pendingGraph.data();
    m_pendingGraph.clear();
    m_pending = PendingEdit::None;
    writeCurve(graph);
}

void PitchBendEditor::cancelCurve()
{
    m_pendingGraph.clear();
    m_pending = PendingEdit::None;
}

uint8_t PitchBendEditor::ccForGraph(const PitchBendGraph *graph) const
{
    return graph == m_modGraph ? uint8_t{1} : DOC_CC_BEND;
}

void PitchBendEditor::updateDescription()
{
    const QString description =
        SongView::tr("BENDR is %1 semitones and LFO speed is %2 for this note. Edit pitch bend "
                     "and modulation; scroll inside the pitch bend graph to change BENDR, and "
                     "hold Shift while drawing for angled lines. Both lanes affect every sounding "
                     "note on this MIDI channel.")
            .arg(m_bendRange)
            .arg(m_lfoSpeed);
    const QString noteDescription =
        SongView::tr("%1 · note-scoped · channel-wide").arg(midiKeyName(m_noteSnapshot.key));
    if (description == m_description && noteDescription == m_noteDescription)
        return;
    m_description = description;
    m_noteDescription = noteDescription;
    emit appearanceChanged();
}

bool PitchBendEditor::noteSpanStillPresent() const
{
    return m_document && m_document->containsNoteSpan(m_engineTrack, m_noteSnapshot, m_endTick);
}

void PitchBendEditor::resolveChromeGeometry()
{
    m_geometry = PitchBendGeometry::resolve(chromeFont(m_songView), chromeDpr(m_songView));
}

void PitchBendEditor::rebuildCachedChrome()
{
    QVariantMap metrics;
    metrics.insert(QStringLiteral("popupWidth"), m_geometry.popupSize.width());
    metrics.insert(QStringLiteral("popupHeight"), m_geometry.popupSize.height());
    metrics.insert(QStringLiteral("headerHeight"), m_geometry.headerHeight);
    metrics.insert(QStringLiteral("graphHeight"), m_geometry.graphHeight);
    metrics.insert(QStringLiteral("outerInset"), m_geometry.outerInset);
    metrics.insert(QStringLiteral("titleHeight"), m_geometry.titleHeight);
    metrics.insert(QStringLiteral("descriptionHeight"), m_geometry.descriptionHeight);
    metrics.insert(QStringLiteral("controlsHeight"), m_geometry.controlsHeight);
    metrics.insert(QStringLiteral("fieldWidth"), m_geometry.fieldWidth);
    metrics.insert(QStringLiteral("fieldHeight"), m_geometry.fieldHeight);
    metrics.insert(QStringLiteral("resetWidth"), m_geometry.resetWidth);
    metrics.insert(QStringLiteral("resetHeight"), m_geometry.resetHeight);
    metrics.insert(QStringLiteral("axisLabelHeight"), m_geometry.axisLabelHeight);
    metrics.insert(QStringLiteral("scrubThreshold"), m_geometry.scrubThreshold);
    metrics.insert(QStringLiteral("hairline"), m_geometry.hairline);

    const QFont base = chromeFont(m_songView);
    QVariantMap appearance;
    appearance.insert(QStringLiteral("windowBackground"),
                      QVariant::fromValue(themes::color(themes::Role::window_background)));
    appearance.insert(QStringLiteral("primaryText"),
                      QVariant::fromValue(themes::color(themes::Role::song_view_primary_text)));
    appearance.insert(QStringLiteral("secondaryText"),
                      QVariant::fromValue(themes::color(themes::Role::song_view_secondary_text)));
    appearance.insert(QStringLiteral("outline"),
                      QVariant::fromValue(themes::color(themes::Role::menu_outline)));
    appearance.insert(QStringLiteral("focus"),
                      QVariant::fromValue(themes::color(themes::Role::focus_outline)));
    QVariantMap dragInput;
    dragInput.insert(QStringLiteral("background"),
                     QVariant::fromValue(themes::color(themes::Role::spin_box_background)));
    dragInput.insert(QStringLiteral("text"),
                     QVariant::fromValue(themes::color(themes::Role::spin_box_text)));
    dragInput.insert(QStringLiteral("outline"),
                     QVariant::fromValue(themes::color(themes::Role::spin_box_outline)));
    dragInput.insert(QStringLiteral("focus"),
                     QVariant::fromValue(themes::color(themes::Role::focus_outline)));
    dragInput.insert(QStringLiteral("font"), QVariant::fromValue(base));
    dragInput.insert(QStringLiteral("borderWidth"), m_geometry.hairline);
    dragInput.insert(QStringLiteral("radius"), layout::space(layout::Space::One));
    dragInput.insert(QStringLiteral("horizontalPadding"), layout::space(layout::Space::One));
    dragInput.insert(QStringLiteral("verticalPadding"), layout::space(layout::Space::Half));
    dragInput.insert(QStringLiteral("dragThreshold"), m_geometry.scrubThreshold);
    appearance.insert(QStringLiteral("dragInput"), dragInput);

    appearance.insert(QStringLiteral("trackColor"),
                      QVariant::fromValue(SongView::trackColor(m_engineTrack)));
    appearance.insert(QStringLiteral("font"), QVariant::fromValue(base));
    appearance.insert(QStringLiteral("titleFont"), QVariant::fromValue(typography::bold(base)));
    appearance.insert(QStringLiteral("captionFont"),
                      QVariant::fromValue(typography::caption(base)));
    appearance.insert(QStringLiteral("monospaceFont"),
                      QVariant::fromValue(typography::bodyMono(base)));

    const bool changed = metrics != m_metrics || appearance != m_appearance;
    m_metrics = std::move(metrics);
    m_appearance = std::move(appearance);
    if (changed)
        emit appearanceChanged();
}

void PitchBendEditor::refreshChrome()
{
    const QVariantMap previousMetrics = m_metrics;
    resolveChromeGeometry();
    rebuildCachedChrome();
    if (m_metrics != previousMetrics) {
        if (m_pitchGraph)
            m_pitchGraph->setMetrics(m_geometry);
        if (m_modGraph)
            m_modGraph->setMetrics(m_geometry);
    }
}

void PitchBendEditor::bindGraph(PitchBendGraph *graph, PitchBendGraph::Lane lane)
{
    if (!graph)
        return;
    PitchBendGraph::Callbacks callbacks;
    callbacks.previewChanged = [this, graph] { markCurvePending(graph); };
    callbacks.commitRequested = [this] { commitCurve(); };
    callbacks.cancelRequested = [this] { close(DismissAction::Cancel, CloseFocus::Restore); };
    // The modulation lane never emits this (it ignores the wheel); binding it
    // for both lanes preserves the widget popup's behavior exactly.
    callbacks.rangeChangeRequested = [this](int steps) { updateRange(steps); };
    callbacks.auditionRequested = [this] {
        commitCurve();
        if (m_songView)
            m_songView->requestPlayPauseFrom(m_startTick);
    };
    callbacks.grabLost = [this] { onGrabLost(); };

    CurveSnapshot snapshot = readCurveSnapshot(m_document.data(), m_engineTrack, ccForGraph(graph),
                                               m_startTick, m_endTick);
    graph->initialize({
        .songView = m_songView.data(),
        .engineTrack = m_engineTrack,
        .startTick = m_startTick,
        .endTick = m_endTick,
        .unterminated = m_unterminated,
        .lane = lane,
        .geometry = m_geometry,
        .bendRange = m_bendRange,
        .points = std::move(snapshot.points),
        .endValue = snapshot.endValue,
        .callbacks = std::move(callbacks),
    });
}

} // namespace songview
