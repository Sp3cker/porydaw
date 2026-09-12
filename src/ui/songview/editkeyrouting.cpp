// ---------------------------------------------------------------- Song command routing
//
// Shared command policy for the timeline editor (plan:
// docs/selection-keyboard-routing-plan.md, "Implementation seam"). Every
// timeline band and the Quick root fallback decline a key here after their
// restricted local handling, and this module resolves each command's target
// from selection and editing origin.
// A command is consumed when shared policy owns it; otherwise it declines
// to local input. Note mutations live in
// pianoroll_commands.cpp, range mutations in rangeedit.cpp — this file
// routes, it does not edit.

#include "core/songdocument.h"
#include "ui/songview.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/editactions.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"
#include "ui/songview/timeruler.h"

#include <QAction>

#include <cstdint>

namespace {

using namespace songview;
using EditCommand = SongView::EditCommand;

enum class SelectionTarget {
    None,
    Notes,
    TimeRange,
};

// Command-specific target resolution happens once before dispatch, derived
// from the row's operations: an active time selection wins when the row has a
// range operation, and selected notes are eligible only from the timeline,
// never from the independent EventList table.
SelectionTarget resolveSelectionTarget(const EditCommandPolicy &policy, bool timeSelectionActive,
                                       SongView::EditKeyOrigin origin)
{
    if (timeSelectionActive && policy.rangeOperation != EditRangeOperation::None)
        return SelectionTarget::TimeRange;
    if (policy.notesOperation != EditNotesOperation::None &&
        origin == SongView::EditKeyOrigin::Timeline)
        return SelectionTarget::Notes;
    return SelectionTarget::None;
}
// Single precedence rule shared by availability and execution: an active
// time selection takes precedence, then notes, then a standalone operation.
// Both entry points resolve through here so the family selection cannot drift.
enum class OperationPath { None, Range, Notes, Standalone };
OperationPath resolveOperationPath(const EditCommandPolicy &policy, bool timeSelectionActive)
{
    if (timeSelectionActive && policy.rangeOperation != EditRangeOperation::None)
        return OperationPath::Range;
    if (policy.notesOperation != EditNotesOperation::None)
        return OperationPath::Notes;
    if (policy.standaloneOperation != EditStandaloneOperation::None)
        return OperationPath::Standalone;
    return OperationPath::None;
}

// Set Velocity joins the notes arms, Loop From Selection the range arms,
// and the loop/signature writes the standalone arms. Availability delegates
// to each operation's predicate and execution asserts it before dispatch.

bool canWriteLoopMarkers(const MidiTimeline *timeline)
{
    return timeline != nullptr;
}

bool canLoopFromSelection(const MidiTimeline *timeline,
                          const EditorSelectionModel::TimeSelection &selection)
{
    return timeline && selection.active() && selection.startTick < selection.endTick;
}

// Loop writes keep the ruler menu's shape: each setLoopTick is its own
// undo command — loop-from-selection and removal stay two-command undo,
// no macro merge.
void runLoopFromSelection(SongDocument &document, const MidiTimeline *timeline,
                          const EditorSelectionModel::TimeSelection &selection)
{
    if (timeline && selection.active() && selection.startTick < selection.endTick) {
        document.setLoopTick(false, int64_t(selection.startTick));
        document.setLoopTick(true, int64_t(selection.endTick));
    }
}

bool canRemoveLoop(const MidiTimeline *timeline)
{
    return timeline && (timeline->loopStartTick != CoreTimeDefaults::kNoTick ||
                        timeline->loopEndTick != CoreTimeDefaults::kNoTick);
}

void runRemoveLoop(SongDocument &document, const MidiTimeline *timeline)
{
    if (!timeline)
        return;
    if (timeline->loopStartTick != CoreTimeDefaults::kNoTick)
        document.setLoopTick(false, -1);
    if (timeline->loopEndTick != CoreTimeDefaults::kNoTick)
        document.setLoopTick(true, -1);
}

// Only an explicit 0x58 event at the edit cursor is removable; the
// implicit opening signature is not.
bool canRemoveTimeSignature(const MidiTimeline *timeline, const TimeAxis &axis, uint64_t cursorTick)
{
    const TimeAxis::ResolvedTimeSignature sig = axis.signatureAt(cursorTick);
    return timeline && !sig.implicit && sig.tick == cursorTick;
}

} // namespace

