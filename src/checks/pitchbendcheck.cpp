#include "pitchbendcheck_internal.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QCursor>
#include <QKeyEvent>
#include <QKeySequence>
#include <QMetaObject>
#include <QMouseEvent>
#include <QObject>
#include <QPointer>
#include <QPushButton>
#include <QSpinBox>
#include <QUndoCommand>
#include <QWheelEvent>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#include "ui/curvegraph/curvegraph.hpp"
#include "ui/pitchbendeditor.hpp"

namespace pitchbendcheck {

void sendMouse(QWidget *widget, QEvent::Type type, QPoint pos, Qt::MouseButton button,
               Qt::MouseButtons buttons, Qt::KeyboardModifiers modifiers)
{
    QMouseEvent event(type, QPointF(pos), QPointF(widget->mapToGlobal(pos)), button, buttons,
                      modifiers);
    QCoreApplication::sendEvent(widget, &event);
}

void sendWheel(QWidget *widget, QPointF pos, int angleDeltaY, int pixelDeltaY,
               Qt::KeyboardModifiers modifiers, int pixelDeltaX)
{
    QWheelEvent event(pos, QPointF(widget->mapToGlobal(pos.toPoint())),
                      QPoint(pixelDeltaX, pixelDeltaY), QPoint(0, angleDeltaY), Qt::NoButton,
                      modifiers, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(widget, &event);
}

void sendKey(QWidget *widget, int key, Qt::KeyboardModifiers modifiers)
{
    QKeyEvent press(QEvent::KeyPress, key, modifiers);
    QCoreApplication::sendEvent(widget, &press);
    QKeyEvent release(QEvent::KeyRelease, key, modifiers);
    QCoreApplication::sendEvent(widget, &release);
}

bool sendStandardUndo(QWidget *widget)
{
    const auto bindings = QKeySequence::keyBindings(QKeySequence::Undo);
    if (bindings.empty())
        return false;
    const QKeyCombination combination = bindings.front()[0];
    QKeyEvent shortcutEvent(QEvent::ShortcutOverride, combination.key(),
                            combination.keyboardModifiers());
    QCoreApplication::sendEvent(widget, &shortcutEvent);
    if (!shortcutEvent.isAccepted())
        return false;
    sendKey(widget, combination.key(), combination.keyboardModifiers());
    return true;
}

void drainPopupDeletes()
{
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
}

void dismissPopup(QPointer<songview::PitchBendEditor> &popup)
{
    if (!popup)
        return;
    QPointer<QWidget> focus = QApplication::focusWidget();
    if (focus && (focus.data() == popup.data() || popup->isAncestorOf(focus.data())))
        sendKey(focus.data(), Qt::Key_Escape, Qt::NoModifier);
    else
        sendKey(popup.data(), Qt::Key_Escape, Qt::NoModifier);
    QCoreApplication::processEvents();
    if (popup && popup->isVisible())
        sendKey(popup.data(), Qt::Key_Escape, Qt::NoModifier);
    drainPopupDeletes();
}

PitchBendCheckContext::PitchBendCheckContext(SongDocument &document, SongView &view, QWidget *roll,
                                             int engineTrack, const DocNote &note,
                                             const QPoint &noteCenter, const QString &songLabel)
    : m_document(document)
    , m_view(view)
    , m_roll(roll)
    , m_engineTrack(engineTrack)
    , m_note(note)
    , m_noteCenter(noteCenter)
    , m_songLabel(songLabel)
{}

int PitchBendCheckContext::run()
{
    const bool viewWasVisible = m_view.isVisible();
    if (!viewWasVisible) {
        m_view.show();
        QCoreApplication::processEvents();
    }
    m_endTick = m_document.noteEndTick(m_note);
    installRangeFixture();
    m_beforeBend = m_document.smf().write();
    m_undoIndex = m_document.undoStack()->index();
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, DOC_CC_BEND)) {
        if (point.tick <= m_endTick)
            m_bendAtEnd = point.value;
    }
    runDuplicateAnchor();
    runSnapshotDuringGesture();
    runLifecycleCancellation();
    runRangeFreehandAndUndo();
    runVertexEditing();
    runModWheelEditing();
    runPointClickAndEscape();
    runModWheelShiftLine();
    runPersistedAltRendering();
    runResetAndAudition();
    runFocusHandoff();
    cleanupBaseFixture();
    runActiveGridBoundary();
    if (!viewWasVisible)
        m_view.hide();
    return m_failures;
}

