#pragma once

#include "ui/songview.h"

#include <QMetaObject>
#include <QObject>
#include <QPointer>

#include <array>
#include <cstddef>
#include <optional>
#include <vector>

class QAction;
class QWidget;

namespace songview {

// How a command's key physically reaches its executor. Window-class commands
// are delivered by Qt's shortcut system through window-scoped QActions;
// EditorRouted-class QActions are never registered with any widget, so the
// editor claims their keys itself and delivers manually. Claiming Window-class
// keys from an editor route would steal them from the real QAction delivery
// and double-fire the manual path.
enum class EditDeliveryClass {
    EditorRouted = 1,
    Window = 2,
};

// The single key recognizer over the canonical command table (hosted in
// editactions.cpp) only claims EditorRouted rows. Window-class keys always
// reach their QActions through Qt's shortcut delivery.
std::optional<SongView::EditCommand> recognizeEditCommand(int key, Qt::KeyboardModifiers modifiers);

// --- Per-command policy rows of the canonical command table ---------------
//
// Everything SongView's availability report, semantic dispatch and key
// routing consume about a command is row data here, so each availability
// predicate, execution body and keyboard rule is stated exactly once.

// A time-selection operation carries both its availability rule and executor.
enum class EditRangeOperation {
    None,
    CopySelection,
    Cut,
    Duplicate,
    Delete,
    Transpose,
    Nudge,
    InsertTime,
    RemoveContents,
    ClearTimeSelection,
};

// A note-selection operation carries both its availability rule and executor.
enum class EditNotesOperation {
    None,
    CopySelection,
    Cut,
    Delete,
    Transpose,
    Nudge,
    SelectAll,
    PitchBend,
};

// An operation that runs when neither selection family owns the command.
enum class EditStandaloneOperation {
    None,
    Paste,
    MuteTracks,
    SoloTracks,
    InsertTime,
    PencilToggle,
    MoveEventRow,
};

// Text focus is a distinct physical owner for the window actions that defer
// to it before song-target dispatch.
enum class EditFocusedTextOwnership {
    None,
    Copy,
    Solo,
};

// How the keyboard policy routes a recognized key for one command (consumed
// by SongView::handleEditKey).
enum class EditKeyRoute {
    SelectionTargeted, // the live selection target decides; None declines
                       // unless the row stays terminal when unmatched
    AlwaysConsume,     // execute unconditionally; the executor no-ops when
                       // the command is currently ineligible
    AvailabilityGated, // editCommandAvailable gates; unavailable declines
};

enum class EditOriginRule {
    AnyOrigin,
    EventListOnly, // the event page alone owns row-reorder delivery
};

enum class EditAutoRepeatRule {
    Reexecute,           // repeats re-run the command (transpose audition)
    ConsumeWhenEligible, // repeats stay consumed without re-triggering
};

// One policy row of the canonical command table (editactions.cpp).
struct EditCommandPolicy {
    EditRangeOperation rangeOperation = EditRangeOperation::None;
    EditNotesOperation notesOperation = EditNotesOperation::None;
    EditStandaloneOperation standaloneOperation = EditStandaloneOperation::None;
    EditKeyRoute keyRoute = EditKeyRoute::SelectionTargeted;
    EditOriginRule originRule = EditOriginRule::AnyOrigin;
    EditAutoRepeatRule autoRepeatRule = EditAutoRepeatRule::Reexecute;
    int transposeSemitones = 0;
    int nudgeDelta = 0;
    int eventRowDelta = 0;
    bool survivesPointerGesture = false;
    bool terminalWhenUnmatched = false;
    EditFocusedTextOwnership focusedTextOwnership = EditFocusedTextOwnership::None;
};

// The policy row of one command, read out of the canonical table.
const EditCommandPolicy &editCommandPolicy(SongView::EditCommand command);

// Where the canonical Copy command acts after text-focus ownership is
// resolved: time selections win, then selected notes.
enum class EditCopyTarget { None, Notes, TimeRange };
EditCopyTarget resolveCopyTarget(const SongView &view);

class EditActions final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(EditActions)

  public:
    explicit EditActions(QObject *parent = nullptr);

    QAction *action(SongView::EditCommand command) const;
    void installWindowShortcuts(QWidget &window);
    std::optional<SongView::EditCommand> editorCommandForKey(int key,
                                                             Qt::KeyboardModifiers modifiers) const;
    bool pasteClipPresent() const;
    // The single transition seam: pass the new view or nullptr. Unbind-then-
    // bind is sequenced inside this call for every transition (A->B, A->null,
    // null->B; A->A is a no-op), so callers issue exactly one call and never
    // observe a transient null window. A foreign action binding is rejected
    // before teardown in both debug and release builds.
    void rebind(SongView *viewOrNull);
    SongView *target() const;
    void refresh();

  private:
    // One slot per EditCommand value; editactions.cpp pins the canonical
    // table to this count and to per-position enum identity.
    static constexpr std::size_t cActionCount =
        static_cast<std::size_t>(SongView::EditCommand::MoveEventDown) + 1;

    void observeTarget(SongView &target);
    void disconnectTargetObservations();
    void refreshPasteEligibility();
    void execute(SongView::EditCommand command);
    bool copyFocusedText() const;
    bool focusedTextTarget() const;
    void refreshCheckedStates(SongView *target);

    std::array<QAction *, cActionCount> m_actions{};
    QPointer<SongView> m_target;
    std::vector<QMetaObject::Connection> m_targetConnections;
    bool m_pasteClipPresent = false;
};

} // namespace songview
