#include "pitchbendeditor.hpp"

#include "core/m4asemantics.h"
#include "layout.h"

#include "songview.h"
#include "theme/themeruntime.h"
#include "typography.h"
#include "ui/keymap.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelinequickview.h"

#include <QCoreApplication>
#include <QDebug>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMouseEvent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QUndoStack>
#include <QUrl>
#include <QVariant>
#include <algorithm>
#include <map>
#include <mutex>
#include <utility>

namespace {
// Editor chrome takes the current application font; the coordinator no
// longer carries widget fonts.
QFont chromeFont()
{
    return QGuiApplication::font();
}

// Effective DPR of the actual Quick window; safe identity before the
// window exists or after the coordinator detaches.
qreal chromeDpr(const QPointer<::SongView> &songView)
{
    return songView ? songView->quickView()->quickDevicePixelRatio() : 1.0;
}

struct CurveSnapshot {
    std::map<Tick, int> points;
    int endValue = 0;
};

CurveSnapshot readCurveSnapshot(const SongDocument *document, int engineTrack, uint8_t cc,
                                Tick startTick, Tick endTick)
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
    , m_focusNoteUnderCursor(std::move(focusNoteUnderCursor))
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
            cancelAndClose();
    });
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
    m_document->writeLanePoints(m_engineTrack, cc, Tick(m_startTick), Tick(m_endTick),
                                {{Tick(m_startTick), value}, {Tick(m_endTick), endValue}});
    return true;
}

void PitchBendEditor::writeCurve(PitchBendGraph *graph)
{
    if (!noteSpanStillPresent())
        return;
    m_document->writeLanePoints(m_engineTrack, ccForGraph(graph), Tick(m_startTick),
                                Tick(m_endTick), graph->curvePoints());
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
    m_geometry = PitchBendGeometry::resolve(chromeFont(), chromeDpr(m_songView));
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

    const QFont base = chromeFont();
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
    callbacks.cancelRequested = [this] { cancelAndClose(); };
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
                                               Tick(m_startTick), Tick(m_endTick));
    graph->initialize({
        .songView = m_songView.data(),
        .engineTrack = m_engineTrack,
        .startTick = Tick(m_startTick),
        .endTick = Tick(m_endTick),
        .unterminated = m_unterminated,
        .lane = lane,
        .geometry = m_geometry,
        .bendRange = m_bendRange,
        .points = std::move(snapshot.points),
        .endValue = snapshot.endValue,
        .callbacks = std::move(callbacks),
    });
}

// The shared canvas engine loads PitchBendPopup.qml through the popup
// session; registering the graph type before the first popup load keeps the
// imperative QML type visible to that engine's later component creations.
void registerPitchBendGraphOnce()
{
    static std::once_flag registered;
    std::call_once(registered, [] {
        qmlRegisterType<songview::PitchBendGraph>("Porydaw.Ui", 1, 0, "PitchBendGraph");
    });
}

PitchBendEditor::~PitchBendEditor()
{
    // Owner/tab teardown cancels unsettled work and never restores focus.
    dispose(DismissAction::Cancel, CloseFocus::Discard, /*deferTeardown=*/false);
}

void PitchBendEditor::cancelAndClose()
{
    dispose(DismissAction::Cancel, CloseFocus::Restore);
}

void PitchBendEditor::cancelAndCloseWithoutFocus()
{
    dispose(DismissAction::Cancel, CloseFocus::Discard);
}

