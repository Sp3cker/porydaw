#include "pitchbendcheck.hpp"

#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QCoreApplication>
#include <QCursor>
#include <QEvent>
#include <QImage>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QMetaObject>
#include <QObject>
#include <QPixmap>
#include <QPointF>
#include <QPointer>
#include <QPushButton>
#include <QRect>
#include <QSpinBox>
#include <QUndoCommand>
#include <QWidget>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "checks/rollcheck/rollcheck.h"
#include "checks/support/eventsynth.h"
#include "ui/pitchbendeditor.hpp"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/theme/themeruntime.h"

namespace {

void sendKeyStroke(QWidget &widget, Qt::Key key, Qt::KeyboardModifiers modifiers, bool autoRepeat)
{
    checks::events::sendKey(widget, QEvent::KeyPress, key, modifiers, QString(), autoRepeat, 1);
    checks::events::sendKey(widget, QEvent::KeyRelease, key, modifiers, QString(), autoRepeat, 1);
}

bool sendStandardUndo(QWidget *widget)
{
    const auto bindings = QKeySequence::keyBindings(QKeySequence::Undo);
    if (bindings.empty())
        return false;
    const QKeyCombination combination = bindings.front()[0];
    // ShortcutOverride acceptance is the assertion, so its event must remain
    // inspectable after dispatch.
    QKeyEvent shortcutEvent(QEvent::ShortcutOverride, combination.key(),
                            combination.keyboardModifiers(), QString(), false, 1);
    QCoreApplication::sendEvent(widget, &shortcutEvent);
    if (!shortcutEvent.isAccepted())
        return false;
    sendKeyStroke(*widget, combination.key(), combination.keyboardModifiers(), false);
    return true;
}

void drainPopupDeletes()
{
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
}

class PitchBendCheckContext final
{
  public:
    PitchBendCheckContext(SongDocument &document, SongView &view, songview::TimelineInputItem *roll,
                          int engineTrack, const DocNote &note, const QPoint &noteCenter,
                          const QString &songLabel)
        : m_document(document)
        , m_view(view)
        , m_roll(roll)
        , m_engineTrack(engineTrack)
        , m_note(note)
        , m_noteCenter(noteCenter)
        , m_songLabel(songLabel)
    {}

    int run()
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
        runControllerButtons();
        runRangeFreehandAndUndo();
        runVertexEditing();
        runModWheelEditing();
        runPersistedAltRendering();
        runResetAndAudition();
        runFocusHandoff();
        cleanupBaseFixture();
        runActiveGridBoundary();
        if (!viewWasVisible)
            m_view.hide();
        return m_failures;
    }

  private:
    void fail(const char *what)
    {
        std::fprintf(stderr, "rollcheck: FAIL %s: %s\n", qUtf8Printable(m_songLabel), what);
        m_failures++;
    }

    void installRangeFixture()
    {
        m_beforeRange = m_document.smf().write();
        m_beforeRangeUndoIndex = m_document.undoStack()->index();
        m_document.writeLanePoints(m_engineTrack, 0x14, m_note.tick, m_note.tick,
                                   {{m_note.tick, 12}});
        if (m_document.undoStack()->index() != m_beforeRangeUndoIndex + 1)
            fail("BENDR fixture did not push exactly one undo command");
    }

    static void activateSyntheticToolWindow(QWidget &window)
    {
        // Direct QQuickItem event synthesis bypasses Cocoa's native key
        // activation path. Keep QApplication's widget-focus bookkeeping in
        // sync before driving child controls.
        QT_WARNING_PUSH
        QT_WARNING_DISABLE_DEPRECATED
        QApplication::setActiveWindow(&window);
        QT_WARNING_POP
    }

    struct RangePopupState {
        songview::PitchBendEditor *popup = nullptr;
        QWidget *graphWidget = nullptr;
        QRect graph;
    };

    RangePopupState openRangePopup()
    {
        const QPoint noteGlobal = m_roll->mapToGlobal(QPointF(m_noteCenter)).toPoint();
        QCursor::setPos(noteGlobal + QPoint(300, 0));
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *bendPopup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!bendPopup || !bendPopup->isVisible()) {
            fail("G did not open the selected note's pitch-bend popup");
            return {};
        }
        activateSyntheticToolWindow(*bendPopup);
        QCoreApplication::processEvents();
        if (!bendPopup->isWindow() || bendPopup->windowType() != Qt::Tool ||
            QApplication::activePopupWidget() == bendPopup) {
            fail("pitch-bend editor did not use a non-modal tool window");
        }
        if (!bendPopup->windowHandle() || !bendPopup->testAttribute(Qt::WA_OpaquePaintEvent)) {
            fail("pitch-bend editor does not own an opaque top-level surface");
        }
        const QPixmap surfacePixmap = bendPopup->grab();
        const QImage surfaceImage = surfacePixmap.toImage();
        const qreal surfaceDpr = surfacePixmap.devicePixelRatio();
        bool opaqueSurface = !surfaceImage.isNull();
        for (int y = 0; opaqueSurface && y < surfaceImage.height(); ++y) {
            for (int x = 0; x < surfaceImage.width(); ++x) {
                if (surfaceImage.pixelColor(x, y).alpha() != 255) {
                    opaqueSurface = false;
                    break;
                }
            }
        }
        if (!opaqueSurface)
            fail("pitch-bend editor did not render an opaque surface");
        const QColor background = themes::color(themes::Role::window_background);
        const auto backgroundAt = [&surfaceImage, surfaceDpr, &background](QPoint logical) {
            const int x = qRound(double(logical.x()) * surfaceDpr);
            const int y = qRound(double(logical.y()) * surfaceDpr);
            return x >= 0 && x < surfaceImage.width() && y >= 0 && y < surfaceImage.height() &&
                   surfaceImage.pixelColor(x, y) == background;
        };
        if (!backgroundAt(QPoint(4, 24)) || !backgroundAt(QPoint(4, 80)) ||
            !backgroundAt(QPoint(4, bendPopup->height() - 4)))
            fail("pitch-bend editor did not retain its window background");
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
        if (!bendPopup->accessibleDescription().contains(QStringLiteral("12 semitones")))
            fail("pitch-bend popup did not present the active BENDR value");
        const QRect graph = bendPopup->graphRect();
        QWidget *graphWidget = bendPopup->findChild<QWidget *>(QStringLiteral("pitchBendGraph"));
        if (!graphWidget) {
            fail("pitch-bend popup has no pitchBendGraph child");
            return {};
        }
        checks::events::sendMouse(*graphWidget, QEvent::MouseMove,
                                  graphWidget->mapFrom(bendPopup, graph.center()), Qt::NoButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (!bendPopup->isVisible())
            fail("idle mouse movement dismissed the pitch-bend popup");
        return {bendPopup, graphWidget, graph};
    }

