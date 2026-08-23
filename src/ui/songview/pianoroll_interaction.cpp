// ---------------------------------------------------------------- PianoRoll pointer interaction

#include "ui/songview/pianoroll.h"

#include "core/mid2agbtables.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"

#include <QApplication>
#include <QCursor>
#include <QEvent>
#include <QMouseEvent>

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;
using namespace songview::pianoroll_detail;

void PianoRoll::mousePressEvent(QMouseEvent *event)
{
    setFocus();
    if (!m_sv->timeline())
        return;
    m_sv->setProjectionLocked(true);

    if (event->button() == Qt::MiddleButton) {
        // Reaper-style pan: drag scrolls the roll on both axes.
        m_panning = true;
        m_panPos = event->globalPosition();
        setCursor(Qt::ClosedHandCursor);
        return;
    }

    // Keyboard column: select the selected track's matching notes and
    // audition the clicked key.
    if (event->position().x() < m_geometry.pianoKeyboardWidth) {
        if (event->button() == Qt::LeftButton) {
            m_kbdKey = yToKey(event->position().y());
            std::vector<NoteId> ids;
            for (const ViewNote &note : m_sv->model().notes) {
                if (note.track == m_sv->selectionModel().primaryTrack() && note.key == m_kbdKey &&
                    note.noteId.isAssigned())
                    ids.push_back(note.noteId);
            }
            m_sv->selectionModel().setNoteSelection(std::move(ids));
            auditionKey(m_kbdKey, 100);
        }
        return;
    }

    SongDocument *doc = m_sv->document();
    const ViewNote *hit = doc ? hitNote(event->position()) : nullptr;

    if (event->button() == Qt::RightButton) {
        // Deferred: a drag from here rubber-band-selects (with Shift, it
        // sweeps a full-height time selection instead); releasing in
        // place context-acts on the pressed note (or on the time
        // selection under the click, or clears the selections over empty
        // space). Resolved in mouseReleaseEvent.
        if (!doc)
            return;
        m_pressPos = m_curPos = event->position();
        m_rightPress = true;
        m_rightShift = event->modifiers() & Qt::ShiftModifier;
        m_rightAnchorTick = m_sv->snapTick(
            m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth));
        m_rightHit = hit != nullptr;
        if (hit)
            m_rightHitId = hit->noteId;
        return;
    }
    if (event->button() != Qt::LeftButton)
        return;

    m_pressPos = m_curPos = event->position();
    m_pressTick = m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    m_pressKey = yToKey(event->position().y());
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    m_modifierVelocityDrag = false;

    if (!hit && doc && m_sv->scaleFold() && (m_pressKey < 0 || !m_sv->isScalePitch(m_pressKey))) {
        return;
    }
    if (hit) {
        const bool rightEdge = nearRightEdge(*hit, event->position());
        const bool leftEdge = nearLeftEdge(*hit, event->position());
        // Ableton-style velocity gesture: with the bound modifier chord
        // held (Ctrl by default), a vertical drag from anywhere on the
        // note adjusts velocity. Deferred like the empty-space press:
        // the click action (Ctrl's selection toggle) resolves on
        // release, a drag past the threshold in mouseMoveEvent.
        const auto &keys = keymap::Registry::instance();
        const auto pressMods = event->modifiers();
        if (keys.matchesModifier(pressMods, QStringLiteral("roll.velocity_drag")) && !rightEdge &&
            !leftEdge) {
            m_velModPress = true;
            m_velModMods =
                keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
            m_velAnchor = *hit;
            m_velAudEff = mid2agbEffectiveVelocity(hit->velocity);
            m_sv->announceNote(*hit);
            m_lastVelocity = hit->velocity;
            auditionKey(hit->key, hit->velocity);
            m_auditioned = true;
            invalidateContent();
            return;
        }
        const auto &storedSelection = m_sv->selectionModel().noteSelection();
        std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
        const NoteId id = hit->noteId;
        if ((event->modifiers() & Qt::ControlModifier) && !rightEdge && !leftEdge) {
            if (std::erase(ids, id) == 0)
                ids.push_back(id);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        } else if (event->modifiers() & Qt::ControlModifier) {
            // Ctrl+edge grab: the grip still starts a resize of the
            // whole selection, so a bulk-select click landing on an
            // edge must join the note to the selection, not replace it.
            if (std::find(ids.begin(), ids.end(), id) == ids.end()) {
                ids.push_back(id);
                m_sv->selectionModel().setNoteSelection(std::move(ids));
            }
        } else if (hit->track != m_sv->selectionModel().primaryTrack() ||
                   !hit->noteId.isAssigned() ||
                   !m_sv->selectionModel().isNoteSelected(hit->noteId)) {
            m_sv->selectionModel().setNoteSelection({id});
        }
        m_sv->announceNote(*hit);
        // Reaper-style velocity latch: touching a note makes its velocity
        // the default for the next drawn note.
        m_lastVelocity = hit->velocity;
        if (rightEdge) {
            m_drag = Drag::Resize;
            m_gripTick = hit->endTick;
            m_gripOpposite = hit->startTick;
        } else if (leftEdge) {
            m_drag = Drag::ResizeLeft;
            m_gripTick = hit->startTick;
            m_gripOpposite = hit->endTick;
        } else if (nearVelocityHandle(*hit, event->position())) {
            m_drag = Drag::Velocity;
            m_velAnchor = *hit;
            m_velAudEff = mid2agbEffectiveVelocity(hit->velocity);
            if (!m_sv->beginVelocityGesture(resolveSelection()))
                cancelVelocityInteraction();
        } else {
            m_drag = Drag::Move;
        }
        // Sound the grabbed note so a press gives the same pitch feedback
        // a drag already does.
        auditionKey(hit->key, hit->velocity);
        m_auditioned = true;
    } else if (doc) {
        // Empty space: deferred, Reaper-style. A horizontal drag from
        // here draws a note (resolved in mouseMoveEvent); releasing in
        // place parks the edit cursor at the click instead. A
        // double-click draws immediately (mouseDoubleClickEvent).
        m_leftPress = true;
        m_sv->selectionModel().clearNoteSelection();
        // Sound the clicked row at the latched velocity so a plain
        // press gives the same pitch feedback a draw already does.
        auditionKey(m_pressKey, m_lastVelocity);
        m_auditioned = true;
    } else {
        // Read-only (no document): park the edit cursor at the click,
        // like the ruler; playback follows when running.
        m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
    }
    invalidateContent();
}