void PitchBendCheckContext::fail(const char *what)
{
    std::fprintf(stderr, "rollcheck: FAIL %s: %s\n", qUtf8Printable(m_songLabel), what);
    m_failures++;
}

void PitchBendCheckContext::installRangeFixture()
{
    m_beforeRange = m_document.smf().write();
    m_beforeRangeUndoIndex = m_document.undoStack()->index();
    m_document.writeLanePoints(m_engineTrack, 0x14, m_note.tick, m_note.tick, {{m_note.tick, 12}});
    if (m_document.undoStack()->index() != m_beforeRangeUndoIndex + 1)
        fail("BENDR fixture did not push exactly one undo command");
}

PitchBendCheckContext::RangePopupState PitchBendCheckContext::openRangePopup()
{
    const QPoint noteGlobal = m_roll->mapToGlobal(m_noteCenter);
    QCursor::setPos(noteGlobal + QPoint(300, 0));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *bendPopup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!bendPopup || !bendPopup->isVisible()) {
        fail("G did not open the selected note's pitch-bend popup");
        return {};
    }
    if (bendPopup->isWindow() || QApplication::activePopupWidget() == bendPopup)
        fail("pitch-bend editor used a native popup window");
    const QPoint popupCenter = bendPopup->mapToGlobal(bendPopup->rect().center());
    QWidget *host = bendPopup->parentWidget();
    const QRect hostGlobal(host->mapToGlobal(host->rect().topLeft()), host->rect().size());
    const QRect available = hostGlobal.adjusted(8, 8, -8, -8);
    const int maxLeft = std::max(available.left(), available.right() - bendPopup->width() + 1);
    const int expectedLeft =
        std::clamp(noteGlobal.x() - bendPopup->width() / 2, available.left(), maxLeft);
    const int expectedCenter = expectedLeft + bendPopup->rect().center().x();
    if (std::abs(popupCenter.x() - expectedCenter) > 12)
        fail("pitch-bend popup followed the mouse instead of the selected note");
    int expectedBendRange = 0;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, 0x14)) {
        if (point.tick <= m_note.tick)
            expectedBendRange = point.value;
    }
    if (!bendPopup->accessibleDescription().contains(
            QStringLiteral("%1 semitones").arg(expectedBendRange))) {
        fail(qUtf8Printable(QStringLiteral("pitch-bend popup active BENDR description was: %1")
                                .arg(bendPopup->accessibleDescription())));
    }
    const QRect graph = bendPopup->graphRect();
    auto *graphWidget = dynamic_cast<songview::CurveGraph *>(
        bendPopup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")));
    if (!graphWidget) {
        fail("pitch-bend popup has no CurveGraph pitchBendGraph child");
        return {};
    }
    sendMouse(graphWidget, QEvent::MouseMove, graphWidget->mapFrom(bendPopup, graph.center()),
              Qt::NoButton, Qt::NoButton);
    if (!bendPopup->isVisible())
        fail("idle mouse movement dismissed the pitch-bend popup");
    return {bendPopup, graphWidget, graph};
}

void PitchBendCheckContext::verifyRangeWheelConfinement(const RangePopupState &range)
{
    sendWheel(range.graphWidget,
              QPointF(range.graphWidget->mapFrom(
                  range.popup, QPoint(range.graph.left() - 4, range.graph.top() - 4))),
              120, 0, Qt::NoModifier);
    if (m_document.undoStack()->index() != m_undoIndex)
        fail("scrolling outside the pitch-bend graph changed BENDR");
    sendWheel(range.graphWidget,
              QPointF(range.graphWidget->mapFrom(range.popup, QPoint(range.graph.center()))), 120,
              0, Qt::NoModifier);
    if (m_document.undoStack()->index() != m_undoIndex + 1)
        fail("graph scroll did not push one note-scoped BENDR edit");
    if (!range.popup->accessibleDescription().contains(QStringLiteral("13 semitones")))
        fail("graph scroll did not update the presented BENDR value");
    bool setRangeAtStart = false;
    bool restoredRangeAtEnd = false;
    for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, 0x14)) {
        if (point.tick == m_note.tick && point.value == 13)
            setRangeAtStart = true;
        if (point.tick == m_endTick && point.value == 12)
            restoredRangeAtEnd = true;
    }
    if (!setRangeAtStart || !restoredRangeAtEnd)
        fail("graph scroll did not confine BENDR to the selected note");
}

