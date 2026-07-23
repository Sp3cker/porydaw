#include <QAction>
#include <QApplication>
#include <QHash>
#include <QKeySequence>
#include <QList>
#include <QMessageBox>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QWidget>
#include <cstdint>
#include <cstdio>

#include "liveshortcuts.hpp"
#include "mainwindow.h"
#include "ui/songview.h"

namespace {

QList<QKeySequence>
expectedShortcuts(const live_shortcuts::Descriptor &descriptor) {
  if (descriptor.standardKey != QKeySequence::UnknownKey) {
    return {QKeySequence(descriptor.standardKey)};
  }
  auto shortcuts = QList<QKeySequence>{};
  shortcuts.reserve(descriptor.keyCount);
  for (auto index = std::uint8_t{0}; index < descriptor.keyCount; ++index) {
    const auto &key = descriptor.keys[index];
    shortcuts.append(QKeySequence(QKeyCombination(key.modifiers, key.key)));
  }
  return shortcuts;
}

QString shortcutList(const QList<QKeySequence> &shortcuts) {
  auto shortcutNames = QStringList{};
  shortcutNames.reserve(shortcuts.size());
  for (const auto &shortcut : shortcuts) {
    shortcutNames.append(shortcut.toString(QKeySequence::PortableText));
  }
  return QStringLiteral("[") + shortcutNames.join(QStringLiteral(", ")) +
         QStringLiteral("]");
}

const char *shortcutContextName(Qt::ShortcutContext context) {
  switch (context) {
  case Qt::ApplicationShortcut:
    return "ApplicationShortcut";
  case Qt::WindowShortcut:
    return "WindowShortcut";
  case Qt::WidgetWithChildrenShortcut:
    return "WidgetWithChildrenShortcut";
  case Qt::WidgetShortcut:
    return "WidgetShortcut";
  }
  return "UnknownShortcutContext";
}
bool shortcutScopesOverlap(const QAction *first, const QAction *second) {
  const auto firstContext = first->shortcutContext();
  const auto secondContext = second->shortcutContext();
  if (firstContext == Qt::ApplicationShortcut ||
      secondContext == Qt::ApplicationShortcut) {
    return true;
  }
  const auto *firstWidget = qobject_cast<const QWidget *>(first->parent());
  const auto *secondWidget = qobject_cast<const QWidget *>(second->parent());
  if (firstWidget == nullptr || secondWidget == nullptr) {
    return true;
  }
  if (firstWidget->window() != secondWidget->window()) {
    return false;
  }
  if (firstContext == Qt::WindowShortcut ||
      secondContext == Qt::WindowShortcut) {
    return true;
  }
  const auto firstContainsSecond =
      firstWidget == secondWidget || firstWidget->isAncestorOf(secondWidget);
  const auto secondContainsFirst =
      firstWidget == secondWidget || secondWidget->isAncestorOf(firstWidget);
  if (firstContext == Qt::WidgetShortcut &&
      secondContext == Qt::WidgetShortcut) {
    return firstWidget == secondWidget;
  }
  if (firstContext == Qt::WidgetWithChildrenShortcut &&
      secondContext == Qt::WidgetWithChildrenShortcut) {
    return firstContainsSecond || secondContainsFirst;
  }
  if (firstContext == Qt::WidgetWithChildrenShortcut &&
      secondContext == Qt::WidgetShortcut) {
    return firstContainsSecond;
  }
  if (firstContext == Qt::WidgetShortcut &&
      secondContext == Qt::WidgetWithChildrenShortcut) {
    return secondContainsFirst;
  }
  return true;
}

int shortcutBindingCount(const QList<QAction *> &registeredActions) {
  auto shortcutBindingCount = 0;
  for (const auto *action : registeredActions) {
    for (const auto &shortcut : action->shortcuts()) {
      if (!shortcut.isEmpty()) {
        ++shortcutBindingCount;
      }
    }
  }
  return shortcutBindingCount;
}
int reportRemovedShortcutCount(const QList<QAction *> &registeredActions) {
  const auto removedShortcuts = QList<QKeySequence>{
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_O)),
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_N)),
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_S)),
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_W)),
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_Q)),
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_F)),
      QKeySequence(QKeyCombination(Qt::ControlModifier, Qt::Key_U)),
      QKeySequence(
          QKeyCombination(Qt::ControlModifier | Qt::ShiftModifier, Qt::Key_U)),
      QKeySequence(
          QKeyCombination(Qt::ControlModifier | Qt::ShiftModifier, Qt::Key_A)),
      QKeySequence(
          QKeyCombination(Qt::ControlModifier | Qt::AltModifier, Qt::Key_J)),
      QKeySequence(
          QKeyCombination(Qt::ControlModifier | Qt::AltModifier, Qt::Key_B))};
  auto removedShortcutCount = 0;
  for (const auto *action : registeredActions) {
    for (const auto &shortcut : action->shortcuts()) {
      if (removedShortcuts.contains(shortcut)) {
        const auto shortcutName =
            shortcut.toString(QKeySequence::PortableText).toLatin1();
        std::printf("ERROR removed shortcut remains bound shortcut=%s\n",
                    shortcutName.constData());
        ++removedShortcutCount;
      }
    }
  }
  return removedShortcutCount;
}

