#include <QAction>
#include <QKeyEvent>
#include <QKeySequenceEdit>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QSettings>
#include <QTemporaryDir>
#include <QTreeWidget>
#include <cstdio>

#include "ui/keyboardshortcutsdialog.h"
#include "ui/keymap.h"

// --keymapcheck: user-configurable keyboard shortcuts check (self-contained,
// no project needed). Verifies the registry's shipped table (unique ids,
// non-empty names, no default conflicts), event matching (exact modifiers,
// keypad tolerance, alternate defaults), override/unbind/reset with
// delta-only QSettings persistence, live re-application to attached
// QActions, cross-context conflict detection, and the shortcuts dialog
// (filter, assign with steal-on-conflict, per-row reset) driven offscreen.
// QSettings is redirected into a temp dir first, so the user's real keymap
// is never read or written.

namespace {

bool keyMatches(const QString &id, int key, Qt::KeyboardModifiers mods)
{
    QKeyEvent event(QEvent::KeyPress, key, mods);
    return keymap::Registry::instance().matches(&event, id);
}

QTreeWidgetItem *findCommandItem(QTreeWidget *tree, const QString &id)
{
    for (int i = 0; i < tree->topLevelItemCount(); ++i) {
        QTreeWidgetItem *category = tree->topLevelItem(i);
        for (int j = 0; j < category->childCount(); ++j) {
            QTreeWidgetItem *item = category->child(j);
            if (item->data(0, Qt::UserRole).toString() == id)
                return item;
        }
    }
    return nullptr;
}

QPushButton *findButton(QWidget *root, const QString &text)
{
    const auto buttons = root->findChildren<QPushButton *>();
    for (QPushButton *button : buttons) {
        if (button->text() == text)
            return button;
    }
    return nullptr;
}

} // namespace