void PitchBendCheckContext::verifyRangeCurve()
{
    const std::vector<DocLanePoint> written = m_document.lanePoints(m_engineTrack, DOC_CC_BEND);
    bool drewBend = false;
    bool restoredEnd = false;
    for (const DocLanePoint &point : written) {
        if (point.tick >= m_note.tick && point.tick < m_endTick && point.value != 0)
            drewBend = true;
        if (point.tick == m_endTick && point.value == m_bendAtEnd)
            restoredEnd = true;
    }
    if (!drewBend)
        fail("pitch-bend popup wrote no nonzero curve inside the note");
    if (!restoredEnd)
        fail("pitch-bend popup did not restore the note-off bend state");
}

void PitchBendCheckContext::verifyRangeRawPitchWheel()
{
    bool rawPitchWheel = false;
    const int smfTrack = m_document.smfTrackFor(m_engineTrack);
    if (smfTrack >= 0) {
        for (const SmfEvent &event : m_document.smf().tracks[size_t(smfTrack)].events) {
            if (event.tick >= m_note.tick && event.tick <= m_endTick && event.typeNibble() == 0xE) {
                rawPitchWheel = true;
                if (event.data0 > 0x7F || event.data1 > 0x7F)
                    fail("pitch-bend popup wrote an invalid SMF data byte");
            }
        }
    }
    if (!rawPitchWheel)
        fail("pitch-bend popup did not serialize SMF pitch-wheel events");
}

void PitchBendCheckContext::undoRangeFreehand()
{
    m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != m_curveUndoIndex ||
        m_document.smf().write() != m_beforeCurve)
        fail("undo did not restore the document after pitch-bend drawing");
}

void PitchBendCheckContext::runDuplicateAnchor()
{
    const MidiTimeline *originalTimeline = m_view.timeline();
    if (!originalTimeline) {
        fail("duplicate-anchor check had no timeline");
        return;
    }
    auto duplicateTimeline = m_document.buildTimeline(48000.0);
    if (!duplicateTimeline) {
        fail("duplicate-anchor check could not build a timeline");
        return;
    }
    TimelineEvent duplicateOn{};
    duplicateOn.tick = uint32_t(m_note.tick);
    duplicateOn.type = 0x9;
    duplicateOn.track = uint8_t(m_engineTrack);
    duplicateOn.data0 = m_note.key;
    duplicateOn.data1 = m_note.velocity;
    duplicateOn.noteId = NoteId{UINT64_MAX};
    TimelineEvent duplicateOff = duplicateOn;
    duplicateOff.tick = uint32_t(m_note.tick + 1);
    duplicateOff.type = 0x8;
    duplicateOff.data1 = 0;
    duplicateOff.noteId = {};
    duplicateTimeline->events.insert(duplicateTimeline->events.begin(), duplicateOff);
    duplicateTimeline->events.insert(duplicateTimeline->events.begin(), duplicateOn);
    m_view.updateSong(duplicateTimeline.get());
    m_view.selectionModel().setNoteSelection({m_note.noteId});
    const RangePopupState range = openRangePopup();
    if (range.popup) {
        sendKey(range.popup, Qt::Key_Escape, Qt::NoModifier);
        drainPopupDeletes();
    }
    m_view.updateSong(originalTimeline);
    m_view.selectionModel().setNoteSelection({m_note.noteId});
    const QByteArray beforeIdentity = m_document.smf().write();
    const int identityUndoIndex = m_document.undoStack()->index();
    m_document.deleteNotes({m_note});
    m_document.addNote(m_engineTrack, m_note.tick, m_note.key, m_note.duration, m_note.velocity);
    DocNote replacement;
    if (!m_document.findNote(m_engineTrack, m_note.tick, m_note.key, &replacement) ||
        replacement.noteId == m_note.noteId ||
        m_document.containsNoteSpan(m_engineTrack, m_note, m_endTick))
        fail("same-tick replacement note satisfied the original pitch-bend span");
    while (m_document.undoStack()->index() > identityUndoIndex && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != identityUndoIndex ||
        m_document.smf().write() != beforeIdentity)
        fail("duplicate-anchor identity check did not restore the document");
    m_view.selectionModel().setNoteSelection({m_note.noteId});
}

