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

#include "ui/keymap.h"
#include "ui/songview/pianoroll.h"

namespace {

using namespace songview;

// Resolve each key once. The gesture guard and semantic dispatch share that
// result; a new command needs a binding-table entry and a dispatch case.
enum class EditCommand {
    None,
    Copy,
    Cut,
    DuplicateTime,
    Paste,
    SelectAll,
    Delete,
    PitchBend,
    TransposeUp,
    TransposeDown,
    TransposeUpOctave,
    TransposeDownOctave,
    NudgeLeft,
    NudgeRight,
    MuteTracks,
    SoloTracks,
};

struct SharedBinding {
    const char *id;
    EditCommand command;
};

// Every binding this policy owns, in recognition order. A live pointer
// gesture consumes exactly this set without mutating, so a shared command
// can never fall through to a local tool while a gesture holds the surface.
// New shared commands register here.
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
};

// The one registry pass per key event: first matching binding wins
// (conflict detection keeps bindings unique), None when nothing matches.
EditCommand resolveEditCommand(const TimelineKeyInput &input)
{
    const auto &keys = keymap::Registry::instance();
    const auto matches = [&keys, &input](const char *id) {
        return keys.matches(input.key, input.modifiers, QLatin1String(id));
    };
    for (const SharedBinding &binding : kSharedBindings) {
        if (matches(binding.id))
            return binding.command;
    }
    return EditCommand::None;
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
    default:
        return 0;
    }
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

    default:
        return SelectionTarget::None;
    }
}

} // namespace

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

    const EditCommand command = resolveEditCommand(input);

    // While a pointer gesture is live the surface is owned: recognized
    // shared commands are a consumed no-op, unknown keys are declined.
    if (timelinePointerGestureActive())
        return command != EditCommand::None;

    const SelectionTarget target =
        resolveSelectionTarget(command, m_selectionModel.timeSelection().active(), origin);

    switch (command) {
    case EditCommand::None:
        return false;

    case EditCommand::Copy:
        if (m_sharedShortcutOwner == SharedShortcutOwner::Window)
            return false;
        copySelection();
        return true;

    case EditCommand::Paste:
        // Paste is not selected-object editing: the single SongView entry
        // owns clip dispatch, edit-cursor placement, retargeting, undo, and
        // the announce, for both note and range clips.
        pasteFromClipboard();
        return true;

    case EditCommand::MuteTracks:
        toggleMuteOnSelectedTracks();
        return true;

    case EditCommand::SoloTracks:
        if (m_sharedShortcutOwner == SharedShortcutOwner::Window)
            return false;
        toggleSoloOnSelectedTracks();
        return true;

    default:
        break;
    }

    switch (target) {
    case SelectionTarget::TimeRange:
        switch (command) {
        case EditCommand::Cut:
            copyTimeSelection();
            deleteTimeSelection();
            return true;

        case EditCommand::Delete:
            deleteTimeSelection();
            return true;

        case EditCommand::TransposeUp:
        case EditCommand::TransposeDown:
        case EditCommand::TransposeUpOctave:
        case EditCommand::TransposeDownOctave:
            // A lane scope has no vertical transpose; the range operation
            // consumes that unavailable direction as a no-op.
            transposeTimeSelection(transposeStepFor(command));
            return true;

        case EditCommand::NudgeLeft:
        case EditCommand::NudgeRight:
            nudgeTimeSelection(command == EditCommand::NudgeRight);
            return true;

        case EditCommand::DuplicateTime:
            duplicateTimeSelection();
            return true;

        default:
            return false;
        }

    case SelectionTarget::Notes:
        switch (command) {
        case EditCommand::SelectAll:
            m_roll->selectAllNotes();
            return true;

        case EditCommand::PitchBend:
            if (!input.autoRepeat)
                m_roll->openPitchBendEditor();
            return true;

        case EditCommand::Cut:
            m_roll->cutSelectedNotes();
            return true;

        case EditCommand::Delete:
            m_roll->deleteSelectedNotes();
            return true;

        case EditCommand::TransposeUp:
        case EditCommand::TransposeDown:
        case EditCommand::TransposeUpOctave:
        case EditCommand::TransposeDownOctave:
            m_roll->transposeSelectedNotes(transposeStepFor(command));
            return true;

        case EditCommand::NudgeLeft:
        case EditCommand::NudgeRight:
            m_roll->nudgeSelectedNotes(command == EditCommand::NudgeRight);
            return true;

        default:
            return false;
        }

    case SelectionTarget::None:
        // A matched time-duplicate binding remains terminal when no range
        // exists. Other unavailable targets decline for their local owner.
        return command == EditCommand::DuplicateTime;
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
