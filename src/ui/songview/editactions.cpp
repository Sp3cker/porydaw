#include "ui/songview/editactions.h"

#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/keymap.h"
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

struct CommandCatalogueEntry {
    EditCommand command;
    const char *id;
};

constexpr std::array kCommandCatalogue = {
    CommandCatalogueEntry{EditCommand::Copy, "roll.copy"},
    CommandCatalogueEntry{EditCommand::Cut, "roll.cut"},
    CommandCatalogueEntry{EditCommand::DuplicateTime, "roll.duplicate_time"},
    CommandCatalogueEntry{EditCommand::Paste, "roll.paste"},
    CommandCatalogueEntry{EditCommand::SelectAll, "roll.select_all"},
    CommandCatalogueEntry{EditCommand::Delete, "roll.delete"},
    CommandCatalogueEntry{EditCommand::PitchBend, "roll.pitch_bend"},
    CommandCatalogueEntry{EditCommand::TransposeUp, "roll.transpose_up"},
    CommandCatalogueEntry{EditCommand::TransposeDown, "roll.transpose_down"},
    CommandCatalogueEntry{EditCommand::TransposeUpOctave, "roll.transpose_up_octave"},
    CommandCatalogueEntry{EditCommand::TransposeDownOctave, "roll.transpose_down_octave"},
    CommandCatalogueEntry{EditCommand::NudgeLeft, "roll.nudge_left"},
    CommandCatalogueEntry{EditCommand::NudgeRight, "roll.nudge_right"},
    CommandCatalogueEntry{EditCommand::MuteTracks, "roll.mute_tracks"},
    CommandCatalogueEntry{EditCommand::SoloTracks, "roll.solo_tracks"},
    CommandCatalogueEntry{EditCommand::InsertTime, "edit.insert_time"},
    CommandCatalogueEntry{EditCommand::DeleteTime, "edit.delete_time"},
    CommandCatalogueEntry{EditCommand::ClearTimeSelection, "edit.clear_time_selection"},
    CommandCatalogueEntry{EditCommand::PencilMode, "automation.pencil_mode"},
    CommandCatalogueEntry{EditCommand::MoveEventUp, "eventlist.move_up"},
    CommandCatalogueEntry{EditCommand::MoveEventDown, "eventlist.move_down"},
};

static_assert(kCommandCatalogue.size() == static_cast<std::size_t>(EditCommand::MoveEventDown) + 1);

constexpr std::size_t actionIndex(EditCommand command)
{
    return static_cast<std::size_t>(command);
}

bool isCheckable(EditCommand command)
{
    return command == EditCommand::MuteTracks || command == EditCommand::SoloTracks ||
           command == EditCommand::PencilMode;
}

} // namespace

EditActions::EditActions(QObject *parent) : QObject(parent)
{
    keymap::Registry &keys = keymap::Registry::instance();
    for (const CommandCatalogueEntry &entry : kCommandCatalogue) {
        const keymap::CommandInfo info = keys.command(QLatin1String(entry.id));
        auto *const commandAction = new QAction(info.name, this);
        keys.attach(QLatin1String(entry.id), commandAction);
        commandAction->setCheckable(isCheckable(entry.command));

        if (entry.command == EditCommand::Copy)
            commandAction->setObjectName(QStringLiteral("copyWindowAction"));
        else if (entry.command == EditCommand::SoloTracks)
            commandAction->setObjectName(QStringLiteral("soloWindowAction"));
        else if (entry.command == EditCommand::InsertTime)
            commandAction->setObjectName(QStringLiteral("insertTimeWindowAction"));
        else if (entry.command == EditCommand::DeleteTime)
            commandAction->setObjectName(QStringLiteral("deleteTimeWindowAction"));

        m_actions[actionIndex(entry.command)] = commandAction;
        connect(commandAction, &QAction::triggered, this,
                [this, command = entry.command] { execute(command); });
    }

    connect(qApp, &QApplication::focusChanged, this, [this](QWidget *, QWidget *) { refresh(); });
    if (QClipboard *const clipboard = QGuiApplication::clipboard()) {
        connect(clipboard, &QClipboard::dataChanged, this, [this] {
            updateClipboardEligibility();
            refresh();
        });
    }

    refresh();
}