int runKeymapCheck()
{
    QTemporaryDir settingsDir;
    if (!settingsDir.isValid()) {
        std::fprintf(stderr, "keymapcheck: no temp dir for settings\n");
        return 1;
    }
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope,
                       settingsDir.path());
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                       settingsDir.path());

    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "keymapcheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };

    auto &registry = keymap::Registry::instance();

    // 1. Shipped table sanity: unique ids, visible names/categories, and no
    // command's default colliding with another live in an overlapping
    // context — a collision here would make two commands fire on one key.
    {
        const QList<keymap::CommandInfo> commands = registry.commands();
        check(!commands.isEmpty(), "empty command table");
        QSet<QString> ids;
        for (const keymap::CommandInfo &info : commands) {
            check(!ids.contains(info.id), "duplicate command id");
            ids.insert(info.id);
            check(!info.name.isEmpty() && !info.category.isEmpty(),
                  "command missing name or category");
            for (const QKeySequence &seq : info.defaults) {
                check(registry.conflicts(info.id, info.context, seq).isEmpty(),
                      "default binding conflicts across commands");
            }
        }
    }

    // 2. Default matching: exact modifiers decide between the semitone and
    // octave transpose commands; keypad arrows still count; StandardKey
    // multi-bindings and the Delete/Backspace alternates all match.
    {
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up,
                         Qt::ControlModifier),
              "Ctrl+Up should transpose up a semitone");
        check(!keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up,
                          Qt::ControlModifier | Qt::ShiftModifier),
              "Ctrl+Shift+Up must not match the semitone command");
        check(keyMatches(QStringLiteral("roll.transpose_up_octave"), Qt::Key_Up,
                         Qt::ControlModifier | Qt::ShiftModifier),
              "Ctrl+Shift+Up should transpose up an octave");
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up,
                         Qt::ControlModifier | Qt::KeypadModifier),
              "keypad Ctrl+Up should still transpose");
        check(keyMatches(QStringLiteral("roll.delete"), Qt::Key_Delete,
                         Qt::NoModifier)
                  && keyMatches(QStringLiteral("roll.delete"), Qt::Key_Backspace,
                                Qt::NoModifier),
              "Delete and Backspace alternates should both delete");
        check(keyMatches(QStringLiteral("roll.copy"), Qt::Key_C,
                         Qt::ControlModifier),
              "Ctrl+C should match roll.copy");
        check(keyMatches(QStringLiteral("transport.play_pause"), Qt::Key_Space,
                         Qt::NoModifier),
              "Space should match play/pause");
        check(!keyMatches(QStringLiteral("transport.play_pause"), Qt::Key_Space,
                          Qt::ControlModifier),
              "Ctrl+Space must not match play/pause");
    }

    // 3. Override: the new key matches, the default stops matching, and the
    // store holds exactly the one delta.
    {
        registry.setBinding(QStringLiteral("roll.transpose_up"),
                            QKeySequence(QStringLiteral("Alt+T")));
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_T,
                         Qt::AltModifier),
              "override Alt+T should match");
        check(!keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up,
                          Qt::ControlModifier),
              "old Ctrl+Up must stop matching after override");
        check(registry.isOverridden(QStringLiteral("roll.transpose_up")),
              "override not marked as overridden");
        QSettings settings;
        check(settings.value(QStringLiteral("keymap/roll.transpose_up"))
                      .toString()
                  == QStringLiteral("Alt+T"),
              "override not persisted as portable text");
        check(!settings.contains(QStringLiteral("keymap/roll.transpose_down")),
              "untouched command leaked into the settings store");
    }

    // 4. Unbind: explicitly bound to nothing, persisted as an empty delta.
    {
        registry.setBinding(QStringLiteral("roll.nudge_left"), QKeySequence());
        check(!keyMatches(QStringLiteral("roll.nudge_left"), Qt::Key_Left,
                          Qt::ControlModifier),
              "unbound command still matches its default");
        check(registry.bindings(QStringLiteral("roll.nudge_left")).isEmpty(),
              "unbound command reports bindings");
        QSettings settings;
        check(settings.contains(QStringLiteral("keymap/roll.nudge_left")),
              "unbind not persisted");
    }

    // 5. Reset: default returns and the delta is removed. Re-assigning the
    // sole default is also a reset — the store stays delta-only.
    {
        registry.resetBinding(QStringLiteral("roll.transpose_up"));
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up,
                         Qt::ControlModifier),
              "reset did not restore the default");
        QSettings settings;
        check(!settings.contains(QStringLiteral("keymap/roll.transpose_up")),
              "reset left a delta behind");
        registry.setBinding(QStringLiteral("view.event_list"),
                            QKeySequence(QStringLiteral("Ctrl+Shift+E")));
        check(!QSettings().contains(QStringLiteral("keymap/view.event_list")),
              "assigning the default value should store no delta");
        registry.resetAll();
        check(!QSettings().contains(QStringLiteral("keymap/roll.nudge_left")),
              "resetAll left deltas behind");
        check(keyMatches(QStringLiteral("roll.nudge_left"), Qt::Key_Left,
                         Qt::ControlModifier),
              "resetAll did not restore nudge left");
    }

    // 6. Attached QActions re-apply live on changes and detach safely on
    // destruction.
    {
        auto *action = new QAction(QStringLiteral("Go to Start"));
        registry.attach(QStringLiteral("transport.go_to_start"), action);
        check(action->shortcut() == QKeySequence(Qt::Key_Home),
              "attach did not apply the default shortcut");
        registry.setBinding(QStringLiteral("transport.go_to_start"),
                            QKeySequence(QStringLiteral("Ctrl+Home")));
        check(action->shortcut() == QKeySequence(QStringLiteral("Ctrl+Home")),
              "override was not re-applied to the attached action");
        delete action;
        // A change after deletion must not touch the dead pointer.
        registry.resetBinding(QStringLiteral("transport.go_to_start"));
    }

    // 7. Conflicts: Global overlaps every context, local contexts overlap
    // themselves.
    {
        const QStringList onSave = registry.conflicts(
            QStringLiteral("roll.copy"), keymap::Context::PianoRoll,
            QKeySequence(QStringLiteral("Ctrl+S")));
        check(onSave.contains(QStringLiteral("file.save_song")),
              "roll binding on Ctrl+S should conflict with Save Song");
        const QStringList onCopy = registry.conflicts(
            QStringLiteral("roll.cut"), keymap::Context::PianoRoll,
            QKeySequence(QStringLiteral("Ctrl+C")));
        check(onCopy.contains(QStringLiteral("roll.copy")),
              "roll binding on Ctrl+C should conflict with roll copy");
        check(registry
                  .conflicts(QStringLiteral("roll.copy"),
                             keymap::Context::PianoRoll,
                             QKeySequence(QStringLiteral("Alt+9")))
                  .isEmpty(),
              "unused sequence reported a conflict");
    }

    // 8. Dialog: filter narrows rows, assigning through the capture widget
    // steals from the conflicting command, and per-row Reset restores it.
    {
        KeyboardShortcutsDialog dialog;
        auto *tree = dialog.findChild<QTreeWidget *>();
        auto *filter = dialog.findChild<QLineEdit *>();
        auto *capture = dialog.findChild<QKeySequenceEdit *>();
        QPushButton *assignButton = findButton(&dialog, QStringLiteral("&Assign"));
        QPushButton *resetButton = findButton(&dialog, QStringLiteral("&Reset"));
        if (!check(tree && filter && capture && assignButton && resetButton,
                   "dialog widgets missing")) {
            return failures ? 1 : 0;
        }

        filter->setText(QStringLiteral("Transpose"));
        QTreeWidgetItem *findSong =
            findCommandItem(tree, QStringLiteral("songs.find"));
        QTreeWidgetItem *transposeUp =
            findCommandItem(tree, QStringLiteral("roll.transpose_up"));
        check(findSong && findSong->isHidden(),
              "filter left a non-matching row visible");
        check(transposeUp && !transposeUp->isHidden(),
              "filter hid a matching row");
        filter->clear();

        // Steal: give Save Song's Ctrl+S to the roll copy command.
        tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.copy")));
        capture->setKeySequence(QKeySequence(QStringLiteral("Ctrl+S")));
        assignButton->click();
        check(registry.bindings(QStringLiteral("roll.copy"))
                  == QList<QKeySequence>{QKeySequence(QStringLiteral("Ctrl+S"))},
              "dialog assign did not apply the binding");
        check(registry.isOverridden(QStringLiteral("file.save_song"))
                  && registry.bindings(QStringLiteral("file.save_song")).isEmpty(),
              "conflicting command was not unbound by the steal");

        QTreeWidgetItem *copyItem =
            findCommandItem(tree, QStringLiteral("roll.copy"));
        check(copyItem
                  && copyItem->text(1).contains(
                      QKeySequence(QStringLiteral("Ctrl+S"))
                          .toString(QKeySequence::NativeText)),
              "tree does not show the new binding");
        check(copyItem && copyItem->font(1).bold(),
              "overridden row is not bold");

        // Per-row reset for both sides of the steal.
        tree->setCurrentItem(copyItem);
        resetButton->click();
        check(!registry.isOverridden(QStringLiteral("roll.copy")),
              "dialog reset did not clear the override");
        tree->setCurrentItem(
            findCommandItem(tree, QStringLiteral("file.save_song")));
        resetButton->click();
        check(keyMatches(QStringLiteral("file.save_song"), Qt::Key_S,
                         Qt::ControlModifier),
              "Save Song did not get Ctrl+S back after reset");
    }

    registry.resetAll();
    if (failures) {
        std::fprintf(stderr, "keymapcheck: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("keymapcheck: PASS\n");
    return 0;
}
