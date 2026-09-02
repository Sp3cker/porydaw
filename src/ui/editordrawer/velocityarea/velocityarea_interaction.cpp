#include "ui/editordrawer/velocityarea/velocityarea.h"

#include <algorithm>
#include <cmath>

#include <QApplication>

#include "core/mid2agbtables.h"
#include "ui/editordrawer/linearramp.h"
#include "ui/editordrawer/velocityarea/detail.h"
#include "ui/songview.h"

using velocityarea::detail::contains;

namespace {

uint8_t exactVelocity(int proposed)
{
    return uint8_t(std::clamp(proposed, 1, 127));
}
// One absolute pointer position -> one velocity for `note`. The unlock
// modifier and the axis context decide between exact MIDI, canonicalized
// continuous, and categorical PSG level resolution.
uint8_t resolvedVelocity(const VelocityAxis &axis, const VelocityMap &noteMap, bool detentUnlock,
                         double y)
{
    if (detentUnlock)
        return exactVelocity(axis.yToVelocity(y));
    if (axis.mode() == VelocityAxis::Mode::Continuous)
        return noteMap.canonicalize(axis.yToVelocity(y));
    return noteMap.representative(axis.yToLevel(y));
}

} // namespace
void VelocityArea::beginFrozenGesture(const std::vector<DocNote> &notes, Interaction interaction,
                                      const QPointF &position, bool detentUnlock)
{
    const std::optional<NoteId> pressedNote = m_pressedNote;
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    const bool controlPress = m_controlPress;
    clearPreview();
    m_pressedNote = pressedNote;
    m_selectionBeforePress = selectionBeforePress;
    m_controlPress = controlPress;
    if (!hasDocument() || notes.empty())
        return;
    m_detentUnlock = detentUnlock;
    appendFrozenNotes(notes);
    if (!m_owner.beginVelocityGesture(notes)) {
        clearPreview();
        return;
    }
    if (m_pressedNote && std::any_of(m_frozen.begin(), m_frozen.end(),
                                     [noteId = *m_pressedNote](const FrozenNote &note) {
                                         return note.noteId == noteId;
                                     }))
        m_announcedNote = *m_pressedNote;
    m_pressPosition = position;
    m_previousPosition = position;
    m_interaction = interaction;
    m_relativeActivated = false;
    pauseFollowScroll(true);
}

void VelocityArea::beginVelocityPaint(const QPointF &position, bool detentUnlock)
{
    const std::optional<NoteId> pressedNote = m_pressedNote;
    const std::vector<NoteId> selectionBeforePress = m_selectionBeforePress;
    const bool controlPress = m_controlPress;
    clearPreview();
    m_pressedNote = pressedNote;
    m_selectionBeforePress = selectionBeforePress;
    m_controlPress = controlPress;
    if (!hasDocument())
        return;
    m_detentUnlock = detentUnlock;
    m_pressPosition = position;
    m_previousPosition = position;
    m_interaction = Interaction::Paint;
    m_relativeActivated = false;
    pauseFollowScroll(true);
}

void VelocityArea::paintSelectedNodesBetween(const QPointF &first, const QPointF &last)
{
    const double deltaX = last.x() - first.x();
    const double radius = double(m_geometry.startNodeHitRadius);
    std::vector<DocNote> notes;
    std::vector<double> ys;
    for (const DocNote &note : selectedNotes()) {
        const double x = xForTick(note.tick);
        double y = last.y();
        if (deltaX == 0.0) {
            if (std::abs(x - last.x()) > radius)
                continue;
        } else {
            if (x < std::min(first.x(), last.x()) - radius ||
                x > std::max(first.x(), last.x()) + radius) {
                continue;
            }
            const double t = std::clamp((x - first.x()) / deltaX, 0.0, 1.0);
            y = first.y() + t * (last.y() - first.y());
        }
        notes.push_back(note);
        ys.push_back(y);
    }
    if (notes.empty())
        return;
    if (m_frozen.empty()) {
        const std::vector<DocNote> selection = selectedNotes();
        if (!m_owner.beginVelocityGesture(selection))
            return;
    }
    appendFrozenNotes(notes);
    std::vector<NoteVelocity> updates;
    updates.reserve(notes.size());
    for (std::size_t index = 0; index < notes.size(); ++index) {
        const auto it = std::find_if(m_frozen.begin(), m_frozen.end(),
                                     [&notes, index](const FrozenNote &frozen) {
                                         return frozen.noteId == notes[index].noteId;
                                     });
        if (it == m_frozen.end())
            continue;
        const uint8_t velocity = resolvedVelocity(m_axis, it->map, m_detentUnlock, ys[index]);
        updates.push_back({it->noteId, int(velocity)});
    }
    if (!updates.empty())
        m_owner.updateVelocityGesture(updates);
    m_announcedNote = notes.front().noteId;
    announcePreview();
}

