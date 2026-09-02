// ---------------------------------------------------------------- PianoRoll press gestures

#include "ui/songview/pianoroll.h"

#include "core/mid2agbtables.h"
#include "porydaw_scale.h"
#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelinequickview.h"
#include <QApplication>

#include <algorithm>
#include <cmath>
#include <utility>
#include <vector>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {

bool PianoRoll::isLiveDrag(LeftDrag drag)
{
    return drag == LeftDrag::Draw || drag == LeftDrag::Move || drag == LeftDrag::Resize ||
           drag == LeftDrag::ResizeLeft || drag == LeftDrag::Velocity;
}

bool PianoRoll::isLiveDrag(RightDrag drag)
{
    return drag == RightDrag::Band || drag == RightDrag::TimeSel;
}

bool PianoRoll::dragLive() const
{
    return isLiveDrag(m_leftDrag) || isLiveDrag(m_rightDrag);
}

void PianoRoll::activateLeftDrag(LeftDrag state)
{
    m_leftDrag = state;
    if (isLiveDrag(m_rightDrag))
        m_rightDrag = RightDrag::PendingMenu;
}

void PianoRoll::clearLiveDragToken()
{
    if (isLiveDrag(m_leftDrag)) {
        m_leftDrag = LeftDrag::None;
    } else if (isLiveDrag(m_rightDrag)) {
        m_rightDrag = RightDrag::PendingMenu;
    }
}

void PianoRoll::beginPanGesture(const TimelinePointerInput &input)
{
    m_panning = true;
    m_panPos = input.globalPosition;
    if (m_inputHost)
        m_inputHost->setCursor(Qt::ClosedHandCursor);
}

void PianoRoll::beginKbdAudition(const TimelinePointerInput &input)
{
    m_kbdKey = yToKey(input.position.y());
    m_sv->selectionModel().setNoteSelection(notesOnKey(m_kbdKey));
    auditionKey(m_kbdKey, 100);
}

std::vector<NoteId> PianoRoll::notesOnKey(int key) const
{
    std::vector<NoteId> ids;
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track == m_sv->selectionModel().primaryTrack() && note.key == key &&
            note.noteId.isAssigned())
            ids.push_back(note.noteId);
    }
    return ids;
}

void PianoRoll::beginPendingMenu(const TimelinePointerInput &input, const ViewNote *hit)
{
    m_pressPos = m_curPos = input.position;
    m_rightDrag = RightDrag::PendingMenu;
    m_rightShift = input.modifiers & Qt::ShiftModifier;
    m_rightAnchorTick = m_grid.snapTick(
        m_camera.tickAtContentX(input.position.x() - m_geometry.pianoKeyboardWidth));
    m_rightHit = hit != nullptr;
    if (hit)
        m_rightHitId = hit->noteId;
}

void PianoRoll::beginLeftPress(const TimelinePointerInput &input)
{
    m_pressPos = m_curPos = input.position;
    m_pressTick = m_camera.tickAtContentX(input.position.x() - m_geometry.pianoKeyboardWidth);
    m_pressKey = yToKey(input.position.y());
    m_dTick = 0;
    m_dKey = 0;
    m_dDur = 0;
    m_dVel = 0;
}

bool PianoRoll::contentPressRejectedByScaleFold(const SongDocument *doc, const ViewNote *hit) const
{
    return !hit && doc && m_sv->scaleFold() &&
           (m_pressKey < 0 ||
            !porydaw_scale::isScalePitch(m_sv->scaleId(), m_sv->scaleRoot(), m_pressKey));
}

void PianoRoll::pressContent(const TimelinePointerInput &input)
{
    beginLeftPress(input);
    SongDocument *doc = m_sv->document();
    const ViewNote *hit = doc ? hitNote(input.position) : nullptr;
    if (contentPressRejectedByScaleFold(doc, hit))
        return;
    if (hit) {
        beginNotePress(*hit, input);
        if (m_leftDrag == LeftDrag::PendingVelocity) // deferred path already invalidated
            return;
    } else if (doc) {
        beginPendingDraw();
    } else {
        m_sv->commitEditCursor(m_grid.snapTick(m_pressTick));
    }
    requestQuickUpdate(PianoRollQuickDirty::NoteBordersAndSelection | PianoRollQuickDirty::Overlay);
}

