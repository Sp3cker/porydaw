#pragma once

#include <QDeadlineTimer>
#include <QHash>
#include <QImage>
#include <QJSValue>
#include <QMutex>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QThread>
#include <QWaitCondition>

#include <atomic>
#include <functional>
#include <map>
#include <memory>
#include <vector>

#include "audio/audiotap.h"
#include "pluginmanifest.h"
#include "ui/keymap.h"

class AudioEngine;
class DecompProject;
class QAction;
class QDockWidget;
class QFileSystemWatcher;
class QJSEngine;
class QKeyEvent;
class QTimer;
class SongDocument;
struct SongSession;

namespace scripting {

// What the host borrows from the main window (docs/scripting/PLAN.md §3).
// Callbacks rather than a MainWindow pointer keep src/scripting/ free of
// the shell; every callback tolerates "no song loaded".
struct HostBindings {
    std::function<void()> play;
    std::function<void()> pause;
    std::function<void()> stop;
    std::function<void(uint64_t tick)> seekTick;
    std::function<void(const QString &text)> statusMessage;
    // Owns a plugin's global-context QAction's shortcut scope: the main
    // window adds it so the binding fires window-wide.
    std::function<void(QAction *action)> addGlobalAction;
    // Adds a plugin's dock (objectName already set) to the main window in
    // `area`, restoring its saved placement from windowState when there is
    // one, and lists it under View. Absent: the dock stays parentless.
    std::function<void(QDockWidget *dock, Qt::DockWidgetArea area)> addDock;
    const AudioEngine *audio = nullptr;
    const DecompProject *project = nullptr;
};

enum class PluginState { Disabled, Loaded, Error };

enum class LogLevel { Info, Warning, Error };

// A command a plugin registered through porydaw.actions.register.
struct PluginAction {
    QString fullId; // keymap id: plugin.<pluginId>.<actionId>
    keymap::Context context;
    QPointer<QAction> action; // global context only; parented to the plugin's facades
};

// One loaded plugin: its own QJSEngine, so one plugin's exception or hang
// can't take another down, plus everything it registered (torn down as a
// unit on unload/reload — nothing leaks across a hot reload).
struct Plugin {
    PluginManifest manifest;
    QString dir;
    bool enabled = true;
    PluginState state = PluginState::Disabled;
    QString error;
    std::unique_ptr<QJSEngine> engine;
    // From the prelude (scriptprelude.js): the event dispatcher and the
    // action runner, both closures over the plugin's `porydaw` object.
    QJSValue dispatch;
    QJSValue runAction;
    QJSValue deactivate;
    // API facade QObjects; destroyed before the engine (they hold QJSValues).
    std::vector<std::unique_ptr<QObject>> facades;
    std::vector<PluginAction> actions;
    bool builtin = false; // the console's own engine: no manifest, no reload
    QTimer *reloadTimer = nullptr;
    QStringList watchedPaths;
    // Live listener counts per event name (the prelude reports them), so
    // the host only pumps frames/beats to plugins that want them and only
    // runs the frame timer while somebody listens.
    QHash<QString, int> listeners;
    // Docks from porydaw.ui.dock (scriptwidgets.h); deleted on teardown
    // before the engine, since their handles hold QJSValue callbacks.
    std::vector<QPointer<QDockWidget>> docks;
    // porydaw.ui.loadImage: decoded images by handle id.
    std::map<int, QImage> images;
    int nextImageId = 1;
};

// A script edit transaction (`porydaw.edit.transaction`, API.md): one
// SongDocument edit group — one undo entry — owned by one plugin. Nested
// transactions of the owner flatten (depth); another plugin can't open
// one while it runs (its edits would land in the owner's undo entry).
// Optimistic concurrency: the transaction expects the document's revision
// to be exactly what its own last edit produced; a foreign mutation in
// between (an undo from a nested event loop, say) aborts it, and an
// aborted transaction refuses every further edit and rolls back on
// commit. inCall is the re-entrancy guard: an edit fires song.changed
// synchronously, so a listener that edits back would see a half-updated
// revision — it is refused instead.
struct EditTransaction {
    Plugin *owner = nullptr;
    QPointer<SongDocument> doc;
    QString name;
    int depth = 0;
    uint64_t revision = 0;
    uint64_t serial = 0; // distinguishes transactions begun inside a guarded call
    bool aborted = false;
    QString abortReason;
    bool inCall = false;
    bool open() const { return depth > 0; }
};

// Interrupts a plugin engine whose single call into script overruns its
// budget (PLAN §1 stance 6): the UI thread is inside QJSEngine::evaluate
// or QJSValue::call, so only another thread can pull the plug.
// Calls nest (plugin A's action plays the transport, whose state event
// reaches plugin B): armed calls form a stack and only the innermost — the
// one actually on the CPU — is watched. When it returns, the next outer
// call's own deadline is watched again.
class Watchdog : public QThread
{
  public:
    ~Watchdog() override;
    void arm(QJSEngine *engine, int budgetMs);
    // Pops the innermost call; returns whether its interrupt fired.
    bool disarm();

