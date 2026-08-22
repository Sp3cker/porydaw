#include "pitchbendeditor.hpp"

#include "theme/themeruntime.h"
#include "typography.h"
#include "ui/keymap.h"

#include <QApplication>
#include <QKeySequence>
#include <QMetaObject>
#include <QMouseEvent>
#include <QPainter>
#include <QSignalBlocker>
#include <QUndoStack>
#include <algorithm>
#include <cmath>
#include <map>
#include <utility>

namespace {
constexpr int kHostInset = 8;
constexpr int kNoteGap = 8;

QPoint hostClippedPopupPosition(const QRect &noteHost, const QRect &hostRect,
                                const QSize &popupSize)
{
    const QRect available = hostRect.adjusted(kHostInset, kHostInset, -kHostInset, -kHostInset);
    QPoint popupPos(noteHost.center().x() - popupSize.width() / 2,
                    noteHost.bottom() + 1 + kNoteGap);
    const int maxX = std::max(available.left(), available.right() - popupSize.width() + 1);
    const int maxY = std::max(available.top(), available.bottom() - popupSize.height() + 1);
    popupPos.setX(std::clamp(popupPos.x(), available.left(), maxX));
    if (popupPos.y() + popupSize.height() > available.bottom() + 1)
        popupPos.setY(noteHost.top() - kNoteGap - popupSize.height());
    popupPos.setY(std::clamp(popupPos.y(), available.top(), maxY));
    return popupPos;
}

class PitchBendCloseController final : public QObject
{
  public:
    PitchBendCloseController(QWidget *popup, std::function<bool(QPointF)> focusNoteUnderCursor,
                             std::function<void()> restoreFocus, std::function<void()> dismiss)
        : QObject(popup)
        , m_popup(popup)
        , m_focusNoteUnderCursor(std::move(focusNoteUnderCursor))
        , m_restoreFocus(std::move(restoreFocus))
        , m_dismiss(std::move(dismiss))
    {
        qApp->installEventFilter(this);
    }

    ~PitchBendCloseController() override { qApp->removeEventFilter(this); }

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (!m_popup || !m_popup->isVisible())
            return false;
        if (event->type() == QEvent::MouseButtonPress) {
            QWidget *target = qobject_cast<QWidget *>(watched);
            if (!target || target == m_popup || m_popup->isAncestorOf(target))
                return false;
            auto *mouseEvent = static_cast<QMouseEvent *>(event);
            if (m_focusNoteUnderCursor && m_focusNoteUnderCursor(mouseEvent->globalPosition())) {
                m_restoreFocus();
                event->accept();
                return true;
            }
            m_dismiss();
            return false;
        }
        if (event->type() == QEvent::ApplicationDeactivate ||
            (event->type() == QEvent::WindowDeactivate && watched == m_popup->window())) {
            m_dismiss();
            return false;
        }
        return false;
    }

  private:
    QPointer<QWidget> m_popup;
    std::function<bool(QPointF)> m_focusNoteUnderCursor;
    std::function<void()> m_restoreFocus;
    std::function<void()> m_dismiss;
};
} // namespace