void PitchBendCheckContext::runSnapshotDuringGesture()
{
    const RangePopupState range = openRangePopup();
    if (!range.popup || !range.graphWidget)
        return;
    auto *graph = range.graphWidget;
    const int beforeUndoIndex = m_document.undoStack()->index();
    const QByteArray before = m_document.smf().write();
    const QPoint start(range.graph.left() + range.graph.width() / 3, range.graph.center().y());
    const QPoint finish(range.graph.left() + 2 * range.graph.width() / 3,
                        range.graph.top() + range.graph.height() / 3);
    sendMouse(graph, QEvent::MouseButtonPress, graph->mapFrom(range.popup, start), Qt::LeftButton,
              Qt::LeftButton);
    sendMouse(graph, QEvent::MouseMove, graph->mapFrom(range.popup, finish), Qt::NoButton,
              Qt::LeftButton);
    if (!graph->hasGesture())
        fail("pitch-bend graph did not retain its active gesture");
    const std::vector<songview::CurvePoint> preview = graph->points();
    m_document.undoStack()->push(new QUndoCommand(QStringLiteral("snapshot check")));
    if (m_document.undoStack()->index() != beforeUndoIndex + 1)
        fail("snapshot check did not advance the undo-stack index");
    const std::vector<songview::CurvePoint> after = graph->points();
    const bool previewPreserved =
        after.size() == preview.size() &&
        std::equal(after.begin(), after.end(), preview.begin(),
                   [](const songview::CurvePoint &lhs, const songview::CurvePoint &rhs) {
                       return lhs.x == rhs.x && lhs.y == rhs.y;
                   });
    if (!previewPreserved)
        fail("undo-stack index change replaced an active pitch-bend preview");
    sendKey(range.popup, Qt::Key_Escape, Qt::NoModifier);
    drainPopupDeletes();
    if (m_document.undoStack()->index() != beforeUndoIndex)
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != beforeUndoIndex || m_document.smf().write() != before)
        fail("snapshot gesture check did not restore the document state");
}

void PitchBendCheckContext::runLifecycleCancellation()
{
    const RangePopupState range = openRangePopup();
    if (!range.popup)
        return;
    QPointer<songview::PitchBendEditor> popup = range.popup;
    auto *bendSpin = popup->findChild<QSpinBox *>(QStringLiteral("bendRangeSpin"));
    if (!bendSpin) {
        fail("pitch-bend lifecycle check had no BENDR control");
        sendKey(popup, Qt::Key_Escape, Qt::NoModifier);
        drainPopupDeletes();
        return;
    }
    const int lifecycleUndoIndex = m_document.undoStack()->index();
    const int bendStep = bendSpin->value() < 127 ? 1 : -1;
    bendStep > 0 ? bendSpin->stepUp() : bendSpin->stepDown();
    if (!popup || !popup->isVisible())
        fail("valid popup-originated edit closed the pitch-bend popup");
    m_view.updateSong(m_view.timeline());
    if (!popup || !popup->isVisible())
        fail("valid document refresh closed the pitch-bend popup");

    m_document.moveNotes({m_note}, 1, 0);
    if (popup && popup->isVisible())
        fail("external note retiming did not hide the pitch-bend popup");
    drainPopupDeletes();
    if (popup)
        fail("external note retiming left a stale pitch-bend popup");

    while (m_document.undoStack()->index() > lifecycleUndoIndex &&
           m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != lifecycleUndoIndex)
        fail("pitch-bend lifecycle check did not restore its document edits");
    m_view.updateSong(m_view.timeline());
    m_view.selectionModel().setNoteSelection({m_note.noteId});
}

