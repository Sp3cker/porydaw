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

#include "ui/songview.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview/editactions.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"

#include <QAction>

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

} // namespace

bool SongView::editCommandAvailable(EditCommand command) const
{
    if (!m_document)
        return false;
    const EditCommandPolicy &policy = editCommandPolicy(command);
    if (timelinePointerGestureActive() && !policy.survivesPointerGesture)
        return false;

    // Each operation owns its availability predicate. An active time
    // selection takes precedence, then notes, then a standalone operation.
    if (m_selectionModel.timeSelection().active() &&
        policy.rangeOperation != EditRangeOperation::None) {
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
        case EditRangeOperation::None:
            break;
        }
        return false;
    }

    if (policy.notesOperation != EditNotesOperation::None) {
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
        case EditNotesOperation::None:
            break;
        }
        return false;
    }

    switch (policy.standaloneOperation) {
    case EditStandaloneOperation::Paste:
        return m_timeline && m_editActions && m_editActions->pasteClipPresent();
    case EditStandaloneOperation::MuteTracks:
    case EditStandaloneOperation::SoloTracks:
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
    if (m_selectionModel.timeSelection().active() &&
        policy.rangeOperation != EditRangeOperation::None) {
        switch (policy.rangeOperation) {
        case EditRangeOperation::CopySelection:
            copyTimeSelection();
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
        case EditRangeOperation::None:
            break;
        }
        return;
    }

    if (policy.notesOperation != EditNotesOperation::None) {
        switch (policy.notesOperation) {
        case EditNotesOperation::CopySelection:
            if (m_roll)
                m_roll->copySelectedNotes();
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
    // gesture while changing that independent mode).
    if (timelinePointerGestureActive() && !policy.survivesPointerGesture)
        return true;

    // Origin rows: the event page alone receives row-reorder delivery; other
    // editor surfaces yield the key back to their local owner.
    if (policy.originRule == EditOriginRule::EventListOnly && origin != EditKeyOrigin::EventList)
        return false;

    QAction *const action = actions->action(*command);
    // Keys judge live eligibility, not the action's cached enablement:
    // menus read the cache (refreshed by target signals), but a key
    // arriving between a state change and its refresh signal must still
    // route correctly. The row says whether an unavailable recognized
    // command is terminal (Duplicate Time) or yields back to the local
    // input owner.
    if (!editCommandAvailable(*command))
        return policy.terminalWhenUnmatched;

    switch (policy.keyRoute) {
    case EditKeyRoute::AlwaysConsume:
        action->trigger();
        return true;

    case EditKeyRoute::AvailabilityGated:
        // B remains local to a ready, visible automation page, and repeats
        // remain consumed without retoggling.
        if (input.autoRepeat && policy.autoRepeatRule == EditAutoRepeatRule::ConsumeWhenEligible)
            return true;
        action->trigger();
        return true;

    case EditKeyRoute::SelectionTargeted: {
        const SelectionTarget target =
            resolveSelectionTarget(policy, m_selectionModel.timeSelection().active(), origin);
        if (target == SelectionTarget::None)
            return policy.terminalWhenUnmatched;
        // Pitch-bend opens only on the first key press.
        if (target == SelectionTarget::Notes && input.autoRepeat &&
            policy.autoRepeatRule == EditAutoRepeatRule::ConsumeWhenEligible)
            return true;
        action->trigger();
        return true;
    }
    }
    return false;
}

namespace songview {

// Where the canonical Copy command acts after text-focus ownership has been
// resolved by EditActions::execute: an active time selection owns the
// command, otherwise selected notes are copied.
EditCopyTarget resolveCopyTarget(const SongView &view)
{
    if (view.selectionModel().timeSelection().active())
        return EditCopyTarget::TimeRange;
    if (!view.selectionModel().noteSelection().empty())
        return EditCopyTarget::Notes;
    return EditCopyTarget::None;
}

} // namespace songview

// Edit action — the window shortcut's physical activation owner. Range
// precedence resolves through resolveCopyTarget: an active time selection
// owns the command, otherwise the selected notes are copied.
// Range/clipboard mechanics live in rangeedit.cpp, note copying in
// pianoroll_commands.cpp.
void SongView::copySelection()
{
    // Window-action entry shares the gesture rule with the key path: a
    // live pointer gesture blocks competing commands — no focus heuristics.
    if (timelinePointerGestureActive())
        return;
    switch (resolveCopyTarget(*this)) {
    case EditCopyTarget::TimeRange:
        copyTimeSelection();
        return;
    case EditCopyTarget::Notes:
        m_roll->copySelectedNotes();
        return;
    case EditCopyTarget::None:
        return;
    }
}

bool SongView::handleEditKeyRelease(const songview::TimelineKeyInput &input)
{
    if (input.autoRepeat || !m_roll)
        return false;
    return m_roll->finishKeyboardAudition();
}
