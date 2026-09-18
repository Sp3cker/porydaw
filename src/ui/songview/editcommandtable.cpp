#include "ui/songview/editcommandtable.h"

#include "ui/songview/editactions.h"

#include <array>
#include <cstddef>

namespace songview {
namespace {

using EditCommand = SongView::EditCommand;

// The canonical command table: one row per EditCommand value, in enum
// order. Construction, installWindowShortcuts, refresh and the key
// recognizer below all iterate this one table. `delivery` mirrors the
// keymap catalogue's Scope for the id (keymap stays SongView-agnostic, so
// the constructor asserts the agreement after attach); `windowObjectName`
// is the window back-channel name, nullptr when the command has none.
// `policy` owns availability, execution, keyboard routing, command arguments
// and text-focus precedence; omitted fields retain their in-class defaults.
struct CommandRow {
    EditCommand command;
    const char *id;
    bool checkable;
    const char *windowObjectName;
    EditDeliveryClass delivery;
    EditCommandPolicy policy;
};

constexpr std::size_t actionIndex(EditCommand command)
{
    return static_cast<std::size_t>(command);
}
constexpr CommandRow transposeRow(EditCommand command, const char *id, int semitones)
{
    return {
        command,
        id,
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::Transpose,
            .notesOperation = EditNotesOperation::Transpose,
            .keyRoute = EditKeyRoute::SelectionTargeted,
            // Lane-scoped Up/Down is an ineligible mutation, not a foreign
            // key: the selection owns it as a consumed no-op.
            .ownershipOnUnavailable = EditKeyOwnershipOnUnavailable::OwnsKey,
            .transposeSemitones = semitones,
        },
    };
}

constexpr CommandRow nudgeRow(EditCommand command, const char *id, int delta)
{
    return {
        command,
        id,
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::Nudge,
            .notesOperation = EditNotesOperation::Nudge,
            .keyRoute = EditKeyRoute::SelectionTargeted,
            .nudgeDelta = delta,
        },
    };
}

// One production row shape for the seven unbound cursor/marker/signature
// commands beside transpose/nudge/event: all are EditorRouted, availability
// is their only gate, and keys consume unconditionally once eligible. Each
// row names its vocabulary operation explicitly — without one, availability
// falls through every switch and the command is dead.
constexpr CommandRow unboundRow(EditCommand command, const char *id,
                                EditRangeOperation range = EditRangeOperation::None,
                                EditNotesOperation notes = EditNotesOperation::None,
                                EditStandaloneOperation standalone = EditStandaloneOperation::None)
{
    return {
        command,
        id,
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = range,
            .notesOperation = notes,
            .standaloneOperation = standalone,
            .keyRoute = EditKeyRoute::AlwaysConsume,
        },
    };
}

constexpr CommandRow eventRow(EditCommand command, const char *id, int delta)
{
    return {
        command,
        id,
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::MoveEventRow,
            .keyRoute = EditKeyRoute::AlwaysConsume,
            .originRule = EditOriginRule::EventListOnly,
            .eventRowDelta = delta,
        },
    };
}

