#include "keymap.h"

#include <QAction>
#include <QStringList>

namespace keymap {
namespace {

// One catalogue row: a hold command carries a bare-modifier chord and empty
// sequences; every other command carries its resolved shipped sequences.
struct Def {
    QString id;
    Scope scope;
    const char *name; // QT_TR_NOOP marker; user-visible label
    QList<QKeySequence> sequences;
    Qt::KeyboardModifiers holdChord; // Qt::NoModifier for sequence commands
};

// Platform-adaptive resolution: the platform's standard-key bindings when it
// ships one, otherwise the ';' separated portable-text alternates.
QList<QKeySequence> shippedSequences(QKeySequence::StandardKey standard, const char *keys)
{
    if (standard != QKeySequence::UnknownKey) {
        const auto bindings = QKeySequence::keyBindings(standard);
        if (!bindings.isEmpty() || keys[0] == '\0')
            return bindings;
    }
    QList<QKeySequence> bindings;
    const QString keyText = QLatin1String(keys);
    // ';' separates alternates; QKeySequence's own multi-stroke separator is
    // ", " so the two never collide.
    for (const QString &part : keyText.split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
        const QKeySequence sequence = QKeySequence::fromString(part, QKeySequence::PortableText);
        if (!sequence.isEmpty())
            bindings.append(sequence);
    }
    return bindings;
}

Def sequenceDef(const char *id, Scope scope, const char *name,
                QKeySequence::StandardKey standard = QKeySequence::UnknownKey,
                const char *keys = "")
{
    return {QLatin1String(id), scope, name, shippedSequences(standard, keys), Qt::NoModifier};
}

// Hold command ("hold X and drag"): a fixed bare-modifier chord, never a key
// sequence.
Def holdDef(const char *id, Scope scope, const char *name, Qt::KeyboardModifiers holdChord)
{
    return {QLatin1String(id), scope, name, {}, holdChord};
}

// Stable fixed catalogue order.
const QList<Def> &catalogue()
{
    static const QList<Def> defs = {
        // File
        sequenceDef("file.open_project", Scope::Window, QT_TR_NOOP("Open Project"),
                    QKeySequence::Open),
        sequenceDef("file.new_song", Scope::Window, QT_TR_NOOP("New Song"), QKeySequence::New),
        sequenceDef("file.import_midi", Scope::Window, QT_TR_NOOP("Import MIDI")),
        sequenceDef("file.save_song", Scope::Window, QT_TR_NOOP("Save Song"), QKeySequence::Save),
        sequenceDef("file.register_song", Scope::Window, QT_TR_NOOP("Register Song")),
        sequenceDef("file.close_tab", Scope::Window, QT_TR_NOOP("Close Tab"), QKeySequence::Close),
        sequenceDef("file.export_wav", Scope::Window, QT_TR_NOOP("Export WAV")),
        sequenceDef("file.quit", Scope::Window, QT_TR_NOOP("Quit"), QKeySequence::Quit),
        // Edit
        sequenceDef("edit.undo", Scope::Window, QT_TR_NOOP("Undo"), QKeySequence::Undo),
        sequenceDef("edit.redo", Scope::Window, QT_TR_NOOP("Redo"), QKeySequence::Redo),
        sequenceDef("edit.insert_time", Scope::Window, QT_TR_NOOP("Insert Time"),
                    QKeySequence::UnknownKey, "Ctrl+Shift+I"),
        sequenceDef("edit.delete_time", Scope::Window, QT_TR_NOOP("Delete Time")),
        sequenceDef("edit.clear_time_selection", Scope::EditorRouted,
                    QT_TR_NOOP("Clear Time Selection")),
        sequenceDef("edit.preferences", Scope::Window, QT_TR_NOOP("Preferences"),
                    QKeySequence::Preferences, "Ctrl+,"),
        sequenceDef("edit.song_settings", Scope::Window, QT_TR_NOOP("Song Settings")),
        sequenceDef("edit.engine_settings", Scope::Window, QT_TR_NOOP("Engine Settings")),
        sequenceDef("edit.set_velocity", Scope::EditorRouted, QT_TR_NOOP("Set Velocity…")),
        sequenceDef("edit.set_loop_start", Scope::EditorRouted,
                    QT_TR_NOOP("Set Loop Start at Edit Cursor")),
        sequenceDef("edit.set_loop_end", Scope::EditorRouted,
                    QT_TR_NOOP("Set Loop End at Edit Cursor")),
        sequenceDef("edit.loop_from_selection", Scope::EditorRouted,
                    QT_TR_NOOP("Loop from Time Selection")),
        sequenceDef("edit.remove_loop", Scope::EditorRouted, QT_TR_NOOP("Remove Loop Markers")),
        sequenceDef("edit.edit_time_signature", Scope::EditorRouted,
                    QT_TR_NOOP("Edit Time Signature at Edit Cursor…")),
        sequenceDef("edit.remove_time_signature", Scope::EditorRouted,
                    QT_TR_NOOP("Remove Time Signature")),
        // View
        sequenceDef("view.theme", Scope::Window, QT_TR_NOOP("Theme")),
        sequenceDef("view.event_list", Scope::Window, QT_TR_NOOP("MIDI Event List"),
                    QKeySequence::UnknownKey, "Ctrl+Shift+E"),
        sequenceDef("view.velocity_colors", Scope::Window, QT_TR_NOOP("Color Notes by Velocity")),
        sequenceDef("view.note_names", Scope::Window, QT_TR_NOOP("Show Note Names")),
        sequenceDef("view.automation_drawer", Scope::Window, QT_TR_NOOP("Automation Drawer"),
                    QKeySequence::UnknownKey, "A"),
        sequenceDef("view.velocity_drawer", Scope::Window, QT_TR_NOOP("Velocity Drawer"),
                    QKeySequence::UnknownKey, "V"),
        sequenceDef("view.voice_changes_drawer", Scope::Window, QT_TR_NOOP("Voice Changes Drawer"),
                    QKeySequence::UnknownKey, "P"),
        sequenceDef("view.polyphony_debugger", Scope::Window, QT_TR_NOOP("Polyphony Debugger"),
                    QKeySequence::UnknownKey, "Ctrl+Shift+P"),
        // Tools
        sequenceDef("tools.import_sample", Scope::Window, QT_TR_NOOP("Import Sample")),
        // Transport
        sequenceDef("transport.go_to_start", Scope::Window, QT_TR_NOOP("Go to Start"),
                    QKeySequence::UnknownKey, "Home"),
        sequenceDef("transport.play", Scope::Window, QT_TR_NOOP("Play")),
        sequenceDef("transport.play_pause", Scope::Window, QT_TR_NOOP("Play/Pause"),
                    QKeySequence::UnknownKey, "Space"),
        sequenceDef("transport.pause", Scope::Window, QT_TR_NOOP("Pause")),
        sequenceDef("transport.stop", Scope::Window, QT_TR_NOOP("Stop")),
        sequenceDef("transport.loop", Scope::Window, QT_TR_NOOP("Toggle Loop")),
        sequenceDef("transport.follow_playhead", Scope::Window, QT_TR_NOOP("Follow Playhead")),
        // Songs dock
        sequenceDef("songs.find", Scope::Window, QT_TR_NOOP("Find Song"), QKeySequence::Find),
        // Help
        sequenceDef("help.about", Scope::Window, QT_TR_NOOP("About porydaw")),
        // Piano roll
        sequenceDef("roll.copy", Scope::Window, QT_TR_NOOP("Copy Selection"), QKeySequence::Copy),
        sequenceDef("roll.cut", Scope::EditorRouted, QT_TR_NOOP("Cut Selection"),
                    QKeySequence::Cut),
        sequenceDef("roll.duplicate_time", Scope::EditorRouted, QT_TR_NOOP("Duplicate time"),
                    QKeySequence::UnknownKey, "Ctrl+D"),
        sequenceDef("roll.paste", Scope::EditorRouted, QT_TR_NOOP("Paste at Edit Cursor"),
                    QKeySequence::Paste),
        sequenceDef("roll.select_all", Scope::EditorRouted, QT_TR_NOOP("Select All Notes"),
                    QKeySequence::SelectAll),
        sequenceDef("roll.delete", Scope::EditorRouted, QT_TR_NOOP("Delete Selection"),
                    QKeySequence::UnknownKey, "Delete;Backspace"),
        sequenceDef("roll.pitch_bend", Scope::EditorRouted, QT_TR_NOOP("Edit Note Pitch Bend"),
                    QKeySequence::UnknownKey, "G"),
        sequenceDef("roll.transpose_up", Scope::EditorRouted, QT_TR_NOOP("Transpose Up (Semitone)"),
                    QKeySequence::UnknownKey, "Up"),
        sequenceDef("roll.transpose_down", Scope::EditorRouted,
                    QT_TR_NOOP("Transpose Down (Semitone)"), QKeySequence::UnknownKey, "Down"),
        sequenceDef("roll.transpose_up_octave", Scope::EditorRouted,
                    QT_TR_NOOP("Transpose Up (Octave)"), QKeySequence::UnknownKey, "Shift+Up"),
        sequenceDef("roll.transpose_down_octave", Scope::EditorRouted,
                    QT_TR_NOOP("Transpose Down (Octave)"), QKeySequence::UnknownKey, "Shift+Down"),
        sequenceDef("roll.nudge_left", Scope::EditorRouted, QT_TR_NOOP("Nudge Left"),
                    QKeySequence::UnknownKey, "Left"),
        sequenceDef("roll.nudge_right", Scope::EditorRouted, QT_TR_NOOP("Nudge Right"),
                    QKeySequence::UnknownKey, "Right"),
        sequenceDef("roll.mute_tracks", Scope::EditorRouted, QT_TR_NOOP("Mute Selected Tracks"),
                    QKeySequence::UnknownKey, "M"),
        sequenceDef("roll.solo_tracks", Scope::Window, QT_TR_NOOP("Solo Selected Tracks"),
                    QKeySequence::UnknownKey, "S"),
        // Ableton-style: hold the modifier and drag vertically anywhere on a
        // note to adjust its velocity. Qt maps Ctrl to Cmd on macOS.
        holdDef("roll.velocity_drag", Scope::EditorRouted,
                QT_TR_NOOP("Adjust Velocity (Hold + Drag Note)"), Qt::ControlModifier),
        // Velocity editor: hold the modifier to unlock continuous velocity detents.
        holdDef("velocity.detent_unlock", Scope::EditorRouted, QT_TR_NOOP("Unlock Detents (Hold)"),
                Qt::ControlModifier),
        // Ableton-style envelope drawing: drag draws the automation shape through
        // the cursor as grid steps, a click places a single snapped point, and
        // Delete or Backspace removes the hovered point.
        sequenceDef("automation.pencil_mode", Scope::EditorRouted, QT_TR_NOOP("Toggle Pencil Mode"),
                    QKeySequence::UnknownKey, "B"),
        // MIDI event list: same-tick reorder nudges (the keyboard face of the
        // row drag).
        sequenceDef("eventlist.move_up", Scope::EditorRouted,
                    QT_TR_NOOP("Move Event Up (Same Tick)"), QKeySequence::UnknownKey, "Alt+Up"),
        sequenceDef("eventlist.move_down", Scope::EditorRouted,
                    QT_TR_NOOP("Move Event Down (Same Tick)"), QKeySequence::UnknownKey,
                    "Alt+Down"),
    };
    return defs;
}

const Def *findDef(const QString &id)
{
    for (const Def &def : catalogue()) {
        if (id == def.id)
            return &def;
    }
    return nullptr;
}

Qt::KeyboardModifiers shortcutModifiers(Qt::KeyboardModifiers modifiers)
{
    return modifiers &
           (Qt::ControlModifier | Qt::ShiftModifier | Qt::AltModifier | Qt::MetaModifier);
}

} // namespace

Registry::Registry() = default;

Registry &Registry::instance()
{
    static Registry registry;
    return registry;
}

QString Registry::label(const QString &id) const
{
    const Def *def = findDef(id);
    Q_ASSERT(def);
    if (!def)
        return {};
    return tr(def->name);
}

QList<QKeySequence> Registry::sequences(const QString &id) const
{
    const Def *def = findDef(id);
    Q_ASSERT(def && def->holdChord == Qt::NoModifier);
    if (!def || def->holdChord != Qt::NoModifier)
        return {};
    return def->sequences;
}

Qt::KeyboardModifiers Registry::modifierBinding(const QString &id) const
{
    const Def *def = findDef(id);
    Q_ASSERT(def && def->holdChord != Qt::NoModifier);
    if (!def)
        return Qt::NoModifier;
    return def->holdChord;
}

bool Registry::matchesModifier(Qt::KeyboardModifiers mods, const QString &id, bool allowShift) const
{
    const Qt::KeyboardModifiers chord = modifierBinding(id);
    if (chord == Qt::NoModifier)
        return false;
    const Qt::KeyboardModifiers held = shortcutModifiers(mods);
    return held == chord || (allowShift && held == (chord | Qt::ShiftModifier));
}

bool Registry::isModifierKey(int key)
{
    return key == Qt::Key_Control || key == Qt::Key_Shift || key == Qt::Key_Alt ||
           key == Qt::Key_Meta;
}

std::optional<QKeyCombination> Registry::singleStroke(const QString &id) const
{
    const QList<QKeySequence> bindings = sequences(id);
    if (bindings.isEmpty() || bindings.front().count() != 1)
        return std::nullopt;
    return bindings.front()[0];
}

bool Registry::matches(int key, Qt::KeyboardModifiers modifiers, const QString &id) const
{
    if (key == 0 || key == Qt::Key_unknown || isModifierKey(key))
        return false;
    const Def *def = findDef(id);
    Q_ASSERT(def && def->holdChord == Qt::NoModifier);
    if (!def || def->holdChord != Qt::NoModifier)
        return false;
    // Keypad arrows arrive with KeypadModifier set; bindings never carry it.
    const int combined = key | int(shortcutModifiers(modifiers).toInt());
    for (const QKeySequence &sequence : def->sequences) {
        if (sequence.count() == 1 && sequence[0].toCombined() == combined)
            return true;
    }
    return false;
}

// attach is the sole writer of an attached action's sequences and
// shortcut context; callers must not pre-write either. EditorRouted
// actions resolve to WidgetShortcut but are parented to a plain QObject
// and never added to any widget, so the Qt shortcut system never
// delivers them — their delivery is entirely manual (editkeyrouting),
// and associating one with a widget double-fires its command.
void Registry::attach(const QString &id, QAction *action)
{
    const Def *def = findDef(id);
    Q_ASSERT(def && def->holdChord == Qt::NoModifier && action);
    if (!def || def->holdChord != Qt::NoModifier || !action)
        return;
    action->setShortcuts(def->sequences);
    action->setShortcutContext(def->scope == Scope::Window ? Qt::WindowShortcut
                                                           : Qt::WidgetShortcut);
}

} // namespace keymap