bool SongView::editCommandAvailable(EditCommand command, bool ignorePointerGesture) const
{
    if (!m_document)
        return false;
    const EditCommandPolicy &policy = editCommandPolicy(command);
    if (!ignorePointerGesture && timelinePointerGestureActive() && !policy.survivesPointerGesture)
        return false;

    // Each operation owns its availability predicate. An active time
    // selection takes precedence, then notes, then a standalone operation.
    // LoopFromSelection resolves beside the range arms (an explicit active
    // selection owns it). The other loop writes are document-global
    // standalone operations and run even while a selection is active.
    if (resolveOperationPath(policy, m_selectionModel.timeSelection().active()) ==
        OperationPath::Range) {
        switch (policy.rangeOperation) {
        case EditRangeOperation::CopySelection:
        case EditRangeOperation::Cut:
        case EditRangeOperation::Delete:
        case EditRangeOperation::Nudge:
            return timeSelectionScope().has_value();
        case EditRangeOperation::Duplicate:
        case EditRangeOperation::RemoveContents:
            return resolveTimeSelectionScope().has_value();
        case EditRangeOperation::Transpose:
            return m_selectionModel.timeSelection().scope !=
                       EditorSelectionModel::TimeSelection::Lanes &&
                   timeSelectionScope().has_value();
        case EditRangeOperation::InsertTime:
            return m_timeline && resolveTimeSelectionScope().has_value();
        case EditRangeOperation::ClearTimeSelection:
            return true;
        case EditRangeOperation::LoopFromSelection:
            return canLoopFromSelection(m_timeline, m_selectionModel.timeSelection());
        case EditRangeOperation::None:
            break;
        }
        return false;
    }

    if (resolveOperationPath(policy, m_selectionModel.timeSelection().active()) ==
        OperationPath::Notes) {
        switch (policy.notesOperation) {
        case EditNotesOperation::CopySelection:
        case EditNotesOperation::Cut:
        case EditNotesOperation::Delete:
        case EditNotesOperation::Transpose:
        case EditNotesOperation::Nudge:
            return m_roll && !m_selectionModel.noteSelection().empty();
        case EditNotesOperation::SelectAll:
            return m_roll != nullptr;
        case EditNotesOperation::PitchBend:
            return m_roll && m_selectionModel.noteSelection().size() == 1;
        case EditNotesOperation::SetVelocity:
            return m_roll && !m_selectionModel.noteSelection().empty();
        case EditNotesOperation::None:
            break;
        }
        return false;
    }

    switch (policy.standaloneOperation) {
    case EditStandaloneOperation::Paste:
        return m_timeline && m_editActions && m_editActions->pasteClipPresent();
    case EditStandaloneOperation::MuteTracks:
        return m_timeline != nullptr;
    case EditStandaloneOperation::SoloTracks:
        return m_timeline != nullptr;
    case EditStandaloneOperation::InsertTime:
        return m_timeline != nullptr;
    case EditStandaloneOperation::PencilToggle: {
        const AutomationPage *const page =
            m_editorDrawer ? m_editorDrawer->automationPage() : nullptr;
        return m_timeline && drawerSectionVisible(EditorDrawerPage::Automations) && page &&
               page->canvas();
    }
    case EditStandaloneOperation::MoveEventRow:
        return m_events && m_events->canMoveCurrentRow(policy.eventRowDelta);
    case EditStandaloneOperation::SetLoopStart:
    case EditStandaloneOperation::SetLoopEnd:
        return canWriteLoopMarkers(m_timeline);
    case EditStandaloneOperation::RemoveLoop:
        return canRemoveLoop(m_timeline);
    case EditStandaloneOperation::EditTimeSignature:
        return m_timeline && m_ruler.get();
    case EditStandaloneOperation::RemoveTimeSignature:
        return canRemoveTimeSignature(m_timeline, m_timeAxis, m_editCursorTick);
    case EditStandaloneOperation::None:
        break;
    }
    return false;
}