void PianoRoll::beginNotePress(const ViewNote &note, const TimelinePointerInput &input)
{
    const bool rightEdge = nearRightEdge(note, input.position);
    const bool leftEdge = nearLeftEdge(note, input.position);
    const auto &keys = keymap::Registry::instance();
    const auto pressMods = input.modifiers;
    if (keys.matchesModifier(pressMods, QStringLiteral("roll.velocity_drag")) && !rightEdge &&
        !leftEdge) {
        m_leftDrag = LeftDrag::PendingVelocity;
        m_velModMods =
            keymap::Registry::instance().modifierBinding(QStringLiteral("roll.velocity_drag"));
        beginVelocityPress(note);
        return;
    }
    applyNotePressSelection(note, rightEdge || leftEdge, pressMods);
    m_sv->announceNote(note);
    m_lastVelocity = note.velocity;
    armNoteDrag(note, input.position);
    auditionKey(note.key, note.velocity); // runs even when the velocity gesture failed
    m_auditioned = true;
}

void PianoRoll::applyNotePressSelection(const ViewNote &note, bool onEdge,
                                        Qt::KeyboardModifiers modifiers)
{
    const auto &storedSelection = m_sv->selectionModel().noteSelection();
    std::vector<NoteId> ids(storedSelection.begin(), storedSelection.end());
    const NoteId id = note.noteId;
    if ((modifiers & Qt::ControlModifier) && !onEdge) {
        if (std::erase(ids, id) == 0)
            ids.push_back(id);
        m_sv->selectionModel().setNoteSelection(std::move(ids));
    } else if (modifiers & Qt::ControlModifier) {
        if (std::find(ids.begin(), ids.end(), id) == ids.end()) {
            ids.push_back(id);
            m_sv->selectionModel().setNoteSelection(std::move(ids));
        }
    } else if (noteRequiresSelectionUpdate(note)) {
        m_sv->selectionModel().setNoteSelection({id});
    }
}

bool PianoRoll::noteRequiresSelectionUpdate(const ViewNote &note) const
{
    return note.track != m_sv->selectionModel().primaryTrack() || !note.noteId.isAssigned() ||
           !m_sv->selectionModel().isNoteSelected(note.noteId);
}

void PianoRoll::armNoteDrag(const ViewNote &note, QPointF position)
{
    if (nearRightEdge(note, position)) {
        activateLeftDrag(LeftDrag::Resize);
        m_gripTick = note.endTick;
        m_gripOpposite = note.startTick;
    } else if (nearLeftEdge(note, position)) {
        activateLeftDrag(LeftDrag::ResizeLeft);
        m_gripTick = note.startTick;
        m_gripOpposite = note.endTick;
    } else {
        activateLeftDrag(LeftDrag::Move);
    }
}

void PianoRoll::beginVelocityPress(const ViewNote &note)
{
    m_velAnchor = note;
    m_velAudEff = mid2agbEffectiveVelocity(note.velocity);
    m_sv->announceNote(note);
    m_lastVelocity = note.velocity;
    auditionKey(note.key, note.velocity);
    m_auditioned = true;
    requestQuickUpdate(PianoRollQuickDirty::KeyboardHighlights);
}

void PianoRoll::beginPendingDraw()
{
    m_leftDrag = LeftDrag::PendingDraw; // pending: direct assignment, no activation
    m_sv->selectionModel().clearNoteSelection();
    auditionKey(m_pressKey, m_lastVelocity);
    m_auditioned = true;
}

void PianoRoll::resolveRightPress(const TimelinePointerInput &input)
{
    if (!dragLive() && (input.position.toPoint() - m_pressPos.toPoint()).manhattanLength() >=
                           QApplication::startDragDistance()) {
        m_rightDrag = m_rightShift ? RightDrag::TimeSel : RightDrag::Band;
        m_bandAud.clear();
    }
}