constexpr std::array kCommandTable = {
    CommandRow{
        EditCommand::Copy,
        "roll.copy",
        false,
        "copyWindowAction",
        EditDeliveryClass::Window,
        {
            .rangeOperation = EditRangeOperation::CopySelection,
            .notesOperation = EditNotesOperation::CopySelection,
            .keyRoute = EditKeyRoute::AlwaysConsume,
            .focusedTextOwnership = EditFocusedTextOwnership::Copy,
        },
    },
    CommandRow{
        EditCommand::Cut,
        "roll.cut",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::Cut,
            .notesOperation = EditNotesOperation::Cut,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::Duplicate,
        "roll.duplicate_time",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::Duplicate,
            .notesOperation = EditNotesOperation::Duplicate,
            .keyRoute = EditKeyRoute::SelectionTargeted,
            .terminalWhenUnmatched = true,
        },
    },
    CommandRow{
        EditCommand::Paste,
        "roll.paste",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::Paste,
            .keyRoute = EditKeyRoute::AlwaysConsume,
        },
    },
    CommandRow{
        EditCommand::SelectAll,
        "roll.select_all",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .notesOperation = EditNotesOperation::SelectAll,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::Delete,
        "roll.delete",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::Delete,
            .notesOperation = EditNotesOperation::Delete,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::PitchBend,
        "roll.pitch_bend",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .notesOperation = EditNotesOperation::PitchBend,
            .keyRoute = EditKeyRoute::SelectionTargeted,
            .autoRepeatRule = EditAutoRepeatRule::ConsumeWhenEligible,
        },
    },
    transposeRow(EditCommand::TransposeUp, "roll.transpose_up", 1),
    transposeRow(EditCommand::TransposeDown, "roll.transpose_down", -1),
    transposeRow(EditCommand::TransposeUpOctave, "roll.transpose_up_octave", 12),
    transposeRow(EditCommand::TransposeDownOctave, "roll.transpose_down_octave", -12),
    nudgeRow(EditCommand::NudgeLeft, "roll.nudge_left", -1),
    nudgeRow(EditCommand::NudgeRight, "roll.nudge_right", 1),
    CommandRow{
        EditCommand::MuteTracks,
        "roll.mute_tracks",
        true,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::MuteTracks,
            .keyRoute = EditKeyRoute::AlwaysConsume,
        },
    },
    CommandRow{
        EditCommand::SoloTracks,
        "roll.solo_tracks",
        true,
        "soloWindowAction",
        EditDeliveryClass::Window,
        {
            .standaloneOperation = EditStandaloneOperation::SoloTracks,
            .keyRoute = EditKeyRoute::AlwaysConsume,
            .focusedTextOwnership = EditFocusedTextOwnership::Solo,
        },
    },
    CommandRow{
        EditCommand::InsertTime,
        "edit.insert_time",
        false,
        "insertTimeWindowAction",
        EditDeliveryClass::Window,
        {
            .rangeOperation = EditRangeOperation::InsertTime,
            .standaloneOperation = EditStandaloneOperation::InsertTime,
            .keyRoute = EditKeyRoute::AlwaysConsume,
        },
    },
    CommandRow{
        EditCommand::DeleteTime,
        "edit.delete_time",
        false,
        "deleteTimeWindowAction",
        EditDeliveryClass::Window,
        {
            .rangeOperation = EditRangeOperation::RemoveContents,
            .keyRoute = EditKeyRoute::AlwaysConsume,
        },
    },
    CommandRow{
        EditCommand::ClearTimeSelection,
        "edit.clear_time_selection",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::ClearTimeSelection,
            .keyRoute = EditKeyRoute::AlwaysConsume,
        },
    },
    // Commands whose operation arm resolves from cursor/marker/signature
    // state: availability is the only gate, so keys consume unconditionally
    // once eligible.
    unboundRow(EditCommand::SetVelocity, "edit.set_velocity", EditRangeOperation::None,
               EditNotesOperation::SetVelocity),
    unboundRow(EditCommand::SetLoopStart, "edit.set_loop_start", EditRangeOperation::None,
               EditNotesOperation::None, EditStandaloneOperation::SetLoopStart),
    unboundRow(EditCommand::SetLoopEnd, "edit.set_loop_end", EditRangeOperation::None,
               EditNotesOperation::None, EditStandaloneOperation::SetLoopEnd),
    unboundRow(EditCommand::LoopFromSelection, "edit.loop_from_selection",
               EditRangeOperation::LoopFromSelection),
    unboundRow(EditCommand::RemoveLoop, "edit.remove_loop", EditRangeOperation::None,
               EditNotesOperation::None, EditStandaloneOperation::RemoveLoop),
    unboundRow(EditCommand::EditTimeSignature, "edit.edit_time_signature", EditRangeOperation::None,
               EditNotesOperation::None, EditStandaloneOperation::EditTimeSignature),
    unboundRow(EditCommand::RemoveTimeSignature, "edit.remove_time_signature",
               EditRangeOperation::None, EditNotesOperation::None,
               EditStandaloneOperation::RemoveTimeSignature),
    CommandRow{
        EditCommand::PencilMode,
        "automation.pencil_mode",
        true,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::PencilToggle,
            .keyRoute = EditKeyRoute::AvailabilityGated,
            .autoRepeatRule = EditAutoRepeatRule::ConsumeWhenEligible,
            .survivesPointerGesture = true,
        },
    },
    eventRow(EditCommand::MoveEventUp, "eventlist.move_up", -1),
    eventRow(EditCommand::MoveEventDown, "eventlist.move_down", 1),
    CommandRow{
        EditCommand::Split,
        "roll.split",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .notesOperation = EditNotesOperation::Split,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::Join,
        "roll.join",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .notesOperation = EditNotesOperation::Join,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::LengthenNote,
        "roll.lengthen_note",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .notesOperation = EditNotesOperation::Lengthen,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::ShortenNote,
        "roll.shorten_note",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .notesOperation = EditNotesOperation::Shorten,
            .keyRoute = EditKeyRoute::SelectionTargeted,
        },
    },
    CommandRow{
        EditCommand::GridNarrow,
        "roll.grid_narrow",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::GridNarrow,
            .keyRoute = EditKeyRoute::AlwaysConsume,
            .originRule = EditOriginRule::TimelineOnly,
        },
    },
    CommandRow{
        EditCommand::GridWiden,
        "roll.grid_widen",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::GridWiden,
            .keyRoute = EditKeyRoute::AlwaysConsume,
            .originRule = EditOriginRule::TimelineOnly,
        },
    },
    CommandRow{
        EditCommand::GridTriplet,
        "roll.grid_triplet",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .standaloneOperation = EditStandaloneOperation::GridTriplet,
            .keyRoute = EditKeyRoute::AvailabilityGated,
            .originRule = EditOriginRule::TimelineOnly,
            // Toggling feel re-lattices the drag's snap positions, so it
            // stays gesture-gated; repeats consume without retoggling.
            .autoRepeatRule = EditAutoRepeatRule::ConsumeWhenEligible,
        },
    },
};

constexpr bool commandTableFollowsEnumOrder()
{
    for (std::size_t index = 0; index < kCommandTable.size(); ++index) {
        if (actionIndex(kCommandTable[index].command) != index)
            return false;
    }
    return true;
}

static_assert(kCommandTable.size() == actionIndex(EditCommand::GridTriplet) + 1);
static_assert(commandTableFollowsEnumOrder());

} // namespace
std::size_t editCommandCount()
{
    return kCommandTable.size();
}

const char *editCommandId(EditCommand command)
{
    return kCommandTable[actionIndex(command)].id;
}

bool editCommandCheckable(EditCommand command)
{
    return kCommandTable[actionIndex(command)].checkable;
}

const char *editCommandWindowObjectName(EditCommand command)
{
    return kCommandTable[actionIndex(command)].windowObjectName;
}

EditDeliveryClass editCommandDelivery(EditCommand command)
{
    return kCommandTable[actionIndex(command)].delivery;
}

const EditCommandPolicy &editCommandPolicy(EditCommand command)
{
    return kCommandTable[actionIndex(command)].policy;
}

} // namespace songview