QString normalizedVisibleLabel(const QString &label) {
  auto normalizedLabel = label;
  normalizedLabel.remove(u'&');
  return normalizedLabel.simplified();
}

int reportRemovedPianoRollActionCount(const SongView &editor) {
  const auto removedActionLabels = QStringList{
      normalizedVisibleLabel(SongView::tr("Quantize")),
      normalizedVisibleLabel(SongView::tr("Quantize Settings")),
      normalizedVisibleLabel(SongView::tr("Invert Selection")),
      normalizedVisibleLabel(SongView::tr("Fit Notes to Time Range"))};
  auto removedActionCount = 0;
  for (const auto *action : editor.findChildren<QAction *>()) {
    const auto actionLabel = normalizedVisibleLabel(action->text());
    if (removedActionLabels.contains(actionLabel)) {
      const auto labelName = actionLabel.toUtf8();
      std::printf("ERROR removed piano-roll action remains label=%s\n",
                  labelName.constData());
      ++removedActionCount;
    }
  }
  return removedActionCount;
}

int reportConflictingShortcutCount(const QList<QAction *> &registeredActions) {
  auto actionsByShortcut = QHash<QString, QList<const QAction *>>{};
  auto conflictingShortcutCount = 0;
  for (const auto *action : registeredActions) {
    auto commandId = action->property("liveShortcutId").toString();
    if (commandId.isEmpty()) {
      commandId = QStringLiteral("<missing liveShortcutId>");
    }
    for (const auto &shortcut : action->shortcuts()) {
      if (shortcut.isEmpty()) {
        continue;
      }
      const auto shortcutBindingId =
          shortcut.toString(QKeySequence::PortableText);
      auto &existingActions = actionsByShortcut[shortcutBindingId];
      for (const auto *existingAction : existingActions) {
        if (!shortcutScopesOverlap(existingAction, action)) {
          continue;
        }
        auto existingCommandId =
            existingAction->property("liveShortcutId").toString();
        if (existingCommandId.isEmpty()) {
          existingCommandId = QStringLiteral("<missing liveShortcutId>");
        }
        const auto existingCommandName = existingCommandId.toLatin1();
        const auto newCommandId = commandId.toLatin1();
        const auto shortcutName =
            shortcut.toString(QKeySequence::PortableText).toLatin1();
        std::printf("ERROR conflicting audited actions ids=%s,%s context=%s "
                    "shortcut=%s\n",
                    existingCommandName.constData(), newCommandId.constData(),
                    shortcutContextName(action->shortcutContext()),
                    shortcutName.constData());
        ++conflictingShortcutCount;
      }
      existingActions.append(action);
    }
  }
  return conflictingShortcutCount;
}

} // namespace