namespace songview {

PitchBendEditor::PitchBendEditor(::SongView *songView, SongDocument *document, const DocNote &note,
                                 QPointer<QWidget> focusTarget,
                                 std::function<bool(QPointF)> focusNoteUnderCursor)
    : QFrame(songView->window())
    , m_songView(songView)
    , m_document(document)
    , m_focusTarget(focusTarget)
    , m_noteSnapshot(note)
    , m_engineTrack(note.engineTrack)
    , m_startTick(note.tick)
    , m_unterminated(note.unterminated())
{
    setObjectName(QStringLiteral("pitchBendPopup"));
    setFixedSize(kPopupWidth, kPopupHeight);
    setFocusPolicy(Qt::StrongFocus);
    setMouseTracking(true);
    setCursor(Qt::CrossCursor);
    setAccessibleName(SongView::tr("Note automation editor"));
    m_endTick = m_document->noteEndTick(m_noteSnapshot);
    m_pitchGraph = new PitchBendGraph(m_songView, m_engineTrack, m_startTick, m_endTick,
                                      m_unterminated, PitchBendGraph::Lane::PitchBend, this);
    m_modGraph = new PitchBendGraph(m_songView, m_engineTrack, m_startTick, m_endTick,
                                    m_unterminated, PitchBendGraph::Lane::ModWheel, this);
    const auto configureGraph = [this](PitchBendGraph *graph) {
        graph->installEventFilter(this);
        graph->setGeometry(0, graph == m_pitchGraph ? kHeaderHeight : kHeaderHeight + kGraphHeight,
                           kPopupWidth, kGraphHeight);
        PitchBendGraph::Callbacks callbacks;
        callbacks.previewChanged = [this, graph] {
            markCurvePending(graph);
            update();
        };
        callbacks.commitRequested = [this] { commitCurve(); };
        callbacks.cancelRequested = [this] { close(CloseState::Cancel, CloseFocus::Restore); };
        callbacks.auditionRequested = [this] {
            commitCurve();
            m_songView->requestPlayPauseFrom(m_startTick);
        };
        if (graph == m_pitchGraph)
            callbacks.rangeChangeRequested = [this](int steps) { updateRange(steps); };
        graph->setCallbacks(std::move(callbacks));
        graph->show();
    };
    configureGraph(m_pitchGraph);
    configureGraph(m_modGraph);
    const auto configureReset = [this](QPushButton *button, PitchBendGraph *graph, int y) {
        button->setGeometry(kPopupWidth - kOuterInset - kResetWidth, y, kResetWidth, kResetHeight);
        button->setFocusPolicy(Qt::NoFocus);
        button->setCursor(Qt::ArrowCursor);
        connect(button, &QPushButton::clicked, this, [this, graph] { resetCurve(graph); });
    };
    m_pitchResetButton = new QPushButton(SongView::tr("Reset"), this);
    m_pitchResetButton->setObjectName(QStringLiteral("pitchBendReset"));
    configureReset(m_pitchResetButton, m_pitchGraph, kHeaderHeight + 5);
    m_modResetButton = new QPushButton(SongView::tr("Reset"), this);
    m_modResetButton->setObjectName(QStringLiteral("modWheelReset"));
    configureReset(m_modResetButton, m_modGraph, kHeaderHeight + kGraphHeight + 5);
    const auto configureController = [this](QSpinBox *spin, const QString &name, int x) {
        spin->setObjectName(name);
        spin->setRange(0, 127);
        spin->setKeyboardTracking(false);
        spin->setGeometry(x, 36, 78, 24);
        spin->setCursor(Qt::ArrowCursor);
        spin->installEventFilter(this);
        for (QObject *child : spin->findChildren<QObject *>())
            child->installEventFilter(this);
    };
    m_bendRangeSpin = new QSpinBox(this);
    configureController(m_bendRangeSpin, QStringLiteral("bendRangeSpin"), 60);
    m_bendRangeSpin->setAccessibleName(SongView::tr("Pitch-bend range"));
    m_bendRangeSpin->setToolTip(SongView::tr("Pitch-bend range in semitones for this note"));
    connect(m_bendRangeSpin, &QSpinBox::valueChanged, this,
            [this](int value) { setBendRange(value); });
    m_lfoSpeedSpin = new QSpinBox(this);
    configureController(m_lfoSpeedSpin, QStringLiteral("lfoSpeedSpin"), 226);
    m_lfoSpeedSpin->setAccessibleName(SongView::tr("LFO speed"));
    m_lfoSpeedSpin->setToolTip(SongView::tr("M4A LFO speed for this note"));
    connect(m_lfoSpeedSpin, &QSpinBox::valueChanged, this,
            [this](int value) { setLfoSpeed(value); });
    snapshotCurves();
    updateDescription();
    connect(m_document->undoStack(), &QUndoStack::indexChanged, this, [this] {
        snapshotCurves();
        updateDescription();
        update();
    });
    connect(m_document, &SongDocument::documentChanged, this, [this] {
        if (!noteSpanStillPresent())
            close(CloseState::Cancel, CloseFocus::Restore);
    });
    new PitchBendCloseController(
        this, std::move(focusNoteUnderCursor),
        [this] { close(CloseState::Open, CloseFocus::Restore); },
        [this] { close(CloseState::Open, CloseFocus::Discard); });
}

void PitchBendEditor::cancelAndClose()
{
    close(CloseState::Cancel, CloseFocus::Restore);
}
void PitchBendEditor::cancelAndCloseWithoutFocus()
{
    close(CloseState::Cancel, CloseFocus::Discard);
}

void PitchBendEditor::openAt(const QRect &noteGlobal, double noteFraction)
{
    const double fraction = noteFraction >= 0.0 && noteFraction <= 1.0 ? noteFraction : 0.5;
    QWidget *host = parentWidget();
    const QRect noteHost(host->mapFromGlobal(noteGlobal.topLeft()),
                         host->mapFromGlobal(noteGlobal.bottomRight()));
    const QPoint popupPos = hostClippedPopupPosition(noteHost, host->rect(), size());
    m_pitchGraph->setKeyboardFraction(fraction);
    m_modGraph->setKeyboardFraction(fraction);
    move(popupPos);
    show();
    raise();
    m_pitchGraph->setFocus(Qt::PopupFocusReason);
}

bool PitchBendEditor::hasEditableSpan() const
{
    return m_endTick > m_startTick;
}

uint64_t PitchBendEditor::endTick() const
{
    return m_endTick;
}

QRect PitchBendEditor::graphRect() const
{
    return m_pitchGraph ? m_pitchGraph->canvasRect().translated(m_pitchGraph->pos()) : QRect();
}

QRect PitchBendEditor::modGraphRect() const
{
    return m_modGraph ? m_modGraph->canvasRect().translated(m_modGraph->pos()) : QRect();
}

void PitchBendEditor::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.fillRect(rect(), themes::color(themes::Role::window_background));
    painter.setPen(QPen(themes::color(themes::Role::menu_outline), 1));
    painter.drawRect(rect().adjusted(0, 0, -1, -1));
    painter.setFont(typography::bold(font()));
    painter.setPen(themes::color(themes::Role::song_view_primary_text));
    painter.drawText(QRect(kOuterInset, 3, width() - 2 * kOuterInset, 17),
                     Qt::AlignLeft | Qt::AlignVCenter, SongView::tr("Note automation"));
    painter.setFont(typography::caption(font()));
    painter.setPen(themes::color(themes::Role::song_view_secondary_text));
    painter.drawText(
        QRect(kOuterInset, 19, width() - 2 * kOuterInset, 15), Qt::AlignLeft | Qt::AlignVCenter,
        SongView::tr("%1 · note-scoped · channel-wide").arg(midiKeyName(m_noteSnapshot.key)));
    painter.drawText(QRect(kOuterInset, 36, 48, 24), Qt::AlignLeft | Qt::AlignVCenter,
                     SongView::tr("BENDR"));
    painter.drawText(QRect(156, 36, 66, 24), Qt::AlignLeft | Qt::AlignVCenter,
                     SongView::tr("LFO speed"));
}

