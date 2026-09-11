// ---------------------------------------------------------------- Song command routing
//
// Shared command policy for the timeline editor (plan:
// docs/selection-keyboard-routing-plan.md, "Implementation seam"). Every
// timeline band, the Quick root fallback, and the Quick window key path
// decline a key here after their restricted local handling, and this
// module resolves each command's target from selection and editing origin.
// A command is consumed when shared policy owns it; otherwise it declines
// to local input. Note mutations live in
// pianoroll_commands.cpp, range mutations in rangeedit.cpp — this file
// routes, it does not edit.
//
// The composition root explicitly selects whether its window actions own
// Copy and Solo. The policy stays independent of the window type, so an
// embedded SongView can keep direct ownership without RTTI coupling.

#include "ui/songview.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/keymap.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/eventlistcontroller.h"

namespace {

using namespace songview;
using EditCommand = SongView::EditCommand;

// Resolve each key once. Gesture arbitration and semantic dispatch share the
// result; the catalogue association remains local until EditActions owns it.
struct SharedBinding {
    const char *id;
    EditCommand command;
};

// Every binding this policy owns, in recognition order. A live pointer
// gesture consumes exactly this set without mutating, so a shared command
// can never fall through to a local tool while a gesture holds the surface.
constexpr SharedBinding kSharedBindings[] = {
    {"roll.copy", EditCommand::Copy},
    {"roll.cut", EditCommand::Cut},
    {"roll.duplicate_time", EditCommand::DuplicateTime},
    {"roll.paste", EditCommand::Paste},
    {"roll.select_all", EditCommand::SelectAll},
    {"roll.delete", EditCommand::Delete},
    {"roll.pitch_bend", EditCommand::PitchBend},
    {"roll.transpose_up", EditCommand::TransposeUp},
    {"roll.transpose_down", EditCommand::TransposeDown},
    {"roll.transpose_up_octave", EditCommand::TransposeUpOctave},
    {"roll.transpose_down_octave", EditCommand::TransposeDownOctave},
    {"roll.nudge_left", EditCommand::NudgeLeft},
    {"roll.nudge_right", EditCommand::NudgeRight},
    {"roll.mute_tracks", EditCommand::MuteTracks},
    {"roll.solo_tracks", EditCommand::SoloTracks},
    {"edit.insert_time", EditCommand::InsertTime},
    {"edit.delete_time", EditCommand::DeleteTime},
    {"edit.clear_time_selection", EditCommand::ClearTimeSelection},
    {"automation.pencil_mode", EditCommand::PencilMode},
    {"eventlist.move_up", EditCommand::MoveEventUp},
    {"eventlist.move_down", EditCommand::MoveEventDown},
};

// The one registry pass per key event: first matching binding wins
// (conflict detection keeps bindings unique), nullopt when nothing matches.
std::optional<EditCommand> resolveEditCommand(const TimelineKeyInput &input)
{
    const auto &keys = keymap::Registry::instance();
    const auto matches = [&keys, &input](const char *id) {
        return keys.matches(input.key, input.modifiers, QLatin1String(id));
    };
    for (const SharedBinding &binding : kSharedBindings) {
        if (matches(binding.id))
            return binding.command;
    }
    return std::nullopt;
}

// Semitone step for the transpose commands (0 otherwise). Shared by the
// note- and time-selection targets so a rebinding changes both at once.
int transposeStepFor(EditCommand command)
{
    switch (command) {
    case EditCommand::TransposeUp:
        return 1;
    case EditCommand::TransposeDown:
        return -1;
    case EditCommand::TransposeUpOctave:
        return 12;
    case EditCommand::TransposeDownOctave:
        return -12;
    case EditCommand::Copy:
    case EditCommand::Cut:
    case EditCommand::DuplicateTime:
    case EditCommand::Paste:
    case EditCommand::SelectAll:
    case EditCommand::Delete:
    case EditCommand::PitchBend:
    case EditCommand::NudgeLeft:
    case EditCommand::NudgeRight:
    case EditCommand::MuteTracks:
    case EditCommand::SoloTracks:
    case EditCommand::InsertTime:
    case EditCommand::DeleteTime:
    case EditCommand::ClearTimeSelection:
    case EditCommand::PencilMode:
    case EditCommand::MoveEventUp:
    case EditCommand::MoveEventDown:
        return 0;
    }
    return 0;
}

enum class SelectionTarget {
    None,
    Notes,
    TimeRange,
};

// Command-specific target resolution happens once before dispatch. A range
// owns shared edits that operate on it; selected notes are eligible only from
// the timeline, never from the independent EventList table.
SelectionTarget resolveSelectionTarget(EditCommand command, bool timeSelectionActive,
                                       SongView::EditKeyOrigin origin)
{
    switch (command) {
    case EditCommand::Cut:
    case EditCommand::Delete:
    case EditCommand::TransposeUp:
    case EditCommand::TransposeDown:
    case EditCommand::TransposeUpOctave:
    case EditCommand::TransposeDownOctave:
    case EditCommand::NudgeLeft:
    case EditCommand::NudgeRight:
        if (timeSelectionActive)
            return SelectionTarget::TimeRange;
        return origin == SongView::EditKeyOrigin::Timeline ? SelectionTarget::Notes
                                                           : SelectionTarget::None;

    case EditCommand::SelectAll:
    case EditCommand::PitchBend:
        return origin == SongView::EditKeyOrigin::Timeline ? SelectionTarget::Notes
                                                           : SelectionTarget::None;

    case EditCommand::DuplicateTime:
        return timeSelectionActive ? SelectionTarget::TimeRange : SelectionTarget::None;

    case EditCommand::Copy:
    case EditCommand::Paste:
    case EditCommand::MuteTracks:
    case EditCommand::SoloTracks:
    case EditCommand::InsertTime:
    case EditCommand::DeleteTime:
    case EditCommand::ClearTimeSelection:
    case EditCommand::PencilMode:
    case EditCommand::MoveEventUp:
    case EditCommand::MoveEventDown:
        return SelectionTarget::None;
    }
    return SelectionTarget::None;
}

} // namespace