    void verifyRangeWheelConfinement(const RangePopupState &range)
    {
        checks::events::sendWheel(
            *range.graphWidget,
            QPointF(range.graphWidget->mapFrom(
                range.popup, QPoint(range.graph.left() - 4, range.graph.top() - 4))),
            QPoint(0, 0), QPoint(0, 120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        if (m_document.undoStack()->index() != m_undoIndex)
            fail("scrolling outside the pitch-bend graph changed BENDR");
        checks::events::sendWheel(
            *range.graphWidget,
            QPointF(range.graphWidget->mapFrom(range.popup, QPoint(range.graph.center()))),
            QPoint(0, 0), QPoint(0, 120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
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

    void verifyShiftLinePreview(const RangePopupState &range)
    {
        const QPoint start(range.graph.left() + range.graph.width() / 8,
                           range.graph.bottom() - range.graph.height() / 8);
        const QPoint finish(range.graph.right() - range.graph.width() / 8,
                            range.graph.top() + range.graph.height() / 8);
        const int undoIndex = m_document.undoStack()->index();
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonPress,
                                  range.graphWidget->mapFrom(range.popup, start), Qt::LeftButton,
                                  Qt::LeftButton, Qt::ShiftModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseMove,
                                  range.graphWidget->mapFrom(range.popup, finish), Qt::NoButton,
                                  Qt::LeftButton, Qt::ShiftModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonRelease,
                                  range.graphWidget->mapFrom(range.popup, finish), Qt::LeftButton,
                                  Qt::NoButton, Qt::ShiftModifier);
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

    bool driveRangeFreehand(const RangePopupState &range)
    {
        m_curveUndoIndex = m_document.undoStack()->index();
        m_beforeCurve = m_document.smf().write();
        const QPoint start(range.graph.left() + range.graph.width() / 3, range.graph.center().y());
        const QPoint finish(range.graph.left() + 2 * range.graph.width() / 3,
                            range.graph.top() + range.graph.height() / 3);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonPress,
                                  range.graphWidget->mapFrom(range.popup, start), Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseMove,
                                  range.graphWidget->mapFrom(range.popup, finish), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonRelease,
                                  range.graphWidget->mapFrom(range.popup, finish), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (!range.popup->isVisible())
            fail("pitch-bend popup dismissed after its freehand stroke");
        sendKeyStroke(*range.popup, Qt::Key_Enter, Qt::NoModifier, false);
        if (!range.popup->isVisible())
            fail("Enter dismissed the pitch-bend popup");
        if (m_document.undoStack()->index() != m_curveUndoIndex + 1) {
            fail("pitch-bend stroke did not push exactly one undo command");
            return false;
        }
        return true;
    }

    bool verifyPopupUndo(const RangePopupState &range)
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

    bool verifyKeyboardControlsIgnored(const RangePopupState &range)
    {
        const int undoIndex = m_document.undoStack()->index();
        const QByteArray curve = m_document.smf().write();
        sendKeyStroke(*range.graphWidget, Qt::Key_Left, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_Right, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_Home, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_End, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_Up, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_Down, Qt::ShiftModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_PageUp, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_PageDown, Qt::NoModifier, false);
        sendKeyStroke(*range.graphWidget, Qt::Key_0, Qt::NoModifier, false);
        if (m_document.undoStack()->index() != undoIndex || m_document.smf().write() != curve) {
            fail("pitch-bend keyboard controls changed the curve");
            return false;
        }
        return true;
    }

    void verifyStackedCurveUndo(const RangePopupState &range)
    {
        const int firstUndoIndex = m_document.undoStack()->index();
        const QByteArray firstCurve = m_document.smf().write();
        const QPoint strokeStart(range.graph.left() + range.graph.width() / 5,
                                 range.graph.bottom() - range.graph.height() / 5);
        const QPoint strokeFinish(range.graph.left() + 2 * range.graph.width() / 5,
                                  range.graph.bottom() - range.graph.height() / 3);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonPress,
                                  range.graphWidget->mapFrom(range.popup, strokeStart),
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseMove,
                                  range.graphWidget->mapFrom(range.popup, strokeFinish),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonRelease,
                                  range.graphWidget->mapFrom(range.popup, strokeFinish),
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
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
        while (m_document.undoStack()->index() > firstUndoIndex &&
               m_document.undoStack()->canUndo())
            m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != firstUndoIndex ||
            m_document.smf().write() != firstCurve)
            fail("stacked pitch-bend undo did not restore the initial stroke");
    }

    void verifyRangeCurve()
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

    void verifyRangeRawPitchWheel()
    {
        bool rawPitchWheel = false;
        const int smfTrack = m_document.smfTrackFor(m_engineTrack);
        if (smfTrack >= 0) {
            for (const SmfEvent &event : m_document.smf().tracks[size_t(smfTrack)].events) {
                if (event.tick >= m_note.tick && event.tick <= m_endTick &&
                    event.typeNibble() == 0xE) {
                    rawPitchWheel = true;
                    if (event.data0 > 0x7F || event.data1 > 0x7F)
                        fail("pitch-bend popup wrote an invalid SMF data byte");
                }
            }
        }
        if (!rawPitchWheel)
            fail("pitch-bend popup did not serialize SMF pitch-wheel events");
    }

    void undoRangeFreehand()
    {
        m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != m_curveUndoIndex ||
            m_document.smf().write() != m_beforeCurve)
            fail("undo did not restore the document after pitch-bend drawing");
    }

    void runDuplicateAnchor()
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
            sendKeyStroke(*range.popup, Qt::Key_Escape, Qt::NoModifier, false);
            drainPopupDeletes();
        }
        m_view.updateSong(originalTimeline);
        m_view.selectionModel().setNoteSelection({m_note.noteId});
        const QByteArray beforeIdentity = m_document.smf().write();
        const int identityUndoIndex = m_document.undoStack()->index();
        m_document.deleteNotes({m_note});
        m_document.addNote(m_engineTrack, m_note.tick, m_note.key, m_note.duration,
                           m_note.velocity);
        DocNote replacement;
        if (!m_document.findNote(m_engineTrack, m_note.tick, m_note.key, &replacement) ||
            replacement.noteId == m_note.noteId ||
            m_document.containsNoteSpan(m_engineTrack, m_note, m_endTick))
            fail("same-tick replacement note satisfied the original pitch-bend span");
        while (m_document.undoStack()->index() > identityUndoIndex &&
               m_document.undoStack()->canUndo())
            m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != identityUndoIndex ||
            m_document.smf().write() != beforeIdentity)
            fail("duplicate-anchor identity check did not restore the document");
        m_view.selectionModel().setNoteSelection({m_note.noteId});
    }

