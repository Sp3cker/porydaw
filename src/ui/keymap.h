#pragma once

#include <QKeySequence>
#include <QList>
#include <QObject>
#include <QString>

class QAction;
class QKeyEvent;

namespace keymap {

// Where a command's semantic operation is meaningful. This remains
// descriptive; Scope controls physical shortcut delivery.
enum class Context {
    Global,
    Timeline,
    PianoRoll,
    Velocity,
    Automation,
    EventList,
};

// How a non-modifier command receives its shortcut.
enum class Scope {
    Window,
    EditorRouted,
};

struct CommandInfo {
    QString id; // stable, never shown ("roll.transpose_up")
    Context context;
    Scope scope;
    QString category;             // user-visible group ("File", "Piano Roll", ...)
    QString name;                 // user-visible name
    QList<QKeySequence> defaults; // empty for modifier commands
    // Mouse-gesture modifier command: bound to a bare modifier chord
    // ("hold Ctrl and drag"), not a key sequence.
    bool modifier = false;
};

// Central fixed shortcut catalogue. Only tier-1 QActions and the piano roll's
// editor commands are registered; widget-internal navigation keys (arrows in
// lists, Return/Escape in inline editors) remain platform conventions.
class Registry : public QObject
{
    Q_OBJECT
  public:
    static Registry &instance();

    // All commands in stable catalogue order.
    QList<CommandInfo> commands() const;
    CommandInfo command(const QString &id) const;

    // Immutable shipped key sequences. Defaults can carry alternates
    // (Delete/Backspace and platform StandardKey lists).
    QList<QKeySequence> bindings(const QString &id) const;

    // Modifier commands hold a fixed bare-modifier chord. Sequence bindings()
    // on a modifier command report empty, and vice versa.
    Qt::KeyboardModifiers modifierBinding(const QString &id) const;
    // Exact match against a modifier command after ignoring non-shortcut
    // modifiers such as KeypadModifier.
    bool matchesModifier(Qt::KeyboardModifiers mods, const QString &id) const;
    static bool isModifierKey(int key);

    // Single-keystroke match against the command's shipped bindings.
    // Keypad/GroupSwitch modifiers are ignored so numpad arrows keep working.
    bool matches(const QKeyEvent *event, const QString &id) const;
    // Value form of the same match: key and modifiers from any event source
    // (the converted TimelineKeyInput bands). Identical rejection of zero,
    // Key_unknown, and bare modifier keys.
    bool matches(int key, Qt::KeyboardModifiers modifiers, const QString &id) const;

    // Configures the action's immutable sequences and physical shortcut
    // context once.
    void attach(const QString &id, QAction *action);

  private:
    Registry();
};

} // namespace keymap