bool SongView::editCommandAvailable(EditCommand command) const
{
    if (!m_document || timelinePointerGestureActive())
        return false;

    const bool timeSelectionActive = m_selectionModel.timeSelection().active();
    const bool notesSelected = !m_selectionModel.noteSelection().empty();
    switch (command) {
    case EditCommand::Copy:
        return timeSelectionActive ? timeSelectionScope().has_value() : m_roll && notesSelected;

    case EditCommand::Cut:
    case EditCommand::Delete:
        return timeSelectionActive ? timeSelectionScope().has_value() : m_roll && notesSelected;

    case EditCommand::DuplicateTime:
    case EditCommand::DeleteTime:
        return resolveTimeSelectionScope().has_value();

    case EditCommand::Paste: {
        if (!m_timeline)
            return false;
        const auto clip = readClipboard(m_timeline->ticksPerBeat);
        return clip && !clip->empty();
    }

    case EditCommand::SelectAll:
        return m_roll != nullptr;

    case EditCommand::PitchBend:
        return m_roll && m_selectionModel.noteSelection().size() == 1;

    case EditCommand::TransposeUp:
    case EditCommand::TransposeDown:
    case EditCommand::TransposeUpOctave:
    case EditCommand::TransposeDownOctave:
        if (timeSelectionActive)
            return m_selectionModel.timeSelection().scope !=
                       EditorSelectionModel::TimeSelection::Lanes &&
                   timeSelectionScope().has_value();
        return m_roll && notesSelected;

    case EditCommand::NudgeLeft:
    case EditCommand::NudgeRight:
        return timeSelectionActive ? timeSelectionScope().has_value() : m_roll && notesSelected;

    case EditCommand::MuteTracks:
    case EditCommand::SoloTracks:
        return m_timeline != nullptr;

    case EditCommand::InsertTime:
        return m_timeline && (!timeSelectionActive || resolveTimeSelectionScope().has_value());

    case EditCommand::ClearTimeSelection:
        return timeSelectionActive;

    case EditCommand::PencilMode: {
        const AutomationPage *const page =
            m_editorDrawer ? m_editorDrawer->automationPage() : nullptr;
        return m_timeline && drawerSectionVisible(EditorDrawerPage::Automations) && page &&
               page->canvas();
    }

    case EditCommand::MoveEventUp:
        return m_events && m_events->canMoveCurrentRow(-1);

    case EditCommand::MoveEventDown:
        return m_events && m_events->canMoveCurrentRow(1);
    }
    return false;
}