bool PitchBendEditor::event(QEvent *event)
{
    if (event->type() == QEvent::ShortcutOverride) {
        auto *keyEvent = static_cast<QKeyEvent *>(event);
        if (keyEvent->matches(QKeySequence::Undo) ||
            keymap::Registry::instance().matches(keyEvent,
                                                 QStringLiteral("transport.play_pause"))) {
            event->accept();
            return true;
        }
    }
    return QFrame::event(event);
}
bool PitchBendEditor::eventFilter(QObject *watched, QEvent *event)
{
    PitchBendGraph *watchedGraph = nullptr;
    if (watched == m_pitchGraph)
        watchedGraph = m_pitchGraph;
    else if (watched == m_modGraph)
        watchedGraph = m_modGraph;
    if (event->type() != QEvent::ShortcutOverride && event->type() != QEvent::KeyPress)
        return QFrame::eventFilter(watched, event);
    auto *keyEvent = static_cast<QKeyEvent *>(event);
    if (keyEvent->matches(QKeySequence::Undo)) {
        if (event->type() == QEvent::KeyPress)
            undoCurve();
        event->accept();
        return true;
    }
    if (event->type() == QEvent::ShortcutOverride &&
        keymap::Registry::instance().matches(keyEvent, QStringLiteral("transport.play_pause"))) {
        event->accept();
        return true;
    }
    if (event->type() == QEvent::KeyPress && tryDeleteSelectedVertex(watchedGraph, keyEvent))
        return true;
    return QFrame::eventFilter(watched, event);
}

