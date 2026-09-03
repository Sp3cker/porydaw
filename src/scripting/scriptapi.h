#pragma once

#include <QJSValue>
#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <memory>
#include <vector>

class QJSEngine;
class SongDocument;
class SongView;
struct DocNote;
struct SongSession;

namespace scripting {

class ScriptHost;
struct Plugin;

// The C++ side of `porydaw.*` (docs/scripting/PLAN.md §4): one thin QObject
// per namespace, instantiated per plugin so every call knows its owner.
// Values cross as plain JS objects/arrays (QVariantMap/QVariantList), never
// live handles; notes are identified by their NoteId token (a number).
// prelude.js wraps these into the user-facing API (getters, on()/off(),
// argument sugar) so this layer stays mechanical.
class ApiObject : public QObject
{
    Q_OBJECT
  public:
    ApiObject(ScriptHost &host, Plugin &plugin);

  protected:
    SongSession *session() const;
    SongDocument *doc() const;
    SongView *view() const;
    QJSEngine *engine() const;
    // JS-side exception for a bad argument; the call still returns.
    void throwError(const QString &message) const;
    ScriptHost &m_host;
    Plugin &m_plugin;
};

class HostApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString apiVersion READ apiVersion CONSTANT)
    Q_PROPERTY(int apiMajor READ apiMajor CONSTANT)
    Q_PROPERTY(QString pluginId READ pluginId CONSTANT)
    Q_PROPERTY(QString pluginName READ pluginName CONSTANT)
    Q_PROPERTY(QString pluginVersion READ pluginVersion CONSTANT)
    Q_PROPERTY(QString pluginDir READ pluginDir CONSTANT)
  public:
    using ApiObject::ApiObject;
    QString appVersion() const;
    QString apiVersion() const;
    int apiMajor() const;
    QString pluginId() const;
    QString pluginName() const;
    QString pluginVersion() const;
    QString pluginDir() const;
    Q_INVOKABLE void log(int level, const QString &text);
    Q_INVOKABLE void reportError(const QJSValue &error);
    Q_INVOKABLE void statusMessage(const QString &text);
};

class SongApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(bool loaded READ loaded)
    Q_PROPERTY(double revision READ revision)
    Q_PROPERTY(QString label READ label)
    Q_PROPERTY(QString midPath READ midPath)
    Q_PROPERTY(int ticksPerBeat READ ticksPerBeat)
    Q_PROPERTY(int ticksPerClock READ ticksPerClock)
    Q_PROPERTY(int startTempo READ startTempo)
    Q_PROPERTY(int trackCount READ trackCount)
    Q_PROPERTY(int trackBudget READ trackBudget)
    Q_PROPERTY(double endTick READ endTick)
  public:
    using ApiObject::ApiObject;
    bool loaded() const;
    double revision() const;
    QString label() const;
    QString midPath() const;
    int ticksPerBeat() const;
    int ticksPerClock() const;
    int startTempo() const;
    int trackCount() const;
    int trackBudget() const;
    double endTick() const;
    // {start, end} in ticks, or null when the song has no loop markers.
    Q_INVOKABLE QVariant loop() const;
    // [{tick, numerator, denominator}] sorted by tick.
    Q_INVOKABLE QVariantList timeSigs() const;
    // [{index, name, channel, muted, soloed, voice}] for every engine track.
    Q_INVOKABLE QVariantList tracks() const;
    // {track?, from?, to?, selectedOnly?} → [{id, track, tick, key, len, vel}].
    // from/to bound the note start tick (half-open).
    Q_INVOKABLE QVariantList notes(const QVariantMap &opts) const;
    Q_INVOKABLE QVariant note(double id) const;
    // Automation points of one lane: cc 0-127, or the pseudo-CCs in
    // porydaw.song.CC (BEND/TEMPO/VOICE). {from?, to?} bound the tick.
    Q_INVOKABLE QVariantList lanePoints(int track, int cc, const QVariantMap &opts) const;
};

class SelectionApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(int track READ track)
    Q_PROPERTY(int trackMask READ trackMask)
  public:
    using ApiObject::ApiObject;
    int track() const;
    int trackMask() const;
    // Selected notes (on the selected track) as [{id, track, tick, key, len, vel}].
    Q_INVOKABLE QVariantList notes() const;
    // {start, end, scope: 'tracks'|'lanes', lanes: [{track, cc}]} or null.
    Q_INVOKABLE QVariant time() const;
    // Replaces the note selection with these note ids. All must be on one
    // track (the selection is per track); that track becomes the selected
    // one. Unknown ids are skipped. Selection state is view state, not a
    // document edit: no undo entry.
    Q_INVOKABLE void setNotes(const QVariantList &ids);
    Q_INVOKABLE void clear();
    Q_INVOKABLE void selectTrack(int track);
};

class CursorApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(double tick READ tick)
  public:
    using ApiObject::ApiObject;
    double tick() const;
    // mode: 'nearest' (default) | 'down' | 'up'.
    Q_INVOKABLE double snap(double tick, const QString &mode) const;
    // The grid cell at a tick: {start, next, beatTicks, feel, minDenom}.
    Q_INVOKABLE QVariant grid(double tick) const;
    // Moves the edit cursor (seeks playback while playing/paused).
    Q_INVOKABLE void set(double tick);
};

class TransportApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(QString state READ state)
    Q_PROPERTY(double playheadTick READ playheadTick)
    Q_PROPERTY(double sampleRate READ sampleRate)
    Q_PROPERTY(bool loopEnabled READ loopEnabled)
  public:
    using ApiObject::ApiObject;
    QString state() const;
    double playheadTick() const;
    double sampleRate() const;
    bool loopEnabled() const;
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(double tick);
};

class ActionsApi : public ApiObject
{
    Q_OBJECT
  public:
    using ApiObject::ApiObject;
    // {id, name, context: 'global'|'roll'|'velocity'|'range', default: keys}
    // → the full keymap id. Throws on a bad spec.
    Q_INVOKABLE QString registerAction(const QVariantMap &spec);
    Q_INVOKABLE void unregister(const QString &fullId);
};

class StorageApi : public ApiObject
{
    Q_OBJECT
  public:
    using ApiObject::ApiObject;
    // JSON-serializable values under plugins/<id>/data/<key> in QSettings.
    Q_INVOKABLE QJSValue get(const QString &key, const QJSValue &fallback) const;
    Q_INVOKABLE void set(const QString &key, const QJSValue &value);
    Q_INVOKABLE void remove(const QString &key);
    Q_INVOKABLE QStringList keys() const;
};

class ProjectApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(bool isOpen READ isOpen)
    Q_PROPERTY(QString root READ root)
  public:
    using ApiObject::ApiObject;
    bool isOpen() const;
    QString root() const;
    // [{id, label, constant, player, midPath, hasMid, registered}].
    Q_INVOKABLE QVariantList songs() const;
};

// Builds the facades into plugin.facades, runs prelude.js against them, and
// installs `porydaw` + `console` as globals of the plugin's engine. False
// with *error on failure (a broken prelude is a porydaw bug, not a plugin's).
bool installApi(ScriptHost &host, Plugin &plugin, QString *error);

// Shared note → JS-object conversion.
QVariantMap noteToVariant(const DocNote &note);

} // namespace scripting
