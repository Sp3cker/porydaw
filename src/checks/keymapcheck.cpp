#include <QAction>
#include <QApplication>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QKeyEvent>
#include <QKeySequenceEdit>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QScrollBar>
#include <QSettings>
#include <QTabWidget>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <cstdio>

#include "ui/keyboardshortcutsdialog.h"
#include "ui/keymap.h"
#include "ui/settingsdialog.h"

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
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up, Qt::ControlModifier),
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
        check(keyMatches(QStringLiteral("roll.delete"), Qt::Key_Delete, Qt::NoModifier) &&
                  keyMatches(QStringLiteral("roll.delete"), Qt::Key_Backspace, Qt::NoModifier),
              "Delete and Backspace alternates should both delete");
        check(keyMatches(QStringLiteral("roll.copy"), Qt::Key_C, Qt::ControlModifier),
              "Ctrl+C should match roll.copy");
        check(keyMatches(QStringLiteral("roll.mute_tracks"), Qt::Key_M, Qt::NoModifier),
              "M should match mute tracks");
        check(!keyMatches(QStringLiteral("roll.mute_tracks"), Qt::Key_M, Qt::ControlModifier),
              "Ctrl+M must not match mute tracks");
        check(keyMatches(QStringLiteral("roll.solo_tracks"), Qt::Key_S, Qt::NoModifier),
              "S should match solo tracks");
        check(keyMatches(QStringLiteral("automation.pencil_mode"), Qt::Key_B, Qt::NoModifier),
              "B should toggle automation pencil mode");
        check(keyMatches(QStringLiteral("roll.pitch_bend"), Qt::Key_G, Qt::NoModifier),
              "G should edit the selected note's pitch bend");
        check(keyMatches(QStringLiteral("transport.play_pause"), Qt::Key_Space, Qt::NoModifier),
              "Space should match play/pause");
        check(
            !keyMatches(QStringLiteral("transport.play_pause"), Qt::Key_Space, Qt::ControlModifier),
            "Ctrl+Space must not match play/pause");
        const QString duplicateId = QStringLiteral("roll.duplicate_time");
        const keymap::CommandInfo duplicate = registry.command(duplicateId);
        check(duplicate.context == keymap::Context::PianoRoll &&
                  duplicate.category == QStringLiteral("Piano Roll") &&
                  duplicate.name == QStringLiteral("Duplicate time"),
              "duplicate time command metadata is wrong");
        check(duplicate.defaults == QList<QKeySequence>{QKeySequence(QStringLiteral("Ctrl+D"))},
              "duplicate time does not register Ctrl+D as its default");
        check(keyMatches(duplicateId, Qt::Key_D, Qt::ControlModifier),
              "Ctrl+D should match duplicate time");
        check(registry
                  .conflicts(duplicateId, duplicate.context, QKeySequence(QStringLiteral("Ctrl+D")))
                  .isEmpty(),
              "Ctrl+D conflicts with another command");
        registry.setBinding(duplicateId, QKeySequence(QStringLiteral("Alt+D")));
        check(registry.bindings(duplicateId) ==
                  QList<QKeySequence>{QKeySequence(QStringLiteral("Alt+D"))},
              "duplicate time override did not apply");
        check(QSettings().value(QStringLiteral("keymap/") + duplicateId).toString() ==
                  QStringLiteral("Alt+D"),
              "duplicate time override did not persist");
        registry.resetBinding(duplicateId);
        check(!registry.isOverridden(duplicateId) &&
                  keyMatches(duplicateId, Qt::Key_D, Qt::ControlModifier),
              "duplicate time reset did not restore Ctrl+D");
    }

    // 3. Override: the new key matches, the default stops matching, and the
    // store holds exactly the one delta.
    {
        registry.setBinding(QStringLiteral("roll.transpose_up"),
                            QKeySequence(QStringLiteral("Alt+T")));
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_T, Qt::AltModifier),
              "override Alt+T should match");
        check(!keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up, Qt::ControlModifier),
              "old Ctrl+Up must stop matching after override");
        check(registry.isOverridden(QStringLiteral("roll.transpose_up")),
              "override not marked as overridden");
        QSettings settings;
        check(settings.value(QStringLiteral("keymap/roll.transpose_up")).toString() ==
                  QStringLiteral("Alt+T"),
              "override not persisted as portable text");
        check(!settings.contains(QStringLiteral("keymap/roll.transpose_down")),
              "untouched command leaked into the settings store");
    }

    // 4. Unbind: explicitly bound to nothing, persisted as an empty delta.
    {
        registry.setBinding(QStringLiteral("roll.nudge_left"), QKeySequence());
        check(!keyMatches(QStringLiteral("roll.nudge_left"), Qt::Key_Left, Qt::ControlModifier),
              "unbound command still matches its default");
        check(registry.bindings(QStringLiteral("roll.nudge_left")).isEmpty(),
              "unbound command reports bindings");
        QSettings settings;
        check(settings.contains(QStringLiteral("keymap/roll.nudge_left")), "unbind not persisted");
    }

    // 5. Reset: default returns and the delta is removed. Re-assigning the
    // sole default is also a reset — the store stays delta-only.
    {
        registry.resetBinding(QStringLiteral("roll.transpose_up"));
        check(keyMatches(QStringLiteral("roll.transpose_up"), Qt::Key_Up, Qt::ControlModifier),
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
        check(keyMatches(QStringLiteral("roll.nudge_left"), Qt::Key_Left, Qt::ControlModifier),
              "resetAll did not restore nudge left");

        QSettings snapshotSettings;
        snapshotSettings.setValue(QStringLiteral("keymap/future.command"), QString());
        const auto snapshot = registry.snapshotOverrides();
        registry.setBinding(QStringLiteral("roll.nudge_left"),
                            QKeySequence(QStringLiteral("Alt+Left")));
        snapshotSettings.setValue(QStringLiteral("keymap/future.command"),
                                  QStringLiteral("changed"));
        snapshotSettings.setValue(QStringLiteral("keymap/added.later"), QStringLiteral("Ctrl+9"));
        registry.restoreOverrides(snapshot);
        QSettings restoredSettings;
        check(keyMatches(QStringLiteral("roll.nudge_left"), Qt::Key_Left, Qt::ControlModifier),
              "snapshot restore did not recover an absent command override");
        check(restoredSettings.contains(QStringLiteral("keymap/future.command")) &&
                  restoredSettings.value(QStringLiteral("keymap/future.command"))
                      .toString()
                      .isEmpty(),
              "snapshot restore did not preserve an explicit empty override");
        check(!restoredSettings.contains(QStringLiteral("keymap/added.later")),
              "snapshot restore retained an override added after the snapshot");
        restoredSettings.remove(QStringLiteral("keymap/future.command"));
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
        const QStringList onSave =
            registry.conflicts(QStringLiteral("roll.copy"), keymap::Context::PianoRoll,
                               QKeySequence(QStringLiteral("Ctrl+S")));
        check(onSave.contains(QStringLiteral("file.save_song")),
              "roll binding on Ctrl+S should conflict with Save Song");
        const QStringList onCopy =
            registry.conflicts(QStringLiteral("roll.cut"), keymap::Context::PianoRoll,
                               QKeySequence(QStringLiteral("Ctrl+C")));
        check(onCopy.contains(QStringLiteral("roll.copy")),
              "roll binding on Ctrl+C should conflict with roll copy");
        check(registry
                  .conflicts(QStringLiteral("roll.copy"), keymap::Context::PianoRoll,
                             QKeySequence(QStringLiteral("Alt+9")))
                  .isEmpty(),
              "unused sequence reported a conflict");
    }

    // 8. Modifier commands: the velocity-drag gesture ships on Ctrl, never
    // matches key events, and overrides/unbinds/resets through the same
    // delta-only store; the chord text round-trips in any spelling.
    {
        const QString id = QStringLiteral("roll.velocity_drag");
        check(registry.command(id).modifier, "velocity drag is not a modifier command");
        check(registry.modifierBinding(id) == Qt::ControlModifier,
              "velocity drag does not default to Ctrl");
        check(registry.bindings(id).isEmpty(), "modifier command reports key-sequence bindings");
        check(!keyMatches(id, Qt::Key_C, Qt::ControlModifier),
              "a key event matched a modifier command");

        registry.setModifierBinding(id, Qt::AltModifier);
        check(registry.modifierBinding(id) == Qt::AltModifier, "modifier override did not apply");
        check(registry.isOverridden(id), "modifier override not marked as overridden");
        check(QSettings().value(QStringLiteral("keymap/roll.velocity_drag")).toString() ==
                  QStringLiteral("Alt"),
              "modifier override not persisted as portable text");

        registry.setModifierBinding(id, Qt::ControlModifier);
        check(!registry.isOverridden(id),
              "re-assigning the default modifier should store no delta");

        registry.setModifierBinding(id, Qt::NoModifier);
        check(registry.modifierBinding(id) == Qt::NoModifier && registry.isOverridden(id),
              "modifier unbind did not persist as an empty delta");
        registry.resetBinding(id);
        check(registry.modifierBinding(id) == Qt::ControlModifier,
              "modifier reset did not restore Ctrl");

        check(keymap::Registry::modifierFromText(QStringLiteral("ctrl+shift")) ==
                  (Qt::ControlModifier | Qt::ShiftModifier),
              "modifier text parse is not case-insensitive");
        check(keymap::Registry::modifierText(Qt::ControlModifier | Qt::ShiftModifier) ==
                  QStringLiteral("Ctrl+Shift"),
              "modifier chord text did not serialize canonically");
        check(keymap::Registry::modifierFromText(QStringLiteral("Ctrl+F5")) == Qt::NoModifier,
              "a non-modifier token parsed as a chord");
    }

    // The Velocity modifier uses the same portable Ctrl default, but its
    // editor-only context does not conflict with the piano-roll gesture.
    {
        const QString id = QStringLiteral("velocity.detent_unlock");
        check(registry.command(id).modifier, "detent unlock is not a modifier command");
        check(registry.command(id).context == keymap::Context::Velocity,
              "detent unlock does not use the Velocity context");
        check(registry.modifierBinding(id) == Qt::ControlModifier &&
                  keymap::Registry::modifierText(registry.modifierBinding(id)) ==
                      QStringLiteral("Ctrl"),
              "detent unlock does not default to portable Ctrl");
        check(registry.bindings(id).isEmpty(), "detent unlock reports key-sequence bindings");
        check(!keyMatches(id, Qt::Key_C, Qt::ControlModifier), "a key event matched detent unlock");
        check(!registry.modifierConflicts(id, keymap::Context::Velocity, Qt::ControlModifier)
                   .contains(QStringLiteral("roll.velocity_drag")),
              "Velocity detent unlock incorrectly conflicts with piano-roll velocity drag");
        check(registry.modifierConflicts(id, keymap::Context::Global, Qt::ControlModifier)
                  .contains(QStringLiteral("roll.velocity_drag")),
              "Global modifier context missed the piano-roll velocity conflict");

        registry.setModifierBinding(id, Qt::AltModifier);
        check(registry.modifierBinding(id) == Qt::AltModifier,
              "detent unlock modifier override did not apply");
        check(QSettings().value(QStringLiteral("keymap/velocity.detent_unlock")).toString() ==
                  QStringLiteral("Alt"),
              "detent unlock modifier override not persisted as portable text");
        registry.setModifierBinding(id, Qt::ControlModifier);
        check(!registry.isOverridden(id),
              "re-assigning the detent unlock default should store no delta");
        registry.setModifierBinding(id, Qt::NoModifier);
        check(registry.modifierBinding(id) == Qt::NoModifier && registry.isOverridden(id),
              "detent unlock unbind did not persist as an empty delta");
        registry.resetBinding(id);
        check(registry.modifierBinding(id) == Qt::ControlModifier,
              "detent unlock reset did not restore Ctrl");
    }

    // 9. Dialog: filter narrows rows, assigning through the capture widget
    // steals from the conflicting command, and per-row Reset restores it.
    // Modifier commands swap the key capture for the chord picker.
    {
        QDialog dialog;
        auto *layout = new QVBoxLayout(&dialog);
        layout->addWidget(new KeyboardShortcutsWidget(&dialog));
        auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close, &dialog);
        QObject::connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
        layout->addWidget(buttons);
        dialog.resize(520, 560);
        dialog.show(); // lay the tree out so column geometry is real
        QApplication::processEvents();
        auto *tree = dialog.findChild<QTreeWidget *>();
        auto *filter = dialog.findChild<QLineEdit *>();
        auto *capture = dialog.findChild<QKeySequenceEdit *>();
        QPushButton *assignButton = findButton(&dialog, QStringLiteral("&Assign"));
        QPushButton *resetButton = findButton(&dialog, QStringLiteral("&Reset"));
        if (!check(tree && filter && capture && assignButton && resetButton,
                   "dialog widgets missing")) {
            return failures ? 1 : 0;
        }

        // The command column must fit its widest row out of the box (user
        // report: names were cut off until the header was dragged).
        // sizeHintForColumn is re-protected by QTreeView; the base keeps it
        // public.
        const int columnHint = static_cast<QAbstractItemView *>(tree)->sizeHintForColumn(0);
        check(tree->columnWidth(0) >= columnHint, "command column narrower than its contents");

        // Captures shed the keypad flag on every platform (macOS nav keys
        // and numpad arrows arrive with it set): bindings never carry it,
        // so keeping it would store a binding that can never match.
        const QKeySequence keypadShiftUp(
            QKeyCombination(Qt::ShiftModifier | Qt::KeypadModifier, Qt::Key_Up));
        const QKeySequence shiftUp(QKeyCombination(Qt::ShiftModifier, Qt::Key_Up));
        tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.copy")));
        capture->setKeySequence(keypadShiftUp);
        check(capture->keySequence() == shiftUp, "shortcut capture kept the keypad modifier");
        assignButton->click();
        check(registry.bindings(QStringLiteral("roll.copy")) == QList<QKeySequence>{shiftUp},
              "shortcut assignment kept the keypad modifier");
        registry.resetBinding(QStringLiteral("roll.copy"));

        filter->setText(QStringLiteral("Transpose"));
        QTreeWidgetItem *findSong = findCommandItem(tree, QStringLiteral("songs.find"));
        QTreeWidgetItem *transposeUp = findCommandItem(tree, QStringLiteral("roll.transpose_up"));
        check(findSong && findSong->isHidden(), "filter left a non-matching row visible");
        check(transposeUp && !transposeUp->isHidden(), "filter hid a matching row");
        filter->clear();

        // Steal: give Save Song's Ctrl+S to the roll copy command.
        tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.copy")));
        capture->setKeySequence(QKeySequence(QStringLiteral("Ctrl+S")));
        const int scrollBeforeAssign = tree->verticalScrollBar()->maximum() / 2;
        tree->verticalScrollBar()->setValue(scrollBeforeAssign);
        assignButton->click();
        check(registry.bindings(QStringLiteral("roll.copy")) ==
                  QList<QKeySequence>{QKeySequence(QStringLiteral("Ctrl+S"))},
              "dialog assign did not apply the binding");
        check(registry.isOverridden(QStringLiteral("file.save_song")) &&
                  registry.bindings(QStringLiteral("file.save_song")).isEmpty(),
              "conflicting command was not unbound by the steal");
        check(tree->verticalScrollBar()->value() == scrollBeforeAssign,
              "dialog assign did not preserve the list scroll position");

        QTreeWidgetItem *copyItem = findCommandItem(tree, QStringLiteral("roll.copy"));
        check(copyItem &&
                  copyItem->text(1).contains(
                      QKeySequence(QStringLiteral("Ctrl+S")).toString(QKeySequence::NativeText)),
              "tree does not show the new binding");
        check(copyItem && copyItem->font(1).bold(), "overridden row is not bold");

        // Per-row reset for both sides of the steal.
        tree->setCurrentItem(copyItem);
        resetButton->click();
        check(!registry.isOverridden(QStringLiteral("roll.copy")),
              "dialog reset did not clear the override");
        tree->setCurrentItem(findCommandItem(tree, QStringLiteral("file.save_song")));
        resetButton->click();
        check(keyMatches(QStringLiteral("file.save_song"), Qt::Key_S, Qt::ControlModifier),
              "Save Song did not get Ctrl+S back after reset");

        // Modifier row: the chord picker replaces the key capture, assigns
        // through the registry, and per-row Reset restores the default.
        auto *modCapture = dialog.findChild<QComboBox *>();
        if (check(modCapture != nullptr, "modifier chord picker missing")) {
            const QString detentId = QStringLiteral("velocity.detent_unlock");
            QTreeWidgetItem *detentItem = findCommandItem(tree, detentId);
            check(detentItem && detentItem->parent() &&
                      detentItem->parent()->text(0) == QStringLiteral("Velocity") &&
                      detentItem->text(0) == QStringLiteral("Unlock Detents (Hold)"),
                  "detent unlock row is missing its Velocity label");
#ifdef Q_OS_MACOS
            const QString detentDefaultText = QStringLiteral("⌘");
#else
            const QString detentDefaultText = QStringLiteral("Ctrl");
#endif
            check(detentItem && detentItem->text(1) == detentDefaultText,
                  "detent unlock row is missing its default modifier");
            tree->setCurrentItem(detentItem);
            check(modCapture->isVisible() && !capture->isVisible(),
                  "detent unlock row did not swap in the chord picker");
            const int ctrlIndex = modCapture->findData(int(Qt::ControlModifier));
            check(ctrlIndex >= 0 && modCapture->currentIndex() == ctrlIndex &&
                      modCapture->itemText(ctrlIndex) == detentDefaultText,
                  "detent unlock picker does not expose the Command/Ctrl default");
            const int detentAltIndex = modCapture->findData(int(Qt::AltModifier));
            const int detentCtrlAltIndex =
                modCapture->findData(int((Qt::ControlModifier | Qt::AltModifier).toInt()));
            check(modCapture->count() == 3 && detentAltIndex >= 0 && detentCtrlAltIndex >= 0 &&
                      modCapture->findData(int(Qt::ShiftModifier)) < 0 &&
                      modCapture->findData(int((Qt::ControlModifier | Qt::ShiftModifier).toInt())) <
                          0 &&
                      modCapture->findData(int((Qt::ShiftModifier | Qt::AltModifier).toInt())) < 0,
                  "detent unlock picker did not filter Shift-bearing choices");

            tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.velocity_drag")));
            check(modCapture->isVisible() && !capture->isVisible(),
                  "modifier row did not swap in the chord picker");
            const int altIndex = modCapture->findData(int(Qt::AltModifier));
            check(altIndex >= 0, "chord picker offers no Alt");
            const int shiftIndex = modCapture->findData(int(Qt::ShiftModifier));
            const int ctrlShiftIndex =
                modCapture->findData(int((Qt::ControlModifier | Qt::ShiftModifier).toInt()));
            const int ctrlAltIndex =
                modCapture->findData(int((Qt::ControlModifier | Qt::AltModifier).toInt()));
            const int shiftAltIndex =
                modCapture->findData(int((Qt::ShiftModifier | Qt::AltModifier).toInt()));
            check(modCapture->count() == 6 && shiftIndex >= 0 && ctrlShiftIndex >= 0 &&
                      ctrlAltIndex >= 0 && shiftAltIndex >= 0,
                  "chord picker did not restore all modifier choices");
#ifdef Q_OS_MACOS
            check(modCapture->itemText(modCapture->findData(int(Qt::ControlModifier))) ==
                          QStringLiteral("⌘") &&
                      modCapture->itemText(altIndex) == QStringLiteral("⌥") &&
                      modCapture->itemText(ctrlShiftIndex) == QStringLiteral("⇧⌘"),
                  "chord picker does not use native macOS modifier labels");
#endif
            modCapture->setCurrentIndex(altIndex);
            assignButton->click();
            check(registry.modifierBinding(QStringLiteral("roll.velocity_drag")) == Qt::AltModifier,
                  "chord picker assign did not apply the modifier");
            QTreeWidgetItem *velItem = findCommandItem(tree, QStringLiteral("roll.velocity_drag"));
#ifdef Q_OS_MACOS
            check(velItem && velItem->text(1) == QStringLiteral("⌥"),
                  "tree does not show the native macOS modifier chord");
#else
            check(velItem && velItem->text(1) == QStringLiteral("Alt"),
                  "tree does not show the new modifier chord");
#endif
            tree->setCurrentItem(velItem);
            resetButton->click();
            check(registry.modifierBinding(QStringLiteral("roll.velocity_drag")) ==
                      Qt::ControlModifier,
                  "modifier reset did not restore Ctrl");
            tree->setCurrentItem(findCommandItem(tree, QStringLiteral("roll.copy")));
            check(!modCapture->isVisible() && capture->isVisible(),
                  "leaving the modifier row did not restore the key capture");
        }
    }
    {
        const auto prefCmd = registry.command(QStringLiteral("edit.preferences"));
        auto expectedPreferences = QKeySequence::keyBindings(QKeySequence::Preferences);
        if (expectedPreferences.isEmpty())
            expectedPreferences.append(QKeySequence(QStringLiteral("Ctrl+,")));
        check(prefCmd.defaults == expectedPreferences,
              "edit.preferences does not match the platform Preferences binding");

        EngineSettings engineSettings;
        engineSettings.pcmMixer = M4A_PCM_MIXER_SAPPY;
        engineSettings.maxPcmChannels = 8;
        SongCfg songCfg;
        songCfg.masterVolume = 110;
        const auto songTarget = SongTarget{songCfg, QStringLiteral("mus_test")};
        const QStringList vgArgs = {QStringLiteral("_abandoned_ship"), QStringLiteral("_route101")};
        const auto originalBinding = QKeySequence(QStringLiteral("Ctrl+Alt+Left"));
        registry.setBinding(QStringLiteral("roll.nudge_left"), originalBinding);
        SettingsDialog dialog(engineSettings, songTarget, vgArgs, SettingsDialog::Tab::Engine);
        bool applyRequested = false;
        QObject::connect(&dialog, &SettingsDialog::applyRequested,
                         [&applyRequested] { applyRequested = true; });
        auto *tabs = dialog.findChild<QTabWidget *>();
        check(tabs != nullptr && tabs->count() == 3, "SettingsDialog does not have 3 tabs");
        if (tabs && tabs->count() == 3) {
            check(tabs->tabText(0) == QStringLiteral("Engine"), "tab 0 is not Engine");
            check(tabs->tabText(1).contains(QStringLiteral("mus_test")),
                  "tab 1 does not name the song");
            check(tabs->tabText(2) == QStringLiteral("Keyboard"), "tab 2 is not Keyboard");
        }
        check(dialog.currentTab() == SettingsDialog::Tab::Engine, "Wrong initial Settings tab");
        auto *mixer = dialog.findChild<QComboBox *>(QStringLiteral("pcmMixerCombo"));
        check(mixer && mixer->count() == 2 && mixer->findData(int(M4A_PCM_MIXER_IPATIX)) >= 0 &&
                  mixer->findData(int(M4A_PCM_MIXER_SAPPY)) >= 0,
              "SettingsDialog does not expose both PCM mixers");
        if (mixer) {
            check(mixer->currentData().toInt() == int(M4A_PCM_MIXER_SAPPY),
                  "SettingsDialog did not show the configured PCM mixer");
            mixer->setCurrentIndex(mixer->findData(int(M4A_PCM_MIXER_IPATIX)));
            check(dialog.engineSettings().pcmMixer == M4A_PCM_MIXER_IPATIX,
                  "SettingsDialog did not return the selected PCM mixer");
        }
        dialog.setCurrentTab(SettingsDialog::Tab::Song);
        check(dialog.currentTab() == SettingsDialog::Tab::Song,
              "SettingsDialog failed to switch to Song tab");
        const auto editedSong = dialog.songCfg();
        check(editedSong && editedSong->masterVolume == 110 && editedSong->reverb == songCfg.reverb,
              "SettingsDialog changed the initial song cfg without an edit");
        dialog.setCurrentTab(SettingsDialog::Tab::Keyboard);
        check(dialog.currentTab() == SettingsDialog::Tab::Keyboard,
              "SettingsDialog failed to switch to Keyboard tab");
        auto *tree = dialog.findChild<QTreeWidget *>();
        check(tree != nullptr, "SettingsDialog does not contain keyboard shortcut tree");
        auto *buttons = dialog.findChild<QDialogButtonBox *>();
        auto *applyButton = findButton(&dialog, QStringLiteral("Apply"));
        check(applyButton, "SettingsDialog does not expose an Apply button");
        const auto appliedBinding = QKeySequence(QStringLiteral("Alt+Left"));
        registry.setBinding(QStringLiteral("roll.nudge_left"), appliedBinding);
        dialog.show();
        if (applyButton)
            applyButton->click();
        const int applyGap =
            buttons && applyButton ? buttons->x() - applyButton->geometry().right() - 1 : -1;
        check(applyRequested && dialog.isVisible() && applyGap >= 0 &&
                  applyGap <= dialog.layout()->spacing(),
              "SettingsDialog Apply is not next to the other buttons");
        registry.setBinding(QStringLiteral("roll.nudge_left"),
                            QKeySequence(QStringLiteral("Shift+Left")));
        if (buttons && buttons->button(QDialogButtonBox::Cancel))
            buttons->button(QDialogButtonBox::Cancel)->click();
        check(registry.bindings(QStringLiteral("roll.nudge_left")).contains(appliedBinding),
              "SettingsDialog Cancel reverted an already applied shortcut");
        registry.resetBinding(QStringLiteral("roll.nudge_left"));
        SettingsDialog noSongDialog(engineSettings, std::nullopt, vgArgs,
                                    SettingsDialog::Tab::Song);
        auto *noSongTabs = noSongDialog.findChild<QTabWidget *>();
        check(noSongTabs && noSongTabs->count() == 3 && !noSongTabs->isTabEnabled(1),
              "SettingsDialog did not disable the unavailable Song tab");
        check(noSongDialog.currentTab() == SettingsDialog::Tab::Engine,
              "SettingsDialog selected an unavailable Song tab");
        check(!noSongDialog.songCfg().has_value(),
              "SettingsDialog produced song settings without a song target");
        EngineSettings persisted = engineSettings;
        persisted.pcmMixer = M4A_PCM_MIXER_SAPPY;
        persisted.save();
        check(EngineSettings::load().pcmMixer == M4A_PCM_MIXER_SAPPY,
              "EngineSettings did not persist the PCM mixer");
        QSettings().setValue(QStringLiteral("engine/pcmMixer"), QStringLiteral("invalid"));
        check(EngineSettings::load().pcmMixer == M4A_PCM_MIXER_IPATIX,
              "EngineSettings did not reject an invalid PCM mixer");
        persisted.save();
    }

    registry.resetAll();
    if (failures) {
        std::fprintf(stderr, "keymapcheck: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("keymapcheck: PASS\n");
    return 0;
}