void PitchBendCheckContext::runRangeFreehandAndUndo()
{
    const RangePopupState range = openRangePopup();
    if (!range.popup || !range.graphWidget)
        return;
    verifyRangeWheelConfinement(range);
    verifyShiftLinePreview(range);
    bool firstStrokeCommitted = driveRangeFreehand(range);
    if (firstStrokeCommitted)
        firstStrokeCommitted = verifyPopupUndo(range);
    if (firstStrokeCommitted)
        firstStrokeCommitted = verifyKeyboardControlsIgnored(range);
    if (firstStrokeCommitted)
        firstStrokeCommitted = driveRangeFreehand(range);
    if (firstStrokeCommitted) {
        verifyStackedCurveUndo(range);
        verifyRangeCurve();
        verifyRangeRawPitchWheel();
        undoRangeFreehand();
    } else {
        while (m_document.undoStack()->index() > m_curveUndoIndex &&
               m_document.undoStack()->canUndo())
            m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != m_curveUndoIndex ||
            m_document.smf().write() != m_beforeCurve)
            fail("failed pitch-bend stroke did not restore the document");
    }
    sendKey(range.popup, Qt::Key_Escape, Qt::NoModifier);
    drainPopupDeletes();
    QCursor::setPos(m_roll->mapToGlobal(m_noteCenter));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *resyncedPopup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    if (!resyncedPopup || !resyncedPopup->isVisible())
        fail("G did not reopen the pitch-bend popup after stacked undo");
}

void PitchBendCheckContext::runControllerButtons()
{
    QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
    auto *bendSpin =
        popup ? popup->findChild<QSpinBox *>(QStringLiteral("bendRangeSpin")) : nullptr;
    auto *lfoSpin = popup ? popup->findChild<QSpinBox *>(QStringLiteral("lfoSpeedSpin")) : nullptr;
    if (!popup || !popup->isVisible() || !bendSpin || !lfoSpin) {
        fail("pitch-bend popup did not expose BENDR and LFOS spin boxes");
        return;
    }

    const int undoIndex = m_document.undoStack()->index();
    const QByteArray before = m_document.smf().write();
    const int oldBend = bendSpin->value();
    const int oldLfo = lfoSpin->value();
    const auto effectiveValue = [this](uint8_t cc, uint64_t tick, int defaultValue) {
        int value = defaultValue;
        for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, cc)) {
            if (point.tick > tick)
                break;
            value = point.value;
        }
        return value;
    };
    const int endBend = effectiveValue(0x14, m_endTick, 2);
    const int endLfo = effectiveValue(0x15, m_endTick, 22);
    const auto hasPoint = [this](uint8_t cc, uint64_t tick, int value) {
        for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, cc)) {
            if (point.tick == tick && point.value == value)
                return true;
        }
        return false;
    };

    const int bendStep = oldBend < 127 ? 1 : -1;
    bendStep > 0 ? bendSpin->stepUp() : bendSpin->stepDown();
    const int changedBend = oldBend + bendStep;
    if (m_document.undoStack()->index() != undoIndex + 1 || bendSpin->value() != changedBend ||
        !hasPoint(0x14, m_note.tick, changedBend) || !hasPoint(0x14, m_endTick, endBend))
        fail("BENDR spin button did not write and restore note-scoped CC 20");
    const QByteArray afterBend = m_document.smf().write();

    const int lfoStep = oldLfo < 127 ? 1 : -1;
    lfoStep > 0 ? lfoSpin->stepUp() : lfoSpin->stepDown();
    const int changedLfo = oldLfo + lfoStep;
    if (m_document.undoStack()->index() != undoIndex + 2 || lfoSpin->value() != changedLfo ||
        !hasPoint(0x15, m_note.tick, changedLfo) || !hasPoint(0x15, m_endTick, endLfo))
        fail("LFOS spin button did not write and restore note-scoped CC 21");

    lfoSpin->setFocus(Qt::OtherFocusReason);
    QCoreApplication::processEvents();
    QWidget *undoTarget = QApplication::focusWidget();
    if (!undoTarget || !sendStandardUndo(undoTarget))
        fail("controller spin box did not claim the standard Undo shortcut");
    if (m_document.undoStack()->index() != undoIndex + 1 || m_document.smf().write() != afterBend ||
        lfoSpin->value() != oldLfo || bendSpin->value() != changedBend)
        fail("Undo did not refresh the popup after the LFOS edit");
    undoTarget = QApplication::focusWidget();
    if (!undoTarget || !sendStandardUndo(undoTarget))
        fail("controller spin box did not route a second Undo");
    if (m_document.undoStack()->index() != undoIndex || m_document.smf().write() != before ||
        bendSpin->value() != oldBend || lfoSpin->value() != oldLfo)
        fail("Undo did not refresh the popup after the BENDR edit");

    while (m_document.undoStack()->index() > undoIndex && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
}