void PianoRoll::mouseDoubleClickEvent(QMouseEvent *event)
{
    // Double-click on empty space drops a grid-sized note (committed on
    // release; dragging before release still sizes it); on a note it
    // deletes that note. Anywhere else a fast click-click behaves as two
    // presses — Qt replaces the second press with this event.
    SongDocument *doc = m_sv->document();
    if (event->button() == Qt::LeftButton && doc &&
        event->position().x() >= m_geometry.pianoKeyboardWidth) {
        m_sv->setProjectionLocked(true);
        setFocus();
        if (const ViewNote *hit = hitNote(event->position())) {
            DocNote note;
            if (doc->findNote(hit->noteId, &note)) {
                doc->deleteNotes({note});
                m_sv->selectionModel().clearNoteSelection();
            }
            return;
        }
        m_pressPos = m_curPos = event->position();
        m_pressTick = m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
        m_pressKey = yToKey(event->position().y());
        beginDraw();
        return;
    }
    mousePressEvent(event);
}

void PianoRoll::mouseMoveEvent(QMouseEvent *event)
{
    // A velocity drag moves the cursor vertically while the note's
    // pitch stays put; the mark pins to the note so the readout
    // doesn't wander off its row.
    setHoverKey(m_drag == Drag::Velocity ? m_velAnchor.key : yToKey(event->position().y()));
    if (m_panning) {
        const QPointF d = event->globalPosition() - m_panPos;
        m_panPos = event->globalPosition();
        m_sv->scrollByPx(-d.x());
        m_sv->scrollRollBy(-d.y());
        return;
    }
    if (m_kbdKey >= 0) {
        // Keyboard column: dragging glisses — the sounding key follows
        // the cursor (the engine's mono preview releases the old key).
        const int key = yToKey(event->position().y());
        if (key != m_kbdKey) {
            m_kbdKey = key;
            auditionKey(m_kbdKey, 100);
        }
        return;
    }
    m_curPos = event->position();
    if (m_rightPress && m_drag == Drag::None &&
        (event->pos() - m_pressPos.toPoint()).manhattanLength() >=
            QApplication::startDragDistance()) {
        m_drag = m_rightShift ? Drag::TimeSel : Drag::Band;
        m_bandAud.clear();
    }
    if (m_leftPress && m_drag == Drag::None) {
        // The pressed row's preview glisses with the cursor, like the
        // keyboard column; a draw started below anchors on the new row.
        const int key = yToKey(event->position().y());
        if (key != m_pressKey) {
            m_pressKey = key;
            auditionKey(key, m_lastVelocity);
            m_auditioned = true;
        }
    }
    if (m_leftPress && m_drag == Drag::None &&
        std::abs(event->position().x() - m_pressPos.x()) >= lyt::space(Space::One)) {
        // The deferred empty-space press turns out to be a draw gesture.
        // Space::One of horizontal travel starts it — enough to filter
        // click jitter while staying well under the platform drag
        // threshold, so the pending note still appears near-immediately;
        // this same event falls through to the Draw branch, which sizes
        // it from the cursor (one snap cell until the drag crosses the
        // next snap line).
        beginDraw();
    }
    if (m_velModPress && m_drag == Drag::None) {
        // The deferred modifier press becomes a velocity drag once it
        // travels vertically past the click threshold (so a jittery
        // Ctrl+click stays a selection toggle). The same event falls
        // through to the Velocity branch, which measures from the press.
        if (std::abs(event->pos().y() - m_pressPos.toPoint().y()) <
            QApplication::startDragDistance())
            return;
        m_velModPress = false;
        const NoteId id = m_velAnchor.noteId;
        const bool switchesNotes =
            m_suppressNextVelocitySelectionAdd && id != m_lastModifierVelocityDragNote;
        if (switchesNotes) {
            m_suppressNextVelocitySelectionAdd = false;
            // A completed modifier velocity edit makes the next such
            // drag on another note switch instead of growing the old
            // selection.
            m_sv->selectionModel().setNoteSelection({id});
        } else if (m_velAnchor.track != m_sv->selectionModel().primaryTrack() ||
                   !m_velAnchor.noteId.isAssigned() ||
                   !m_sv->selectionModel().isNoteSelected(m_velAnchor.noteId)) {
            if (m_velModMods & Qt::ControlModifier) {
                // Ctrl in the chord: like the Ctrl+edge grab, the
                // gesture joins the note to the bulk selection built
                // with the same modifier instead of replacing it, and
                // the drag then nudges the whole selection.
                const auto &storedSelection = m_sv->selectionModel().noteSelection();
                std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
                ids.push_back(id);
                m_sv->selectionModel().setNoteSelection(std::move(ids));
            } else {
                m_sv->selectionModel().setNoteSelection({id});
            }
        }
        m_modifierVelocityDrag = true;
        m_drag = Drag::Velocity;
        if (!m_sv->beginVelocityGesture(resolveSelection()))
            cancelVelocityInteraction();
        // The pass at the top of this event ran before the drag existed;
        // re-pin the mark to the note's row now.
        if (m_drag == Drag::Velocity)
            setHoverKey(m_velAnchor.key);
    }
    if (m_drag == Drag::None) {
        refreshHoverCursor(event->position(), event->modifiers());
        return;
    }

    const double tick = m_sv->tickAtContentX(event->position().x() - m_geometry.pianoKeyboardWidth);
    const int64_t grid = int64_t(m_sv->snapTicksAt(uint64_t(std::max(0.0, m_pressTick))));
    const int64_t snappedD = int64_t(std::llround((tick - m_pressTick) / double(grid))) * grid;

    if (m_drag == Drag::Move) {
        const int dKey = m_sv->scaleFold() ? foldDegreeDeltaForPointer(event->position().y())
                                           : yToKey(event->position().y()) - m_pressKey;
        if (snappedD != m_dTick || dKey != m_dKey) {
            m_dTick = snappedD;
            if (dKey != m_dKey) {
                m_dKey = dKey;
                // Audition the new pitch while dragging vertically.
                const std::vector<DocNote> notes = resolveSelection();
                if (!notes.empty()) {
                    const int key = m_sv->scaleFold()
                                        ? m_sv->nextScalePitch(notes.front().key, m_dKey)
                                        : std::clamp(int(notes.front().key) + m_dKey, 0, 127);
                    if (key >= 0) {
                        auditionKey(key, notes.front().velocity);
                        m_auditioned = true;
                    }
                }
            }
            invalidateContent();
        }
    } else if (m_drag == Drag::Resize || m_drag == Drag::ResizeLeft) {
        // Snap the dragged edge to absolute ruler grid lines, not offsets from
        // its original (possibly off-grid) position. Keep at least one tick.
        const double desired = double(m_gripTick) + (tick - m_pressTick);
        const uint64_t snapped =
            m_drag == Drag::Resize
                ? std::max(m_sv->snapTick(desired), m_sv->snapTickUp(double(m_gripOpposite) + 1.0))
                : std::min(m_sv->snapTick(desired),
                           m_sv->snapTickDown(double(m_gripOpposite) - 1.0));
        const int64_t delta =
            std::abs(desired - double(m_gripTick)) < std::abs(desired - double(snapped))
                ? 0
                : int64_t(snapped) - int64_t(m_gripTick);
        int64_t &target = m_drag == Drag::Resize ? m_dDur : m_dTick;
        if (delta != target) {
            target = delta;
            invalidateContent();
        }
    } else if (m_drag == Drag::Velocity) {
        const int dv = m_pressPos.toPoint().y() - event->pos().y(); // up = louder
        if (dv != m_dVel) {
            m_dVel = dv;
            const int vel = std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127);
            ViewNote preview = m_velAnchor;
            preview.velocity = uint8_t(vel);
            m_sv->announceNote(preview);
            // Re-audition whenever the effective (played) velocity moves
            // to the next mid2agb step.
            const int eff = mid2agbEffectiveVelocity(vel);
            if (eff != m_velAudEff) {
                m_velAudEff = eff;
                auditionKey(m_velAnchor.key, vel);
                m_auditioned = true;
            }
            invalidateContent();
            m_sv->updateVelocityGestureByDelta(m_dVel);
        }
    } else if (m_drag == Drag::Draw) {
        // The edge under the cursor follows it: right of the anchor cell
        // the end grows (rounded up to the next snap line, never shorter
        // than one snap cell); left of it the start moves back (snapped
        // down) with the end pinned to the anchor cell. The key follows the
        // cursor vertically — a slight misclick on mouse-down is fixable
        // mid-gesture, with the new pitch auditioned.
        const uint64_t anchor = m_drawAnchor;
        uint64_t start = anchor;
        int64_t dur;
        if (tick >= double(anchor)) {
            const uint64_t end = std::max(anchor + uint64_t(grid), m_sv->snapTickUp(tick));
            dur = int64_t(end - anchor);
        } else {
            start = m_sv->snapTickDown(tick);
            dur = int64_t(anchor + uint64_t(grid) - start);
        }
        const int key = yToKey(event->position().y());
        const bool isScaleKey = !m_sv->scaleFold() || (key >= 0 && m_sv->isScalePitch(key));
        if (start != m_drawTick || dur != m_drawDur || (isScaleKey && key != m_drawKey)) {
            m_drawTick = start;
            m_drawDur = dur;
            if (isScaleKey && key != m_drawKey) {
                m_drawKey = key;
                auditionKey(m_drawKey, m_lastVelocity);
                m_auditioned = true;
            }
            invalidateContent();
        }
    } else if (m_drag == Drag::TimeSel) {
        // Full-height sweep: a time selection over the selected tracks
        const uint64_t t = m_sv->snapTick(tick);
        EditorSelectionModel::TimeSelection sel;
        sel.startTick = std::min(m_rightAnchorTick, t);
        sel.endTick = std::max(m_rightAnchorTick, t);
        m_sv->selectionModel().setTimeSelection(sel);
    } else if (m_drag == Drag::Band) {
        auditionBandEntrants(QRectF(m_pressPos, m_curPos).normalized());
        invalidateContent();
    }
}