void PitchBendEditor::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Escape) {
        close(CloseState::Cancel, CloseFocus::Restore);
        event->accept();
        return;
    }
    if (event->matches(QKeySequence::Undo)) {
        undoCurve();
        event->accept();
        return;
    }
    if (tryDeleteSelectedVertex(focusedGraph(), event))
        return;
    if (PitchBendGraph *graph = focusedGraph(); graph && graph->handleKeyPress(event))
        return;
    // Only solo routes out of the popup; the remaining roll edit commands
    // must not reach the song while the note automation popup has focus.
    if (m_songView &&
        keymap::Registry::instance().matches(event, QStringLiteral("roll.solo_tracks"))) {
        m_songView->toggleSoloOnSelectedTracks();
        event->accept();
        return;
    }
    event->accept();
}

void PitchBendEditor::focusInEvent(QFocusEvent *event)
{
    QFrame::focusInEvent(event);
    update();
    m_pitchGraph->update();
    m_modGraph->update();
}

void PitchBendEditor::focusOutEvent(QFocusEvent *event)
{
    QFrame::focusOutEvent(event);
    update();
    m_pitchGraph->update();
    m_modGraph->update();
}

void PitchBendEditor::hideEvent(QHideEvent *event)
{
    QFrame::hideEvent(event);
    if (m_closeState == CloseState::Closed)
        return;
    m_pitchGraph->cancelGesture();
    m_modGraph->cancelGesture();
    if (m_closeState == CloseState::Cancel)
        cancelCurve();
    else
        commitCurve();
    m_closeState = CloseState::Closed;
    if (m_closeFocus == CloseFocus::Restore && m_focusTarget) {
        const QPointer<QWidget> focusTarget = m_focusTarget;
        QMetaObject::invokeMethod(
            focusTarget,
            [focusTarget] {
                if (focusTarget)
                    focusTarget->setFocus(Qt::PopupFocusReason);
            },
            Qt::QueuedConnection);
    }
    deleteLater();
}

PitchBendGraph *PitchBendEditor::focusedGraph() const
{
    return m_modGraph && m_modGraph->hasFocus() ? m_modGraph : m_pitchGraph;
}

bool PitchBendEditor::tryDeleteSelectedVertex(PitchBendGraph *graph, QKeyEvent *event)
{
    const bool deleting = event->key() == Qt::Key_Delete || event->key() == Qt::Key_Backspace;
    if (!deleting || !graph || !graph->selectedTick())
        return false;
    if (noteSpanStillPresent())
        graph->removeSelectedVertex();
    event->accept();
    return true;
}

uint8_t PitchBendEditor::ccForGraph(const PitchBendGraph *graph) const
{
    return graph == m_modGraph ? uint8_t{1} : DOC_CC_BEND;
}

