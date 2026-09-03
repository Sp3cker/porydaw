#pragma once

#include <QDeadlineTimer>
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
#include <memory>
#include <vector>

#include "pluginmanifest.h"
#include "ui/keymap.h"

class AudioEngine;
class DecompProject;
class QAction;
class QFileSystemWatcher;
class QJSEngine;
class QKeyEvent;
class QTimer;
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
    const Plugin *plugin(const QString &id) const;
    // Persisted under plugins/<id>/enabled; loads or unloads immediately.
    void setEnabled(const QString &id, bool enabled);
    void reload(const QString &id);

    // The song whose document/view the read API reflects (nullptr = none).
    void setSession(SongSession *session);
    SongSession *session() const { return m_session; }
    // Called at the UI cadence: detects transport-state changes to report.
    void tick();

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
    void fault(Plugin &plugin, const QString &why);
    void watch(Plugin &plugin);
    void unwatch(Plugin &plugin);
    void onPathChanged(const QString &path);
    void runPluginAction(Plugin &plugin, const QString &fullId);
    QString formatError(const QJSValue &error) const;
    static bool enabledSetting(const QString &id);

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
};

} // namespace scripting