int runShortcutCheck() {
  // An unavailable audio device opens a synchronous warning in MainWindow's
  // constructor. Close only that warning so the action audit is independent
  // of the benchmark machine's audio configuration.
  QTimer::singleShot(0, [] {
    for (auto *widget : QApplication::topLevelWidgets()) {
      if (auto *message = qobject_cast<QMessageBox *>(widget)) {
        message->accept();
      }
    }
  });

  MainWindow window;
  SongView editor(&window);
  const auto registeredActions = window.findChildren<QAction *>();
  auto actionsByCommandId = QHash<QString, QList<QAction *>>{};
  for (auto *action : registeredActions) {
    const auto commandId = action->property("liveShortcutId").toString();
    if (!commandId.isEmpty()) {
      actionsByCommandId[commandId].append(action);
    }
  }

  const auto &commandDescriptors = live_shortcuts::descriptors();
  auto descriptorIds = QHash<QString, bool>{};
  for (const auto &descriptor : commandDescriptors) {
    descriptorIds.insert(QString::fromLatin1(descriptor.shortcutId), true);
  }
  auto matchedCommandCount = 0;
  auto missingCommandCount = 0;
  auto invalidActionCount = 0;
  auto unknownActionCount = 0;
  for (const auto *action : registeredActions) {
    const auto commandId = action->property("liveShortcutId").toString();
    if (!commandId.isEmpty() && !descriptorIds.contains(commandId)) {
      const auto unknownCommandId = commandId.toLatin1();
      std::printf("ERROR unknown audited action id=%s\n",
                  unknownCommandId.constData());
      ++unknownActionCount;
    }
  }
  for (const auto &descriptor : commandDescriptors) {
    const auto commandId = QString::fromLatin1(descriptor.shortcutId);
    const auto actionsForCommand = actionsByCommandId.constFind(commandId);
    if (actionsForCommand == actionsByCommandId.cend()) {
      std::printf("ERROR missing audited action id=%s\n",
                  descriptor.shortcutId);
      ++missingCommandCount;
      continue;
    }
    const auto &commandActions = actionsForCommand.value();
    const auto expected = expectedShortcuts(descriptor);
    auto allActionsValid = true;
    for (const auto *action : commandActions) {
      const auto shortcutMatches = action->shortcuts() == expected;
      const auto shortcutContextMatches =
          action->shortcutContext() == descriptor.context;
      if (!shortcutMatches) {
        const auto expectedShortcutList = shortcutList(expected).toLatin1();
        const auto actualShortcutList =
            shortcutList(action->shortcuts()).toLatin1();
        std::printf("ERROR shortcut mismatch id=%s expected=%s actual=%s\n",
                    descriptor.shortcutId, expectedShortcutList.constData(),
                    actualShortcutList.constData());
      }
      if (!shortcutContextMatches) {
        std::printf(
            "ERROR shortcut context mismatch id=%s expected=%s actual=%s\n",
            descriptor.shortcutId, shortcutContextName(descriptor.context),
            shortcutContextName(action->shortcutContext()));
      }
      if (!shortcutMatches || !shortcutContextMatches) {
        allActionsValid = false;
        ++invalidActionCount;
      }
    }
    if (allActionsValid) {
      ++matchedCommandCount;
    }
  }

  const auto conflictingShortcutCount =
      reportConflictingShortcutCount(registeredActions);
  const auto removedShortcutCount =
      reportRemovedShortcutCount(registeredActions);
  const auto removedPianoRollActionCount =
      reportRemovedPianoRollActionCount(editor);
  const auto auditFailed =
      missingCommandCount != 0 || invalidActionCount != 0 ||
      unknownActionCount != 0 ||
      matchedCommandCount != static_cast<int>(commandDescriptors.size());
  std::printf("METRIC ableton_shortcut_matches=%d\n", matchedCommandCount);
  std::printf("METRIC shortcut_bindings=%d\n",
              shortcutBindingCount(registeredActions));
  std::printf("METRIC shortcut_conflicts=%d\n", conflictingShortcutCount);
  std::printf("METRIC removed_shortcut_bindings=%d\n", removedShortcutCount);
  std::printf("METRIC removed_piano_roll_actions=%d\n",
              removedPianoRollActionCount);
  return auditFailed || conflictingShortcutCount != 0 ||
                 removedShortcutCount != 0 || removedPianoRollActionCount != 0
             ? 1
             : 0;
}
