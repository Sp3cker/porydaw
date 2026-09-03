#include <QAction>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCoreApplication>
#include <QDeadlineTimer>
#include <QDir>
#include <QDockWidget>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJSEngine>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QLabel>
#include <QMenu>
#include <QMouseEvent>
#include <QObject>
#include <QPushButton>
#include <QSettings>
#include <QSlider>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QThread>
#include <QTreeWidget>
#include <QUndoStack>
#include <QWheelEvent>
#include <functional>

#include "audio/audiotap.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "scripting/scripthost.h"
#include "scripting/scriptwidgets.h"
#include "songsession.h"
#include "ui/keyboardshortcutspage.h"
#include "ui/keymap.h"
#include "ui/settingsdialog.h"
#include "ui/songview.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

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
    porydaw.actions.register({ id: "esc", name: "Steals Escape", context: "roll",
        default: "Escape", run: function () {} });
    porydaw.song.on("changed", function (e) { porydaw.storage.set("rev", e.revision); });
    porydaw.log("activated v1 " + ctx.id + " " + porydaw.plugin.version);
}
export function deactivate() { porydaw.log("deactivated"); }
)";

// v2 (hot reload): keeps "hello", adds "hello2", drops the rest. Its
// song.changed listener tries to open a transaction from inside the
// notification (refused: the stack may be mid-undo) and records the error.
const char *kFixtureMainV2 = R"(
export function activate(ctx) {
    porydaw.actions.register({ id: "hello", name: "Hello", context: "global",
        default: "Ctrl+Alt+Shift+F9", run: function () {} });
    porydaw.actions.register({ id: "hello2", name: "Hello Two", context: "global",
        run: function () {} });
    porydaw.song.on("changed", function () {
        try { porydaw.edit.transaction("Steal", function () {}); }
        catch (e) { porydaw.storage.set("stealErr", String(e.message)); }
    });
    porydaw.log("activated v2");
}
)";

// Injected into the Script Console engine as `harness`: an edit made by
// C++ while a script transaction is open (what a user-driven nested event
// loop would do), to trip the revision guard.
class HarnessBridge : public QObject
{
    Q_OBJECT
  public:
    SongDocument *doc = nullptr;
    Q_INVOKABLE void externalEdit() { doc->setStartTempo(doc->startTempo() + 1); }
};

const char *kBrokenManifest = R"({ "id": "broken", "name": "Broken", "api": 1 })";
const char *kBrokenMain =
    "export function activate() {\n  var x = 1;\n  throw new Error('boom');\n}\n";
const char *kBadManifest = R"({ "id": "badmanifest", "name": "Future", "api": 99 })";
const char *kSyntaxManifest = R"({ "id": "syntax", "name": "Syntax", "api": 1 })";
const char *kSyntaxMain = "export function activate() {\n  return (;\n}\n";
// Phase 3: a dock built from every widget primitive, plus an image.
const char *kPanelManifest = R"({ "id": "panel", "name": "Panel", "version": "1.0.0", "api": 1 })";
const char *kPanelMain = R"(
var dock = null, img = 0;
function count(key) { porydaw.storage.set(key, porydaw.storage.get(key, 0) + 1); }
export function activate() {
    img = porydaw.ui.loadImage("pic.png");
    porydaw.storage.set("imgw", porydaw.ui.imageSize(img).width);
    dock = porydaw.ui.dock({ id: "main", title: "Panel", area: "left", build: function (root) {
        var row = root.addRow();
        row.addLabel("hello");
        row.addButton("Go", function () { count("clicks"); });
        root.addCheckbox("On", false, function (on) { porydaw.storage.set("checked", on ? 1 : 0); });
        root.addSlider(0, 100, 50, function (v) { porydaw.storage.set("slider", v); }, {});
        root.addCombo(["a", "b", "c"], 1, function (i) { porydaw.storage.set("combo", i); });
        root.addCanvas({ minHeight: 40 }, function (g) {
            g.clear("#000000");
            g.image(img, 0, 0, -1, -1, 0, 0, 0, 0);
            count("panelpaints");
        }, null);
        root.addStretch();
    }});
}
export function deactivate() { dock.close(); porydaw.ui.freeImage(img); }
)";
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

// ---- Phase 2: edit transactions ----

using Check = std::function<bool(bool, const char *)>;