void PitchBendEditor::openAt(const QRectF &noteScene, double noteFraction)
{
    QuickPopupSession *session =
        m_songView && m_songView->quickView() ? m_songView->quickView()->popupSession() : nullptr;
    if (!isOpen() || !session || !session->window()) {
        dispose(DismissAction::Cancel, CloseFocus::Discard, /*deferTeardown=*/false);
        return;
    }
    registerPitchBendGraphOnce();
    // The pitch editor owns note anchoring and outside-click retargeting. The
    // shared session only owns the common overlay lifetime and shortcut
    // arbitration. Open before connecting to session dismissal: replacement
    // first retires the prior owner, whose signals must not dispose this one.
    m_noteAnchor = noteScene;
    if (!session->openSurface(QUrl(QStringLiteral("qrc:/qt/qml/Porydaw/Ui/PitchBendPopup.qml")),
                              this)) {
        dispose(DismissAction::Cancel, CloseFocus::Discard);
        return;
    }
    m_session = session;
    m_sessionWindow = session->window();
    // Document undo claims its chord before Quick child-first delivery (see
    // eventFilter); the application filter only refreshes cached chrome and
    // never dismisses anything.
    m_sessionWindow->installEventFilter(this);
    QCoreApplication::instance()->installEventFilter(this);
    m_sessionClosedConnection = connect(session, &QuickPopupSession::closed, this, [this] {
        dispose(DismissAction::Commit, CloseFocus::Discard);
    });
    m_sessionCancelledConnection =
        connect(session, &QuickPopupSession::cancelled, this, [this](bool restoreFocus) {
            dispose(DismissAction::Commit,
                    restoreFocus ? CloseFocus::Restore : CloseFocus::Discard);
        });

    QQuickItem *const root = session->contentItem();
    if (!root) {
        qCritical("QuickPopupSession opened pitch-bend surface without QML content");
        dispose(DismissAction::Cancel, CloseFocus::Discard);
        return;
    }
    connect(root, &QQuickItem::implicitWidthChanged, this, &PitchBendEditor::placeContent);
    connect(root, &QQuickItem::implicitHeightChanged, this, &PitchBendEditor::placeContent);
    placeContent();
    PitchBendGraph *pitchGraph =
        root ? qobject_cast<PitchBendGraph *>(
                   root->findChild<QQuickItem *>(QStringLiteral("pitchBendGraph")))
             : nullptr;
    PitchBendGraph *modGraph = root ? qobject_cast<PitchBendGraph *>(root->findChild<QQuickItem *>(
                                          QStringLiteral("modWheelGraph")))
                                    : nullptr;
    if (!pitchGraph || !modGraph) {
        if (!pitchGraph)
            qCritical("Qt Quick pitch-bend popup QML has no PitchBendGraph named pitchBendGraph");
        if (!modGraph)
            qCritical("Qt Quick pitch-bend popup QML has no PitchBendGraph named modWheelGraph");
        dispose(DismissAction::Cancel, CloseFocus::Discard);
        return;
    }
    m_pitchGraph = pitchGraph;
    m_modGraph = modGraph;
    // Graphs belong to the shared surface content; bind complete document
    // snapshots synchronously so no graph can receive input uninitialized.
    bindGraph(m_pitchGraph.data(), PitchBendGraph::Lane::PitchBend);
    bindGraph(m_modGraph.data(), PitchBendGraph::Lane::ModWheel);
    const double fraction = noteFraction >= 0.0 && noteFraction <= 1.0 ? noteFraction : 0.5;
    m_pitchGraph->setKeyboardFraction(fraction);
    m_modGraph->setKeyboardFraction(fraction);
    m_pitchGraph->forceActiveFocus(Qt::PopupFocusReason);
}

void PitchBendEditor::placeContent()
{
    QuickPopupSession *const session = m_session.data();
    QQuickWindow *const window = m_sessionWindow.data();
    QQuickItem *const content = session ? session->contentItem() : nullptr;
    if (!session || !window || !content || !session->owns(this))
        return;

    const qreal width = content->implicitWidth();
    const qreal height = content->implicitHeight();
    if (width <= 0.0 || height <= 0.0)
        return;

    content->setWidth(width);
    content->setHeight(height);
    content->setScale(1.0);
    const qreal margin = layout::space(layout::Space::One);
    const qreal gap = layout::space(layout::Space::One);
    const qreal maxX = std::max(margin, window->width() - margin - width);
    const qreal x = std::round(std::clamp(m_noteAnchor.center().x() - width / 2.0, margin, maxX));
    qreal y = m_noteAnchor.bottom() + layout::singlePixel() + gap;
    if (y + height > window->height() - margin)
        y = m_noteAnchor.top() - gap - height;
    const qreal maxY = std::max(margin, window->height() - margin - height);
    content->setPosition(QPointF{x, std::round(std::clamp(y, margin, maxY))});
}