void PianoRoll::resolveDrawPress(const TimelinePointerInput &input)
{
    const int key = yToKey(input.position.y());
    if (key != m_pressKey) { // row glissando BEFORE threshold and beginDraw
        m_pressKey = key;
        auditionKey(key, m_lastVelocity);
        m_auditioned = true;
    }
    if (std::abs(input.position.x() - m_pressPos.x()) >= lyt::space(Space::One))
        beginDraw();
}

bool PianoRoll::resolveVelocityPress(const TimelinePointerInput &input)
{
    if (std::abs(input.position.toPoint().y() - m_pressPos.toPoint().y()) <
        QApplication::startDragDistance())
        return false; // consumes the entire event
    applyVelocityDragSelection();
    activateLeftDrag(LeftDrag::Velocity);
    if (!m_sv->beginVelocityGesture(resolveSelection()))
        cancelVelocityInteraction();
    if (m_leftDrag == LeftDrag::Velocity) // re-pin AFTER activation
        setHoverKey(m_velAnchor.key);
    return true;
}

void PianoRoll::applyVelocityDragSelection()
{
    if (!noteRequiresSelectionUpdate(m_velAnchor))
        return;
    m_sv->selectionModel().setNoteSelection({m_velAnchor.noteId});
}

void PianoRoll::beginDraw()
{
    if (m_sv->scaleFold() && (m_pressKey < 0 || !m_sv->isScalePitch(m_pressKey))) {
        return;
    }
    m_drawAnchor = m_grid.snapTickDown(m_pressTick);
    m_drawTick = m_drawAnchor;
    m_drawDur = int64_t(m_grid.gridTicksAt(m_drawAnchor));
    m_drawKey = m_pressKey;
    activateLeftDrag(LeftDrag::Draw);
    m_sv->selectionModel().clearNoteSelection();
    ViewNote pending{};
    pending.startTick = uint32_t(m_drawTick);
    pending.endTick = uint32_t(m_drawTick + uint64_t(m_drawDur));
    pending.key = uint8_t(m_drawKey);
    pending.velocity = m_lastVelocity;
    pending.track = uint8_t(m_sv->selectionModel().primaryTrack());
    m_sv->announceNote(pending);
    // The empty-space press already sounds this row; don't re-attack it.
    if (m_soundingKey != m_drawKey)
        auditionKey(m_drawKey, m_lastVelocity);
    m_auditioned = true;
    requestQuickUpdate(PianoRollQuickDirty::NoteBordersAndSelection |
                       PianoRollQuickDirty::DrawPreviewFill | PianoRollQuickDirty::Overlay |
                       PianoRollQuickDirty::NoteText);
}

void PianoRoll::auditionBandEntrants(const QRectF &band)
{
    std::vector<ViewNote> inBand;
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track != m_sv->selectionModel().primaryTrack() || !noteRect(note).intersects(band))
            continue;
        const auto found =
            std::find_if(m_bandAud.begin(), m_bandAud.end(),
                         [&](const ViewNote &old) { return old.noteId == note.noteId; });
        if (found == m_bandAud.end())
            m_sv->auditionTimed(note.track, note.key, note.velocity, note.startTick, note.endTick);
        inBand.push_back(note);
    }
    for (const ViewNote &old : m_bandAud) {
        const auto found = std::find_if(inBand.begin(), inBand.end(), [&](const ViewNote &note) {
            return note.noteId == old.noteId;
        });
        if (found != inBand.end())
            continue;
        // Previews are one-per-key: keep the key sounding while the band
        // still covers another note of the same pitch.
        const bool keyCovered =
            std::any_of(inBand.begin(), inBand.end(),
                        [&](const ViewNote &note) { return note.key == old.key; });
        if (!keyCovered)
            m_sv->auditionTimedOff(m_sv->selectionModel().primaryTrack(), old.key);
    }
    m_bandAud = std::move(inBand);
}

void PianoRoll::stopBandAuditions()
{
    for (const ViewNote &note : m_bandAud)
        m_sv->auditionTimedOff(m_sv->selectionModel().primaryTrack(), note.key);
    m_bandAud.clear();
}

} // namespace songview