QAction *EditActions::action(EditCommand command) const
{
    const std::size_t index = actionIndex(command);
    Q_ASSERT(index < m_actions.size());
    return index < m_actions.size() ? m_actions[index] : nullptr;
}

void EditActions::installWindowShortcuts(QWidget &window)
{
    for (const CommandCatalogueEntry &entry : kCommandCatalogue) {
        QAction *const commandAction = action(entry.command);
        if (commandAction->shortcutContext() == Qt::WindowShortcut)
            window.addAction(commandAction);
    }
}

std::optional<EditCommand> EditActions::editorCommandForKey(int key,
                                                            Qt::KeyboardModifiers modifiers) const
{
    const keymap::Registry &keys = keymap::Registry::instance();
    for (const CommandCatalogueEntry &entry : kCommandCatalogue) {
        const QAction *const commandAction = action(entry.command);
        if (commandAction->shortcutContext() == Qt::WidgetShortcut &&
            keys.matches(key, modifiers, QLatin1String(entry.id))) {
            return entry.command;
        }
    }
    return std::nullopt;
}

void EditActions::rebind(SongView *target)
{
    disconnectTargetObservations();
    m_target = nullptr;
    m_clipboardEligible = false;

    if (target) {
        m_target = target;
        observeTarget(*target);
        updateClipboardEligibility();
    }
    refresh();
}

SongView *EditActions::target() const
{
    return m_target.data();
}

void EditActions::refresh()
{
    SongView *const boundTarget = m_target.data();
    for (const CommandCatalogueEntry &entry : kCommandCatalogue) {
        bool enabled = false;
        if (boundTarget) {
            enabled = entry.command == EditCommand::Copy
                          ? focusedTextTarget() || boundTarget->editCommandAvailable(entry.command)
                      : entry.command == EditCommand::Paste
                          ? m_clipboardEligible
                          : boundTarget->editCommandAvailable(entry.command);
        }
        action(entry.command)->setEnabled(enabled);
    }
    refreshCheckedStates(boundTarget);
}

void EditActions::observeTarget(SongView &target)
{
    m_targetConnections.emplace_back(connect(&target, &QObject::destroyed, this, [this] {
        disconnectTargetObservations();
        m_target = nullptr;
        m_clipboardEligible = false;
        refresh();
    }));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::selectedTrackChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::muteMaskChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::soloMaskChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::editorViewStateChanged, this, &EditActions::refresh));
    m_targetConnections.emplace_back(
        connect(&target, &SongView::eventListVisibilityChanged, this, &EditActions::refresh));

    if (SongDocument *const document = target.document()) {
        m_targetConnections.emplace_back(
            connect(document, &SongDocument::documentChanged, this, [this] {
                updateClipboardEligibility();
                refresh();
            }));
    }

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

    if (EditorDrawer *const drawer = target.editorDrawer()) {
        if (AutomationPage *const page = drawer->automationPage()) {
            if (AutomationCanvas *const canvas = page->canvas()) {
                m_targetConnections.emplace_back(connect(canvas,
                                                         &AutomationCanvas::activeParameterChanged,
                                                         this, &EditActions::refresh));
                m_targetConnections.emplace_back(
                    connect(canvas, &AutomationCanvas::parameterSelectionChanged, this,
                            &EditActions::refresh));
                m_targetConnections.emplace_back(
                    connect(canvas, &AutomationCanvas::parameterPresentationChanged, this,
                            &EditActions::refresh));
            }
        }
    }
}

void EditActions::disconnectTargetObservations()
{
    for (const QMetaObject::Connection &connection : m_targetConnections)
        QObject::disconnect(connection);
    m_targetConnections.clear();
}

void EditActions::updateClipboardEligibility()
{
    SongView *const boundTarget = m_target.data();
    m_clipboardEligible = boundTarget && boundTarget->editCommandAvailable(EditCommand::Paste);
}

void EditActions::execute(EditCommand command)
{
    SongView *const boundTarget = m_target.data();
    if (!boundTarget) {
        refresh();
        return;
    }

    if (command == EditCommand::Copy && copyFocusedText()) {
        refresh();
        return;
    }
    if (command == EditCommand::SoloTracks && focusedTextTarget()) {
        refresh();
        return;
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