  protected:
    void run() override;

  private:
    struct Armed {
        QJSEngine *engine;
        QDeadlineTimer deadline;
        bool fired;
    };
    QMutex m_mutex;
    QWaitCondition m_wake;
    std::vector<Armed> m_stack;
    bool m_quit = false;
};

// The plugin host: discovery, lifecycle, hot reload, the watchdog, and the
// bridge between the app and every plugin's `porydaw` object. Lives on the
// UI thread; scripts run only on the UI thread (PLAN §1 stance 2).
class ScriptHost : public QObject
{
    Q_OBJECT
  public:
    explicit ScriptHost(QObject *parent = nullptr);
    ~ScriptHost() override;

    void setBindings(HostBindings bindings);
    const HostBindings &bindings() const { return m_bindings; }

    // <AppDataLocation>/plugins unless PORYDAW_PLUGINS_DIR overrides it.
    static QString defaultPluginsDir();
    void setPluginsDir(const QString &dir);
    QString pluginsDir() const { return m_pluginsDir; }
    // Per-call script budget (default 5000 ms). Harnesses shorten it.
    void setWatchdogMs(int ms) { m_watchdogMs = ms; }
    int watchdogMs() const { return m_watchdogMs; }

    // Scans the plugins dir and loads every enabled plugin. Also starts the
    // file watchers, so later edits hot-reload. Safe to call again (rescan).
    void loadAll();
    void unloadAll();

    QStringList pluginIds() const;
    // Also answers "console" with the Script Console's own plugin (once
    // the REPL has run).
    const Plugin *plugin(const QString &id) const;
    // Persisted under plugins/<id>/enabled; loads or unloads immediately.
    void setEnabled(const QString &id, bool enabled);
    void reload(const QString &id);

    // The song whose document/view the read API reflects (nullptr = none).
    void setSession(SongSession *session);
    SongSession *session() const { return m_session; }
    // Called at the UI cadence: detects transport-state changes to report.
    void tick();
    // One realtime frame (PLAN §4): polls the audio tap and emits
    // audio.frame, transport.tick and transport.beat to the plugins that
    // listen. The host's own ~60 Hz timer calls this while any plugin
    // listens; harnesses call it directly.
    void pumpFrame();
    bool frameTimerActive() const;
    // The analysis the last pumpFrame produced (porydaw.audio reads it).
    AudioAnalyzer &analyzer() { return m_analyzer; }

    // Script Console REPL: evaluates in the console's own engine (which has
    // the full porydaw API). Returns the result's text; errors go to log().
    QString evalConsole(const QString &code);

    // Runs a registered command by keymap id; false when none matches.
    bool runCommand(const QString &fullId);
    // SongView's plugin key handler (installed by the host).
    bool handleKey(QKeyEvent *event, keymap::Context surface, bool timeSelectionActive);

