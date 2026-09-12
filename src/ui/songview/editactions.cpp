#include "ui/songview/editactions.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/keymap.h"
#include "ui/songview/clipmime.h"
#include "ui/songview/detail.h"
#include "ui/songview/quick/eventlistcontroller.h"

#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QGuiApplication>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QTextEdit>
#include <QWidget>

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

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
        EditCommand::DuplicateTime,
        "roll.duplicate_time",
        false,
        nullptr,
        EditDeliveryClass::EditorRouted,
        {
            .rangeOperation = EditRangeOperation::Duplicate,
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
};

constexpr bool commandTableFollowsEnumOrder()
{
    for (std::size_t index = 0; index < kCommandTable.size(); ++index) {
        if (actionIndex(kCommandTable[index].command) != index)
            return false;
    }
    return true;
}

static_assert(kCommandTable.size() == actionIndex(EditCommand::MoveEventDown) + 1);
static_assert(commandTableFollowsEnumOrder());

// Copy alone becomes enabled for focused text; Solo still requires its
// existing song target even though text focus owns its execution.
bool liveRowEnabled(const SongView &target, const CommandRow &row, bool textFocused)
{
    if (textFocused && row.policy.focusedTextOwnership == EditFocusedTextOwnership::Copy)
        return true;
    return target.editCommandAvailable(row.command);
}

} // namespace

const EditCommandPolicy &editCommandPolicy(EditCommand command)
{
    return kCommandTable[actionIndex(command)].policy;
}

std::optional<EditCommand> recognizeEditCommand(int key, Qt::KeyboardModifiers modifiers)
{
    const keymap::Registry &keys = keymap::Registry::instance();
    for (const CommandRow &row : kCommandTable) {
        if (row.delivery == EditDeliveryClass::EditorRouted &&
            keys.matches(key, modifiers, QLatin1String(row.id)))
            return row.command;
    }
    return std::nullopt;
}

EditActions::EditActions(QObject *parent) : QObject(parent)
{
    static_assert(kCommandTable.size() == cActionCount,
                  "the command table and the m_actions array must cover the same commands");
    keymap::Registry &keys = keymap::Registry::instance();
    for (const CommandRow &row : kCommandTable) {
        auto *const commandAction = new QAction(keys.label(QLatin1String(row.id)), this);
        keys.attach(QLatin1String(row.id), commandAction);
        commandAction->setCheckable(row.checkable);
        if (row.windowObjectName)
            commandAction->setObjectName(QLatin1String(row.windowObjectName));

        // The delivery column mirrors the keymap catalogue's Scope, and
        // attach is the sole shortcut-context writer — drift between the
        // two aborts here instead of silently rerouting a key's delivery.
        Q_ASSERT((row.delivery == EditDeliveryClass::Window) ==
                 (commandAction->shortcutContext() == Qt::WindowShortcut));

        m_actions[actionIndex(row.command)] = commandAction;
        connect(commandAction, &QAction::triggered, this,
                [this, command = row.command] { execute(command); });
    }

    connect(qApp, &QApplication::focusChanged, this, [this](QWidget *, QWidget *) { refresh(); });
    if (QClipboard *const clipboard = QGuiApplication::clipboard())
        connect(clipboard, &QClipboard::dataChanged, this, &EditActions::refreshPasteEligibility);

    refresh();
}

QAction *EditActions::action(EditCommand command) const
{
    const std::size_t index = actionIndex(command);
    Q_ASSERT(index < m_actions.size());
    return m_actions[index];
}

bool EditActions::pasteClipPresent() const
{
    return m_pasteClipPresent;
}

void EditActions::installWindowShortcuts(QWidget &window)
{
    // Only Window-class commands join the widget tree; EditorRouted actions
    // are delivered manually and must never be registered, or keys would
    // fire both through the QAction and the manual resolver.
    for (const CommandRow &row : kCommandTable) {
        if (row.delivery == EditDeliveryClass::Window)
            window.addAction(action(row.command));
    }
}

std::optional<EditCommand> EditActions::editorCommandForKey(int key,
                                                            Qt::KeyboardModifiers modifiers) const
{
    return recognizeEditCommand(key, modifiers);
}

void EditActions::rebind(SongView *target)
{
    SongView *const previousTarget = m_target.data();
    // A->A on a live view is a no-op inside the transition: callers observe
    // one completed rebind and never a transient null window. Null->null is
    // not a no-op — it still runs the clip-presence refresh below.
    if (target && target == previousTarget)
        return;

    const bool targetBoundElsewhere = target && target->m_editActions;
    Q_ASSERT(!targetBoundElsewhere);
    if (targetBoundElsewhere)
        return;

    // Unbind before binding every remaining transition (A->B, A->nullptr,
    // nullptr->B, nullptr->nullptr). No signal runs between clearing the old
    // borrow and assigning the new one, so callers observe only this
    // completed transition.
    disconnectTargetObservations();
    if (previousTarget && previousTarget->m_editActions == this)
        previousTarget->m_editActions = nullptr;
    m_target = nullptr;

    if (target) {
        m_target = target;
        target->m_editActions = this;
        observeTarget(*target);
    }
    refreshPasteEligibility();
    if (previousTarget)
        previousTarget->invalidateContextMenus(/*restoreFocus=*/false);
}

SongView *EditActions::target() const
{
    return m_target.data();
}

