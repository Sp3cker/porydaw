#pragma once

#include <QKeySequence>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QString>

class QAction;
class QKeyEvent;

namespace keymap {

// Where a command's shortcut is live. Global shortcuts are window-level and
// stay active while a local context has focus, so conflict detection treats
// Global as overlapping every other context.
enum class Context {
    Global,
    PianoRoll,
};

struct CommandInfo {
    QString id;        // stable, never shown ("roll.transpose_up")
    Context context;
    QString category;  // user-visible group ("File", "Piano Roll", ...)
    QString name;      // user-visible name
    QList<QKeySequence> defaults;
};

// Central shortcut table: every user-configurable binding flows through here.
// Only tier-1 QActions and the piano roll's editor commands are registered;
// widget-internal navigation keys (arrows in lists, Return/Escape in inline
// editors) are platform conventions and deliberately stay hardcoded.
//
// Persistence is delta-only: QSettings holds just the bindings that differ
// from the defaults (an empty stored string means "explicitly unbound"), so
// shipped defaults can evolve without fighting stale full dumps.
class Registry : public QObject
{
    Q_OBJECT
public:
    static Registry &instance();

    // All commands in stable table order (the settings UI's display order).
    QList<CommandInfo> commands() const;
    CommandInfo command(const QString &id) const;

    // Effective bindings: the user override if one is stored, else the
    // defaults. An overridden command has at most one sequence; defaults may
    // carry alternates (Delete/Backspace, platform StandardKey lists).
    QList<QKeySequence> bindings(const QString &id) const;
    bool isOverridden(const QString &id) const;

    // An empty sequence unbinds the command. Writes QSettings and re-applies
    // attached QActions immediately.
    void setBinding(const QString &id, const QKeySequence &sequence);
    void resetBinding(const QString &id);
    void resetAll();

    // Commands other than excludeId whose effective bindings contain
    // sequence and whose context can be active at the same time as context.
    QStringList conflicts(const QString &excludeId, Context context,
                          const QKeySequence &sequence) const;

    // Single-keystroke match against the command's effective bindings.
    // Keypad/GroupSwitch modifiers are ignored so numpad arrows keep working.
    bool matches(const QKeyEvent *event, const QString &id) const;

    // Applies the command's bindings to the action now and re-applies them on
    // every user change for the action's lifetime.
    void attach(const QString &id, QAction *action);

signals:
    void bindingsChanged();

private:
    Registry();
    void applyToActions();

    struct Attached {
        QString id;
        QPointer<QAction> action;
    };
    QList<Attached> m_actions;
};

} // namespace keymap