void runEditChecks(const Check &check, scripting::ScriptHost &host, SongSession &session,
                   QList<Message> &messages, bool haveExamples)
{
    SongDocument &doc = session.doc;
    SongView &view = *session.view;
    QUndoStack &undo = *doc.undoStack();
    const auto run = [&](const char *code) { return host.evalConsole(QLatin1String(code)); };
    // The caller left a redo entry (tempo edit + undo); park the stack at
    // its top so "no entry" means count == index.
    while (undo.canRedo())
        undo.redo();
    const QByteArray base = doc.smf().write();
    const int index0 = undo.index();
    // Snapshot of the stack (count, index) that "untouched" compares to:
    // taken at the start and after every oneEntryThenUndo, whose undo
    // legitimately leaves a redo entry behind.
    int snapCount = undo.count();
    int snapIndex = undo.index();
    const auto mark = [&] {
        snapCount = undo.count();
        snapIndex = undo.index();
    };
    // One undo entry sits on top of index0, named `name`, and undoing it
    // restores the file byte for byte (leaving the stack at index0).
    const auto oneEntryThenUndo = [&](const char *name, const char *what) {
        bool ok = undo.count() == index0 + 1 && undo.index() == index0 + 1 &&
                  undo.text(index0) == QLatin1String(name);
        check(ok, what);
        undo.undo();
        ok = doc.smf().write() == base && undo.index() == index0;
        check(ok, "undo of a script transaction did not restore the SMF byte for byte");
        mark();
        return ok;
    };
    // The stack is exactly as before: no entry, no redo, same bytes.
    const auto untouched = [&](const char *what) {
        check(undo.count() == snapCount && undo.index() == snapIndex && doc.smf().write() == base,
              what);
    };
    // A transaction that pushed edits and was then rolled back: bytes as
    // before, no entry of its own and no redo (its pushes cleared any
    // earlier redo entry, like every edit does).
    const auto rolledBack = [&](const char *what) {
        check(undo.count() == index0 && undo.index() == index0 && doc.smf().write() == base, what);
        mark();
    };

    // Outside a transaction every edit is refused.
    check(run("porydaw.edit.addNotes(0, [{tick: 0, key: 60, len: 24, vel: 100}])").isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2,
                         QStringLiteral("inside porydaw.edit.transaction")),
          "edit.addNotes outside a transaction was not refused");
    untouched("a refused edit touched the document");
    check(run("porydaw.edit.active") == QStringLiteral("false"), "edit.active true at rest");

    // Several edits, one entry; ids come back and re-resolve; the
    // transaction returns fn's value.
    check(run("var ids = porydaw.edit.transaction('T1', function () {"
              "  if (!porydaw.edit.active) throw new Error('not active');"
              "  var ids = porydaw.edit.addNotes(0, [{tick: 0, key: 60, len: 24, vel: 100},"
              "                                      {tick: 48, key: 62, len: 24, vel: 90}]);"
              "  porydaw.edit.moveNotes(ids, 24, 1);"
              "  porydaw.edit.setVelocity(ids[1], 77);"
              "  porydaw.edit.resizeNotes(ids, 12);"
              "  return ids; });"
              "var a = porydaw.song.note(ids[0]), b = porydaw.song.note(ids[1]);"
              "ids.length === 2 && a.tick === 24 && a.key === 61 && a.len === 36 && a.vel === 100"
              " && b.tick === 72 && b.key === 63 && b.vel === 77 && b.len === 36") ==
              QStringLiteral("true"),
          "edit.addNotes/moveNotes/setVelocity/resizeNotes did not land as expected");
    oneEntryThenUndo("T1", "a transaction with four edits is not exactly one undo entry");

    // A transaction that edits nothing leaves nothing — the redo list
    // included: with an entry undone, a no-op or failed transaction must
    // not clear it (the macro opens lazily, on the first push).
    run("porydaw.edit.transaction('Nothing', function () {})");
    untouched("an empty transaction left an undo entry");
    run("porydaw.edit.transaction('Redo bait', function () {"
        "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]); })");
    undo.undo();
    check(undo.canRedo(), "undo left nothing to redo");
    run("porydaw.edit.transaction('Nothing', function () {})");
    check(run("porydaw.edit.transaction('Fails', function () { throw new Error('x'); })").isNull(),
          "a throwing no-op transaction did not propagate");
    check(undo.canRedo() && undo.count() == index0 + 1 && undo.index() == index0,
          "a no-op / failed transaction discarded the user's redo entry");
    // A transaction that does push clears the redo entry like any edit.
    check(run("porydaw.edit.transaction('Fresh', function () {"
              "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]); }); 'ok'") ==
              QStringLiteral("ok"),
          "transaction after a redo entry failed");
    oneEntryThenUndo("Fresh", "a transaction pushed over a redo entry is not one entry");

    // An exception mid-transaction rolls everything back — no entry, no redo.
    check(run("porydaw.edit.transaction('Boom', function () {"
              "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]);"
              "  throw new Error('boom2'); })")
                  .isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("boom2")),
          "exception inside a transaction did not propagate");
    rolledBack("an exception mid-transaction did not roll the document back");
    check(run("porydaw.edit.active") == QStringLiteral("false"),
          "edit.active stayed true after a rollback");

    // Nested transactions flatten into the outer entry.
    run("porydaw.edit.transaction('Outer', function () {"
        "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]);"
        "  porydaw.edit.transaction('Inner', function () {"
        "    porydaw.edit.addNotes(0, [{tick: 0, key: 62, len: 24, vel: 100}]); }); })");
    oneEntryThenUndo("Outer", "nested transactions did not flatten into one entry");

    // A refused inner edit that the script swallows still aborts the whole
    // transaction at commit.
    check(run("porydaw.edit.transaction('Swallow', function () {"
              "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]);"
              "  try { porydaw.edit.transaction('In', function () { throw new Error('x'); }); }"
              "  catch (e) {} })")
                  .isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("rolled back")),
          "a swallowed inner failure did not abort the outer transaction");
    rolledBack("a swallowed inner failure left edits behind");

    // Revision guard: a foreign edit while the transaction is open.
    HarnessBridge bridge;
    bridge.doc = &doc;
    const scripting::Plugin *console = host.plugin(QStringLiteral("console"));
    if (check(console && console->engine, "console plugin not reachable for the bridge")) {
        QJSEngine::setObjectOwnership(&bridge, QJSEngine::CppOwnership);
        console->engine->globalObject().setProperty(QStringLiteral("harness"),
                                                    console->engine->newQObject(&bridge));
        check(run("porydaw.edit.transaction('Guard', function () {"
                  "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]);"
                  "  harness.externalEdit();"
                  "  porydaw.edit.addNotes(0, [{tick: 0, key: 62, len: 24, vel: 100}]); })")
                      .isNull() &&
                  hasMessage(messages, QStringLiteral("console"), 2,
                             QStringLiteral("changed outside the transaction")),
              "a foreign edit during a transaction did not trip the revision guard");
        rolledBack("the revision-guard rollback did not restore the document");
        // ...and one that lands after the last script edit trips it at commit.
        check(run("porydaw.edit.transaction('Guard2', function () {"
                  "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]);"
                  "  harness.externalEdit(); })")
                  .isNull(),
              "a foreign edit after the last script edit did not fail the commit");
        rolledBack("the commit-time guard rollback did not restore the document");
        console->engine->globalObject().deleteProperty(QStringLiteral("harness"));
    }

    // Re-entrancy: a song.changed listener editing back during the edit
    // that woke it is refused (the transaction itself is fine), and one
    // opening its own transaction from the notification is refused too.
    run("var offRe = porydaw.song.on('changed', function () {"
        "  porydaw.edit.addNotes(0, [{tick: 0, key: 70, len: 1, vel: 1}]); })");
    QSettings().remove(QStringLiteral("plugins/fixture/data/stealErr"));
    run("porydaw.edit.transaction('Reenter', function () {"
        "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]); })");
    check(hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("re-entered")),
          "a listener editing during an edit was not refused");
    check(QSettings()
              .value(QStringLiteral("plugins/fixture/data/stealErr"))
              .toByteArray()
              .contains("song.changed listener"),
          "another plugin opening a transaction from song.changed was not refused");
    check(run("porydaw.song.notes({track: 0, from: 0, to: 1}).some(function (n) { "
              "return n.key === 70 && n.len === 1 && n.vel === 1; })") == QStringLiteral("false"),
          "the refused listener edit landed anyway");
    oneEntryThenUndo("Reenter", "the listener's refused edit disturbed the transaction");
    run("offRe()");

    // Selection ops through the transaction; view/time-selection state.
    check(run("var sel = porydaw.song.notes({track: 0}).slice(0, 2);"
              "porydaw.selection.setNotes(sel);"
              "porydaw.edit.transaction('Up', function () {"
              "  if (!porydaw.edit.transposeSelection(2)) throw new Error('no move'); });"
              "porydaw.selection.notes().every(function (n, i) { return n.key === sel[i].key + 2 "
              "&& n.id === sel[i].id; })") == QStringLiteral("true"),
          "edit.transposeSelection did not move the selected notes (ids kept)");
    oneEntryThenUndo("Up", "edit.transposeSelection is not one undo entry");
    check(run("porydaw.selection.setTime({start: 0, end: 96}); porydaw.selection.time().end") ==
                  QStringLiteral("96") &&
              view.timeSelection().active() && view.timeSelection().endTick == 96,
          "selection.setTime did not reach the view");
    run("porydaw.selection.clearTime()");
    check(!view.timeSelection().active(), "selection.clearTime left the selection");
    check(run("porydaw.selection.setTime({start: 10, end: 5})").isNull(),
          "selection.setTime accepted an empty span");
    check(run("porydaw.view.velocityLane = true; porydaw.view.velocityLane") ==
                  QStringLiteral("true") &&
              view.velocityLaneVisible(),
          "view.velocityLane setter did not reach the view");
    check(run("var vt = porydaw.view.visibleTicks(); vt.to > vt.from") == QStringLiteral("true"),
          "view.visibleTicks is not a span");
    check(run("var mid = Math.floor(porydaw.song.endTick / 2); porydaw.view.revealTick(mid);"
              "var vt2 = porydaw.view.visibleTicks(); vt2.from <= mid && mid <= vt2.to") ==
              QStringLiteral("true"),
          "view.revealTick did not scroll the tick into view");
    run("porydaw.view.revealTick(0)");

    // The rest of the surface in one transaction; undo restores the bytes.
    check(run("porydaw.edit.transaction('Sink', function () {"
              "  var e = porydaw.edit, CC = porydaw.song.CC;"
              "  e.addLanePoint(0, 7, 96, 100);"
              "  e.writeLanePoints(0, 10, 0, 192, [{tick: 0, value: 10}, {tick: 192, value: 120}]);"
              "  e.moveLanePoints(0, 10, [{tick: 192, newTick: 144, newValue: 64}]);"
              "  if (e.deleteLanePoints(0, 7, [96]) !== 1) throw new Error('del');"
              "  e.addLanePoint(-1, CC.TEMPO, 480, 150);"
              "  e.setStartTempo(99);"
              "  e.setLoop(96, 960);"
              "  e.setTimeSig(384, 3, 4);"
              "  var t = e.addTrack(5); if (t < 0) throw new Error('addTrack');"
              "  e.renameTrack(t, 'Scripted');"
              "  if (!e.insertTimeRange(0, 96, {tracks: [0]})) throw new Error('insert');"
              "  if (!e.removeTimeRange(0, 96, {tracks: [0]})) throw new Error('remove');"
              "  e.deleteTrack(t); }); 'ok'") == QStringLiteral("ok"),
          "the kitchen-sink transaction threw");
    check(run("var p10 = porydaw.song.lanePoints(0, 10, {from: 0, to: 193}); p10.length === 2 && "
              "p10[0].tick === 0 && p10[0].value === 10 && p10[1].tick === 144 && "
              "p10[1].value === 64") == QStringLiteral("true"),
          "writeLanePoints/moveLanePoints did not land as expected");
    check(run("porydaw.song.lanePoints(0, 7, {from: 96, to: 97}).length") == QStringLiteral("0"),
          "addLanePoint + deleteLanePoints did not cancel out");
    check(run("porydaw.song.startTempo === 99 && porydaw.song.lanePoints(-1, "
              "porydaw.song.CC.TEMPO).some(function (p) { return p.tick === 480 && "
              "p.value === 150; })") == QStringLiteral("true"),
          "setStartTempo / tempo addLanePoint did not land");
    check(run("porydaw.song.loop().start === 96 && porydaw.song.loop().end === 960") ==
              QStringLiteral("true"),
          "setLoop did not land");
    check(run("porydaw.song.timeSigs().some(function (s) { return s.tick === 384 && "
              "s.numerator === 3 && s.denominator === 4; })") == QStringLiteral("true"),
          "setTimeSig did not land");
    oneEntryThenUndo("Sink", "the kitchen-sink transaction is not one undo entry");
    check(run("porydaw.edit.transaction('Bad', function () { porydaw.edit.addNotes(99, []); })")
                  .isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("no such track")),
          "edit.addNotes with a bad track was not refused");
    untouched("a refused structural edit left an entry");
    // Argument hygiene: a missing track or a non-object note must throw,
    // not coerce to track 0 / an empty note.
    check(run("porydaw.edit.transaction('Undef', function () { porydaw.edit.deleteTrack(); })")
                  .isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2,
                         QStringLiteral("track must be an integer")),
          "edit.deleteTrack() with no track was not refused");
    check(
        run("porydaw.edit.transaction('Undef2', function () { porydaw.edit.addNotes(0); })")
                .isNull() &&
            hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("must be an object")),
        "edit.addNotes with a non-object note was not refused");
    check(run("porydaw.edit.transaction('Undef3', function () { "
              "porydaw.edit.removeTimeRange(0, 96, {tracks: [undefined]}); })")
              .isNull(),
          "scope.tracks with undefined was not refused");
    untouched("refused argument-hygiene edits left an entry");
    // Two batch entries on one (tick, key): the later wins, the earlier
    // reports id 0.
    check(run("var dup = porydaw.edit.transaction('Dup', function () { return "
              "porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}, "
              "{tick: 0, key: 61, len: 48, vel: 100}]); }); "
              "dup[0] === 0 && dup[1] > 0 && porydaw.song.note(dup[1]).len === 48") ==
              QStringLiteral("true"),
          "duplicate (tick, key) entries in addNotes did not resolve last-wins");
    oneEntryThenUndo("Dup", "the duplicate addNotes transaction is not one entry");
    // selection.setNotes takes one note as well as a list.
    check(run("var one = porydaw.song.notes({track: 0})[0]; porydaw.selection.setNotes(one); "
              "porydaw.selection.notes().length === 1 && porydaw.selection.notes()[0].id === "
              "one.id") == QStringLiteral("true"),
          "selection.setNotes with a single note cleared the selection");

    // Watchdog inside a transaction: the interrupt can't run the script's
    // catch, so the host rolls the open transaction back itself.
    host.setWatchdogMs(200);
    messages.clear();
    run("porydaw.edit.transaction('Runaway', function () {"
        "  porydaw.edit.addNotes(0, [{tick: 0, key: 61, len: 24, vel: 100}]);"
        "  while (true) {} })");
    check(hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("stopped")) &&
              !host.transaction().open(),
          "an interrupted transaction was not closed");
    check(!hasMessage(messages, QStringLiteral("console"), 2, QStringLiteral("Interrupted")),
          "the rollback fanned song.changed into the interrupted engine");
    rolledBack("an interrupted transaction left its edits or an undo entry");
    check(waitFor([&] { return !console || !console->engine; }, 2000),
          "faulted console engine was not torn down");
    host.setWatchdogMs(5000);
    check(run("porydaw.song.loaded") == QStringLiteral("true") && console &&
              console->state == scripting::PluginState::Loaded,
          "console did not come back after the fault");

    // Bundled Note Tools: each command is one undo entry that undoes clean.
    // A setup transaction adds a track with four notes to work on (the
    // fourth off the grid), so the checks don't depend on the song.
    if (haveExamples) {
        const auto tool = [&](const char *id) {
            return host.runCommand(QStringLiteral("plugin.note-tools.") + QLatin1String(id));
        };
        check(
            run("var st = porydaw.edit.transaction('Setup', function () {"
                "  var t = porydaw.edit.addTrack(0); if (t < 0) throw new Error('no track');"
                "  return {track: t, ids: porydaw.edit.addNotes(t, ["
                "    {tick: 0, key: 60, len: 12, vel: 100}, {tick: 48, key: 62, len: 12, vel: 100},"
                "    {tick: 96, key: 64, len: 12, vel: 100}, {tick: 145, key: 65, len: 12, vel: "
                "100}"
                "  ])}; }); st.ids.length") == QStringLiteral("4") &&
                undo.count() == index0 + 1,
            "note-tools setup transaction failed");
        const int setup = index0 + 1;
        const auto toolEntryThenUndo = [&](const char *id, const char *name, const char *what) {
            run("porydaw.selection.setNotes(st.ids)");
            check(tool(id) && undo.count() == setup + 1 && undo.index() == setup + 1 &&
                      undo.text(setup) == QLatin1String(name),
                  what);
            const bool ok = check(
                hasMessage(messages, QStringLiteral("note-tools"), 2, QStringLiteral("")) == false,
                "a note-tools command logged an error");
            undo.undo();
            check(undo.index() == setup, "undo after a note-tools command did not step back");
            return ok;
        };
        messages.clear();
        run("porydaw.selection.setNotes(st.ids)");
        check(tool("legato") && undo.count() == setup + 1 &&
                  undo.text(setup) == QLatin1String("Legato") &&
                  run("porydaw.song.note(st.ids[0]).len === 48 && "
                      "porydaw.song.note(st.ids[2]).len === 49 && "
                      "porydaw.song.note(st.ids[3]).len === 12") == QStringLiteral("true"),
              "legato did not stretch each note to the next start as one undo entry");
        undo.undo();
        toolEntryThenUndo("humanize", "Humanize velocities", "humanize is not one undo entry");
        run("porydaw.selection.setNotes(st.ids)");
        check(tool("quantize") && undo.count() == setup + 1 &&
                  undo.text(setup) == QLatin1String("Quantize to grid") &&
                  run("porydaw.song.note(st.ids[3]).tick") == QStringLiteral("144"),
              "quantize did not snap the off-grid note as one undo entry");
        undo.undo();
        // Insert a chord at the cursor, then strum it.
        run("porydaw.selection.selectTrack(st.track); porydaw.selection.clear(); "
            "porydaw.cursor.set(192)");
        check(tool("chord") && undo.count() == setup + 1 &&
                  undo.text(setup) == QLatin1String("Insert chord") &&
                  run("var ch = porydaw.selection.notes(); ch.length === 3 && "
                      "ch.every(function (n) { return n.tick === 192; }) && "
                      "ch.map(function (n) { return n.key; }).sort().join() === '60,64,67'") ==
                      QStringLiteral("true"),
              "insert chord did not add a selected triad as one undo entry");
        check(tool("strum") && undo.count() == setup + 2 &&
                  undo.text(setup + 1) == QLatin1String("Strum") &&
                  run("var c = porydaw.selection.notes(); c.length === 3 && "
                      "c.every(function (n) { return n.key === 60 ? n.tick === 192 : "
                      "n.tick > 192 && n.tick + n.len === 192 + ch[0].len; })") ==
                      QStringLiteral("true"),
              "strum did not stagger the chord (ends kept) as one undo entry");
        check(!hasMessage(messages, QStringLiteral("note-tools"), 2, QStringLiteral("")),
              "a note-tools command logged an error");
        undo.undo();
        undo.undo();
        undo.undo();
        check(doc.smf().write() == base && undo.index() == index0,
              "undoing the note-tools runs + setup did not restore the SMF");
    }
    run("porydaw.selection.clear()");
}

} // namespace