void SongView::executeEditCommand(EditCommand command)
{
    if (!m_document)
        return;
    const EditCommandPolicy &policy = editCommandPolicy(command);
    if (timelinePointerGestureActive() && !policy.survivesPointerGesture)
        return;

    // Each operation owns its executor. Eligibility was the caller's
    // decision (canonical actions are enablement-gated, the keyboard policy
    // routes per row); every body remains safe to run.
    const auto &timeSelection = m_selectionModel.timeSelection();
    if (resolveOperationPath(policy, timeSelection.active()) == OperationPath::Range) {
        switch (policy.rangeOperation) {
        case EditRangeOperation::CopySelection:
            // Copy is a single musical operation: the active time selection
            // (or selected notes) resolves inside copySelection().
            copySelection();
            break;
        case EditRangeOperation::Cut:
            copyTimeSelection();
            deleteTimeSelection();
            break;
        case EditRangeOperation::Duplicate:
            duplicateTimeSelection();
            break;
        case EditRangeOperation::Delete:
            deleteTimeSelection();
            break;
        case EditRangeOperation::Transpose:
            // A lane scope has no vertical transpose; its existing no-op is
            // still terminal for keyboard routing.
            transposeTimeSelection(policy.transposeSemitones);
            break;
        case EditRangeOperation::Nudge:
            nudgeTimeSelection(policy.nudgeDelta > 0);
            break;
        case EditRangeOperation::InsertTime:
            insertTime();
            break;
        case EditRangeOperation::RemoveContents:
            removeTimeSelectionContents();
            break;
        case EditRangeOperation::ClearTimeSelection:
            m_selectionModel.clearTimeSelection();
            break;
        case EditRangeOperation::LoopFromSelection:
            Q_ASSERT(canLoopFromSelection(m_timeline, timeSelection));
            runLoopFromSelection(*m_document, m_timeline, timeSelection);
            break;
        }
        return;
    }

    if (resolveOperationPath(policy, timeSelection.active()) == OperationPath::Notes) {
        switch (policy.notesOperation) {
        case EditNotesOperation::CopySelection:
            // Selected notes reach the same authoritative Copy operation.
            copySelection();
            break;
        case EditNotesOperation::Cut:
            if (m_roll)
                m_roll->cutSelectedNotes();
            break;
        case EditNotesOperation::Delete:
            if (m_roll)
                m_roll->deleteSelectedNotes();
            break;
        case EditNotesOperation::Transpose:
            if (m_roll)
                m_roll->transposeSelectedNotes(policy.transposeSemitones);
            break;
        case EditNotesOperation::Nudge:
            if (m_roll)
                m_roll->nudgeSelectedNotes(policy.nudgeDelta > 0);
            break;
        case EditNotesOperation::SelectAll:
            if (m_roll)
                m_roll->selectAllNotes();
            break;
        case EditNotesOperation::PitchBend:
            if (m_roll)
                m_roll->openPitchBendEditor();
            break;
        case EditNotesOperation::SetVelocity:
            if (m_roll)
                m_roll->openSelectedVelocityPrompt();
            break;
        case EditNotesOperation::None:
            break;
        }
        return;
    }

    switch (policy.standaloneOperation) {
    case EditStandaloneOperation::Paste:
        // One entry owns clip dispatch, cursor placement, retargeting, undo,
        // and announcements for both note and range clips.
        pasteFromClipboard();
        break;
    case EditStandaloneOperation::MuteTracks:
        toggleMuteOnSelectedTracks();
        break;
    case EditStandaloneOperation::SoloTracks:
        toggleSoloOnSelectedTracks();
        break;
    case EditStandaloneOperation::InsertTime:
        // The selection half dispatched above; this is the prompt path.
        insertTime();
        break;
    case EditStandaloneOperation::PencilToggle: {
        AutomationPage *const page = m_editorDrawer ? m_editorDrawer->automationPage() : nullptr;
        AutomationCanvas *const canvas = page ? page->canvas() : nullptr;
        if (canvas)
            canvas->setPencilMode(!canvas->pencilMode());
        break;
    }
    case EditStandaloneOperation::MoveEventRow:
        if (m_events && m_events->canMoveCurrentRow(policy.eventRowDelta))
            m_events->moveCurrentRow(policy.eventRowDelta);
        break;
    case EditStandaloneOperation::SetLoopStart:
        Q_ASSERT(canWriteLoopMarkers(m_timeline));
        m_document->setLoopTick(false, int64_t(m_editCursorTick));
        break;
    case EditStandaloneOperation::SetLoopEnd:
        Q_ASSERT(canWriteLoopMarkers(m_timeline));
        m_document->setLoopTick(true, int64_t(m_editCursorTick));
        break;
    case EditStandaloneOperation::RemoveLoop:
        Q_ASSERT(canRemoveLoop(m_timeline));
        runRemoveLoop(*m_document, m_timeline);
        break;
    case EditStandaloneOperation::EditTimeSignature:
        Q_ASSERT(m_timeline && m_ruler.get());
        if (m_ruler)
            m_ruler->editTimeSignatureAtCursor();
        break;
    case EditStandaloneOperation::RemoveTimeSignature:
        Q_ASSERT(canRemoveTimeSignature(m_timeline, m_timeAxis, m_editCursorTick));
        m_document->deleteTimeSig(m_editCursorTick);
        break;
    case EditStandaloneOperation::None:
        break;
    }
}

