#include <QAction>
#include <QApplication>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QThread>
#include <QTreeWidget>
#include <QUndoStack>
#include <functional>

#include "core/songdocument.h"
#include "mainwindow.h"
#include "scripting/scripthost.h"
#include "songsession.h"
#include "ui/keyboardshortcutspage.h"
#include "ui/keymap.h"
#include "ui/settingsdialog.h"
#include "ui/songview.h"
#include <atomic>
#include <cstdio>
#include <cstdlib>

// --scriptcheck: scripting host check (self-contained, no project needed).
// Phase 0 of docs/scripting/PLAN.md: proves that the linked QJSEngine does
// the four things the plugin host is built on — evaluates a script,
// bridges a QObject's Q_INVOKABLEs and properties into JS, reports thrown
// errors with the script's file name and line number, and can be
// interrupted from a watchdog thread while the UI thread is stuck inside
// evaluate(). The watchdog assertion carries a wall-clock cap so a broken
// interrupt shows up as a FAIL rather than a hang.

namespace {

// Stand-in for a `porydaw.*` facade: a plain QObject whose invokables and
// properties are what a plugin script sees.
class Bridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int revision READ revision CONSTANT)
  public:
    int revision() const { return 42; }
    Q_INVOKABLE int add(int a, int b) { return a + b; }
    Q_INVOKABLE QString echo(const QString &s)
    {
        lastEcho = s;
        return s + s;
    }
    Q_INVOKABLE void log(const QString &line) { lines << line; }
    QString lastEcho;
    QStringList lines;
};

} // namespace