void PitchBendCheckContext::runResetAndAudition()
{
    drainPopupDeletes();
    QCursor::setPos(m_roll->mapToGlobal(m_noteCenter));
    sendKey(m_roll, Qt::Key_G, Qt::NoModifier);
    QWidget *resetWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
    auto *resetPopup = dynamic_cast<songview::PitchBendEditor *>(resetWidget);
    if (!resetPopup || !resetPopup->isVisible()) {
        fail("G did not reopen the pitch-bend popup");
        return;
    }
    auto *resetButton = resetPopup->findChild<QPushButton *>(QStringLiteral("pitchBendReset"));
    if (!resetButton) {
        fail("pitch-bend popup has no Reset button");
    } else {
        const int resetBaseline = m_document.undoStack()->index();
        resetButton->click();
        if (!resetPopup->isVisible())
            fail("Reset closed the pitch-bend popup");
        if (m_document.undoStack()->index() != resetBaseline + 1)
            fail("Reset did not push exactly one pitch-bend edit immediately");
        bool zeroedSpan = true;
        bool restoredEnd = false;
        for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, DOC_CC_BEND)) {
            if (point.tick >= m_note.tick && point.tick < m_endTick && point.value != 0)
                zeroedSpan = false;
            if (point.tick == m_endTick && point.value == m_bendAtEnd)
                restoredEnd = true;
        }
        if (!zeroedSpan)
            fail("Reset did not zero the pitch bend across the note");
        if (!restoredEnd)
            fail("Reset did not restore the note-off bend state");
        uint64_t requestedTick = UINT64_MAX;
        int playbackRequests = 0;
        const QMetaObject::Connection connection =
            QObject::connect(&m_view, &SongView::playPauseFromRequested,
                             [&requestedTick, &playbackRequests](uint64_t tick) {
                                 requestedTick = tick;
                                 playbackRequests++;
                             });
        sendKey(resetPopup, Qt::Key_Space, Qt::NoModifier);
        QObject::disconnect(connection);
        if (playbackRequests != 1 || requestedTick != m_note.tick)
            fail("Space did not request playback from the selected note's start");
        if (!resetPopup->isVisible())
            fail("Space closed the pitch-bend popup");
        if (m_document.undoStack()->index() != resetBaseline + 1)
            fail("Reset audition did not push exactly one pitch-bend edit");
        m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != m_curveUndoIndex ||
            m_document.smf().write() != m_beforeCurve)
            fail("undo did not restore the document after pitch-bend Reset");
    }
    sendKey(resetPopup, Qt::Key_Escape, Qt::NoModifier);
    if (resetPopup->isVisible() || m_document.smf().write() != m_beforeCurve ||
        m_view.selectionModel().noteSelection().size() != 1 ||
        m_view.selectionModel().noteSelection().front() != m_note.noteId)
        fail("Escape did not dismiss the pitch-bend popup while retaining the note");
    drainPopupDeletes();
}

void PitchBendCheckContext::cleanupBaseFixture()
{
    while (m_document.undoStack()->index() > m_undoIndex && m_document.undoStack()->canUndo())
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != m_undoIndex || m_document.smf().write() != m_beforeBend)
        fail("note-scoped BENDR edit did not restore the document");
    if (m_document.undoStack()->index() == m_beforeRangeUndoIndex + 1)
        m_document.undoStack()->undo();
    if (m_document.undoStack()->index() != m_beforeRangeUndoIndex ||
        m_document.smf().write() != m_beforeRange)
        fail("BENDR fixture did not restore the document");
    if (!m_document.containsNoteSpan(m_engineTrack, m_note, m_endTick))
        fail("pitch-bend checks changed the selected note span");
    drainPopupDeletes();
}

} // namespace pitchbendcheck

int runPitchBendCheck(SongDocument &document, SongView &view, QWidget *roll, int engineTrack,
                      const DocNote &note, const QPoint &noteCenter, const QString &songLabel)
{
    return pitchbendcheck::PitchBendCheckContext(document, view, roll, engineTrack, note,
                                                 noteCenter, songLabel)
        .run();
}