void VelocityArea::updateRampPreview(const QPointF &position)
{
    if (m_frozen.empty())
        return;
    const double radius = double(m_geometry.startNodeHitRadius);
    const double firstX = std::min(m_pressPosition.x(), position.x()) - radius;
    const double lastX = std::max(m_pressPosition.x(), position.x()) + radius;
    std::vector<NoteVelocity> updates;
    updates.reserve(m_frozen.size());
    for (const FrozenNote &note : m_frozen) {
        const double x = xForTick(note.tick);
        uint8_t velocity = note.velocity;
        if (x >= firstX && x <= lastX) {
            const double y = ui::linearRampValue(x, m_pressPosition.x(), m_pressPosition.y(),
                                                 position.x(), position.y());
            velocity = resolvedVelocity(m_axis, note.map, m_detentUnlock, y);
            m_announcedNote = note.noteId;
        }
        updates.push_back({note.noteId, int(velocity)});
    }
    m_owner.updateVelocityGesture(updates);
    announcePreview();
}

void VelocityArea::updateRelativePreview(const QPointF &position)
{
    if (m_frozen.empty())
        return;
    const double distance =
        std::abs(position.x() - m_pressPosition.x()) + std::abs(position.y() - m_pressPosition.y());
    if (!m_relativeActivated) {
        const bool intrinsicChange =
            !m_detentUnlock && m_axis.mode() == VelocityAxis::Mode::Intrinsic &&
            m_axis.yToLevel(position.y()) != m_axis.yToLevel(m_pressPosition.y());
        if (distance < double(m_geometry.relativeDragActivationDistance) && !intrinsicChange)
            return;
        m_relativeActivated = true;
    }
    std::vector<NoteVelocity> updates;
    updates.reserve(m_frozen.size());
    if (m_detentUnlock || m_axis.mode() == VelocityAxis::Mode::Continuous) {
        const int delta =
            m_axis.yToVelocity(position.y()) - m_axis.yToVelocity(m_pressPosition.y());
        for (const FrozenNote &note : m_frozen) {
            const int proposal = int(note.velocity) + delta;
            const uint8_t velocity =
                m_detentUnlock ? exactVelocity(proposal) : note.map.canonicalize(proposal);
            updates.push_back({note.noteId, int(velocity)});
        }
    } else {
        const int levelDelta = m_axis.yToLevel(position.y()) - m_axis.yToLevel(m_pressPosition.y());
        for (const FrozenNote &note : m_frozen)
            updates.push_back(
                {note.noteId, int(note.map.moveLevels(note.exactOrigin, levelDelta))});
    }
    m_owner.updateVelocityGesture(updates);
    announcePreview();
}

void VelocityArea::updateBandPreview(const QPointF &position)
{
    m_bandRect = QRectF(m_pressPosition, position).normalized();
    m_bandPreview.clear();
    for (const DocNote &note : primaryTrackNotes()) {
        if (m_bandRect.intersects(nodeRect(note)))
            m_bandPreview.push_back(note.noteId);
    }
    requestQuickUpdate();
}

void VelocityArea::finishGesture(bool commit)
{
    if (m_interaction == Interaction::None)
        return;
    const bool hadVelocityGesture = !m_frozen.empty();
    pauseFollowScroll(false);
    m_interaction = Interaction::None;
    m_relativeActivated = false;
    clearPreview();
    if (hadVelocityGesture) {
        if (!commit) {
            m_owner.cancelVelocityGesture();
        } else {
            switch (m_owner.commitVelocityGesture()) {
            case SongView::VelocityCommitResult::Committed:
                m_owner.announce(tr("Painted note velocities."));
                break;
            case SongView::VelocityCommitResult::Unchanged:
                rebuildVisualState();
                break;
            case SongView::VelocityCommitResult::Rejected:
                m_owner.announce(tr("Velocity edit cancelled because notes changed."));
                break;
            case SongView::VelocityCommitResult::NoGesture:
                break;
            }
        }
    } else {
        rebuildVisualState();
    }
}