namespace {

int runEngineCheck()
{
    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "scriptcheck: FAIL: %s\n", what);
            failures++;
        }
    };

    QJSEngine engine;
    engine.installExtensions(QJSEngine::ConsoleExtension);

    // Plain evaluation.
    {
        const QJSValue v = engine.evaluate(QStringLiteral("1 + 2"));
        check(!v.isError() && v.toInt() == 3, "1 + 2 did not evaluate to 3");
        const QJSValue arr = engine.evaluate(QStringLiteral("[3, 1, 2].sort().map(x => x * 2)"));
        check(!arr.isError() && arr.isArray() &&
                  arr.property(QStringLiteral("length")).toInt() == 3 &&
                  arr.property(0).toInt() == 2 && arr.property(2).toInt() == 6,
              "arrow functions / array methods missing (ES6 baseline)");
    }

    // QObject bridge: properties, invokables, values crossing both ways.
    {
        Bridge bridge;
        engine.globalObject().setProperty(QStringLiteral("porydaw"), engine.newQObject(&bridge));
        // The engine must not delete a C++-owned object when the JS wrapper
        // is collected.
        QJSEngine::setObjectOwnership(&bridge, QJSEngine::CppOwnership);
        const QJSValue sum = engine.evaluate(QStringLiteral("porydaw.add(porydaw.revision, 8)"));
        check(!sum.isError() && sum.toInt() == 50, "Q_INVOKABLE + Q_PROPERTY bridge broke");
        const QJSValue echo = engine.evaluate(QStringLiteral("porydaw.echo('ab')"));
        check(!echo.isError() && echo.toString() == QStringLiteral("abab") &&
                  bridge.lastEcho == QStringLiteral("ab"),
              "QString did not round-trip through the bridge");
        // A JS function held as a QJSValue callback, called from C++ with an
        // argument — the shape of every `on('event', fn)` subscription.
        QJSValue fn = engine.evaluate(
            QStringLiteral("(function(n) { porydaw.log('tick ' + n); return n + 1; })"));
        check(fn.isCallable(), "function literal is not callable");
        const QJSValue r = fn.call({QJSValue(6)});
        check(!r.isError() && r.toInt() == 7 &&
                  bridge.lines == QStringList{QStringLiteral("tick 6")},
              "callback from C++ did not run against the bridge");
        engine.collectGarbage();
        const QJSValue again = engine.evaluate(QStringLiteral("porydaw.add(1, 1)"));
        check(!again.isError() && again.toInt() == 2, "bridge object died across a GC");
    }

    // Errors carry file name + line number, which the Script Console needs.
    {
        const QJSValue err =
            engine.evaluate(QStringLiteral("var a = 1;\nvar b = 2;\nundefinedThing.call();\n"),
                            QStringLiteral("plugin/main.js"));
        check(err.isError(), "reference error was not reported as an error");
        check(err.property(QStringLiteral("lineNumber")).toInt() == 3,
              "error line number is not the throwing line");
        // The engine URL-ifies the name ("file:plugin/main.js"); the console
        // will pass QUrl::fromLocalFile paths, so only the tail is asserted.
        check(err.property(QStringLiteral("fileName"))
                  .toString()
                  .endsWith(QStringLiteral("plugin/main.js")),
              "error file name is not the script name passed to evaluate");
        check(err.property(QStringLiteral("stack")).toString().contains(QStringLiteral("main.js")),
              "error stack does not mention the script");
        const QJSValue thrown = engine.evaluate(QStringLiteral("throw new Error('boom')"));
        check(thrown.isError() &&
                  thrown.property(QStringLiteral("message")).toString() == QStringLiteral("boom"),
              "thrown Error lost its message");
        // The engine must be usable after an error: a plugin crashing must
        // not poison later calls.
        check(engine.evaluate(QStringLiteral("2 * 21")).toInt() == 42,
              "engine unusable after an exception");
    }

    // Watchdog: a runaway script is interrupted from another thread and
    // evaluate() returns. The watchdog thread also enforces the wall-clock
    // cap: if evaluate() has not come back 5 s after the interrupt, the
    // interrupt is broken and the UI thread is stuck for good, so the
    // thread reports the failure and exits the process instead of letting
    // the harness hang.
    {
        struct Watchdog : QThread {
            QJSEngine *engine = nullptr;
            std::atomic<bool> returned{false};
            void run() override
            {
                msleep(150);
                engine->setInterrupted(true);
                for (int i = 0; i < 50 && !returned.load(); ++i)
                    msleep(100);
                if (!returned.load()) {
                    std::fprintf(
                        stderr,
                        "scriptcheck: FAIL: infinite loop was not interrupted within 5 s\n");
                    std::fprintf(stderr, "scriptcheck: 1 failure(s)\n");
                    std::_Exit(1);
                }
            }
        } dog;
        dog.engine = &engine;
        QElapsedTimer clock;
        clock.start();
        dog.start();
        const QJSValue looped = engine.evaluate(QStringLiteral("var n = 0; while (true) n++; n"));
        const qint64 elapsedMs = clock.elapsed();
        dog.returned.store(true);
        dog.wait();
        check(elapsedMs >= 100, "interrupted before the watchdog fired (loop never ran?)");
        check(looped.isError() || looped.isUndefined(),
              "interrupted evaluate returned a normal value");
        check(engine.isInterrupted(), "isInterrupted() not set after the watchdog fired");
        // Clearing the flag must bring the engine back for the next plugin
        // call — an interrupted plugin gets disabled, the others carry on.
        engine.setInterrupted(false);
        const QJSValue after = engine.evaluate(QStringLiteral("'alive'"));
        check(!after.isError() && after.toString() == QStringLiteral("alive"),
              "engine not usable after clearing the interrupt");
    }

    return failures;
}

// ---- plugin host fixtures ----

bool writeFile(const QString &path, const QString &text)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.write(text.toUtf8());
    return true;
}

const char *kFixtureManifest = R"({ "id": "fixture", "name": "Fixture Plugin", "version": "1.0.0",
  "api": "1.0", "description": "harness fixture" })";