void PitchBendEditor::dispose(DismissAction action, CloseFocus focus, bool deferTeardown)
{
    if (m_lifecycle != Lifecycle::Open)
        return;
    // Set the lifecycle guard before callbacks can write: each dismissal
    // settles exactly once on every close, tab, document, and path where the
    // session itself initiated the cancellation.
    m_lifecycle = Lifecycle::Closed;
    if (m_pitchGraph)
        m_pitchGraph->cancelGesture();
    if (m_modGraph)
        m_modGraph->cancelGesture();
    if (action == DismissAction::Cancel)
        cancelCurve();
    else
        commitCurve();
    m_pitchGraph.clear();
    m_modGraph.clear();
    m_pendingGraph.clear();
    QCoreApplication::instance()->removeEventFilter(this);
    if (m_sessionWindow)
        m_sessionWindow->removeEventFilter(this);
    m_sessionWindow.clear();
    // Restore-focus policy rides the session cancellation itself; the
    // cancelled()/closed() handlers re-enter through the Closed guard.
    if (QuickPopupSession *session = m_session.data();
        session && session->isOpen() && session->owns(this)) {
        if (action == DismissAction::Cancel)
            session->cancel(focus == CloseFocus::Restore);
        else
            session->close();
    }
    m_session.clear();
    if (deferTeardown)
        deleteLater();
}

bool PitchBendEditor::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_sessionWindow.data() && m_lifecycle == Lifecycle::Open) {
        switch (event->type()) {
        case QEvent::MouseButtonPress: {
            const auto *const mouseEvent = static_cast<QMouseEvent *>(event);
            const QPointer<QuickPopupSession> session = m_session;
            if (!session || !session->owns(this))
                break;
            const QPointer<QQuickItem> content = session->contentItem();
            if (!content)
                break;
            const QPointF scenePos = mouseEvent->position();
            if (content->mapRectToScene(content->boundingRect()).contains(scenePos))
                break;

            // Cancel can settle this editor and schedule its deletion. Copy
            // every needed value first and do not touch editor state after it.
            const std::function<bool(QPointF)> focusNoteUnderCursor = m_focusNoteUnderCursor;
            const bool consume = focusNoteUnderCursor && focusNoteUnderCursor(scenePos);
            if (session)
                session->cancel(consume);
            return consume;
        }
        case QEvent::Resize:
            placeContent();
            break;
        case QEvent::KeyPress: {
            // Pre-delivery: document undo wins before a focused TextInput can
            // turn the chord into a local text undo.
            auto *keyEvent = static_cast<QKeyEvent *>(event);
            if (keyEvent->matches(QKeySequence::Undo)) {
                undoCurve();
                event->accept();
                return true;
            }
            break;
        }
        default:
            break;
        }
    }
    if (watched == QCoreApplication::instance() && m_lifecycle == Lifecycle::Open) {
        if (event->type() == QEvent::ApplicationPaletteChange ||
            event->type() == QEvent::ApplicationFontChange)
            refreshChrome();
    }
    return QObject::eventFilter(watched, event);
}

bool PitchBendEditor::handleUnclaimedKeyPress(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace) {
        if (PitchBendGraph *graph = focusedGraph(); graph && graph->selectedTick()) {
            if (noteSpanStillPresent())
                graph->removeSelectedVertex();
            return true;
        }
    }
    if (PitchBendGraph *graph = focusedGraph(); graph && graph->handleKeyPress(event))
        return true;
    // Only solo routes out of the popup; the remaining roll edit commands
    // must not reach the song while the note automation popup has focus.
    if (m_songView && keymap::Registry::instance().matches(event->key(), event->modifiers(),
                                                           QStringLiteral("roll.solo_tracks"))) {
        m_songView->toggleSoloOnSelectedTracks();
        return true;
    }
    return false;
}

bool PitchBendEditor::routeUnclaimedKey(int key, int modifiers, bool autoRepeat)
{
    if (m_lifecycle != Lifecycle::Open)
        return false;
    QKeyEvent event(QEvent::KeyPress, key, Qt::KeyboardModifiers(modifiers), QString(), autoRepeat);
    return handleUnclaimedKeyPress(&event);
}

} // namespace songview