void VelocityArea::announcePreview()
{
    const SongDocument *document = m_owner.document();
    if (!document || m_frozen.empty())
        return;
    if (!m_announcedNote.isAssigned())
        m_announcedNote = m_frozen.front().noteId;
    for (const FrozenNote &note : m_frozen) {
        if (note.noteId != m_announcedNote)
            continue;
        const uint8_t velocity = m_owner.previewVelocity(note.noteId).value_or(note.velocity);
        const uint64_t clocks =
            document->ticksPerClock() == 0 ? 0 : note.duration / document->ticksPerClock();
        const DrawerPageNoteStatus status{
            note.key, velocity, uint8_t(mid2agbEffectiveVelocity(velocity)), note.duration, clocks};
        m_owner.showDrawerPageNoteStatus(std::optional<DrawerPageNoteStatus>{status});
        return;
    }
}

bool VelocityArea::pointerPress(const songview::TimelinePointerInput &input)
{
    if (!hasDocument())
        return false;
    Q_ASSERT(m_inputHost);
    m_inputHost->requestFocus(Qt::MouseFocusReason);
    const QPointF position = input.position;
    m_pressPosition = position;
    m_previousPosition = position;
    m_selectionBeforePress = m_owner.selectionModel().noteSelection();
    m_pressedNote.reset();
    if (input.button == Qt::MiddleButton) {
        m_interaction = Interaction::Pan;
        pauseFollowScroll(true);
        return true;
    }
    if (input.button == Qt::RightButton) {
        if (const std::optional<DocNote> hit = notesAt(position, true))
            m_pressedNote = hit->noteId;
        m_interaction = Interaction::PendingBand;
        m_controlPress = input.modifiers.testFlag(Qt::ControlModifier);
        if (m_pressedNote && !m_controlPress && !contains(m_selectionBeforePress, *m_pressedNote))
            setSelection({*m_pressedNote});
        pauseFollowScroll(true);
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    const bool inRulerPosition = inRuler(position);
    const bool detentUnlock = detentsUnlocked(
        input.modifiers, !inRulerPosition && input.modifiers.testFlag(Qt::ShiftModifier));
    if (inRulerPosition) {
        const int velocity = detentUnlock ? exactVelocity(m_axis.yToVelocity(position.y()))
                                          : rulerVelocityAt(position);
        if (velocity >= 1) {
            const std::vector<DocNote> notes = selectedNotes();
            beginFrozenGesture(notes, Interaction::Relative, position, detentUnlock);
            std::vector<NoteVelocity> updates;
            updates.reserve(m_frozen.size());
            for (const FrozenNote &note : m_frozen)
                updates.push_back({note.noteId, velocity});
            if (!updates.empty())
                m_owner.updateVelocityGesture(updates);
            finishGesture(true);
        }
        return true;
    }
    if (input.modifiers.testFlag(Qt::ShiftModifier)) {
        beginFrozenGesture(selectedNotes(), Interaction::Ramp, position, detentUnlock);
        updateRampPreview(position);
        return true;
    }
    const std::optional<DocNote> hit = notesAt(position, true);
    if (hit)
        m_pressedNote = hit->noteId;
    m_controlPress = input.modifiers.testFlag(Qt::ControlModifier);
    if (!hit) {
        beginVelocityPaint(position, detentUnlock);
        paintSelectedNodesBetween(position, position);
        return true;
    }
    if (m_controlPress) {
        std::vector<NoteId> selection = m_selectionBeforePress;
        if (!contains(selection, hit->noteId))
            selection.push_back(hit->noteId);
        setSelection(selection);
    } else if (!contains(m_selectionBeforePress, hit->noteId)) {
        setSelection({hit->noteId});
    }
    beginFrozenGesture(selectedNotes(), Interaction::Relative, position, detentUnlock);
    return true;
}

bool VelocityArea::pointerMove(const songview::TimelinePointerInput &input)
{
    const QPointF position = input.position;
    if (m_interaction == Interaction::None)
        updateHoveredNote(position);
    if (m_interaction == Interaction::Relative)
        updateRelativePreview(position);
    else if (m_interaction == Interaction::Paint)
        paintSelectedNodesBetween(m_previousPosition, position);
    else if (m_interaction == Interaction::Ramp)
        updateRampPreview(position);
    else if (m_interaction == Interaction::PendingBand) {
        const double distance = std::abs(position.x() - m_pressPosition.x()) +
                                std::abs(position.y() - m_pressPosition.y());
        if (distance >= double(QApplication::startDragDistance()))
            m_interaction = Interaction::Band;
    }
    if (m_interaction == Interaction::Band)
        updateBandPreview(position);
    else if (m_interaction == Interaction::Pan) {
        const auto requestedScroll =
            m_live.horizontalScroll - (position.x() - m_previousPosition.x());
        m_owner.setEditorHorizontalScroll(requestedScroll);
        m_live.horizontalScroll = m_camera.scrollX();
        requestQuickUpdate();
    }
    m_previousPosition = position;
    return true;
}

void VelocityArea::pointerLeave()
{
    setHoveredNote(std::nullopt);
}

bool VelocityArea::pointerRelease(const songview::TimelinePointerInput &input)
{
    if (input.button == Qt::MiddleButton && m_interaction == Interaction::Pan) {
        pauseFollowScroll(false);
        m_interaction = Interaction::None;
        return true;
    }
    if (input.button == Qt::RightButton &&
        (m_interaction == Interaction::PendingBand || m_interaction == Interaction::Band)) {
        if (m_interaction == Interaction::Band) {
            std::vector<NoteId> selection =
                m_controlPress ? m_selectionBeforePress : std::vector<NoteId>{};
            for (const NoteId noteId : m_bandPreview) {
                if (!contains(selection, noteId))
                    selection.push_back(noteId);
            }
            setSelection(selection);
        } else if (m_controlPress && m_pressedNote) {
            std::vector<NoteId> selection = m_owner.selectionModel().noteSelection();
            const auto it = std::find(selection.begin(), selection.end(), *m_pressedNote);
            if (it == selection.end())
                selection.push_back(*m_pressedNote);
            else
                selection.erase(it);
            setSelection(selection);
        } else if (!m_controlPress && !m_pressedNote) {
            setSelection({});
        }
        finishGesture(false);
        return true;
    }
    if (input.button != Qt::LeftButton)
        return false;
    if (m_interaction == Interaction::Paint) {
        const bool commit = !m_frozen.empty();
        if (!commit)
            setSelection({});
        finishGesture(commit);
    } else if (m_interaction == Interaction::Ramp) {
        finishGesture(m_pressPosition != m_previousPosition);
    } else if (m_interaction == Interaction::Relative) {
        if (!m_relativeActivated) {
            if (m_controlPress) {
                std::vector<NoteId> selection = m_selectionBeforePress;
                if (m_pressedNote) {
                    const auto it = std::find(selection.begin(), selection.end(), *m_pressedNote);
                    if (it == selection.end())
                        selection.push_back(*m_pressedNote);
                    else
                        selection.erase(it);
                }
                setSelection(selection);
            } else if (m_pressedNote) {
                setSelection({*m_pressedNote});
            } else {
                setSelection({});
            }
        }
        finishGesture(m_relativeActivated);
    }
    return true;
}

bool VelocityArea::wheel(const songview::TimelineWheelInput &input)
{
    const bool horizontal = input.modifiers.testFlag(Qt::ShiftModifier) ||
                            input.angleDelta.x() != 0 || input.pixelDelta.x() != 0;
    if (horizontal) {
        const int delta = input.pixelDelta.x() != 0 ? input.pixelDelta.x() : input.angleDelta.y();
        m_owner.setEditorHorizontalScroll(m_live.horizontalScroll - double(delta));
        return true;
    }
    if (inRuler(input.position))
        return false;
    m_owner.zoomTimelineAtWheel(input, input.position.x() - plotOrigin());
    return true;
}

bool VelocityArea::keyPress(const songview::TimelineKeyInput &input)
{
    if (input.key != Qt::Key_Escape)
        return false;
    cancelInteraction();
    return true;
}

void VelocityArea::inputCancelled(songview::TimelineInputCancelReason)
{
    cancelInteraction();
}