// v1: a global action, a roll action, a range action, a conflicting
// default, a song.changed listener, and log lines the harness looks for.
const char *kFixtureMainV1 = R"(
function bump(key) {
    porydaw.storage.set(key, (porydaw.storage.get(key, 0) || 0) + 1);
}
export function activate(ctx) {
    porydaw.actions.register({ id: "hello", name: "Hello", context: "global",
        default: "Ctrl+Alt+Shift+F9", run: function () { bump("ran"); } });
    porydaw.actions.register({ id: "roll", name: "Roll Thing", context: "roll",
        default: "Ctrl+Alt+Shift+F10", run: function () { bump("roll"); } });
    porydaw.actions.register({ id: "range", name: "Range Thing", context: "range",
        default: "Ctrl+Alt+Shift+F11", run: function () { bump("range"); } });
    porydaw.actions.register({ id: "conflict", name: "Steals Delete", context: "roll",
        default: "Delete", run: function () {} });
    porydaw.actions.register({ id: "vel", name: "Velocity Thing", context: "velocity",
        default: "Ctrl+Alt+Shift+F8", run: function () { bump("vel"); } });
    porydaw.actions.register({ id: "save", name: "Steals Save Default", context: "global",
        default: "Ctrl+S", run: function () {} });
    porydaw.song.on("changed", function (e) { porydaw.storage.set("rev", e.revision); });
    porydaw.log("activated v1 " + ctx.id + " " + porydaw.plugin.version);
}
export function deactivate() { porydaw.log("deactivated"); }
)";

// v2 (hot reload): keeps "hello", adds "hello2", drops the rest.
const char *kFixtureMainV2 = R"(
export function activate(ctx) {
    porydaw.actions.register({ id: "hello", name: "Hello", context: "global",
        default: "Ctrl+Alt+Shift+F9", run: function () {} });
    porydaw.actions.register({ id: "hello2", name: "Hello Two", context: "global",
        run: function () {} });
    porydaw.log("activated v2");
}
)";

const char *kBrokenManifest = R"({ "id": "broken", "name": "Broken", "api": 1 })";
const char *kBrokenMain =
    "export function activate() {\n  var x = 1;\n  throw new Error('boom');\n}\n";
const char *kBadManifest = R"({ "id": "badmanifest", "name": "Future", "api": 99 })";
const char *kSyntaxManifest = R"({ "id": "syntax", "name": "Syntax", "api": 1 })";
const char *kSyntaxMain = "export function activate() {\n  return (;\n}\n";
const char *kRunawayManifest = R"({ "id": "runaway", "name": "Runaway", "api": 1 })";
const char *kRunawayMain = R"(
export function activate() {
    porydaw.actions.register({ id: "loop", name: "Loop Forever", context: "global",
        run: function () { while (true) {} } });
}
)";

struct Message {
    QString plugin;
    int level;
    QString text;
};

bool hasMessage(const QList<Message> &messages, const QString &plugin, int level,
                const QString &fragment)
{
    for (const Message &m : messages) {
        if (m.plugin == plugin && m.level == level && m.text.contains(fragment))
            return true;
    }
    return false;
}

// Pumps events until pred() holds or the deadline passes.
bool waitFor(const std::function<bool()> &pred, int ms)
{
    QDeadlineTimer deadline(ms);
    while (!deadline.hasExpired()) {
        QApplication::processEvents(QEventLoop::AllEvents, 50);
        if (pred())
            return true;
        QThread::msleep(10);
    }
    return pred();
}

int storedCounter(const QString &plugin, const QString &key)
{
    const QByteArray raw =
        QSettings().value(QStringLiteral("plugins/%1/data/%2").arg(plugin, key)).toByteArray();
    return QJsonDocument::fromJson(raw).object().value(QLatin1String("v")).toInt(-1);
}

} // namespace