void EditActions::refresh()
{
    SongView *const boundTarget = m_target.data();
    const bool textFocused = boundTarget && focusedTextTarget();
    for (const CommandRow &row : kCommandTable) {
        const bool enabled = boundTarget && liveRowEnabled(*boundTarget, row, textFocused);
        action(row.command)->setEnabled(enabled);
    }
    refreshCheckedStates(boundTarget);
}

void EditActions::observeTarget(SongView &target)
{
    // Paste caches only clip presence for this target's timeline. The four
    // cache seams — rebind(), QClipboard::dataChanged, documentChanged and
    // this destroyed handler — all call refreshPasteEligibility(); document,
    // gesture and timeline gates remain live in editCommandAvailable().
    // EditorDrawer and AutomationCanvas are construction-fixed inside
    // SongView and never replaced after bind: no replacement re-observation
    // machinery exists or is wanted. The canvas parameter signals carry only
    // view-local presentation quantities (active parameter, parameter
    // selection, labels/appearance) that no availability or checked state
    // reads; document and track rebuilds arrive through documentChanged.
    m_targetConnections.emplace_back(connect(&target, &QObject::destroyed, this, [this] {
        // ~QObject invalidates m_target before destroyed() is emitted. The
        // connection teardown and clip-presence refresh remain necessary when
        // a view dies without ~SongView reaching rebind(nullptr).
        disconnectTargetObservations();
        refreshPasteEligibility();
    }));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::selectionContextChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::muteMaskChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::soloMaskChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::editorViewStateChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::eventListVisibilityChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::editCursorMoved, this, &EditActions::refresh));

    if (SongDocument *const document = target.document())
        m_targetConnections.emplace_back(connect(document, &SongDocument::documentChanged, this,
                                                 &EditActions::refreshPasteEligibility));

    if (EventListController *const events = target.eventListController()) {
        m_targetConnections.emplace_back(
            connect(events, &EventListController::chunkChanged, this, &EditActions::refresh));
        m_targetConnections.emplace_back(
            connect(events, &EventListController::filterMaskChanged, this, &EditActions::refresh));
        m_targetConnections.emplace_back(
            connect(events, &EventListController::currentRowChanged, this, &EditActions::refresh));
        m_targetConnections.emplace_back(connect(events, &EventListController::selectedRowsChanged,
                                                 this, &EditActions::refresh));
        m_targetConnections.emplace_back(
            connect(events, &EventListController::visibleChanged, this, &EditActions::refresh));
        m_targetConnections.emplace_back(
            connect(events, &EventListController::editingChanged, this, &EditActions::refresh));
    }
}

void EditActions::disconnectTargetObservations()
{
    for (const QMetaObject::Connection &connection : m_targetConnections)
        QObject::disconnect(connection);
    m_targetConnections.clear();
}

void EditActions::refreshPasteEligibility()
{
    m_pasteClipPresent = false;
    SongView *const boundTarget = m_target.data();
    if (boundTarget) {
        if (const MidiTimeline *const timeline = boundTarget->timeline()) {
            const auto clip = readClipboard(timeline->ticksPerBeat);
            m_pasteClipPresent = clip && !clip->empty();
        }
    }
    refresh();
}

void EditActions::execute(EditCommand command)
{
    SongView *const boundTarget = m_target.data();
    if (!boundTarget) {
        refresh();
        return;
    }

    const EditCommandPolicy &policy = editCommandPolicy(command);
    if (focusedTextTarget()) {
        switch (policy.focusedTextOwnership) {
        case EditFocusedTextOwnership::Copy:
            copyFocusedText();
            refresh();
            return;
        case EditFocusedTextOwnership::Solo:
            refresh();
            return;
        case EditFocusedTextOwnership::None:
            break;
        }
    }

    if (boundTarget->editCommandAvailable(command))
        boundTarget->executeEditCommand(command);
    refresh();
}

bool EditActions::copyFocusedText() const
{
    QWidget *const focus = QApplication::focusWidget();
    if (auto *const lineEdit = qobject_cast<QLineEdit *>(focus)) {
        lineEdit->copy();
        return true;
    }
    if (auto *const plainTextEdit = qobject_cast<QPlainTextEdit *>(focus)) {
        plainTextEdit->copy();
        return true;
    }
    if (auto *const textEdit = qobject_cast<QTextEdit *>(focus)) {
        textEdit->copy();
        return true;
    }
    return false;
}

bool EditActions::focusedTextTarget() const
{
    QWidget *const focus = QApplication::focusWidget();
    return qobject_cast<QLineEdit *>(focus) || qobject_cast<QPlainTextEdit *>(focus) ||
           qobject_cast<QTextEdit *>(focus);
}

void EditActions::refreshCheckedStates(SongView *target)
{
    bool muteChecked = false;
    bool soloChecked = false;
    bool pencilChecked = false;
    if (target) {
        const uint32_t scope =
            target->selectionModel().resolvedTrackScope(detail::usedTrackMask(target->timeline()));
        if (scope != 0) {
            muteChecked = (target->muteMask() & scope) == scope;
            soloChecked = (target->soloMask() & scope) == scope;
        }

        if (EditorDrawer *const drawer = target->editorDrawer()) {
            if (AutomationPage *const page = drawer->automationPage()) {
                if (AutomationCanvas *const canvas = page->canvas())
                    pencilChecked = canvas->pencilMode();
            }
        }
    }

    action(EditCommand::MuteTracks)->setChecked(muteChecked);
    action(EditCommand::SoloTracks)->setChecked(soloChecked);
    action(EditCommand::PencilMode)->setChecked(pencilChecked);
}

} // namespace songview
