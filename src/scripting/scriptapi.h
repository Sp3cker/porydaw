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
    // The prelude reports how many listeners an event has (frame pumping
    // is gated on it).
    Q_INVOKABLE void subscribed(const QString &event, int count);
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
    // {start, end, scope?: 'tracks'|'lanes', lanes?: [{track, cc}]}: a
    // time selection. Track scope covers the header-selected tracks
    // (trackMask); lanes scope needs at least one lane.
    Q_INVOKABLE void setTime(const QVariantMap &spec);
    Q_INVOKABLE void clearTime();
};

// porydaw.edit: every document mutation, allowed only inside a transaction
// (ScriptHost::beginTransaction) so a script action is one undo entry.
// Note arguments are id lists; ids that no longer resolve are skipped and
// the count of notes actually edited is returned. Ticks/keys/velocities/
// values are clamped to their ranges. Structural arguments (a bad track,
// cc, or scope) throw.
class EditApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active)
  public:
    using ApiObject::ApiObject;
    bool active() const;
    Q_INVOKABLE void begin(const QString &name);
    Q_INVOKABLE void commit();
    Q_INVOKABLE void rollback();

    // [{tick, key, len, vel}] → the new notes' ids (same order; 0 where a
    // later note in the batch replaced it).
    Q_INVOKABLE QVariantList addNotes(int track, const QVariantList &notes);
    Q_INVOKABLE int deleteNotes(const QVariantList &ids);
    Q_INVOKABLE int moveNotes(const QVariantList &ids, double dTick, int dKey);
    // dLen: change in length. fromLeft moves the note-on instead of the
    // note-off (the end stays put).
    Q_INVOKABLE int resizeNotes(const QVariantList &ids, double dLen, bool fromLeft);
    // [{id, vel}]
    Q_INVOKABLE int setVelocities(const QVariantList &pairs);
    Q_INVOKABLE int nudgeVelocity(const QVariantList &ids, int delta);

    Q_INVOKABLE void addLanePoint(int track, int cc, double tick, int value);
    // Replaces the lane's points in [from, to] with [{tick, value}].
    Q_INVOKABLE void writeLanePoints(int track, int cc, double from, double to,
                                     const QVariantList &points);
    // [{tick, newTick?, newValue?}]; points that don't exist are skipped.
    Q_INVOKABLE int moveLanePoints(int track, int cc, const QVariantList &moves);
    Q_INVOKABLE int deleteLanePoints(int track, int cc, const QVariantList &ticks);

    Q_INVOKABLE void setStartTempo(int bpm);
    // null/undefined removes the marker.
    Q_INVOKABLE void setLoop(const QJSValue &start, const QJSValue &end);
    Q_INVOKABLE void setTimeSig(double tick, int numerator, int denominator);
    Q_INVOKABLE void deleteTimeSig(double tick);

    // scope: {tracks?: [i], lanes?: [{track, cc}], wholeSong?: bool}.
    Q_INVOKABLE bool removeTimeRange(double start, double end, const QVariantMap &scope);
    Q_INVOKABLE bool insertTimeRange(double at, double span, const QVariantMap &scope);

    Q_INVOKABLE int addTrack(int voice);
    Q_INVOKABLE int duplicateTrack(int track);
    Q_INVOKABLE void deleteTrack(int track);
    Q_INVOKABLE bool moveTrack(int track, int target);
    Q_INVOKABLE void renameTrack(int track, const QString &name);

    // The roll's keyboard transpose/nudge on the current note selection.
    Q_INVOKABLE bool transposeSelection(int dKey);
    Q_INVOKABLE bool nudgeSelection(bool right);

  private:
    // Begins an edit call: the transaction's document, or nullptr after
    // throwing. Pair with done().
    SongDocument *begin();
    void done();
    std::vector<DocNote> resolveNotes(const SongDocument *d, const QVariantList &ids) const;
    bool checkTrack(const SongDocument *d, int track, const char *api);
    // Validates a lane address; returns the document's engine track for it
    // (-1 for the tempo lane) or -2 after throwing.
    int laneTrack(const SongDocument *d, int track, int cc, const char *api);
};

// porydaw.view: the roll's camera and lane visibility (view state, no
// undo entries).
class ViewApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(bool velocityLane READ velocityLane WRITE setVelocityLane)
    Q_PROPERTY(bool automationLanes READ automationLanes WRITE setAutomationLanes)
    Q_PROPERTY(bool tempoLane READ tempoLane WRITE setTempoLane)
    Q_PROPERTY(bool eventList READ eventList WRITE setEventList)
    Q_PROPERTY(double pxPerBeat READ pxPerBeat)
    Q_PROPERTY(double keyHeight READ keyHeight)
  public:
    using ApiObject::ApiObject;
    bool velocityLane() const;
    void setVelocityLane(bool on);
    bool automationLanes() const;
    void setAutomationLanes(bool on);
    bool tempoLane() const;
    void setTempoLane(bool on);
    bool eventList() const;
    void setEventList(bool on);
    double pxPerBeat() const;
    double keyHeight() const;
    // {from, to} ticks the roll viewport shows, or null without a song.
    Q_INVOKABLE QVariant visibleTicks() const;
    Q_INVOKABLE void revealTick(double tick);
    Q_INVOKABLE void revealRange(double from, double to);
    Q_INVOKABLE bool revealNote(double id);
    Q_INVOKABLE void revealKey(int key);
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

// porydaw.audio: the last pumped frame's analysis (ScriptHost::pumpFrame)
// plus the engine's channel activity. The frame event carries peak/RMS;
// waveform and spectrum are pulled on demand because the FFT costs more
// than every listener wants to pay.
class AudioApi : public ApiObject
{
    Q_OBJECT
    Q_PROPERTY(double sampleRate READ sampleRate)
    Q_PROPERTY(int windowFrames READ windowFrames)
  public:
    using ApiObject::ApiObject;
    double sampleRate() const;
    int windowFrames() const;
    Q_INVOKABLE QVariantList peak() const;
    Q_INVOKABLE QVariantList rms() const;
    // The newest windowFrames stereo frames, interleaved, as an
    // ArrayBuffer of float32 (the prelude wraps it in a Float32Array).
    Q_INVOKABLE QByteArray pcm() const;
    // `bins` bands of 0..1 magnitudes, linear in frequency.
    Q_INVOKABLE QByteArray spectrum(int bins) const;
    // {pcm: [{on, releasing, track, key}], cgb: [...], maxPcm, activePcm, activeCgb}.
    Q_INVOKABLE QVariant channels() const;
};

// porydaw.ui beyond statusMessage: docks (scriptwidgets.h), theme colors
// and images.
class UiApi : public ApiObject
{
    Q_OBJECT
  public:
    using ApiObject::ApiObject;
    // spec: {id, title?, area?, minWidth?, minHeight?}; one of paint/build
    // callable. → DockHandle, or throws.
    Q_INVOKABLE QObject *dock(const QVariantMap &spec, const QJSValue &build, const QJSValue &paint,
                              const QJSValue &mouse);
    // A theme color by role name ("#rrggbb"/"#rrggbbaa"), or an object of
    // every exposed role when name is empty. Unknown names throw.
    Q_INVOKABLE QVariant theme(const QString &name) const;
    // Decodes an image file inside the plugin's folder → id (throws when
    // missing or outside the folder).
    Q_INVOKABLE int loadImage(const QString &relativePath);
    Q_INVOKABLE QVariant imageSize(int id) const;
    Q_INVOKABLE void freeImage(int id);
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