bool MainWindow::runScriptHostCheck(const QString &pluginsDir, const QString &projectRoot,
                                    const QString &songLabel)
{
    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "scriptcheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };
    scripting::ScriptHost &host = *m_scriptHost;
    auto &keys = keymap::Registry::instance();
    QList<Message> messages;
    connect(&host, &scripting::ScriptHost::message, this,
            [&messages](const QString &plugin, int level, const QString &text) {
                messages.append({plugin, level, text});
            });

    // --- fixtures ---
    const QString fixtureDir = pluginsDir + QStringLiteral("/fixture");
    check(
        writeFile(fixtureDir + QStringLiteral("/plugin.json"), QLatin1String(kFixtureManifest)) &&
            writeFile(fixtureDir + QStringLiteral("/main.js"), QLatin1String(kFixtureMainV1)) &&
            writeFile(pluginsDir + QStringLiteral("/broken/plugin.json"),
                      QLatin1String(kBrokenManifest)) &&
            writeFile(pluginsDir + QStringLiteral("/broken/main.js"), QLatin1String(kBrokenMain)) &&
            writeFile(pluginsDir + QStringLiteral("/badmanifest/plugin.json"),
                      QLatin1String(kBadManifest)) &&
            writeFile(pluginsDir + QStringLiteral("/runaway/plugin.json"),
                      QLatin1String(kRunawayManifest)) &&
            writeFile(pluginsDir + QStringLiteral("/runaway/main.js"),
                      QLatin1String(kRunawayMain)) &&
            writeFile(pluginsDir + QStringLiteral("/syntax/plugin.json"),
                      QLatin1String(kSyntaxManifest)) &&
            writeFile(pluginsDir + QStringLiteral("/syntax/main.js"), QLatin1String(kSyntaxMain)) &&
            writeFile(pluginsDir + QStringLiteral("/notaplugin/readme.txt"),
                      QStringLiteral("no manifest")),
        "could not write fixture plugins");

    // The bundled examples double as API smoke tests (PLAN §8): copied in
    // from the source tree when the binary runs out of its build dir.
    bool haveExamples = false;
    {
        const QDir examples(QCoreApplication::applicationDirPath() +
                            QStringLiteral("/../plugins/examples"));
        for (const QString &name :
             examples.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
            const QDir src(examples.filePath(name));
            for (const QString &file : src.entryList(QDir::Files)) {
                QFile in(src.filePath(file));
                if (in.open(QIODevice::ReadOnly))
                    writeFile(pluginsDir + QLatin1Char('/') + name + QLatin1Char('/') + file,
                              QString::fromUtf8(in.readAll()));
            }
            haveExamples = true;
        }
    }

    const int shippedCommands = keys.commands().size();
    // A user who moved Save off Ctrl+S: the plugin's Ctrl+S default must
    // still be refused, since Reset would bring the collision back.
    keys.setBinding(QStringLiteral("file.save_song"),
                    QKeySequence(QStringLiteral("Ctrl+Alt+Shift+F7")));
    host.setPluginsDir(pluginsDir);
    host.loadAll();
    keys.resetBinding(QStringLiteral("file.save_song"));

    // --- discovery + states ---
    QStringList expectedIds{QStringLiteral("badmanifest"), QStringLiteral("broken"),
                            QStringLiteral("fixture"), QStringLiteral("runaway"),
                            QStringLiteral("syntax")};
    int exampleCommands = 0;
    if (haveExamples) {
        expectedIds.append(QStringLiteral("select-same-pitch"));
        expectedIds.sort();
        const scripting::Plugin *example = host.plugin(QStringLiteral("select-same-pitch"));
        check(example && example->state == scripting::PluginState::Loaded,
              "bundled example plugin select-same-pitch did not load");
        check(keys.command(QStringLiteral("plugin.select-same-pitch.select")).context ==
                  keymap::Context::PianoRoll,
              "bundled example did not register its roll command");
        exampleCommands = example ? int(example->actions.size()) : 0;
    }
    check(host.pluginIds() == expectedIds,
          "plugin discovery did not list exactly the manifest-bearing folders, sorted");
    const scripting::Plugin *fixture = host.plugin(QStringLiteral("fixture"));
    const scripting::Plugin *broken = host.plugin(QStringLiteral("broken"));
    const scripting::Plugin *bad = host.plugin(QStringLiteral("badmanifest"));
    if (!check(fixture && broken && bad, "fixture plugins missing from the host"))
        return false;
    check(fixture->state == scripting::PluginState::Loaded, "fixture plugin did not load");
    check(fixture->manifest.name == QStringLiteral("Fixture Plugin") &&
              fixture->manifest.apiMajor == 1,
          "manifest fields (name, api \"1.0\" → major 1) not parsed");
    check(broken->state == scripting::PluginState::Error &&
              broken->error.contains(QStringLiteral("boom")) &&
              broken->error.contains(QStringLiteral("main.js:3")),
          "activate() throwing did not fault the plugin with file:line");
    check(!broken->engine, "a faulted plugin kept its engine");
    check(bad->state == scripting::PluginState::Error &&
              bad->error.contains(QStringLiteral("API 99")),
          "api major mismatch was not refused with the version in the message");
    check(hasMessage(messages, QStringLiteral("fixture"), 0,
                     QStringLiteral("activated v1 fixture 1.0.0")),
          "porydaw.log from activate() did not reach the console signal");
    check(hasMessage(messages, QStringLiteral("broken"), 2, QStringLiteral("boom")),
          "activate() error was not logged at error level");
    const scripting::Plugin *syntax = host.plugin(QStringLiteral("syntax"));
    check(syntax && syntax->state == scripting::PluginState::Error && !syntax->engine &&
              hasMessage(messages, QStringLiteral("syntax"), 2, QStringLiteral("main.js")),
          "a module syntax error was not faulted and logged to the console");

    // --- actions in the keymap ---
    const QString hello = QStringLiteral("plugin.fixture.hello");
    check(keys.command(hello).id == hello &&
              keys.command(hello).category == QStringLiteral("Fixture Plugin") &&
              keys.command(hello).context == keymap::Context::Global,
          "global action not registered under the plugin's name");
    check(keys.bindings(hello) ==
              QList<QKeySequence>{QKeySequence(QStringLiteral("Ctrl+Alt+Shift+F9"))},
          "action default binding not applied");
    check(keys.commands().size() == shippedCommands + 7 + exampleCommands,
          "dynamic commands not appended to the registry (expected 6 fixture + 1 runaway)");
    check(keys.bindings(QStringLiteral("plugin.fixture.conflict")).isEmpty() &&
              hasMessage(messages, QStringLiteral("fixture"), 1, QStringLiteral("already used by")),
          "a default that collides with a shipped roll binding was not dropped with a warning");
    check(keys.bindings(QStringLiteral("plugin.fixture.save")).isEmpty() &&
              hasMessage(messages, QStringLiteral("fixture"), 1, QStringLiteral("file.save_song")),
          "a default that collides with a shipped DEFAULT (currently rebound) was not dropped");
    check(keys.command(QStringLiteral("plugin.fixture.nope")).id.isEmpty(),
          "unknown command id did not report empty");
    check(host.runCommand(hello) &&
              storedCounter(QStringLiteral("fixture"), QStringLiteral("ran")) == 1,
          "runCommand did not run the action (storage counter)");
    check(!host.runCommand(QStringLiteral("plugin.fixture.nope")),
          "runCommand accepted an unknown id");
    QAction *helloAction = nullptr;
    for (QAction *a : actions()) {
        if (a->text() == QStringLiteral("Hello"))
            helloAction = a;
    }
    check(helloAction &&
              helloAction->shortcut() == QKeySequence(QStringLiteral("Ctrl+Alt+Shift+F9")),
          "global action has no window-level QAction with the binding");
    if (helloAction)
        helloAction->trigger();
    check(storedCounter(QStringLiteral("fixture"), QStringLiteral("ran")) == 2,
          "triggering the window QAction did not run the plugin action");

    // Editor-context actions dispatch through the key handler.
    QKeyEvent rollKey(QEvent::KeyPress, Qt::Key_F10,
                      Qt::ControlModifier | Qt::AltModifier | Qt::ShiftModifier);
    QKeyEvent rangeKey(QEvent::KeyPress, Qt::Key_F11,
                       Qt::ControlModifier | Qt::AltModifier | Qt::ShiftModifier);
    QKeyEvent otherKey(QEvent::KeyPress, Qt::Key_F10, Qt::ControlModifier);
    using keymap::Context;
    QKeyEvent velKey(QEvent::KeyPress, Qt::Key_F8,
                     Qt::ControlModifier | Qt::AltModifier | Qt::ShiftModifier);
    check(host.handleKey(&rollKey, Context::PianoRoll, false) &&
              storedCounter(QStringLiteral("fixture"), QStringLiteral("roll")) == 1,
          "roll-context action did not fire from the key handler");
    check(!host.handleKey(&otherKey, Context::PianoRoll, false),
          "key handler matched an unbound chord");
    check(!host.handleKey(&rollKey, Context::Velocity, false),
          "roll-context action fired from the velocity lane");
    check(!host.handleKey(&velKey, Context::PianoRoll, false),
          "velocity-context action fired from the piano roll");
    check(host.handleKey(&velKey, Context::Velocity, false) &&
              storedCounter(QStringLiteral("fixture"), QStringLiteral("vel")) == 1,
          "velocity-context action did not fire from the velocity lane");
    check(!host.handleKey(&rangeKey, Context::PianoRoll, false),
          "range-context action fired without a time selection");
    check(host.handleKey(&rangeKey, Context::Velocity, true) &&
              storedCounter(QStringLiteral("fixture"), QStringLiteral("range")) == 1,
          "range-context action did not fire inside a time selection");

    // The Shortcuts page lists the plugin's group.
    {
        auto *tree = settingsDialog()->shortcutsPage()->findChild<QTreeWidget *>();
        bool found = false;
        for (int i = 0; tree && i < tree->topLevelItemCount(); ++i) {
            QTreeWidgetItem *cat = tree->topLevelItem(i);
            for (int j = 0; j < cat->childCount(); ++j) {
                if (cat->child(j)->data(0, Qt::UserRole).toString() == hello)
                    found = cat->text(0) == QStringLiteral("Fixture Plugin");
            }
        }
        check(found, "Keyboard Shortcuts page does not list the plugin action under its group");
    }

    // --- console ---
    check(host.evalConsole(QStringLiteral("1 + 2")) == QStringLiteral("3"),
          "console did not evaluate 1 + 2");
    check(host.evalConsole(QStringLiteral("porydaw.plugin.id")) == QStringLiteral("console"),
          "console engine has no porydaw API");
    check(host.evalConsole(QStringLiteral("({a: 1})")).contains(QStringLiteral("\"a\": 1")),
          "console did not pretty-print an object");
    check(host.evalConsole(QStringLiteral("nope()")).isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("nope")),
          "console error was not logged");
    check(host.evalConsole(QStringLiteral("porydaw.song.loaded")) == QStringLiteral("false"),
          "song.loaded not false with no song");
    check(host.evalConsole(QStringLiteral("porydaw.actions.register({id: 'x', name: 'X', context: "
                                          "'bogus', run: function(){}})"))
                  .isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("context must be")),
          "bad action context did not throw a TypeError into the script");

    // --- disable / enable ---
    host.setEnabled(QStringLiteral("fixture"), false);
    check(fixture->state == scripting::PluginState::Disabled && !fixture->engine,
          "disabling did not unload the plugin");
    check(hasMessage(messages, QStringLiteral("fixture"), 0, QStringLiteral("deactivated")),
          "deactivate() did not run on disable");
    check(keys.command(hello).id.isEmpty() && !actions().contains(helloAction),
          "disabling left the plugin's command/QAction behind");
    check(QSettings().value(QStringLiteral("plugins/fixture/enabled")).toBool() == false,
          "disabled state not persisted");
    host.setEnabled(QStringLiteral("fixture"), true);
    check(fixture->state == scripting::PluginState::Loaded && keys.command(hello).id == hello,
          "re-enabling did not reload the plugin and its command");

    // --- hot reload keeps user rebinds ---
    keys.setBinding(hello, QKeySequence(QStringLiteral("Ctrl+Alt+Shift+F12")));
    messages.clear();
    check(writeFile(fixtureDir + QStringLiteral("/main.js"), QLatin1String(kFixtureMainV2)),
          "could not rewrite main.js");
    check(waitFor(
              [&] {
                  return hasMessage(messages, QStringLiteral("fixture"), 0,
                                    QStringLiteral("activated v2"));
              },
              4000),
          "editing main.js did not hot-reload the plugin");
    check(hasMessage(messages, QStringLiteral("fixture"), 0, QStringLiteral("deactivated")),
          "hot reload did not deactivate the old instance first");
    check(keys.command(QStringLiteral("plugin.fixture.hello2")).id ==
                  QStringLiteral("plugin.fixture.hello2") &&
              keys.command(QStringLiteral("plugin.fixture.roll")).id.isEmpty(),
          "hot reload did not swap the registered command set");
    check(keys.bindings(hello) ==
              QList<QKeySequence>{QKeySequence(QStringLiteral("Ctrl+Alt+Shift+F12"))},
          "user rebind of a plugin action did not survive the reload");
    keys.resetBinding(hello);

    // --- watchdog ---
    host.setWatchdogMs(200);
    QElapsedTimer clock;
    clock.start();
    check(host.runCommand(QStringLiteral("plugin.runaway.loop")) && clock.elapsed() < 5000,
          "runaway action was not interrupted");
    const scripting::Plugin *runaway = host.plugin(QStringLiteral("runaway"));
    check(runaway && runaway->state == scripting::PluginState::Error &&
              hasMessage(messages, QStringLiteral("runaway"), 2, QStringLiteral("stopped")),
          "watchdog interrupt did not fault the plugin");
    check(waitFor([&] { return !runaway->engine; }, 2000) &&
              keys.command(QStringLiteral("plugin.runaway.loop")).id.isEmpty(),
          "faulted plugin was not torn down (engine + commands)");
    check(fixture->state == scripting::PluginState::Loaded &&
              host.evalConsole(QStringLiteral("2 * 2")) == QStringLiteral("4"),
          "other engines were disturbed by the watchdog");
    host.setWatchdogMs(5000);

    // --- song half ---
    if (!projectRoot.isEmpty()) {
        if (!check(openProjectDir(projectRoot, /*interactive=*/false),
                   "could not open the project"))
            return false;
        loadSongByLabel(songLabel);
        if (!check(m_active != nullptr, "song did not load"))
            return false;
        SongDocument &doc = m_active->doc;
        check(host.evalConsole(QStringLiteral("porydaw.song.loaded")) == QStringLiteral("true"),
              "song.loaded not true after loading");
        check(host.evalConsole(QStringLiteral("porydaw.song.label")) == songLabel,
              "song.label wrong");
        check(host.evalConsole(QStringLiteral("porydaw.song.tracks().length")).toInt() ==
                  doc.engineTrackCount(),
              "song.tracks() count differs from the document");
        check(host.evalConsole(QStringLiteral("porydaw.song.ticksPerBeat")).toInt() ==
                  int(doc.smf().division),
              "song.ticksPerBeat differs from the SMF division");
        int total = 0;
        for (int t = 0; t < doc.engineTrackCount(); ++t)
            total += int(doc.notesForTrack(t).size());
        check(host.evalConsole(QStringLiteral("porydaw.song.notes().length")).toInt() == total &&
                  total > 0,
              "song.notes() count differs from the document");
        check(host.evalConsole(QStringLiteral(
                  "porydaw.song.notes({track: 0, from: 0, to: 1}).every(function(n){ return n.tick "
                  "=== 0 && n.track === 0; })")) == QStringLiteral("true"),
              "song.notes() range/track filter wrong");
        check(host.evalConsole(QStringLiteral(
                  "var n0 = porydaw.song.notes()[0]; porydaw.song.note(n0.id).tick === n0.tick && "
                  "porydaw.song.note(-5) === null")) == QStringLiteral("true"),
              "song.note(id) round trip failed");
        check(host.evalConsole(QStringLiteral("porydaw.project.songs().some(function(s){ return "
                                              "s.label === porydaw.song.label; })")) ==
                  QStringLiteral("true"),
              "project.songs() does not list the loaded song");
        // Selection round trip, then a document edit observed by a listener.
        check(host.evalConsole(QStringLiteral(
                  "porydaw.selection.setNotes(porydaw.song.notes({track: 0}).slice(0, 2)); "
                  "porydaw.selection.notes().length")) == QStringLiteral("2"),
              "selection.setNotes/notes round trip failed");
        check(m_active->view->selection().size() == 2 && m_active->view->selectedTrack() == 0,
              "selection.setNotes did not reach the view");
        host.evalConsole(QStringLiteral("porydaw.cursor.set(1e30)"));
        check(m_active->view->editCursorTick() <= (1ull << 40),
              "cursor.set did not clamp a wild tick");
        host.evalConsole(QStringLiteral("porydaw.cursor.set(NaN)"));
        check(m_active->view->editCursorTick() == 0 &&
                  host.evalConsole(QStringLiteral("porydaw.song.note(NaN)")) ==
                      QStringLiteral("null"),
              "NaN tick/id did not read as 0 / null");
        host.evalConsole(QStringLiteral("porydaw.cursor.set(96)"));
        check(m_active->view->editCursorTick() == 96 &&
                  host.evalConsole(QStringLiteral("porydaw.cursor.tick")) == QStringLiteral("96"),
              "cursor.set did not move the edit cursor");
        check(host.evalConsole(QStringLiteral("porydaw.cursor.grid(96).beatTicks")).toInt() > 0,
              "cursor.grid reports no beat ticks");
        host.evalConsole(QStringLiteral("porydaw.song.on('changed', function (e) { "
                                        "porydaw.storage.set('rev', e.revision); })"));
        const uint64_t before = doc.revision();
        doc.setStartTempo(doc.startTempo() == 120 ? 121 : 120);
        check(doc.revision() > before &&
                  storedCounter(QStringLiteral("console"), QStringLiteral("rev")) ==
                      int(doc.revision()),
              "song.changed listener did not see the new revision");
        doc.undoStack()->undo();
        check(storedCounter(QStringLiteral("console"), QStringLiteral("rev")) ==
                  int(doc.revision()),
              "song.changed listener did not fire on undo");
        // Transport through the bindings.
        if (m_audioOk) {
            host.evalConsole(QStringLiteral("porydaw.transport.on('state', function (e) { "
                                            "porydaw.storage.set('tstate', e.state); })"));
            host.evalConsole(QStringLiteral("porydaw.transport.play()"));
            check(host.evalConsole(QStringLiteral("porydaw.transport.state")) ==
                      QStringLiteral("playing"),
                  "transport.play() did not start playback");
            host.tick();
            check(QSettings()
                      .value(QStringLiteral("plugins/console/data/tstate"))
                      .toByteArray()
                      .contains("playing"),
                  "transport.state event did not fire on play");
            host.evalConsole(QStringLiteral("porydaw.transport.stop()"));
            check(host.evalConsole(QStringLiteral("porydaw.transport.state")) ==
                      QStringLiteral("stopped"),
                  "transport.stop() did not stop playback");
        }
        // Switching to no song drops the API's view.
        activateSession(nullptr);
        check(host.evalConsole(QStringLiteral("porydaw.song.loaded")) == QStringLiteral("false"),
              "song.loaded stayed true after the session went away");
    }

    host.unloadAll();
    check(keys.commands().size() == shippedCommands, "unloadAll left dynamic commands behind");
    disconnect(&host, nullptr, this, nullptr);
    return failures == 0;
}

int runScriptCheck(const QString &projectRoot, const QString &songLabel)
{
    int failures = runEngineCheck();

    QTemporaryDir settingsDir;
    QTemporaryDir pluginsDir;
    if (!settingsDir.isValid() || !pluginsDir.isValid()) {
        std::fprintf(stderr, "scriptcheck: no temp dir\n");
        return 1;
    }
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
    {
        MainWindow window;
        window.show();
        if (!window.runScriptHostCheck(pluginsDir.path(), projectRoot, songLabel))
            failures++;
    }

    if (failures) {
        std::fprintf(stderr, "scriptcheck: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("scriptcheck: PASS (Qt %s%s)\n", qVersion(),
                projectRoot.isEmpty() ? ", no project" : "");
    return 0;
}

#include "scriptcheck.moc"