    // --- for the API facades ---
    void log(const Plugin &plugin, LogLevel level, const QString &text);
    // Registers a command for `plugin`; returns the full id, or empty with
    // *error set. Global-context commands get a QAction on the window.
    QString registerAction(Plugin &plugin, const QString &actionId, const QString &name,
                           keymap::Context context, const QString &defaultKeys, QString *error);
    void unregisterAction(Plugin &plugin, const QString &fullId);
    // Emits an event to one plugin / every loaded plugin (prelude dispatch).
    void emitEvent(Plugin &plugin, const QString &event, const QJSValue &payload);
    void emitEventAll(const QString &event, const QVariant &payload);
    // "Name: message (file:line)" plus the stack, for the console.
    QString formatError(const QJSValue &error) const;
    // Calls a plugin's JS function (a widget callback) under the watchdog;
    // errors are logged. Returns an undefined value when the plugin can't
    // run (faulted, interrupted, unloading).
    QJSValue invoke(Plugin &plugin, const QJSValue &fn, const QJSValueList &args);
    // The prelude reports listener counts here (see Plugin::listeners).
    void setListenerCount(Plugin &plugin, const QString &event, int count);
    // Hands a freshly built dock to the main window (HostBindings::addDock)
    // and tracks it for teardown.
    void registerDock(Plugin &plugin, QDockWidget *dock, Qt::DockWidgetArea area);

    // Edit transactions (EditTransaction above). begin/commit return false
    // with *error set; the prelude turns that into a thrown Error.
    bool beginTransaction(Plugin &plugin, const QString &name, QString *error);
    bool commitTransaction(Plugin &plugin, QString *error);
    void rollbackTransaction(Plugin &plugin);
    // Every edit call starts here: the document to edit, or nullptr with
    // *error (no transaction, another plugin's, re-entered from a
    // listener, aborted, or the revision guard tripped — the last two
    // abort the transaction). A non-null result must be followed by
    // transactionEdited() once the edit is done.
    SongDocument *transactionDocument(Plugin &plugin, QString *error);
    void transactionEdited();
    const EditTransaction &transaction() const { return m_transaction; }

  signals:
    // Plugin list or a plugin's state changed.
    void pluginsChanged();
    // A line for the Script Console (pluginId "console" for the REPL).
    void message(const QString &pluginId, int level, const QString &text);

  private:
    Plugin *findPlugin(const QString &id);
    Plugin *pluginForPath(const QString &path);
    void scan();
    void load(Plugin &plugin);
    void teardown(Plugin &plugin);
    void teardown(Plugin &plugin, bool callDeactivate);
    void buildEngine(Plugin &plugin);
    // Runs `fn` (a call into the engine) under the watchdog; on interrupt
    // the plugin is faulted (disabled until reload) and an error returned.
    QJSValue guarded(Plugin &plugin, const std::function<QJSValue()> &fn);
    void abortTransaction(const QString &reason);
    // Closes a transaction its owner can no longer finish (interrupted by
    // the watchdog, torn down): reverts and logs.
    void forceRollback(const QString &why);
    void fault(Plugin &plugin, const QString &why);
    void watch(Plugin &plugin);
    void unwatch(Plugin &plugin);
    void onPathChanged(const QString &path);
    void runPluginAction(Plugin &plugin, const QString &fullId);
    static bool enabledSetting(const QString &id);
    bool anyListener(const QString &event) const;
    void updateFrameTimer();
    // Emits to every plugin with a listener for `event` (payload converted
    // per engine, so the conversion is skipped for the rest).
    void emitEventListening(const QString &event, const QVariant &payload);

    HostBindings m_bindings;
    QString m_pluginsDir;
    int m_watchdogMs = 5000;
    std::vector<std::unique_ptr<Plugin>> m_plugins;
    std::unique_ptr<Plugin> m_console;
    Watchdog m_watchdog;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer *m_rescanTimer = nullptr;
    SongSession *m_session = nullptr;
    QMetaObject::Connection m_docConnection;
    int m_lastTransport = -1;
    QTimer *m_frameTimer = nullptr;
    AudioAnalyzer m_analyzer;
    int64_t m_lastBeat = -1; // global beat index of the last transport.beat
    bool m_inFrame = false;  // pumpFrame re-entrancy (a listener that pumps)
    EditTransaction m_transaction;
    uint64_t m_transactionSerial = 0;
    // Inside the song.changed fan-out: a transaction begun there would push
    // onto the undo stack while it is mid-undo/redo (the notification comes
    // from inside QUndoStack::undo), so beginTransaction refuses.
    bool m_inDocumentNotify = false;
};

} // namespace scripting