    void runSnapshotDuringGesture()
    {
        const RangePopupState range = openRangePopup();
        if (!range.popup || !range.graphWidget)
            return;
        auto *graph = dynamic_cast<songview::PitchBendGraph *>(range.graphWidget);
        if (!graph) {
            fail("pitch-bend graph child had the wrong type");
            sendKeyStroke(*range.popup, Qt::Key_Escape, Qt::NoModifier, false);
            drainPopupDeletes();
            return;
        }
        const int beforeUndoIndex = m_document.undoStack()->index();
        const QByteArray before = m_document.smf().write();
        const QPoint start(range.graph.left() + range.graph.width() / 3, range.graph.center().y());
        const QPoint finish(range.graph.left() + 2 * range.graph.width() / 3,
                            range.graph.top() + range.graph.height() / 3);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseButtonPress,
                                  range.graphWidget->mapFrom(range.popup, start), Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*range.graphWidget, QEvent::MouseMove,
                                  range.graphWidget->mapFrom(range.popup, finish), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        if (!graph->hasGesture())
            fail("pitch-bend graph did not retain its active gesture");
        const std::vector<SongDocument::LanePointValue> preview = graph->curvePoints();
        m_document.undoStack()->push(new QUndoCommand(QStringLiteral("snapshot check")));
        if (m_document.undoStack()->index() != beforeUndoIndex + 1)
            fail("snapshot check did not advance the undo-stack index");
        const std::vector<SongDocument::LanePointValue> after = graph->curvePoints();
        const bool previewPreserved =
            after.size() == preview.size() &&
            std::equal(after.begin(), after.end(), preview.begin(),
                       [](const SongDocument::LanePointValue &lhs,
                          const SongDocument::LanePointValue &rhs) {
                           return lhs.tick == rhs.tick && lhs.value == rhs.value;
                       });
        if (!previewPreserved)
            fail("undo-stack index change replaced an active pitch-bend preview");
        sendKeyStroke(*range.popup, Qt::Key_Escape, Qt::NoModifier, false);
        drainPopupDeletes();
        if (m_document.undoStack()->index() != beforeUndoIndex)
            m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != beforeUndoIndex ||
            m_document.smf().write() != before)
            fail("snapshot gesture check did not restore the document state");
    }

    void runLifecycleCancellation()
    {
        const RangePopupState range = openRangePopup();
        if (!range.popup)
            return;
        QPointer<songview::PitchBendEditor> popup = range.popup;
        auto *bendSpin = popup->findChild<QSpinBox *>(QStringLiteral("bendRangeSpin"));
        if (!bendSpin) {
            fail("pitch-bend lifecycle check had no BENDR control");
            sendKeyStroke(*popup, Qt::Key_Escape, Qt::NoModifier, false);
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

    void runRangeFreehandAndUndo()
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
        sendKeyStroke(*range.popup, Qt::Key_Escape, Qt::NoModifier, false);
        drainPopupDeletes();
        QCursor::setPos(m_roll->mapToGlobal(QPointF(m_noteCenter)).toPoint());
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *resyncedPopup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!resyncedPopup || !resyncedPopup->isVisible())
            fail("G did not reopen the pitch-bend popup after stacked undo");
    }
    void runVertexEditing()
    {
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!popup || !popup->isVisible()) {
            fail("pitch-bend popup was not visible for vertex editing");
            return;
        }
        auto *bendGraph = dynamic_cast<songview::PitchBendGraph *>(
            popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")));
        auto *modGraph = dynamic_cast<songview::PitchBendGraph *>(
            popup->findChild<QWidget *>(QStringLiteral("modWheelGraph")));
        if (!bendGraph)
            fail("pitch-bend popup had no pitch-bend graph for vertex editing");
        else
            runVertexEditingGraph(bendGraph, DOC_CC_BEND);
        if (!modGraph)
            fail("pitch-bend popup had no mod-wheel graph for vertex editing");
        else
            runVertexEditingGraph(modGraph, 1);
    }

    void runVertexEditingGraph(songview::PitchBendGraph *graph, uint8_t cc)
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
        const QPoint strokeStart(canvas.left() + canvas.width() / 5,
                                 graph->lane() == songview::PitchBendGraph::Lane::ModWheel
                                     ? canvas.bottom() - canvas.height() / 4
                                     : canvas.center().y() + canvas.height() / 4);
        const QPoint strokeFinish(canvas.left() + 4 * canvas.width() / 5,
                                  graph->lane() == songview::PitchBendGraph::Lane::ModWheel
                                      ? canvas.top() + canvas.height() / 4
                                      : canvas.center().y() - canvas.height() / 4);
        checks::events::sendMouse(*graph, QEvent::MouseButtonPress, strokeStart, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*graph, QEvent::MouseMove, strokeFinish, Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*graph, QEvent::MouseButtonRelease, strokeFinish, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
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
        const QPoint targetPos = graph->vertexPosition(target.tick, target.value);
        const auto hit = graph->hitTest(QPointF(targetPos));
        if (!hit || hit->first != target.tick) {
            fail("automation vertex center did not hit the expected node");
            restoreBaseline();
            return;
        }
        checks::events::sendMouse(*graph, QEvent::MouseButtonPress, targetPos, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::processEvents();
        if (!graph->selectedTick() || *graph->selectedTick() != target.tick) {
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
        checks::events::sendMouse(*graph, QEvent::MouseMove, movedPos, Qt::NoButton, Qt::LeftButton,
                                  Qt::AltModifier);
        checks::events::sendMouse(*graph, QEvent::MouseButtonRelease, movedPos, Qt::LeftButton,
                                  Qt::NoButton, Qt::AltModifier);
        QCoreApplication::processEvents();
        if (m_document.undoStack()->index() != dragUndo + 1) {
            fail("automation vertex drag did not push one undo command");
            restoreBaseline();
            return;
        }
        const auto movedHit = graph->hitTest(QPointF(movedPos));
        DocLanePoint movedPoint;
        if (!movedHit || movedHit->first == target.tick ||
            !m_document.findLanePoint(m_engineTrack, cc, movedHit->first, &movedPoint) ||
            movedPoint.value != movedHit->second ||
            m_document.findLanePoint(m_engineTrack, cc, target.tick, nullptr) ||
            !graph->isVisible()) {
            fail("automation vertex drag did not move the document node");
            restoreBaseline();
            return;
        }
        m_document.undoStack()->undo();
        QCoreApplication::processEvents();
        const std::vector<DocLanePoint> restoredAfterDrag =
            m_document.lanePoints(m_engineTrack, cc);
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
        const QPoint restoredPos = graph->vertexPosition(target.tick, restoredTarget.value);
        checks::events::sendMouse(*graph, QEvent::MouseButtonPress, restoredPos, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::processEvents();
        if (!graph->selectedTick() || *graph->selectedTick() != target.tick) {
            fail("automation vertex could not be reselected for deletion");
            restoreBaseline();
            return;
        }
        graph->cancelGesture();
        const int deleteUndo = m_document.undoStack()->index();
        const std::vector<DocLanePoint> beforeDelete = m_document.lanePoints(m_engineTrack, cc);
        sendKeyStroke(*graph, Qt::Key_Delete, Qt::NoModifier, false);
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
            const QPoint position = graph->vertexPosition(tick, value);
            checks::events::sendMouse(*graph, QEvent::MouseButtonPress, position, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            QCoreApplication::processEvents();
            if (!graph->selectedTick() || *graph->selectedTick() != tick) {
                fail("automation endpoint click did not select its node");
                graph->cancelGesture();
                return;
            }
            graph->cancelGesture();
            sendKeyStroke(*graph, Qt::Key_Delete, Qt::NoModifier, false);
            QCoreApplication::processEvents();
            if (m_document.undoStack()->index() != beforeUndo ||
                !sameLanePoints(m_document.lanePoints(m_engineTrack, cc), before))
                fail("automation endpoint deletion changed the document");
        };
        endpointDelete(m_note.tick, startPoint.value);
        endpointDelete(m_endTick, endPoint.value);
        restoreBaseline();
        if (m_document.undoStack()->index() != baselineUndo ||
            m_document.smf().write() != baselineSmf)
            fail("vertex checks did not restore the document");
    }

    void runModWheelEditing()
    {
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        QWidget *graphWidget =
            popup ? popup->findChild<QWidget *>(QStringLiteral("modWheelGraph")) : nullptr;
        if (!popup || !popup->isVisible() || !graphWidget) {
            fail("pitch-bend popup did not expose its mod-wheel graph");
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
        checks::events::sendMouse(*graphWidget, QEvent::MouseButtonPress,
                                  graphWidget->mapFrom(popup, start), Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*graphWidget, QEvent::MouseMove,
                                  graphWidget->mapFrom(popup, finish), Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*graphWidget, QEvent::MouseButtonRelease,
                                  graphWidget->mapFrom(popup, finish), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
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

    void runControllerButtons()
    {
        const RangePopupState range = openRangePopup();
        if (!range.popup)
            return;
        auto *bendSpin = range.popup->findChild<QSpinBox *>(QStringLiteral("bendRangeSpin"));
        auto *lfoSpin = range.popup->findChild<QSpinBox *>(QStringLiteral("lfoSpeedSpin"));
        auto *bendEdit = bendSpin ? bendSpin->findChild<QLineEdit *>() : nullptr;
        auto *lfoEdit = lfoSpin ? lfoSpin->findChild<QLineEdit *>() : nullptr;
        if (!bendSpin || !lfoSpin || !bendEdit || !lfoEdit) {
            fail("pitch-bend popup did not expose BENDR and LFOS line edits");
            sendKeyStroke(*range.popup, Qt::Key_Escape, Qt::NoModifier, false);
            drainPopupDeletes();
            return;
        }
        if (bendEdit->cursor().shape() != Qt::SizeVerCursor ||
            lfoEdit->cursor().shape() != Qt::SizeVerCursor)
            fail("controller line edits did not advertise vertical dragging");

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
        const auto dragLineEdit = [](QLineEdit *edit, int step, Qt::KeyboardModifiers modifiers) {
            const QPoint start = edit->rect().center();
            // 5px clears DragSpinBox's 3px threshold then yields 2 * 0.5 = 1 normal step;
            // 8px leaves 5 * 0.2 = 1 Shift step.
            const int pixels = modifiers & Qt::ShiftModifier ? 8 : 5;
            const QPoint finish = start + QPoint(0, step > 0 ? -pixels : pixels);
            checks::events::sendMouse(*edit, QEvent::MouseButtonPress, start, Qt::LeftButton,
                                      Qt::LeftButton, modifiers);
            checks::events::sendMouse(*edit, QEvent::MouseMove, finish, Qt::NoButton,
                                      Qt::LeftButton, modifiers);
            checks::events::sendMouse(*edit, QEvent::MouseButtonRelease, finish, Qt::LeftButton,
                                      Qt::NoButton, modifiers);
        };

        const int bendStep = oldBend < 127 ? 1 : -1;
        dragLineEdit(bendEdit, bendStep, Qt::NoModifier);
        const int changedBend = oldBend + bendStep;
        if (m_document.undoStack()->index() != undoIndex + 1 || bendSpin->value() != changedBend ||
            !hasPoint(0x14, m_note.tick, changedBend) || !hasPoint(0x14, m_endTick, endBend))
            fail("normal BENDR line-edit drag did not write note-scoped controller 0x14");
        const QByteArray afterBend = m_document.smf().write();

        const int lfoStep = oldLfo < 127 ? 1 : -1;
        dragLineEdit(lfoEdit, lfoStep, Qt::ShiftModifier);
        const int changedLfo = oldLfo + lfoStep;
        if (m_document.undoStack()->index() != undoIndex + 2 || lfoSpin->value() != changedLfo ||
            !hasPoint(0x15, m_note.tick, changedLfo) || !hasPoint(0x15, m_endTick, endLfo))
            fail("Shift LFOS line-edit drag did not write note-scoped controller 0x15");
        if (!range.popup->isVisible())
            fail("controller line-edit drags dismissed the pitch-bend popup");

        const int clickUndoIndex = m_document.undoStack()->index();
        const QByteArray beforeClick = m_document.smf().write();
        const QPoint clickPoint = lfoEdit->rect().center();
        checks::events::sendMouse(*lfoEdit, QEvent::MouseButtonPress, clickPoint, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*lfoEdit, QEvent::MouseButtonRelease, clickPoint, Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        QCoreApplication::processEvents();
        if (m_document.undoStack()->index() != clickUndoIndex ||
            m_document.smf().write() != beforeClick || bendSpin->value() != changedBend ||
            lfoSpin->value() != changedLfo)
            fail("stationary controller click changed the value or document");
        if (!lfoEdit->hasFocus() && !lfoSpin->hasFocus())
            fail("stationary controller click did not focus the input");
        if (lfoEdit->selectedText().isEmpty())
            fail("stationary controller click did not select the input text");

        if (!sendStandardUndo(lfoEdit))
            fail("controller line edit did not claim the standard Undo shortcut");
        if (m_document.undoStack()->index() != undoIndex + 1 ||
            m_document.smf().write() != afterBend || lfoSpin->value() != oldLfo ||
            bendSpin->value() != changedBend)
            fail("first controller Undo did not restore the post-BENDR state");
        if (!range.popup->isVisible())
            fail("first controller Undo dismissed the pitch-bend popup");
        if (!sendStandardUndo(lfoEdit))
            fail("controller line edit did not route a second Undo");
        if (m_document.undoStack()->index() != undoIndex || m_document.smf().write() != before ||
            bendSpin->value() != oldBend || lfoSpin->value() != oldLfo)
            fail("second controller Undo did not restore the byte-identical baseline");
        if (!range.popup->isVisible())
            fail("second controller Undo dismissed the pitch-bend popup");

        while (m_document.undoStack()->index() > undoIndex && m_document.undoStack()->canUndo())
            m_document.undoStack()->undo();
        sendKeyStroke(*range.popup, Qt::Key_Escape, Qt::NoModifier, false);
        drainPopupDeletes();
    }

    struct PersistedAltPopupState {
        songview::PitchBendEditor *popup = nullptr;
        QWidget *graphWidget = nullptr;
        QRect graph;
    };

    bool openPersistedAltPopup(PersistedAltPopupState *state)
    {
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!popup || !popup->isVisible()) {
            fail("pitch-bend popup disappeared before its Alt line");
            return false;
        }
        state->popup = popup;
        state->graph = popup->graphRect();
        state->graphWidget = popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph"));
        if (!state->graphWidget) {
            fail("pitch-bend popup has no pitchBendGraph child for its Alt line");
            return false;
        }
        return true;
    }

    void drivePersistedAltRamp(const PersistedAltPopupState &state)
    {
        const QPoint lineStart(state.graph.left() + state.graph.width() / 16,
                               state.graph.bottom() - state.graph.height() / 12);
        const QPoint lineFinish(state.graph.right() - state.graph.width() / 16,
                                state.graph.top() + state.graph.height() / 12);
        checks::events::sendMouse(*state.graphWidget, QEvent::MouseButtonPress,
                                  state.graphWidget->mapFrom(state.popup, lineStart),
                                  Qt::LeftButton, Qt::LeftButton, Qt::AltModifier);
        checks::events::sendMouse(*state.graphWidget, QEvent::MouseMove,
                                  state.graphWidget->mapFrom(state.popup, lineFinish), Qt::NoButton,
                                  Qt::LeftButton, Qt::AltModifier);
        checks::events::sendMouse(*state.graphWidget, QEvent::MouseButtonRelease,
                                  state.graphWidget->mapFrom(state.popup, lineFinish),
                                  Qt::LeftButton, Qt::NoButton, Qt::AltModifier);
        if (!state.popup->isVisible())
            fail("pitch-bend popup dismissed after its Alt line");
        if (m_document.undoStack()->index() != m_curveUndoIndex + 1)
            fail("Alt line did not push exactly one pitch-bend edit");
        std::vector<DocLanePoint> angled;
        for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, DOC_CC_BEND)) {
            if (point.tick > m_note.tick && point.tick < m_endTick)
                angled.push_back(point);
        }
        bool fineLinearRamp = angled.size() >= 3;
        for (size_t i = 1; i < angled.size(); i++) {
            if (angled[i].tick - angled[i - 1].tick > m_view.fineGridTicks() ||
                angled[i].value <= angled[i - 1].value) {
                fineLinearRamp = false;
                break;
            }
        }
        if (!fineLinearRamp)
            fail("Alt drag did not write a fine-grid angled pitch-bend ramp");
    }

    bool reopenPersistedAltPopup(PersistedAltPopupState *state)
    {
        QCursor::setPos(m_roll->mapToGlobal(QPointF(m_noteCenter)).toPoint());
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!popup || !popup->isVisible()) {
            fail("G did not reopen the pitch-bend popup after the Alt line");
            return false;
        }
        state->popup = popup;
        state->graph = popup->graphRect();
        state->graphWidget = popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph"));
        if (!state->graphWidget)
            fail("reopened pitch-bend popup has no pitchBendGraph child");
        return true;
    }

    bool persistedCurvePixelNear(const QImage &image, qreal dpr, QPoint logical,
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

    void verifyPersistedAltDiagonal(const PersistedAltPopupState &state)
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
            const QPoint visualPoint(qRound(double(visualStart.x()) +
                                            fraction * double(visualFinish.x() - visualStart.x())),
                                     qRound(double(visualStart.y()) +
                                            fraction * double(visualFinish.y() - visualStart.y())));
            if (persistedCurvePixelNear(angledImage, angledDpr, visualPoint, curveColor))
                diagonalHits++;
        }
        if (diagonalHits < 4)
            fail("Alt pitch-bend ramp painted as stair steps instead of diagonal segments");
    }

    void restorePersistedAltCurve()
    {
        drainPopupDeletes();
        m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != m_curveUndoIndex ||
            m_document.smf().write() != m_beforeCurve)
            fail("undo did not restore the document after the Alt pitch-bend line");
    }

    void runPersistedAltRendering()
    {
        PersistedAltPopupState current;
        if (!openPersistedAltPopup(&current))
            return;
        drivePersistedAltRamp(current);
        sendKeyStroke(*current.popup, Qt::Key_Escape, Qt::NoModifier, false);
        if (current.popup->isVisible())
            fail("Escape did not dismiss the pitch-bend popup");
        drainPopupDeletes();
        PersistedAltPopupState reopened;
        if (reopenPersistedAltPopup(&reopened)) {
            if (reopened.graphWidget)
                verifyPersistedAltDiagonal(reopened);
            sendKeyStroke(*reopened.popup, Qt::Key_Escape, Qt::NoModifier, false);
            if (reopened.popup->isVisible())
                fail("Escape did not dismiss the reopened pitch-bend popup");
        }
        restorePersistedAltCurve();
    }

    void runResetAndAudition()
    {
        drainPopupDeletes();
        QCursor::setPos(m_roll->mapToGlobal(QPointF(m_noteCenter)).toPoint());
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
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
            QWidget *keyTarget = QApplication::focusWidget();
            if (!keyTarget || (keyTarget != resetPopup && !resetPopup->isAncestorOf(keyTarget)))
                keyTarget = resetPopup;
            QKeyEvent playPauseOverride(QEvent::ShortcutOverride, Qt::Key_Space, Qt::NoModifier);
            QCoreApplication::sendEvent(keyTarget, &playPauseOverride);
            if (!playPauseOverride.isAccepted())
                fail("pitch-bend editor did not claim Space from the window transport shortcut");
            uint64_t requestedTick = UINT64_MAX;
            int playbackRequests = 0;
            const QMetaObject::Connection connection =
                QObject::connect(&m_view, &SongView::playPauseFromRequested,
                                 [&requestedTick, &playbackRequests](uint64_t tick) {
                                     requestedTick = tick;
                                     playbackRequests++;
                                 });
            sendKeyStroke(*keyTarget, Qt::Key_Space, Qt::NoModifier, false);
            QObject::disconnect(connection);
            if (playbackRequests != 1 || requestedTick != m_note.tick)
                fail("Space did not request playback from the selected note's start");
            if (!resetPopup->isVisible())
                fail("Space closed the pitch-bend popup");
            const uint32_t muteBefore = m_view.muteMask();
            sendKeyStroke(*keyTarget, Qt::Key_M, Qt::NoModifier, false);
            if (m_view.muteMask() != muteBefore)
                fail("M from the pitch-bend editor reached the roll mute command");
            const uint32_t soloBefore = m_view.soloMask();
            sendKeyStroke(*keyTarget, Qt::Key_S, Qt::NoModifier, false);
            if (m_view.soloMask() != (soloBefore ^ (uint32_t{1} << m_engineTrack)))
                fail("S from the pitch-bend editor did not toggle the selected track's Solo");
            sendKeyStroke(*keyTarget, Qt::Key_S, Qt::NoModifier, false);
            if (m_view.soloMask() != soloBefore)
                fail("second S from the pitch-bend editor did not restore the Solo state");
            if (m_document.undoStack()->index() != resetBaseline + 1)
                fail("Reset audition did not push exactly one pitch-bend edit");
            m_document.undoStack()->undo();
            if (m_document.undoStack()->index() != m_curveUndoIndex ||
                m_document.smf().write() != m_beforeCurve)
                fail("undo did not restore the document after pitch-bend Reset");
        }
        sendKeyStroke(*resetPopup, Qt::Key_Escape, Qt::NoModifier, false);
        if (resetPopup->isVisible() || m_document.smf().write() != m_beforeCurve ||
            m_view.selectionModel().noteSelection().size() != 1 ||
            m_view.selectionModel().noteSelection().front() != m_note.noteId)
            fail("Escape did not dismiss the pitch-bend popup while retaining the note");
        drainPopupDeletes();
    }

    void runFocusHandoff()
    {
        drainPopupDeletes();
        QCursor::setPos(m_roll->mapToGlobal(QPointF(m_noteCenter)).toPoint());
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        QPointer<songview::PitchBendEditor> popup =
            dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!popup || !popup->isVisible()) {
            fail("G did not reopen the pitch-bend popup for focus handoff");
            return;
        }
        checks::events::sendMouse(*m_roll, QEvent::MouseButtonPress, m_noteCenter, Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::processEvents();
        if (popup && popup->isVisible())
            fail("clicking the selected note did not dismiss the pitch-bend popup");
        if (m_view.selectionModel().noteSelection().size() != 1 ||
            m_view.selectionModel().noteSelection().front() != m_note.noteId)
            fail("clicking the selected note did not preserve note focus");
        drainPopupDeletes();
        QPoint edgeHandle;
        bool foundEdge = false;
        for (int x = 0; x < qRound(m_roll->bounds().width()); ++x) {
            const QPoint candidate(x, m_noteCenter.y());
            checks::events::sendMouse(*m_roll, QEvent::MouseMove, candidate, Qt::NoButton,
                                      Qt::NoButton, Qt::NoModifier);
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
        checks::events::sendMouse(*m_roll, QEvent::MouseMove, QPoint(1, m_noteCenter.y()),
                                  Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        if (m_roll->cursor().shape() != Qt::ArrowCursor)
            fail("piano-roll cursor stopped tracking after pitch-bend click-away dismissal");
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!popup || !popup->isVisible()) {
            fail("G did not reopen the pitch-bend popup for cursor handoff");
            return;
        }
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        drainPopupDeletes();
        popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (popup)
            activateSyntheticToolWindow(*popup);
        QCoreApplication::processEvents();
        QWidget *replacementGraph =
            popup ? popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph")) : nullptr;
        if (!popup || !popup->isVisible() || !replacementGraph || !replacementGraph->hasFocus()) {
            fail("replacing the pitch-bend popup did not retain graph focus");
            return;
        }
        const QPoint edgeGlobal = m_roll->mapToGlobal(QPointF(edgeHandle)).toPoint();
        QCursor::setPos(edgeGlobal);
        QCoreApplication::processEvents();
        const bool cursorWarped = QCursor::pos() == edgeGlobal;
        sendKeyStroke(*popup, Qt::Key_Escape, Qt::NoModifier, false);
        drainPopupDeletes();
        QCoreApplication::processEvents();
        if (cursorWarped && m_roll->cursor().pixmap().isNull())
            fail("dismissing the pitch-bend popup did not restore the note-edge cursor");
    }

    void cleanupBaseFixture()
    {
        while (m_document.undoStack()->index() > m_undoIndex && m_document.undoStack()->canUndo())
            m_document.undoStack()->undo();
        if (m_document.undoStack()->index() != m_undoIndex ||
            m_document.smf().write() != m_beforeBend)
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

    struct BoundaryFixtureState {
        QByteArray beforeSmf;
        int beforeUndoIndex = 0;
        std::vector<NoteId> beforeSelection;
        SongView::ViewState beforeViewState;
        uint64_t clock = 1;
        uint64_t fixtureTick = 0;
        uint64_t fixtureEndTick = 0;
        uint64_t span = 0;
        uint64_t boundaryTick = 0;
        uint8_t fixtureKey = 0;
        double pixelsPerTick = 0.0;
        SongView::GridSeg initialSegment;
        uint64_t initialCell = 0;
        DocNote fixtureNote;
    };

    void runActiveGridBoundary()
    {
        BoundaryFixtureState fixture;
        bool ready = createBoundaryFixture(&fixture);
        if (ready)
            ready = inspectBoundaryFixturePopup(&fixture);
        if (ready)
            ready = installBoundarySignature(&fixture);
        if (ready)
            ready = driveBoundaryFreehand(&fixture);
        if (ready)
            verifyBoundarySamples(fixture);
        restoreBoundaryFixture(fixture);
    }

    void restoreBoundaryFixture(const BoundaryFixtureState &fixture)
    {
        drainPopupDeletes();
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (popup && popup->isVisible()) {
            sendKeyStroke(*popup, Qt::Key_Escape, Qt::NoModifier, false);
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
        if (m_view.gridFeel() != (fixture.beforeViewState.gridTriplet
                                      ? SongView::GridFeel::Triplet
                                      : SongView::GridFeel::Straight) ||
            m_view.gridMinDenom() != fixture.beforeViewState.gridMinDenom ||
            m_view.selectionModel().noteSelection() != fixture.beforeSelection)
            fail("active-grid fixture did not restore view grid settings and selection");
        if (!m_document.containsNoteSpan(m_engineTrack, m_note, m_endTick))
            fail("active-grid fixture changed the original note span");
    }

    bool createBoundaryFixture(BoundaryFixtureState *fixture)
    {
        fixture->beforeSmf = m_document.smf().write();
        fixture->beforeUndoIndex = m_document.undoStack()->index();
        fixture->beforeSelection = m_view.selectionModel().noteSelection();
        fixture->beforeViewState = m_view.viewState();
        fixture->clock = std::max<uint64_t>(1, m_document.ticksPerClock());
        uint64_t fixtureEnd = 0;
        for (const SmfTrack &track : m_document.smf().tracks)
            fixtureEnd = std::max(fixtureEnd, track.endTick);
        const uint64_t margin = std::max<uint64_t>(fixture->clock * 8, 96);
        if (fixtureEnd > UINT64_MAX - margin) {
            fail("active-grid fixture tick overflowed");
            return false;
        }
        fixture->fixtureTick = fixtureEnd + margin;
        fixture->span = std::max<uint64_t>(fixture->clock * 96, 192);
        if (fixture->fixtureTick > UINT64_MAX - fixture->span) {
            fail("active-grid fixture span overflowed");
            return false;
        }
        fixture->fixtureEndTick = fixture->fixtureTick + fixture->span;
        fixture->fixtureKey = m_note.key == 127 ? 126 : uint8_t(m_note.key + 1);
        m_document.addNote(m_engineTrack, fixture->fixtureTick, fixture->fixtureKey,
                           uint32_t(fixture->span), 100);
        QCoreApplication::processEvents();
        if (!m_document.findNote(m_engineTrack, fixture->fixtureTick, fixture->fixtureKey,
                                 &fixture->fixtureNote)) {
            fail("active-grid fixture note was not created");
            return false;
        }
        return true;
    }

    songview::PitchBendEditor *openBoundaryPopup(const BoundaryFixtureState &fixture,
                                                 const char *failure)
    {
        m_view.selectTrack(m_engineTrack);
        m_view.selectionModel().setNoteSelection({fixture.fixtureNote.noteId});
        QCursor::setPos(m_roll->mapToGlobal(QPointF(m_noteCenter)).toPoint());
        checks::rollcheck::sendKeyStroke(*m_roll, Qt::Key_G, Qt::NoModifier, false);
        QWidget *popupWidget = m_view.findChild<QWidget *>(QStringLiteral("pitchBendPopup"));
        auto *popup = dynamic_cast<songview::PitchBendEditor *>(popupWidget);
        if (!popup || !popup->isVisible()) {
            fail(failure);
            return nullptr;
        }
        return popup;
    }

    bool inspectBoundaryFixturePopup(BoundaryFixtureState *fixture)
    {
        auto *popup = openBoundaryPopup(
            *fixture, "active-grid fixture note did not open its pitch-bend popup");
        if (!popup)
            return false;
        const QRect graph = popup->graphRect();
        fixture->pixelsPerTick = double(graph.width()) / double(fixture->span);
        fixture->initialSegment = m_view.gridSegAt(fixture->fixtureTick);
        fixture->initialCell =
            m_view.gridTicksAtScale(fixture->fixtureTick, fixture->pixelsPerTick);
        sendKeyStroke(*popup, Qt::Key_Escape, Qt::NoModifier, false);
        drainPopupDeletes();
        if (fixture->initialCell == 0) {
            fail("active-grid fixture produced no normal grid cell");
            return false;
        }
        return true;
    }

    bool installBoundarySignature(BoundaryFixtureState *fixture)
    {
        const std::vector<uint64_t> offsets{fixture->span / 5, fixture->span / 3, fixture->span / 2,
                                            (fixture->span * 2) / 3, (fixture->span * 4) / 5};
        bool signatureInstalled = false;
        for (const uint64_t offset : offsets) {
            if (offset <= fixture->clock || offset >= fixture->span - fixture->clock)
                continue;
            const uint64_t candidate = fixture->fixtureTick + offset;
            m_document.setTimeSig(candidate, 8, 3);
            QCoreApplication::processEvents();
            bool oldStartAnchorWouldFail = false;
            const uint64_t delta = candidate > fixture->initialSegment.start
                                       ? candidate - fixture->initialSegment.start
                                       : 0;
            const uint64_t steps = delta / fixture->initialCell + 1;
            if (steps <= (UINT64_MAX - fixture->initialSegment.start) / fixture->initialCell) {
                uint64_t oldTick = fixture->initialSegment.start + steps * fixture->initialCell;
                while (oldTick < fixture->fixtureEndTick) {
                    if (oldTick > candidate) {
                        const SongView::GridSeg segment = m_view.gridSegAt(oldTick);
                        const uint64_t cell =
                            m_view.gridTicksAtScale(oldTick, fixture->pixelsPerTick);
                        if (cell == 0 || oldTick < segment.start ||
                            (oldTick - segment.start) % cell != 0) {
                            oldStartAnchorWouldFail = true;
                            break;
                        }
                    }
                    if (UINT64_MAX - oldTick < fixture->initialCell)
                        break;
                    oldTick += fixture->initialCell;
                }
            }
            if (oldStartAnchorWouldFail) {
                fixture->boundaryTick = candidate;
                signatureInstalled = true;
                break;
            }
            m_document.undoStack()->undo();
            QCoreApplication::processEvents();
        }
        if (!signatureInstalled) {
            fail("active-grid fixture could not separate signature grid anchors");
            return false;
        }
        return true;
    }

    bool driveBoundaryFreehand(BoundaryFixtureState *fixture)
    {
        auto *popup = openBoundaryPopup(
            *fixture, "active-grid fixture could not reopen its pitch-bend popup");
        if (!popup)
            return false;
        QWidget *graphWidget = popup->findChild<QWidget *>(QStringLiteral("pitchBendGraph"));
        if (!graphWidget) {
            fail("active-grid popup has no pitchBendGraph child");
            sendKeyStroke(*popup, Qt::Key_Escape, Qt::NoModifier, false);
            return false;
        }
        if (!m_document.findNote(m_engineTrack, fixture->fixtureTick, fixture->fixtureKey,
                                 &fixture->fixtureNote) ||
            !m_document.containsNoteSpan(m_engineTrack, fixture->fixtureNote,
                                         fixture->fixtureEndTick))
            fail("active-grid fixture note span was not preserved");
        const QRect graph = popup->graphRect();
        const QPoint lineStart(graph.left() + graph.width() / 12,
                               graph.bottom() - graph.height() / 10);
        const QPoint lineFinish(graph.right() - graph.width() / 12,
                                graph.top() + graph.height() / 10);
        const int curveUndoIndex = m_document.undoStack()->index();
        checks::events::sendMouse(*graphWidget, QEvent::MouseButtonPress,
                                  graphWidget->mapFrom(popup, lineStart), Qt::LeftButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*graphWidget, QEvent::MouseMove,
                                  graphWidget->mapFrom(popup, lineFinish), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*graphWidget, QEvent::MouseButtonRelease,
                                  graphWidget->mapFrom(popup, lineFinish), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (!popup->isVisible())
            fail("active-grid freehand drag dismissed the pitch-bend popup");
        if (m_document.undoStack()->index() != curveUndoIndex + 1)
            fail("active-grid freehand drag did not push exactly one curve command");
        return true;
    }

    void verifyBoundarySamples(const BoundaryFixtureState &fixture)
    {
        bool sawBeforeBoundary = false;
        bool sawAfterBoundary = false;
        bool misaligned = false;
        for (const DocLanePoint &point : m_document.lanePoints(m_engineTrack, DOC_CC_BEND)) {
            if (point.tick <= fixture.fixtureTick || point.tick >= fixture.fixtureEndTick)
                continue;
            const SongView::GridSeg segment = m_view.gridSegAt(point.tick);
            const uint64_t cell = m_view.gridTicksAtScale(point.tick, fixture.pixelsPerTick);
            const bool aligned =
                cell > 0 && point.tick >= segment.start && (point.tick - segment.start) % cell == 0;
            if (!aligned)
                misaligned = true;
            if (point.tick < fixture.boundaryTick)
                sawBeforeBoundary = true;
            if (point.tick > fixture.boundaryTick)
                sawAfterBoundary = true;
        }
        if (misaligned)
            fail("normal freehand drag used a stale start-segment grid anchor");
        if (!sawBeforeBoundary || !sawAfterBoundary)
            fail("active-grid freehand drag did not sample both signature segments");
    }

    SongDocument &m_document;
    SongView &m_view;
    songview::TimelineInputItem *m_roll = nullptr;
    int m_engineTrack = -1;
    DocNote m_note;
    QPoint m_noteCenter;
    QString m_songLabel;
    int m_failures = 0;
    QByteArray m_beforeRange;
    QByteArray m_beforeBend;
    QByteArray m_beforeCurve;
    int m_beforeRangeUndoIndex = 0;
    int m_undoIndex = 0;
    int m_curveUndoIndex = 0;
    uint64_t m_endTick = 0;
    int m_bendAtEnd = 0;
};

} // namespace

int runPitchBendCheck(SongDocument &document, SongView &view, songview::TimelineInputItem *roll,
                      int engineTrack, const DocNote &note, const QPoint &noteCenter,
                      const QString &songLabel)
{
    return PitchBendCheckContext(document, view, roll, engineTrack, note, noteCenter, songLabel)
        .run();
}