void PianoRoll::leaveEvent(QEvent *)
{
    setHoverKey(-1);
}

void PianoRoll::mouseReleaseEvent(QMouseEvent *event)
{
    const auto completeProjectionGesture = [this] {
        m_sv->setProjectionLocked(false);
        m_sv->flushProjectionIfDirty();
    };
    if (event->button() == Qt::MiddleButton && m_panning) {
        m_panning = false;
        setCursor(Qt::ArrowCursor);
        completeProjectionGesture();
        return;
    }
    if (m_kbdKey >= 0) {
        auditionKey(m_kbdKey, 0);
        m_kbdKey = -1;
    }
    SongDocument *doc = m_sv->document();
    if (event->button() == Qt::RightButton && m_rightPress) {
        const Drag drag = m_drag;
        m_rightPress = false;
        m_drag = Drag::None;
        if (drag == Drag::TimeSel) {
            if (m_sv->selectionModel().timeSelection().active())
                m_sv->announceTimeSelection();
            else
                m_sv->selectionModel().clearTimeSelection();
        } else if (drag == Drag::Band) {
            stopBandAuditions();
            selectBand(QRectF(m_pressPos, m_curPos).normalized(),
                       event->modifiers() & Qt::ControlModifier);
        } else if (doc && m_rightHit) {
            const auto &selection = m_sv->selectionModel().noteSelection();
            if (std::find(selection.begin(), selection.end(), m_rightHitId) == selection.end())
                m_sv->selectionModel().setNoteSelection({m_rightHitId});
            showNoteMenu(event->position());
        } else if (insideTimeSelection(event->position().x())) {
            m_sv->showTimeSelectionMenu(event->globalPosition().toPoint());
        } else {
            m_sv->selectionModel().clearNoteSelection();
            m_sv->selectionModel().clearTimeSelection();
        }
        invalidateContent();
        completeProjectionGesture();
        return;
    }
    if (event->button() == Qt::LeftButton && m_leftPress) {
        m_leftPress = false;
        if (m_drag == Drag::None) {
            if (insideTimeSelection(event->position().x()))
                m_sv->selectionModel().clearTimeSelection();
            // Click without a drag: park the edit cursor at the click,
            // like the ruler; playback follows when running.
            m_sv->commitEditCursor(m_sv->snapTick(m_pressTick));
            invalidateContent();
            completeProjectionGesture();
            stopNoteAudition();
            return;
        }
    }
    if (event->button() == Qt::LeftButton && m_velModPress) {
        // The modifier press never grew into a velocity drag: give the
        // click its undeferred meaning — Ctrl in the chord keeps its
        // selection toggle, any other chord selects like a plain click.
        m_velModPress = false;
        const NoteId id = m_velAnchor.noteId;
        if (m_velModMods & Qt::ControlModifier) {
            const auto &storedSelection = m_sv->selectionModel().noteSelection();
            std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
            if (std::erase(ids, id) == 0)
                ids.push_back(id);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        } else if (m_velAnchor.track != m_sv->selectionModel().primaryTrack() ||
                   !m_velAnchor.noteId.isAssigned() ||
                   !m_sv->selectionModel().isNoteSelected(m_velAnchor.noteId)) {
            m_sv->selectionModel().setNoteSelection({id});
        }
        invalidateContent();
        completeProjectionGesture();
        stopNoteAudition();
        return;
    }
    if (event->button() != Qt::LeftButton || m_drag == Drag::None) {
        if (event->button() != Qt::LeftButton && m_drag == Drag::Velocity)
            cancelVelocityInteraction();
        completeProjectionGesture();
        stopNoteAudition();
        return;
    }

    const Drag drag = m_drag;
    const bool modifierVelocityDrag = m_modifierVelocityDrag;
    m_modifierVelocityDrag = false;
    m_drag = Drag::None;
    SongView::VelocityCommitResult velocityResult = SongView::VelocityCommitResult::NoGesture;
    if (drag == Drag::Velocity)
        velocityResult = m_sv->commitVelocityGesture();
    const bool velocityCommitted = velocityResult == SongView::VelocityCommitResult::Committed ||
                                   velocityResult == SongView::VelocityCommitResult::Unchanged;
    if (modifierVelocityDrag && velocityResult == SongView::VelocityCommitResult::Committed &&
        keymap::Registry::instance().matchesModifier(event->modifiers(),
                                                     QStringLiteral("roll.velocity_drag"))) {
        m_suppressNextVelocitySelectionAdd = true;
        m_lastModifierVelocityDragNote = m_velAnchor.noteId;
    }

    if (doc && drag == Drag::Draw) {
        const int selectedTrack = m_sv->selectionModel().primaryTrack();
        const std::vector<DocNote> before = doc->notesForTrack(selectedTrack);
        doc->addNote(selectedTrack, m_drawTick, uint8_t(m_drawKey), uint32_t(m_drawDur),
                     m_lastVelocity);
        m_sv->selectionModel().setNoteSelection(insertedNoteIds(selectedTrack, before));
    } else if (doc && drag == Drag::Move && (m_dTick != 0 || m_dKey != 0)) {
        std::vector<DocNote> notes = resolveSelection();
        if (notes.empty()) {
            m_sv->selectionModel().clearNoteSelection();
        } else if (m_sv->scaleFold() && m_dKey != 0) {
            std::vector<uint8_t> destinations;
            if (m_sv->resolveFoldDestinations(notes, m_dKey, destinations) &&
                doc->moveNotesToPitches(notes, destinations, m_dTick)) {
                std::vector<NoteId> ids;
                ids.reserve(notes.size());
                for (const DocNote &note : notes)
                    ids.push_back(note.noteId);
                m_sv->selectionModel().setNoteSelection(std::move(ids));
            }
        } else {
            doc->moveNotes(notes, m_dTick, m_dKey);
            // Follow the notes with the selection.
            std::vector<NoteId> ids;
            ids.reserve(notes.size());
            for (const DocNote &note : notes)
                ids.push_back(note.noteId);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        }
    } else if (doc && drag == Drag::Resize && m_dDur != 0) {
        doc->resizeNotes(resolveSelection(), m_dDur);
    } else if (doc && drag == Drag::ResizeLeft && m_dTick != 0) {
        const std::vector<DocNote> notes = resolveSelection();
        doc->resizeNotesLeft(notes, m_dTick);
    } else if (drag == Drag::Velocity && m_dVel != 0 && velocityCommitted) {
        // Latch the dragged note's final velocity for the next draw.
        m_lastVelocity = uint8_t(std::clamp(int(m_velAnchor.velocity) + m_dVel, 1, 127));
    }
    stopNoteAudition();
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
    invalidateContent();
    completeProjectionGesture();
}

void PianoRoll::stopNoteAudition()
{
    if (!m_auditioned)
        return;
    auditionKey(0, 0);
    m_auditioned = false;
}

void PianoRoll::auditionKey(int key, int velocity)
{
    m_sv->audition(m_sv->selectionModel().primaryTrack(), key, velocity);
    const int sounding = velocity > 0 ? key : -1;
    if (sounding != m_soundingKey) {
        m_soundingKey = sounding;
        invalidateContent(QRegion(lyt::space(Space::Zero), lyt::space(Space::Zero),
                                  m_geometry.pianoKeyboardWidth, height()));
    }
}
} // namespace songview
