#pragma once

#include <QKeyCombination>
#include <QKeySequence>
#include <QList>
#include <QObject>
#include <QString>

#include <optional>

class QAction;

namespace keymap {

// How a non-modifier command receives its shortcut.
enum class Scope {
    Window,
    EditorRouted,
};

// Central fixed shortcut catalogue. Only tier-1 QActions and the piano roll's
// editor commands are registered; widget-internal navigation keys (arrows in
// lists, Return/Escape in inline editors) remain platform conventions.
class Registry : public QObject
{
    Q_OBJECT
  public:
    static Registry &instance();

    // User-visible command name ("Open Project").
    QString label(const QString &id) const;

    // Immutable shipped key sequences. Defaults can carry alternates
    // (Delete/Backspace and platform StandardKey lists). Empty for hold
    // chords.
    QList<QKeySequence> sequences(const QString &id) const;

    // Hold commands ("hold X and drag") bind a fixed bare-modifier chord,
    // never a key sequence; sequence commands hold Qt::NoModifier.
    Qt::KeyboardModifiers modifierBinding(const QString &id) const;
    // Exact match against a hold command's chord after ignoring non-shortcut
    // modifiers such as KeypadModifier. allowShift also accepts the chord
    // plus exactly one ShiftModifier (the Shift-ramp carve-out).
    bool matchesModifier(Qt::KeyboardModifiers mods, const QString &id,
                         bool allowShift = false) const;
    static bool isModifierKey(int key);

    // The command's first shipped binding when it is a single keystroke.
    std::optional<QKeyCombination> singleStroke(const QString &id) const;
    // Single-keystroke match against the command's shipped bindings, from any
    // event source (the converted TimelineKeyInput bands). Keypad/GroupSwitch
    // modifiers are ignored so numpad arrows keep working; zero, Key_unknown,
    // and bare modifier keys never match.
    bool matches(int key, Qt::KeyboardModifiers modifiers, const QString &id) const;

    // Configures the action's immutable sequences and physical shortcut
    // context once.
    void attach(const QString &id, QAction *action);

  private:
    Registry();
};

} // namespace keymap