namespace {

// ---- Phase 3: docks, canvas, images ----

int countMessages(const QList<Message> &messages, const QString &plugin, const QString &fragment)
{
    int n = 0;
    for (const Message &m : messages) {
        if (m.plugin == plugin && m.text.contains(fragment))
            n++;
    }
    return n;
}

void clickCanvas(QWidget *canvas, const QPoint &pos)
{
    QMouseEvent press(QEvent::MouseButtonPress, QPointF(pos), QPointF(canvas->mapToGlobal(pos)),
                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(canvas, &press);
    QMouseEvent release(QEvent::MouseButtonRelease, QPointF(pos), QPointF(canvas->mapToGlobal(pos)),
                        Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(canvas, &release);
}

void runPanelChecks(const Check &check, scripting::ScriptHost &host, MainWindow &window,
                    QList<Message> &messages, QMenu *panelsMenu)
{
    const scripting::Plugin *panel = host.plugin(QStringLiteral("panel"));
    if (!check(panel && panel->state == scripting::PluginState::Loaded,
               "panel fixture plugin did not load"))
        return;
    const QString dockName = QStringLiteral("plugin.panel.main");
    QPointer<QDockWidget> dock = window.findChild<QDockWidget *>(dockName);
    if (!check(dock && panel->docks.size() == 1 && panel->docks.front() == dock,
               "ui.dock did not create the panel's dock on the window"))
        return;
    check(window.dockWidgetArea(dock) == Qt::LeftDockWidgetArea && !dock->isHidden(),
          "panel dock did not land in the requested area, shown");
    check(dock->windowTitle() == QStringLiteral("Panel") && dock->titleBarWidget() &&
              dock->titleBarWidget()->inherits("QLabel"),
          "panel dock did not get its title strip");
    check(panelsMenu && panelsMenu->menuAction()->isVisible() &&
              panelsMenu->actions().contains(dock->toggleViewAction()),
          "View → Plugin Panels did not list the dock");
    check(storedCounter(QStringLiteral("panel"), QStringLiteral("imgw")) == 16,
          "ui.loadImage/imageSize did not decode the plugin's image");

    // Every widget primitive is a real QWidget under the dock, and its
    // callback reaches the script.
    // (Searched under the body: the title strip is a QLabel too.)
    QWidget *body = dock->widget();
    auto *label = body->findChild<QLabel *>();
    auto *button = body->findChild<QPushButton *>();
    auto *box = body->findChild<QCheckBox *>();
    auto *slider = body->findChild<QSlider *>();
    auto *combo = body->findChild<QComboBox *>();
    auto *canvas = body->findChild<scripting::CanvasWidget *>();
    if (!check(label && button && box && slider && combo && canvas,
               "build(root) did not create every widget primitive"))
        return;
    check(label->text() == QStringLiteral("hello") && button->text() == QStringLiteral("Go") &&
              combo->count() == 3 && combo->currentIndex() == 1 && slider->value() == 50,
          "widget primitives did not take their initial arguments");
    check(button->focusPolicy() == Qt::NoFocus && canvas->focusPolicy() == Qt::NoFocus,
          "plugin widgets may take keyboard focus away from the roll");
    button->click();
    check(storedCounter(QStringLiteral("panel"), QStringLiteral("clicks")) == 1,
          "button onClick did not reach the script");
    box->setChecked(true);
    check(storedCounter(QStringLiteral("panel"), QStringLiteral("checked")) == 1,
          "checkbox onChange did not reach the script");
    slider->setValue(70);
    check(storedCounter(QStringLiteral("panel"), QStringLiteral("slider")) == 70,
          "slider onChange did not reach the script");
    combo->setCurrentIndex(2);
    check(storedCounter(QStringLiteral("panel"), QStringLiteral("combo")) == 2,
          "combo onChange did not reach the script");
    // The canvas painted the plugin's image at its natural size.
    canvas->resize(64, 48);
    const QImage shot = canvas->grab().toImage();
    check(storedCounter(QStringLiteral("panel"), QStringLiteral("panelpaints")) >= 1 &&
              canvas->paintCount() >= 1 && canvas->errorCount() == 0,
          "canvas paint(g) did not run");
    check(shot.pixelColor(2, 2) == QColor(255, 0, 0) && shot.pixelColor(40, 20) == QColor(0, 0, 0),
          "g.image/g.clear did not paint what the script asked");

    // Dock placement survives a reload through the window state: move
    // it, save, unload (dock gone), restore, reload — it comes back on
    // the right.
    window.addDockWidget(Qt::RightDockWidgetArea, dock);
    const QByteArray state = window.saveState();
    const int menuEntries = panelsMenu->actions().size();
    host.setEnabled(QStringLiteral("panel"), false);
    QApplication::processEvents();
    check(dock.isNull() && !window.findChild<QDockWidget *>(dockName),
          "unloading the plugin did not delete its dock");
    check(panelsMenu->actions().size() == menuEntries - 1,
          "View → Plugin Panels kept the unloaded plugin's entry");
    window.restoreState(state);
    host.setEnabled(QStringLiteral("panel"), true);
    dock = window.findChild<QDockWidget *>(dockName);
    check(dock && window.dockWidgetArea(dock) == Qt::RightDockWidgetArea && !dock->isHidden(),
          "a reloaded plugin's dock did not restore its saved placement, shown");
    // A dock the user closed stays closed across a reload (and, through
    // the same setting, across restarts); reopening it is remembered too.
    // (trigger() is the user's click; setChecked() would be programmatic.)
    dock->toggleViewAction()->trigger();
    check(dock->isHidden(), "the toggle action did not close the dock");
    host.reload(QStringLiteral("panel"));
    dock = window.findChild<QDockWidget *>(dockName);
    check(dock && dock->isHidden(), "a closed plugin dock reopened on reload");
    dock->toggleViewAction()->trigger();
    host.reload(QStringLiteral("panel"));
    dock = window.findChild<QDockWidget *>(dockName);
    check(dock && !dock->isHidden(), "a reopened plugin dock did not stay open on reload");
    // The dock's own close button counts too; a script's hide() does not.
    dock->close();
    host.reload(QStringLiteral("panel"));
    dock = window.findChild<QDockWidget *>(dockName);
    check(dock && dock->isHidden(), "the dock's close button was not remembered");
    dock->toggleViewAction()->trigger();
    check(!dock->isHidden(), "reopening from the menu did not show the dock");
    dock->hide();
    host.reload(QStringLiteral("panel"));
    dock = window.findChild<QDockWidget *>(dockName);
    check(dock && !dock->isHidden(), "a programmatic hide was mistaken for a user close");
    check(!hasMessage(messages, QStringLiteral("panel"), 2, QStringLiteral("")),
          "the panel fixture logged an error");
}

void runDockChecks(const Check &check, scripting::ScriptHost &host, MainWindow &window,
                   QList<Message> &messages)
{
    // Console-built dock: pixel probe, `g` outside paint, mouse, closing.
    host.evalConsole(QStringLiteral("var G = null;"));
    check(!host.evalConsole(QStringLiteral(
                                "var meter = porydaw.ui.dock({id: 'meter', title: 'Meter', "
                                "area: 'left', minWidth: 40, minHeight: 40, paint: function (g) "
                                "{ porydaw.storage.set('paints', porydaw.storage.get('paints', 0) "
                                "+ 1); g.clear('#000000'); g.fillRect(0, 0, 10, 10, 'red'); "
                                "g.text(2, 30, 'hi', 'white', {}); G = g; }, mouse: function (ev) "
                                "{ porydaw.storage.set('mouse', ev.type + ':' + ev.x + ':' + "
                                "ev.button); }}); meter.id"))
               .isNull(),
          "ui.dock with a paint callback threw");
    QPointer<QDockWidget> dock =
        window.findChild<QDockWidget *>(QStringLiteral("plugin.console.meter"));
    if (!check(dock && window.dockWidgetArea(dock) == Qt::LeftDockWidgetArea,
               "console dock was not created on the left"))
        return;
    auto *canvas = dock->findChild<scripting::CanvasWidget *>();
    if (!check(canvas, "single-paint dock has no canvas"))
        return;
    canvas->resize(48, 48);
    const QImage shot = canvas->grab().toImage();
    check(storedCounter(QStringLiteral("console"), QStringLiteral("paints")) >= 1,
          "console dock paint did not run");
    check(shot.pixelColor(5, 5) == QColor(255, 0, 0) && shot.pixelColor(30, 5) == QColor(0, 0, 0),
          "fillRect/clear pixels are wrong");
    check(host.evalConsole(QStringLiteral("G.fillRect(0, 0, 1, 1, 'red')")).isNull() &&
              hasMessage(messages, QStringLiteral("console"), 2,
                         QStringLiteral("only usable inside paint")),
          "painter used outside paint() was not refused");
    check(host.evalConsole(QStringLiteral("G.width")).toInt() == canvas->width() &&
              canvas->width() >= 16,
          "painter width did not match the canvas");
    clickCanvas(canvas, QPoint(3, 4));
    check(QSettings()
              .value(QStringLiteral("plugins/console/data/mouse"))
              .toByteArray()
              .contains("release:3:left"),
          "mouse events did not reach the script");
    {
        QWheelEvent wheel(QPointF(3, 4), QPointF(canvas->mapToGlobal(QPoint(3, 4))), QPoint(),
                          QPoint(0, -120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(canvas, &wheel);
        check(QSettings()
                  .value(QStringLiteral("plugins/console/data/mouse"))
                  .toByteArray()
                  .contains("wheel:3"),
              "wheel events did not reach the script");
    }
    check(host.evalConsole(QStringLiteral("meter.visible")) == QStringLiteral("true"),
          "dock.visible did not read true");
    host.evalConsole(QStringLiteral("meter.hide()"));
    check(dock->isHidden() &&
              host.evalConsole(QStringLiteral("meter.visible")) == QStringLiteral("false"),
          "dock.hide() did not hide the dock");
    host.evalConsole(QStringLiteral("meter.title = 'Renamed'"));
    check(dock->windowTitle() == QStringLiteral("Renamed"), "dock.title setter did not apply");
    // Theme colors.
    check(host.evalConsole(QStringLiteral("porydaw.ui.theme('window_text')"))
                  .startsWith(QLatin1Char('#')) &&
              host.evalConsole(QStringLiteral("Object.keys(porydaw.ui.theme()).length > 10")) ==
                  QStringLiteral("true"),
          "ui.theme did not return colors");
    check(host.evalConsole(QStringLiteral("porydaw.ui.theme('scrollbar_handle')")).isNull(),
          "ui.theme accepted an unexposed role");
    // Refusals.
    check(host.evalConsole(QStringLiteral("porydaw.ui.dock({id: 'meter', paint: function () {}})"))
              .isNull(),
          "a duplicate dock id was accepted");
    check(host.evalConsole(QStringLiteral("porydaw.ui.dock({id: 'bad id', paint: function () {}})"))
              .isNull(),
          "a bad dock id was accepted");
    check(host.evalConsole(QStringLiteral("porydaw.ui.dock({id: 'nothing'})")).isNull(),
          "a dock without paint or build was accepted");
    check(host.evalConsole(QStringLiteral(
                               "porydaw.ui.dock({id: 'x', area: 'middle', paint: function () {}})"))
              .isNull(),
          "a bad dock area was accepted");
    check(host.evalConsole(QStringLiteral("porydaw.ui.loadImage('nope.png')")).isNull(),
          "loadImage in the folder-less console did not throw");
    host.evalConsole(QStringLiteral("meter.close()"));
    QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    check(dock.isNull() &&
              host.evalConsole(QStringLiteral("meter.open")) == QStringLiteral("false"),
          "dock.close() did not dispose the dock");

    // A paint that throws is logged once, then held back for a moment.
    host.evalConsole(QStringLiteral(
        "var thrower = porydaw.ui.dock({id: 'thrower', paint: function (g) { throw new "
        "Error('paint boom'); }})"));
    QDockWidget *throwerDock =
        window.findChild<QDockWidget *>(QStringLiteral("plugin.console.thrower"));
    auto *throwerCanvas =
        throwerDock ? throwerDock->findChild<scripting::CanvasWidget *>() : nullptr;
    if (check(throwerCanvas, "thrower dock missing")) {
        throwerCanvas->grab();
        throwerCanvas->grab();
        check(countMessages(messages, QStringLiteral("console"), QStringLiteral("paint boom")) ==
                      1 &&
                  throwerCanvas->errorCount() == 1,
              "a throwing paint was not logged exactly once per hold");
        host.evalConsole(QStringLiteral("thrower.close()"));
        QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
    }

    // The watchdog reaches into paint too: a hung paint faults the plugin
    // and its docks go with it.
    host.setWatchdogMs(200);
    host.evalConsole(QStringLiteral(
        "var hang = porydaw.ui.dock({id: 'hang', paint: function (g) { while (true) {} }})"));
    QDockWidget *hangDock = window.findChild<QDockWidget *>(QStringLiteral("plugin.console.hang"));
    auto *hangCanvas = hangDock ? hangDock->findChild<scripting::CanvasWidget *>() : nullptr;
    if (check(hangCanvas, "hang dock missing")) {
        QElapsedTimer clock;
        clock.start();
        hangCanvas->grab();
        const scripting::Plugin *console = host.plugin(QStringLiteral("console"));
        check(clock.elapsed() < 5000 && console && console->state == scripting::PluginState::Error,
              "a hung paint was not interrupted");
        check(waitFor(
                  [&] {
                      return !window.findChild<QDockWidget *>(
                          QStringLiteral("plugin.console.hang"));
                  },
                  2000),
              "a faulted plugin's dock was not torn down");
    }
    host.setWatchdogMs(5000);
    check(host.evalConsole(QStringLiteral("1 + 1")) == QStringLiteral("2"),
          "the console did not revive after a paint fault");
}

// ---- Phase 3: audio frames + transport beats ----

void runRealtimeChecks(const Check &check, scripting::ScriptHost &host, MainWindow &window,
                       QList<Message> &messages, bool audioOk)
{
    runDockChecks(check, host, window, messages);
    if (!audioOk)
        return;
    // Let the bundled examples run against real playback first, and keep
    // a picture of each panel when asked (PORYDAW_SCRIPTCHECK_SHOTS=<dir>)
    // — the only way to eyeball a plugin's painting headlessly.
    const QString shotsDir = qEnvironmentVariable("PORYDAW_SCRIPTCHECK_SHOTS");
    if (host.plugin(QStringLiteral("vu-meter"))) {
        host.evalConsole(QStringLiteral("porydaw.transport.play()"));
        waitFor([] { return false; }, 1500);
        for (const char *id : {"vu-meter", "spectrum", "dancer"}) {
            const scripting::Plugin *p = host.plugin(QLatin1String(id));
            if (!p || p->docks.empty() || !p->docks.front())
                continue;
            auto *canvas = p->docks.front()->findChild<scripting::CanvasWidget *>();
            if (!check(canvas && canvas->paintCount() > 0 && canvas->errorCount() == 0,
                       "an example panel did not paint cleanly during playback"))
                continue;
            if (!shotsDir.isEmpty()) {
                canvas->resize(240, 160);
                canvas->grab().save(shotsDir + QLatin1Char('/') + QLatin1String(id) +
                                    QStringLiteral(".png"));
            }
        }
        host.evalConsole(QStringLiteral("porydaw.transport.stop()"));
    }
    // The bundled examples listen for frames; park them so the timer
    // gating below sees only the console's listeners (and unloading them
    // must drop their listener counts).
    QStringList parked;
    for (const char *id : {"vu-meter", "spectrum", "dancer"}) {
        const scripting::Plugin *p = host.plugin(QLatin1String(id));
        if (p && p->state == scripting::PluginState::Loaded) {
            parked.append(QLatin1String(id));
            host.setEnabled(QLatin1String(id), false);
        }
    }
    check(!host.frameTimerActive(), "the frame timer runs with nobody listening");
    // With the examples parked and the console's docks gone, the menu
    // lists only the panel fixture; parking that too empties and hides it.
    if (auto *panels = window.findChild<QMenu *>(QStringLiteral("viewPluginPanelsMenu"))) {
        check(panels->actions().size() == 1 && panels->menuAction()->isVisible(),
              "View → Plugin Panels did not list exactly the one open plugin dock");
        host.setEnabled(QStringLiteral("panel"), false);
        check(panels->actions().isEmpty() && !panels->menuAction()->isVisible(),
              "View → Plugin Panels stayed visible after the last plugin dock closed");
        host.setEnabled(QStringLiteral("panel"), true);
    }
    check(!host
               .evalConsole(QStringLiteral(
                   "var offFrame = porydaw.audio.on('frame', function (f) { "
                   "var v = Math.round(Math.max(f.rms[0], f.rms[1]) * 100000); "
                   "if (v > porydaw.storage.get('rms', 0)) porydaw.storage.set('rms', v); "
                   "porydaw.storage.set('frames', porydaw.storage.get('frames', 0) + 1); "
                   "if (f.frames > 0) porydaw.storage.set('fresh', 1); });"))
               .isNull(),
          "audio.on('frame') threw");
    check(host.frameTimerActive(), "an audio.frame listener did not start the frame timer");
    host.evalConsole(
        QStringLiteral("var offTick = porydaw.transport.on('tick', function (t) { "
                       "porydaw.storage.set('ticks', porydaw.storage.get('ticks', 0) + 1); "
                       "if (t.playing) porydaw.storage.set('tickplaying', 1); });"
                       "var offBeat = porydaw.transport.on('beat', function (b) { "
                       "porydaw.storage.set('beats', porydaw.storage.get('beats', 0) + 1); "
                       "porydaw.storage.set('bpb', b.beatsPerBar); "
                       "porydaw.storage.set('beatidx', b.bar * b.beatsPerBar + b.beat); "
                       "if (b.bpm > 0 && b.beatTicks > 0) porydaw.storage.set('beatok', 1); });"));
    host.evalConsole(QStringLiteral("porydaw.transport.play()"));
    const auto counter = [](const char *key) {
        return storedCounter(QStringLiteral("console"), QLatin1String(key));
    };
    // The null device advances in real time; a couple of seconds of the
    // fixture song yield audible RMS and at least two beats.
    check(waitFor([&] { return counter("rms") > 0 && counter("beats") >= 2; }, 6000),
          "no non-zero RMS / second beat arrived while the song played");
    check(counter("frames") > 0 && counter("fresh") == 1, "audio frames carried no new samples");
    check(counter("ticks") > 0 && counter("tickplaying") == 1,
          "transport.tick did not fire while playing");
    check(counter("bpb") > 0 && counter("beatok") == 1 && counter("beatidx") >= 1,
          "transport.beat payload is malformed");
    check(host.evalConsole(QStringLiteral("porydaw.audio.pcm() instanceof Float32Array && "
                                          "porydaw.audio.pcm().length === "
                                          "porydaw.audio.windowFrames * 2")) ==
              QStringLiteral("true"),
          "audio.pcm() is not a Float32Array of the window");
    check(host.evalConsole(QStringLiteral("porydaw.audio.spectrum(32).length")) ==
              QStringLiteral("32"),
          "audio.spectrum(32) did not return 32 bands");
    check(host.evalConsole(QStringLiteral("porydaw.audio.spectrum(32).some(function (v) { "
                                          "return v > 0; })")) == QStringLiteral("true"),
          "audio.spectrum is silent while the song plays");
    check(host.evalConsole(QStringLiteral("porydaw.audio.channels().pcm.length > 0")) ==
              QStringLiteral("true"),
          "audio.channels() has no pcm pool");
    check(host.evalConsole(QStringLiteral("porydaw.audio.peak.length === 2 && "
                                          "porydaw.audio.rms.length === 2")) ==
              QStringLiteral("true"),
          "audio.peak/rms are not stereo pairs");
    host.evalConsole(QStringLiteral("porydaw.transport.stop()"));
    // A stop then play restarts the beat sequence (the first beat fires
    // again).
    const int beatsBefore = counter("beats");
    host.evalConsole(QStringLiteral("porydaw.transport.play()"));
    check(waitFor([&] { return counter("beats") > beatsBefore; }, 2000),
          "restarting playback did not re-fire the starting beat");
    host.evalConsole(QStringLiteral("porydaw.transport.stop()"));
    host.evalConsole(QStringLiteral("offFrame(); offTick(); offBeat();"));
    check(!host.frameTimerActive(), "removing every listener did not stop the frame timer");
    for (const QString &id : parked)
        host.setEnabled(id, true);
    if (!parked.isEmpty())
        check(host.frameTimerActive(), "re-enabled examples did not restart the frame timer");
    // The examples' listeners ran during the song half; none may have thrown.
    for (const QString &id : parked)
        check(!hasMessage(messages, id, 2, QStringLiteral("")),
              "an example plugin logged an error");
}

// ---- Phase 3: the tap ring and analyzer, no engine ----

int runTapCheck()
{
    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "scriptcheck: FAIL: %s\n", what);
            failures++;
        }
    };
    AudioTap tap(1000); // rounds up to 1024
    check(tap.capacity() == 1024, "tap capacity did not round up to a power of two");
    std::vector<float> out(4096);
    check(tap.readLatest(out.data(), 8) == 0 && out[0] == 0.0f && out[15] == 0.0f,
          "reading an empty tap did not yield silence");
    std::vector<float> in;
    for (int i = 0; i < 10; i++) {
        in.push_back(float(i));
        in.push_back(float(-i));
    }
    tap.write(in.data(), 10);
    check(tap.framesWritten() == 10, "framesWritten did not count the write");
    check(tap.readLatest(out.data(), 4) == 4 && out[0] == 6.0f && out[1] == -6.0f && out[6] == 9.0f,
          "readLatest did not return the newest frames oldest-first");
    check(tap.readLatest(out.data(), 16) == 10 && out[0] == 0.0f && out[11] == 0.0f &&
              out[12] == 0.0f && out[13] == 0.0f && out[30] == 9.0f,
          "readLatest did not pad pre-history with silence");
    in.clear();
    for (int i = 0; i < 2000; i++) {
        in.push_back(float(i));
        in.push_back(float(-i));
    }
    tap.write(in.data(), 2000); // wraps and overruns the capacity
    check(tap.framesWritten() == 2010 && tap.readLatest(out.data(), 1024) == 1024 &&
              out[0] == 976.0f && out[2046] == 1999.0f && out[2047] == -1999.0f,
          "an oversized write did not keep exactly the newest capacity");

    // FFT: DC only lands in bin 0.
    std::vector<float> reim(16, 0.0f);
    for (int i = 0; i < 8; i++)
        reim[i * 2] = 1.0f;
    AudioAnalyzer::fft(reim.data(), 8);
    check(std::fabs(reim[0] - 8.0f) < 1e-4f && std::fabs(reim[2]) < 1e-4f &&
              std::fabs(reim[14]) < 1e-4f,
          "fft of DC is wrong");

    // Analyzer: a half-scale sine at bin 8 of a 256 window.
    AudioTap tap2(4096);
    AudioAnalyzer an(256);
    check(an.windowFrames() == 256, "analyzer window did not round");
    in.clear();
    for (int i = 0; i < 1024; i++) {
        const float v = 0.5f * std::sin(2.0f * float(M_PI) * 8.0f * float(i) / 256.0f);
        in.push_back(v);
        in.push_back(v);
    }
    tap2.write(in.data(), 1024);
    check(an.poll(tap2) == 1024 && an.newFrames() == 1024, "poll did not count the new frames");
    check(std::fabs(an.peak(0) - 0.5f) < 0.01f && std::fabs(an.rms(1) - 0.3536f) < 0.02f,
          "peak/rms of a half-scale sine are wrong");
    const std::vector<float> &spec = an.spectrum(128);
    const auto argmax = [](const std::vector<float> &v) {
        return int(std::max_element(v.begin(), v.end()) - v.begin());
    };
    check(spec.size() == 128 && argmax(spec) == 8 && spec[8] > 0.4f && spec[8] < 0.6f &&
              spec[40] < 0.01f,
          "spectrum did not place a bin-8 sine at bin 8 with ~0.5 magnitude");
    const std::vector<float> &bands = an.spectrum(16);
    check(bands.size() == 16 && argmax(bands) == 1, "spectrum banding did not fold bins");
    check(an.spectrum(0).size() == 1 && an.spectrum(100000).size() == 128,
          "spectrum bins were not clamped");
    check(an.poll(tap2) == 0 && an.peak(0) == 0.0f && an.rms(0) == 0.0f,
          "a poll with nothing new did not read silence");
    return failures;
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
                      QStringLiteral("no manifest")) &&
            writeFile(pluginsDir + QStringLiteral("/panel/plugin.json"),
                      QLatin1String(kPanelManifest)) &&
            writeFile(pluginsDir + QStringLiteral("/panel/main.js"), QLatin1String(kPanelMain)),
        "could not write fixture plugins");
    {
        QImage pic(16, 9, QImage::Format_ARGB32);
        pic.fill(QColor(255, 0, 0));
        check(pic.save(pluginsDir + QStringLiteral("/panel/pic.png")),
              "could not write the panel fixture image");
    }