void PitchBendEditor::undoCurve()
{
    m_pitchGraph->cancelGesture();
    m_modGraph->cancelGesture();
    cancelCurve();
    if (!m_document->undoStack()->canUndo())
        return;
    m_document->undoStack()->undo();
}

void PitchBendEditor::resetCurve(PitchBendGraph *graph)
{
    graph->resetCurve();
    commitCurve();
    graph->setFocus(Qt::MouseFocusReason);
    update();
}

void PitchBendEditor::snapshotCurves()
{
    if (m_pitchGraph->hasGesture() || m_modGraph->hasGesture())
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
    const QSignalBlocker bendBlocker(m_bendRangeSpin);
    const QSignalBlocker lfoBlocker(m_lfoSpeedSpin);
    m_bendRangeSpin->setValue(m_bendRange);
    m_lfoSpeedSpin->setValue(m_lfoSpeed);
    m_pitchGraph->setBendRange(m_bendRange);
    snapshotCurve(m_pitchGraph, DOC_CC_BEND);
    snapshotCurve(m_modGraph, 1);
}

void PitchBendEditor::snapshotCurve(PitchBendGraph *graph, uint8_t cc)
{
    const auto points = m_document->lanePoints(m_engineTrack, cc);
    std::map<uint64_t, int> curve;
    int enteringValue = 0;
    int endValue = 0;
    for (const DocLanePoint &point : points) {
        if (point.tick <= m_startTick)
            enteringValue = point.value;
        if (point.tick <= m_endTick)
            endValue = point.value;
        if (point.tick > m_startTick && point.tick < m_endTick)
            curve[point.tick] = point.value;
    }
    curve[m_startTick] = enteringValue;
    curve[m_endTick] = endValue;
    graph->setCurve(curve, endValue);
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
    if (m_pending != PendingEdit::Curve || !m_pendingGraph)
        return;
    PitchBendGraph *graph = m_pendingGraph;
    m_pendingGraph = nullptr;
    m_pending = PendingEdit::None;
    writeCurve(graph);
}

void PitchBendEditor::cancelCurve()
{
    m_pendingGraph = nullptr;
    m_pending = PendingEdit::None;
}

void PitchBendEditor::updateRange(int steps)
{
    m_bendRangeSpin->setValue(std::clamp(m_bendRange + steps, 0, 127));
}

void PitchBendEditor::setBendRange(int range)
{
    range = std::clamp(range, 0, 127);
    if (range == m_bendRange)
        return;
    if (!writeController(0x14, range, m_endRange)) {
        const QSignalBlocker blocker(m_bendRangeSpin);
        m_bendRangeSpin->setValue(m_bendRange);
        return;
    }
    m_bendRange = range;
    m_pitchGraph->setBendRange(range);
    updateDescription();
    update();
}

void PitchBendEditor::setLfoSpeed(int speed)
{
    speed = std::clamp(speed, 0, 127);
    if (speed == m_lfoSpeed)
        return;
    if (!writeController(0x15, speed, m_endLfoSpeed)) {
        const QSignalBlocker blocker(m_lfoSpeedSpin);
        m_lfoSpeedSpin->setValue(m_lfoSpeed);
        return;
    }
    m_lfoSpeed = speed;
    updateDescription();
    update();
}

void PitchBendEditor::close(CloseState state, CloseFocus focus)
{
    if (m_closeState == CloseState::Closed)
        return;
    m_pitchGraph->cancelGesture();
    m_modGraph->cancelGesture();
    m_closeState = state;
    m_closeFocus = focus;
    hide();
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
    setAccessibleDescription(description);
    setToolTip(description);
}

bool PitchBendEditor::noteSpanStillPresent() const
{
    return m_document && m_document->containsNoteSpan(m_engineTrack, m_noteSnapshot, m_endTick);
}

} // namespace songview
