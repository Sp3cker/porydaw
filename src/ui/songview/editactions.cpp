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

constexpr std::size_t actionIndex(EditCommand command)
{
    return static_cast<std::size_t>(command);
}

// Copy alone becomes enabled for focused text; Solo still requires its
// existing song target even though text focus owns its execution.
// Presentation refresh ignores the transient pointer gesture: every live
// dispatch path (keys, execute, triggered) re-applies the gate itself, so
// the cached state describes the committed selection and never the sweep
// that produced it.
bool liveRowEnabled(const SongView &target, EditCommand command, bool textFocused)
{
    if (textFocused &&
        editCommandPolicy(command).focusedTextOwnership == EditFocusedTextOwnership::Copy)
        return true;
    return target.editCommandAvailable(command, /*ignorePointerGesture=*/true);
}

} // namespace

EditActions::EditActions(QObject *parent) : QObject(parent)
{
    Q_ASSERT(editCommandCount() == cActionCount);
    keymap::Registry &keys = keymap::Registry::instance();
    for (std::size_t index = 0; index < editCommandCount(); ++index) {
        const EditCommand command = static_cast<EditCommand>(index);
        auto *const commandAction =
            new QAction(keys.label(QLatin1String(editCommandId(command))), this);
        keys.attach(QLatin1String(editCommandId(command)), commandAction);
        commandAction->setCheckable(editCommandCheckable(command));
        if (const char *const windowObjectName = editCommandWindowObjectName(command))
            commandAction->setObjectName(QLatin1String(windowObjectName));

        // The delivery column mirrors the keymap catalogue's Scope, and
        // attach is the sole shortcut-context writer — drift between the
        // two aborts here instead of silently rerouting a key's delivery.
        Q_ASSERT((editCommandDelivery(command) == EditDeliveryClass::Window) ==
                 (commandAction->shortcutContext() == Qt::WindowShortcut));

        m_actions[actionIndex(command)] = commandAction;
        connect(commandAction, &QAction::triggered, this, [this, command] { execute(command); });
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
    for (std::size_t index = 0; index < editCommandCount(); ++index) {
        const EditCommand command = static_cast<EditCommand>(index);
        if (editCommandDelivery(command) == EditDeliveryClass::Window)
            window.addAction(action(command));
    }
}

std::optional<EditCommand> EditActions::editorCommandForKey(int key,
                                                            Qt::KeyboardModifiers modifiers) const
{
    // Every catalogue row with a binding recognizes here, regardless of
    // delivery class: the column governs Qt shortcut registration
    // (installWindowShortcuts), not key ownership. Fixtures never install
    // window shortcuts - their input targets the view directly - and the
    // ShortcutOverride filter consults this same table, so excluding Window
    // rows silently drops Copy/Insert Time/Delete Time/Solo from every
    // manual key route. All dispatch re-gates live (gesture, availability),
    // and override-first consumption keeps single delivery in production.
    const keymap::Registry &keys = keymap::Registry::instance();
    for (std::size_t index = 0; index < editCommandCount(); ++index) {
        const EditCommand command = static_cast<EditCommand>(index);
        if (keys.matches(key, modifiers, QLatin1String(editCommandId(command))))
            return command;
    }
    return std::nullopt;
}

void EditActions::activateEditorCommand(EditCommand command)
{
    SongView *const boundTarget = m_target.data();
    if (!boundTarget)
        return;

    QAction *const commandAction = action(command);
    commandAction->setEnabled(liveRowEnabled(*boundTarget, command, focusedTextTarget()));
    if (commandAction->isEnabled())
        commandAction->trigger();
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
    for (std::size_t index = 0; index < editCommandCount(); ++index) {
        const EditCommand command = static_cast<EditCommand>(index);
        const bool enabled = boundTarget && liveRowEnabled(*boundTarget, command, textFocused);
        action(command)->setEnabled(enabled);
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

    m_targetConnections.emplace_back(connect(&target.document(), &SongDocument::documentChanged,
                                             this, &EditActions::refreshPasteEligibility));

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