void SongView::executeEditCommand(EditCommand command)
{
    if (!m_document || timelinePointerGestureActive())
        return;

    const bool timeSelectionActive = m_selectionModel.timeSelection().active();
    switch (command) {
    case EditCommand::Copy:
        // copySelection() is the sole time-before-notes precedence resolver.
        copySelection();
        return;

    case EditCommand::Cut:
        if (timeSelectionActive) {
            copyTimeSelection();
            deleteTimeSelection();
        } else if (m_roll) {
            m_roll->cutSelectedNotes();
        }
        return;

    case EditCommand::DuplicateTime:
        duplicateTimeSelection();
        return;

    case EditCommand::Paste:
        // One entry owns clip dispatch, cursor placement, retargeting, undo,
        // and announcements for both note and range clips.
        pasteFromClipboard();
        return;

    case EditCommand::SelectAll:
        if (m_roll)
            m_roll->selectAllNotes();
        return;

    case EditCommand::Delete:
        if (timeSelectionActive) {
            deleteTimeSelection();
        } else if (m_roll) {
            m_roll->deleteSelectedNotes();
        }
        return;

    case EditCommand::PitchBend:
        if (m_roll)
            m_roll->openPitchBendEditor();
        return;

    case EditCommand::TransposeUp:
    case EditCommand::TransposeDown:
    case EditCommand::TransposeUpOctave:
    case EditCommand::TransposeDownOctave:
        if (timeSelectionActive) {
            // A lane scope has no vertical transpose; its existing no-op is
            // still terminal for keyboard routing.
            transposeTimeSelection(transposeStepFor(command));
        } else if (m_roll) {
            m_roll->transposeSelectedNotes(transposeStepFor(command));
        }
        return;

    case EditCommand::NudgeLeft:
    case EditCommand::NudgeRight:
        if (timeSelectionActive) {
            nudgeTimeSelection(command == EditCommand::NudgeRight);
        } else if (m_roll) {
            m_roll->nudgeSelectedNotes(command == EditCommand::NudgeRight);
        }
        return;

    case EditCommand::MuteTracks:
        toggleMuteOnSelectedTracks();
        return;

    case EditCommand::SoloTracks:
        toggleSoloOnSelectedTracks();
        return;

    case EditCommand::InsertTime:
        insertTime();
        return;

    case EditCommand::DeleteTime:
        removeTimeSelectionContents();
        return;

    case EditCommand::ClearTimeSelection:
        m_selectionModel.clearTimeSelection();
        return;

    case EditCommand::PencilMode: {
        if (!editCommandAvailable(command))
            return;
        AutomationPage *const page = m_editorDrawer->automationPage();
        AutomationCanvas *const canvas = page ? page->canvas() : nullptr;
        if (canvas)
            canvas->setPencilMode(!canvas->pencilMode());
        return;
    }

    case EditCommand::MoveEventUp:
        if (m_events && m_events->canMoveCurrentRow(-1))
            m_events->moveCurrentRow(-1);
        return;

    case EditCommand::MoveEventDown:
        if (m_events && m_events->canMoveCurrentRow(1))
            m_events->moveCurrentRow(1);
        return;
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

    const std::optional<EditCommand> command = resolveEditCommand(input);

    // While a pointer gesture is live the surface is owned: recognized
    // shared commands are a consumed no-op, unknown keys are declined.
    if (timelinePointerGestureActive())
        return command.has_value();
    if (!command)
        return false;

    if (*command == EditCommand::Copy) {
        if (m_sharedShortcutOwner == SharedShortcutOwner::Window)
            return false;
        executeEditCommand(*command);
        return true;
    }

    if (*command == EditCommand::Paste) {
        executeEditCommand(*command);
        return true;
    }

    if (*command == EditCommand::MuteTracks) {
        executeEditCommand(*command);
        return true;
    }

    if (*command == EditCommand::SoloTracks) {
        if (m_sharedShortcutOwner == SharedShortcutOwner::Window)
            return false;
        executeEditCommand(*command);
        return true;
    }
    if (*command == EditCommand::InsertTime || *command == EditCommand::DeleteTime ||
        *command == EditCommand::ClearTimeSelection) {
        executeEditCommand(*command);
        return true;
    }

    if (*command == EditCommand::PencilMode) {
        // B remains local to a ready, visible automation page, and repeats
        // remain consumed without retoggling.
        if (!editCommandAvailable(*command))
            return false;
        if (input.autoRepeat)
            return true;
        executeEditCommand(*command);
        return true;
    }

    if (*command == EditCommand::MoveEventUp || *command == EditCommand::MoveEventDown) {
        // The event page alone owns row-reorder delivery. It remains terminal
        // for its local key path even when the current move is unavailable.
        if (origin != EditKeyOrigin::EventList)
            return false;
        executeEditCommand(*command);
        return true;
    }

    const SelectionTarget target =
        resolveSelectionTarget(*command, m_selectionModel.timeSelection().active(), origin);
    switch (target) {
    case SelectionTarget::TimeRange:
        executeEditCommand(*command);
        return true;

    case SelectionTarget::Notes:
        // Pitch-bend opens only on the first key press.
        if (*command == EditCommand::PitchBend && input.autoRepeat)
            return true;
        executeEditCommand(*command);
        return true;

    case SelectionTarget::None:
        // A matched time-duplicate binding remains terminal when no range
        // exists. Other unavailable targets decline for their local owner.
        return *command == EditCommand::DuplicateTime;
    }
    return false;
}

// Canonical Copy command, shared by the key route above and the MainWindow
// Edit action — the window shortcut's physical activation owner. An active
// time selection owns the command; otherwise the selected notes are copied.
// Range/clipboard mechanics live in rangeedit.cpp, note copying in
// pianoroll_commands.cpp.
void SongView::copySelection()
{
    // Window-action entry shares the gesture rule with the key path: a
    // live pointer gesture blocks competing commands — no focus heuristics.
    if (timelinePointerGestureActive())
        return;
    if (m_selectionModel.timeSelection().active())
        copyTimeSelection();
    else
        m_roll->copySelectedNotes();
}

void SongView::setSharedShortcutOwner(SharedShortcutOwner owner)
{
    m_sharedShortcutOwner = owner;
}

bool SongView::handleEditKeyRelease(const songview::TimelineKeyInput &input)
{
    if (input.autoRepeat || !m_roll)
        return false;
    return m_roll->finishKeyboardAudition();
}