    // The bundled examples double as API smoke tests (PLAN §8): copied in
    // from the source tree when the binary runs out of its build dir.
    bool haveExamples = false;
    {
        const QDir examples(QCoreApplication::applicationDirPath() +
                            QStringLiteral("/../plugins/examples"));
        for (const QString &name :
             examples.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name)) {
            const QDir src(examples.filePath(name));
            const QString dst = pluginsDir + QLatin1Char('/') + name;
            QDir().mkpath(dst);
            for (const QString &file : src.entryList(QDir::Files))
                QFile::copy(src.filePath(file), dst + QLatin1Char('/') + file);
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
                            QStringLiteral("fixture"),     QStringLiteral("panel"),
                            QStringLiteral("runaway"),     QStringLiteral("syntax")};
    int exampleCommands = 0;
    if (haveExamples) {
        expectedIds.append(QStringLiteral("select-same-pitch"));
        expectedIds.append(QStringLiteral("note-tools"));
        expectedIds.append(QStringLiteral("vu-meter"));
        expectedIds.append(QStringLiteral("spectrum"));
        expectedIds.append(QStringLiteral("dancer"));
        expectedIds.sort();
        // The Phase 3 examples each open a dock in activate().
        for (const char *id : {"vu-meter", "spectrum", "dancer"}) {
            const scripting::Plugin *p = host.plugin(QLatin1String(id));
            check(p && p->state == scripting::PluginState::Loaded && p->docks.size() == 1 &&
                      p->docks.front() && findChild<QDockWidget *>(p->docks.front()->objectName()),
                  "a Phase 3 example plugin did not load with its dock");
        }
        const scripting::Plugin *example = host.plugin(QStringLiteral("select-same-pitch"));
        check(example && example->state == scripting::PluginState::Loaded,
              "bundled example plugin select-same-pitch did not load");
        check(keys.command(QStringLiteral("plugin.select-same-pitch.select")).context ==
                  keymap::Context::PianoRoll,
              "bundled example did not register its roll command");
        exampleCommands = example ? int(example->actions.size()) : 0;
        const scripting::Plugin *tools = host.plugin(QStringLiteral("note-tools"));
        check(tools && tools->state == scripting::PluginState::Loaded && tools->actions.size() == 5,
              "bundled example plugin note-tools did not load its 5 commands");
        check(!hasMessage(messages, QStringLiteral("note-tools"), 1, QStringLiteral("already")),
              "a note-tools default shortcut collides with a shipped binding");
        exampleCommands += tools ? int(tools->actions.size()) : 0;
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
    check(keys.commands().size() == shippedCommands + 8 + exampleCommands,
          "dynamic commands not appended to the registry (expected 7 fixture + 1 runaway)");
    check(keys.bindings(QStringLiteral("plugin.fixture.conflict")).isEmpty() &&
              hasMessage(messages, QStringLiteral("fixture"), 1, QStringLiteral("already used by")),
          "a default that collides with a shipped roll binding was not dropped with a warning");
    check(keys.bindings(QStringLiteral("plugin.fixture.save")).isEmpty() &&
              hasMessage(messages, QStringLiteral("fixture"), 1, QStringLiteral("file.save_song")),
          "a default that collides with a shipped DEFAULT (currently rebound) was not dropped");
    check(keys.bindings(QStringLiteral("plugin.fixture.esc")).isEmpty() &&
              hasMessage(messages, QStringLiteral("fixture"), 1, QStringLiteral("Escape")),
          "an Escape default was not refused");
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

    runPanelChecks(check, host, *this, messages, m_pluginPanelsMenu);

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
        runEditChecks(check, host, *m_active, messages, haveExamples);
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
        runRealtimeChecks(check, host, *this, messages, m_audioOk);
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
    int failures = runEngineCheck() + runTapCheck();

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