bool SongView::handleEditKey(const songview::TimelineKeyInput &input, EditKeyOrigin origin)
{
    if (!m_document)
        return false;

    // Escape is the platform gesture-cancel key: with a pointer gesture
    // live it cancels only that gesture and preserves its captured
    // selection; an idle Escape clears the song selection.
    if (input.key == Qt::Key_Escape) {
        if (timelinePointerGestureActive()) {
            // The canonical cancellation path delegates to the Quick host
            // when present and otherwise tears down the native topology.
            cancelActiveInteractions();
        } else {
            m_selectionModel.clearNoteSelection();
            m_selectionModel.clearTimeSelection();
        }
        return true;
    }

    songview::EditActions *const actions = m_editActions.data();
    if (!actions)
        return false;

    const std::optional<EditCommand> command =
        actions->editorCommandForKey(input.key, input.modifiers);
    if (!command)
        return false;

    const EditCommandPolicy &policy = editCommandPolicy(*command);

    // A live pointer gesture owns every matched command except rows that
    // explicitly survive it (PencilToggle preserves the active automation
    // gesture while changing that independent mode). The command is
    // consumed without acting.
    if (timelinePointerGestureActive() && !policy.survivesPointerGesture)
        return true;

    // Origin rows: the event page alone receives row-reorder delivery; other
    // editor surfaces yield the key back to their local owner.
    if (policy.originRule == EditOriginRule::EventListOnly && origin != EditKeyOrigin::EventList)
        return false;

    switch (policy.keyRoute) {
    case EditKeyRoute::AlwaysConsume:
        // The QAction enablement keeps unavailable commands no-ops, and the
        // executor itself is safe to run.
        break;

    case EditKeyRoute::AvailabilityGated:
        // B returns to its local owner while unavailable, and repeats stay
        // consumed without retoggling.
        if (!editCommandAvailable(*command))
            return false;
        if (input.autoRepeat && policy.autoRepeatRule == EditAutoRepeatRule::ConsumeWhenEligible)
            return true;
        break;

    case EditKeyRoute::SelectionTargeted: {
        const SelectionTarget target =
            resolveSelectionTarget(policy, m_selectionModel.timeSelection().active(), origin);
        if (target == SelectionTarget::None)
            return policy.terminalWhenUnmatched;
        // Keys judge live eligibility, not the action's cached enablement:
        // menus read the cache (refreshed by target signals), but a key
        // arriving between a state change and its refresh signal must still
        // route correctly. Unavailable eligibility is distinct from key
        // ownership: a lane-scoped time selection owns Up/Down — the
        // transpose key is a consumed no-op — while other unavailable
        // commands hand the key back to the local input owner. With no
        // musical target at all the key never belonged to this policy.
        if (target == SelectionTarget::TimeRange && !editCommandAvailable(*command))
            return policy.ownershipOnUnavailable == songview::EditKeyOwnershipOnUnavailable::OwnsKey
                       ? true
                       : policy.terminalWhenUnmatched;
        // Pitch-bend opens only on the first key press.
        if (target == SelectionTarget::Notes && input.autoRepeat &&
            policy.autoRepeatRule == EditAutoRepeatRule::ConsumeWhenEligible)
            return true;
        break;
    }
    }

    // The single activation tail: every surviving path activates once.
    QAction *const action = actions->action(*command);
    action->trigger();
    return true;
}

// Edit action — the window shortcut's physical activation owner and the one
// canonical musical Copy implementation. An active time selection owns the
// command, otherwise the selected notes are copied. Range/clipboard
// mechanics live in rangeedit.cpp, note copying in pianoroll_commands.cpp.
void SongView::copySelection()
{
    // Window-action entry shares the gesture rule with the key path: a
    // live pointer gesture blocks competing commands — no focus heuristics.
    if (timelinePointerGestureActive())
        return;
    const auto &timeSelection = m_selectionModel.timeSelection();
    if (timeSelection.active()) {
        copyTimeSelection();
        return;
    }
    if (m_roll && !m_selectionModel.noteSelection().empty())
        m_roll->copySelectedNotes();
}

bool SongView::handleEditKeyRelease(const songview::TimelineKeyInput &input)
{
    if (input.autoRepeat || !m_roll)
        return false;
    return m_roll->finishKeyboardAudition();
}
