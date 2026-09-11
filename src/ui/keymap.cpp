#include "keymap.h"

#include <QAction>
#include <QKeyEvent>
#include <QStringList>

#include <iterator>

namespace keymap {
namespace {

struct Def {
    const char *id;
    Context context;
    Scope scope;
    const char *category;
    const char *name;
    // Platform-adaptive default; UnknownKey means use `keys` instead.
    QKeySequence::StandardKey standard;
    // Portable-text alternates separated by ';' ("Delete;Backspace"), also
    // used as a fallback when a standard key has no platform binding.
    const char *keys;
    // Mouse-gesture modifier command ("hold X and drag"): fixed bare-modifier
    // chord, never a key sequence.
    Qt::KeyboardModifiers modifierBinding;
};

// Stable fixed catalogue order.
const Def kDefs[] = {
    // File
    {"file.open_project", Context::Global, Scope::Window, QT_TR_NOOP("File"),
     QT_TR_NOOP("Open Project"), QKeySequence::Open, "", Qt::NoModifier},
    {"file.new_song", Context::Global, Scope::Window, QT_TR_NOOP("File"), QT_TR_NOOP("New Song"),
     QKeySequence::New, "", Qt::NoModifier},
    {"file.import_midi", Context::Global, Scope::Window, QT_TR_NOOP("File"),
     QT_TR_NOOP("Import MIDI"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"file.save_song", Context::Global, Scope::Window, QT_TR_NOOP("File"), QT_TR_NOOP("Save Song"),
     QKeySequence::Save, "", Qt::NoModifier},
    {"file.register_song", Context::Global, Scope::Window, QT_TR_NOOP("File"),
     QT_TR_NOOP("Register Song"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"file.close_tab", Context::Global, Scope::Window, QT_TR_NOOP("File"), QT_TR_NOOP("Close Tab"),
     QKeySequence::Close, "", Qt::NoModifier},
    {"file.export_wav", Context::Global, Scope::Window, QT_TR_NOOP("File"),
     QT_TR_NOOP("Export WAV"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"file.quit", Context::Global, Scope::Window, QT_TR_NOOP("File"), QT_TR_NOOP("Quit"),
     QKeySequence::Quit, "", Qt::NoModifier},
    // Edit
    {"edit.undo", Context::Global, Scope::Window, QT_TR_NOOP("Edit"), QT_TR_NOOP("Undo"),
     QKeySequence::Undo, "", Qt::NoModifier},
    {"edit.redo", Context::Global, Scope::Window, QT_TR_NOOP("Edit"), QT_TR_NOOP("Redo"),
     QKeySequence::Redo, "", Qt::NoModifier},
    {"edit.insert_time", Context::Global, Scope::Window, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Insert Time"), QKeySequence::UnknownKey, "Ctrl+Shift+I", Qt::NoModifier},
    {"edit.delete_time", Context::Global, Scope::Window, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Delete Time"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.clear_time_selection", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Clear Time Selection"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.preferences", Context::Global, Scope::Window, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Preferences"), QKeySequence::Preferences, "Ctrl+,", Qt::NoModifier},
    {"edit.song_settings", Context::Global, Scope::Window, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Song Settings"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.engine_settings", Context::Global, Scope::Window, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Engine Settings"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.set_velocity", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Set Velocity…"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.set_loop_start", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Set Loop Start at Edit Cursor"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.set_loop_end", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Set Loop End at Edit Cursor"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.loop_from_selection", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Loop from Time Selection"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.remove_loop", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Remove Loop Markers"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"edit.edit_time_signature", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Edit Time Signature at Edit Cursor…"), QKeySequence::UnknownKey, "",
     Qt::NoModifier},
    {"edit.remove_time_signature", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Edit"),
     QT_TR_NOOP("Remove Time Signature"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    // View
    {"view.theme", Context::Global, Scope::Window, QT_TR_NOOP("View"), QT_TR_NOOP("Theme"),
     QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"view.event_list", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("MIDI Event List"), QKeySequence::UnknownKey, "Ctrl+Shift+E", Qt::NoModifier},
    {"view.velocity_colors", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("Color Notes by Velocity"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"view.note_names", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("Show Note Names"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"view.automation_drawer", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("Automation Drawer"), QKeySequence::UnknownKey, "A", Qt::NoModifier},
    {"view.velocity_drawer", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("Velocity Drawer"), QKeySequence::UnknownKey, "V", Qt::NoModifier},
    {"view.voice_changes_drawer", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("Voice Changes Drawer"), QKeySequence::UnknownKey, "P", Qt::NoModifier},
    {"view.polyphony_debugger", Context::Global, Scope::Window, QT_TR_NOOP("View"),
     QT_TR_NOOP("Polyphony Debugger"), QKeySequence::UnknownKey, "Ctrl+Shift+P", Qt::NoModifier},
    // Tools
    {"tools.import_sample", Context::Global, Scope::Window, QT_TR_NOOP("Tools"),
     QT_TR_NOOP("Import Sample"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    // Transport
    {"transport.go_to_start", Context::Global, Scope::Window, QT_TR_NOOP("Transport"),
     QT_TR_NOOP("Go to Start"), QKeySequence::UnknownKey, "Home", Qt::NoModifier},
    {"transport.play", Context::Global, Scope::Window, QT_TR_NOOP("Transport"), QT_TR_NOOP("Play"),
     QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"transport.play_pause", Context::Global, Scope::Window, QT_TR_NOOP("Transport"),
     QT_TR_NOOP("Play/Pause"), QKeySequence::UnknownKey, "Space", Qt::NoModifier},
    {"transport.pause", Context::Global, Scope::Window, QT_TR_NOOP("Transport"),
     QT_TR_NOOP("Pause"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"transport.stop", Context::Global, Scope::Window, QT_TR_NOOP("Transport"), QT_TR_NOOP("Stop"),
     QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"transport.loop", Context::Global, Scope::Window, QT_TR_NOOP("Transport"),
     QT_TR_NOOP("Toggle Loop"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    {"transport.follow_playhead", Context::Global, Scope::Window, QT_TR_NOOP("Transport"),
     QT_TR_NOOP("Follow Playhead"), QKeySequence::UnknownKey, "", Qt::NoModifier},
    // Songs dock
    {"songs.find", Context::Global, Scope::Window, QT_TR_NOOP("Songs"), QT_TR_NOOP("Find Song"),
     QKeySequence::Find, "", Qt::NoModifier},
    // Help
    {"help.about", Context::Global, Scope::Window, QT_TR_NOOP("Help"), QT_TR_NOOP("About porydaw"),
     QKeySequence::UnknownKey, "", Qt::NoModifier},
    // Piano roll
    {"roll.copy", Context::Global, Scope::Window, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Copy Selection"), QKeySequence::Copy, "", Qt::NoModifier},
    {"roll.cut", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Cut Selection"), QKeySequence::Cut, "", Qt::NoModifier},
    {"roll.duplicate_time", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Duplicate time"), QKeySequence::UnknownKey, "Ctrl+D", Qt::NoModifier},
    {"roll.paste", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Paste at Edit Cursor"), QKeySequence::Paste, "", Qt::NoModifier},
    {"roll.select_all", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Select All Notes"), QKeySequence::SelectAll, "", Qt::NoModifier},
    {"roll.delete", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Delete Selection"), QKeySequence::UnknownKey, "Delete;Backspace", Qt::NoModifier},
    {"roll.pitch_bend", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Edit Note Pitch Bend"), QKeySequence::UnknownKey, "G", Qt::NoModifier},
    {"roll.transpose_up", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Transpose Up (Semitone)"), QKeySequence::UnknownKey, "Up", Qt::NoModifier},
    {"roll.transpose_down", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Transpose Down (Semitone)"), QKeySequence::UnknownKey, "Down", Qt::NoModifier},
    {"roll.transpose_up_octave", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Transpose Up (Octave)"), QKeySequence::UnknownKey, "Shift+Up", Qt::NoModifier},
    {"roll.transpose_down_octave", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Transpose Down (Octave)"), QKeySequence::UnknownKey, "Shift+Down", Qt::NoModifier},
    {"roll.nudge_left", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Nudge Left"), QKeySequence::UnknownKey, "Left", Qt::NoModifier},
    {"roll.nudge_right", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Nudge Right"), QKeySequence::UnknownKey, "Right", Qt::NoModifier},
    {"roll.mute_tracks", Context::Timeline, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Mute Selected Tracks"), QKeySequence::UnknownKey, "M", Qt::NoModifier},
    {"roll.solo_tracks", Context::Global, Scope::Window, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Solo Selected Tracks"), QKeySequence::UnknownKey, "S", Qt::NoModifier},
    // Ableton-style: hold the modifier and drag vertically anywhere on a
    // note to adjust its velocity. Qt maps Ctrl to Cmd on macOS.
    {"roll.velocity_drag", Context::PianoRoll, Scope::EditorRouted, QT_TR_NOOP("Piano Roll"),
     QT_TR_NOOP("Adjust Velocity (Hold + Drag Note)"), QKeySequence::UnknownKey, "",
     Qt::ControlModifier},
    // Velocity editor: hold the modifier to unlock continuous velocity detents.
    {"velocity.detent_unlock", Context::Velocity, Scope::EditorRouted, QT_TR_NOOP("Velocity"),
     QT_TR_NOOP("Unlock Detents (Hold)"), QKeySequence::UnknownKey, "", Qt::ControlModifier},
    // Ableton-style envelope drawing: drag draws the automation shape through
    // the cursor as grid steps, a click places a single snapped point, and
    // Delete or Backspace removes the hovered point.
    {"automation.pencil_mode", Context::Automation, Scope::EditorRouted, QT_TR_NOOP("Automation"),
     QT_TR_NOOP("Toggle Pencil Mode"), QKeySequence::UnknownKey, "B", Qt::NoModifier},
    // MIDI event list: same-tick reorder nudges (the keyboard face of the
    // row drag).
    {"eventlist.move_up", Context::EventList, Scope::EditorRouted, QT_TR_NOOP("MIDI Event List"),
     QT_TR_NOOP("Move Event Up (Same Tick)"), QKeySequence::UnknownKey, "Alt+Up", Qt::NoModifier},
    {"eventlist.move_down", Context::EventList, Scope::EditorRouted, QT_TR_NOOP("MIDI Event List"),
     QT_TR_NOOP("Move Event Down (Same Tick)"), QKeySequence::UnknownKey, "Alt+Down",
     Qt::NoModifier},
};

struct CachedDef {
    const Def *definition;
    QList<QKeySequence> sequences;
};

QList<QKeySequence> shippedBindings(const Def &def)
{
    if (def.modifierBinding != Qt::NoModifier)
        return {};
    if (def.standard != QKeySequence::UnknownKey) {
        const auto bindings = QKeySequence::keyBindings(def.standard);
        if (!bindings.isEmpty() || def.keys[0] == '\0')
            return bindings;
    }
    QList<QKeySequence> bindings;
    const QString keys = QLatin1String(def.keys);
    // ';' separates alternates; QKeySequence's own multi-stroke separator is
    // ", " so the two never collide.
    for (const QString &part : keys.split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
        const QKeySequence sequence = QKeySequence::fromString(part, QKeySequence::PortableText);
        if (!sequence.isEmpty())
            bindings.append(sequence);
    }
    return bindings;
}

const QList<CachedDef> &cachedDefs()
{
    static const QList<CachedDef> defs = [] {
        QList<CachedDef> definitions;
        definitions.reserve(int(std::size(kDefs)));
        for (const Def &def : kDefs)
            definitions.append({&def, shippedBindings(def)});
        return definitions;
    }();
    return defs;
}

const CachedDef *findDef(const QString &id)
{
    for (const CachedDef &def : cachedDefs()) {
        if (id == QLatin1String(def.definition->id))
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

QList<CommandInfo> Registry::commands() const
{
    const QList<CachedDef> &definitions = cachedDefs();
    QList<CommandInfo> commands;
    commands.reserve(definitions.size());
    for (const CachedDef &cached : definitions) {
        const Def &def = *cached.definition;
        commands.append({QLatin1String(def.id), def.context, def.scope, tr(def.category),
                         tr(def.name), cached.sequences, def.modifierBinding != Qt::NoModifier});
    }
    return commands;
}

CommandInfo Registry::command(const QString &id) const
{
    const CachedDef *cached = findDef(id);
    Q_ASSERT(cached);
    if (!cached)
        return {};
    const Def &def = *cached->definition;
    return {QLatin1String(def.id),
            def.context,
            def.scope,
            tr(def.category),
            tr(def.name),
            cached->sequences,
            def.modifierBinding != Qt::NoModifier};
}

QList<QKeySequence> Registry::bindings(const QString &id) const
{
    const CachedDef *cached = findDef(id);
    Q_ASSERT(cached);
    if (!cached || cached->definition->modifierBinding != Qt::NoModifier)
        return {};
    return cached->sequences;
}

Qt::KeyboardModifiers Registry::modifierBinding(const QString &id) const
{
    const CachedDef *cached = findDef(id);
    Q_ASSERT(cached && cached->definition->modifierBinding != Qt::NoModifier);
    if (!cached)
        return Qt::NoModifier;
    return cached->definition->modifierBinding;
}

bool Registry::matchesModifier(Qt::KeyboardModifiers mods, const QString &id) const
{
    const auto binding = modifierBinding(id);
    return binding != Qt::NoModifier && shortcutModifiers(mods) == binding;
}

bool Registry::isModifierKey(int key)
{
    return key == Qt::Key_Control || key == Qt::Key_Shift || key == Qt::Key_Alt ||
           key == Qt::Key_Meta;
}

bool Registry::matches(int key, Qt::KeyboardModifiers modifiers, const QString &id) const
{
    if (key == 0 || key == Qt::Key_unknown || isModifierKey(key))
        return false;
    const CachedDef *cached = findDef(id);
    Q_ASSERT(cached && cached->definition->modifierBinding == Qt::NoModifier);
    if (!cached || cached->definition->modifierBinding != Qt::NoModifier)
        return false;
    // Keypad arrows arrive with KeypadModifier set; bindings never carry it.
    const auto mods = shortcutModifiers(modifiers);
    const int combined = key | int(mods.toInt());
    for (const QKeySequence &sequence : cached->sequences) {
        if (sequence.count() == 1 && sequence[0].toCombined() == combined)
            return true;
    }
    return false;
}

bool Registry::matches(const QKeyEvent *event, const QString &id) const
{
    Q_ASSERT(event);
    if (!event)
        return false;
    return matches(event->key(), event->modifiers(), id);
}

void Registry::attach(const QString &id, QAction *action)
{
    const CachedDef *cached = findDef(id);
    Q_ASSERT(cached && cached->definition->modifierBinding == Qt::NoModifier && action);
    if (!cached || cached->definition->modifierBinding != Qt::NoModifier || !action)
        return;
    action->setShortcuts(cached->sequences);
    action->setShortcutContext(cached->definition->scope == Scope::Window ? Qt::WindowShortcut
                                                                          : Qt::WidgetShortcut);
}

} // namespace keymap
