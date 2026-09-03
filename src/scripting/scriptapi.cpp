#include "scriptapi.h"

#include <QAction>
#include <QFile>
#include <QJSEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

#include <algorithm>
#include <cmath>

#include "audio/audioengine.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "scripthost.h"
#include "songsession.h"
#include "ui/songview.h"

namespace scripting {

namespace {

QString storageKey(const Plugin &plugin, const QString &key)
{
    return QStringLiteral("plugins/") + plugin.manifest.id + QStringLiteral("/data/") + key;
}

// Script numbers → ticks/ids: NaN/Infinity read as 0 and anything past
// kMaxTick is clamped, so a wild value never reaches the document (an
// out-of-range double→uint64 conversion is undefined behaviour).
constexpr double kMaxTick = double(1ull << 40);

uint64_t clampTick(double value)
{
    if (!std::isfinite(value) || value <= 0.0)
        return 0;
    return uint64_t(std::min(value, kMaxTick));
}

// NoteId tokens are sequential; the same guard, with 0 as "no note".
uint64_t clampId(double value)
{
    if (!std::isfinite(value) || value <= 0.0)
        return 0;
    return uint64_t(std::min(value, 9007199254740992.0)); // 2^53, exact in a double
}

bool tickRange(const QVariantMap &opts, uint64_t *from, uint64_t *to)
{
    *from = 0;
    *to = UINT64_MAX;
    if (opts.contains(QStringLiteral("from")))
        *from = clampTick(opts.value(QStringLiteral("from")).toDouble());
    if (opts.contains(QStringLiteral("to")))
        *to = clampTick(opts.value(QStringLiteral("to")).toDouble());
    return *from < *to;
}

} // namespace

// An invalid QVariant crosses as `undefined`; the API promises `null`.
QVariant jsNull()
{
    return QVariant::fromValue(nullptr);
}

QVariantMap noteToVariant(const DocNote &note)
{
    return {{QStringLiteral("id"), double(note.noteId.token())},
            {QStringLiteral("track"), note.engineTrack},
            {QStringLiteral("tick"), double(note.tick)},
            {QStringLiteral("key"), int(note.key)},
            {QStringLiteral("len"), double(note.duration)},
            {QStringLiteral("vel"), int(note.velocity)}};
}

// ---- ApiObject ----

ApiObject::ApiObject(ScriptHost &host, Plugin &plugin) : m_host(host), m_plugin(plugin) {}

SongSession *ApiObject::session() const
{
    return m_host.session();
}

SongDocument *ApiObject::doc() const
{
    SongSession *s = session();
    return s ? &s->doc : nullptr;
}

SongView *ApiObject::view() const
{
    SongSession *s = session();
    return s ? s->view : nullptr;
}

QJSEngine *ApiObject::engine() const
{
    return m_plugin.engine.get();
}

void ApiObject::throwError(const QString &message) const
{
    if (QJSEngine *e = engine())
        e->throwError(QJSValue::TypeError, message);
}

// ---- HostApi ----

QString HostApi::appVersion() const
{
    return QStringLiteral(PORYDAW_VERSION);
}

QString HostApi::apiVersion() const
{
    return QLatin1String(kApiVersion);
}

int HostApi::apiMajor() const
{
    return kApiMajor;
}

QString HostApi::pluginId() const
{
    return m_plugin.manifest.id;
}

QString HostApi::pluginName() const
{
    return m_plugin.manifest.name;
}

QString HostApi::pluginVersion() const
{
    return m_plugin.manifest.version;
}

QString HostApi::pluginDir() const
{
    return m_plugin.dir;
}

void HostApi::log(int level, const QString &text)
{
    m_host.log(m_plugin, LogLevel(std::clamp(level, 0, 2)), text);
}

void HostApi::reportError(const QJSValue &error)
{
    const QJSValue stack = error.property(QStringLiteral("stack"));
    m_host.log(m_plugin, LogLevel::Error, stack.isString() ? stack.toString() : error.toString());
}

void HostApi::statusMessage(const QString &text)
{
    if (m_host.bindings().statusMessage)
        m_host.bindings().statusMessage(text);
}

// ---- SongApi ----

bool SongApi::loaded() const
{
    return doc() != nullptr;
}

double SongApi::revision() const
{
    const SongDocument *d = doc();
    return d ? double(d->revision()) : 0.0;
}

QString SongApi::label() const
{
    const SongDocument *d = doc();
    return d ? d->label() : QString();
}

QString SongApi::midPath() const
{
    const SongDocument *d = doc();
    return d ? d->midPath() : QString();
}

int SongApi::ticksPerBeat() const
{
    const SongDocument *d = doc();
    return d ? int(d->smf().division) : 0;
}

int SongApi::ticksPerClock() const
{
    const SongDocument *d = doc();
    return d ? int(d->ticksPerClock()) : 0;
}

int SongApi::startTempo() const
{
    const SongDocument *d = doc();
    return d ? d->startTempo() : 0;
}

int SongApi::trackCount() const
{
    const SongDocument *d = doc();
    return d ? d->engineTrackCount() : 0;
}

int SongApi::trackBudget() const
{
    const SongDocument *d = doc();
    return d ? d->trackBudget() : 0;
}

double SongApi::endTick() const
{
    const SongDocument *d = doc();
    if (!d)
        return 0.0;
    uint64_t end = 0;
    for (const SmfTrack &track : d->smf().tracks)
        end = std::max(end, track.endTick);
    return double(end);
}

QVariant SongApi::loop() const
{
    const SongDocument *d = doc();
    if (!d)
        return jsNull();
    const uint64_t start = d->loopTick(false);
    const uint64_t end = d->loopTick(true);
    if (start == UINT64_MAX || end == UINT64_MAX)
        return jsNull();
    return QVariantMap{{QStringLiteral("start"), double(start)},
                       {QStringLiteral("end"), double(end)}};
}

QVariantList SongApi::timeSigs() const
{
    QVariantList out;
    const SongDocument *d = doc();
    if (!d)
        return out;
    for (const DocTimeSig &sig : d->timeSigs()) {
        out.append(QVariantMap{{QStringLiteral("tick"), double(sig.tick)},
                               {QStringLiteral("numerator"), int(sig.numerator)},
                               {QStringLiteral("denominator"), 1 << sig.denomPow2}});
    }
    return out;
}

QVariantList SongApi::tracks() const
{
    QVariantList out;
    const SongDocument *d = doc();
    const SongView *v = view();
    if (!d)
        return out;
    for (int t = 0; t < d->engineTrackCount(); ++t) {
        out.append(QVariantMap{{QStringLiteral("index"), t},
                               {QStringLiteral("name"), d->trackName(t)},
                               {QStringLiteral("channel"), int(d->channelFor(t))},
                               {QStringLiteral("muted"), v && v->trackMuted(t)},
                               {QStringLiteral("soloed"), v && v->trackSoloed(t)},
                               {QStringLiteral("voice"), v ? v->currentProgram(t) : -1}});
    }
    return out;
}

QVariantList SongApi::notes(const QVariantMap &opts) const
{
    QVariantList out;
    const SongDocument *d = doc();
    if (!d)
        return out;
    uint64_t from, to;
    if (!tickRange(opts, &from, &to))
        return out;
    int first = 0, last = d->engineTrackCount() - 1;
    if (opts.contains(QStringLiteral("track"))) {
        first = last = opts.value(QStringLiteral("track")).toInt();
        if (first < 0 || first >= d->engineTrackCount())
            return out;
    }
    const bool selectedOnly = opts.value(QStringLiteral("selectedOnly")).toBool();
    const SongView *v = view();
    if (selectedOnly) {
        if (!v)
            return out;
        first = last = v->selectedTrack();
        if (first < 0 || first >= d->engineTrackCount())
            return out;
    }
    for (int t = first; t <= last; ++t) {
        for (const DocNote &note : d->notesForTrack(t)) {
            if (note.tick < from || note.tick >= to)
                continue;
            if (selectedOnly &&
                !v->isSelected(ViewNote{note.noteId, uint32_t(note.tick),
                                        uint32_t(note.tick + note.duration), note.key,
                                        note.velocity, uint8_t(t), note.unterminated()}))
                continue;
            out.append(noteToVariant(note));
        }
    }
    return out;
}

QVariant SongApi::note(double id) const
{
    const SongDocument *d = doc();
    DocNote note;
    if (!d || clampId(id) == 0 || !d->findNote(NoteId(clampId(id)), &note))
        return jsNull();
    return noteToVariant(note);
}

QVariantList SongApi::lanePoints(int track, int cc, const QVariantMap &opts) const
{
    QVariantList out;
    const SongDocument *d = doc();
    if (!d || cc < 0 || cc > 0xFF)
        return out;
    // The tempo lane is song-wide: the document addresses it as track -1.
    if (cc != DOC_CC_TEMPO && (track < 0 || track >= d->engineTrackCount()))
        return out;
    uint64_t from, to;
    if (!tickRange(opts, &from, &to))
        return out;
    for (const DocLanePoint &p : d->lanePoints(cc == DOC_CC_TEMPO ? -1 : track, uint8_t(cc))) {
        if (p.tick < from || p.tick >= to)
            continue;
        out.append(QVariantMap{{QStringLiteral("tick"), double(p.tick)},
                               {QStringLiteral("value"), p.value}});
    }
    return out;
}

// ---- SelectionApi ----

int SelectionApi::track() const
{
    const SongView *v = view();
    return v ? v->selectedTrack() : -1;
}

int SelectionApi::trackMask() const
{
    const SongView *v = view();
    return v ? int(v->trackSelectionMask()) : 0;
}

QVariantList SelectionApi::notes() const
{
    QVariantList out;
    const SongDocument *d = doc();
    const SongView *v = view();
    if (!d || !v)
        return out;
    const int track = v->selectedTrack();
    for (const SongView::NoteKey &key : v->selection()) {
        DocNote note;
        if (d->findNote(track, key.tick, key.key, &note))
            out.append(noteToVariant(note));
    }
    return out;
}

QVariant SelectionApi::time() const
{
    const SongView *v = view();
    if (!v || !v->timeSelection().active())
        return jsNull();
    const SongView::TimeSelection &sel = v->timeSelection();
    QVariantList lanes;
    for (const auto &lane : sel.lanes)
        lanes.append(QVariantMap{{QStringLiteral("track"), lane.first},
                                 {QStringLiteral("cc"), int(lane.second)}});
    return QVariantMap{{QStringLiteral("start"), double(sel.startTick)},
                       {QStringLiteral("end"), double(sel.endTick)},
                       {QStringLiteral("scope"), sel.scope == SongView::TimeSelection::Lanes
                                                     ? QStringLiteral("lanes")
                                                     : QStringLiteral("tracks")},
                       {QStringLiteral("lanes"), lanes}};
}

void SelectionApi::setNotes(const QVariantList &ids)
{
    SongDocument *d = doc();
    SongView *v = view();
    if (!d || !v)
        return;
    std::vector<SongView::NoteKey> keys;
    int track = -1;
    for (const QVariant &id : ids) {
        DocNote note;
        if (clampId(id.toDouble()) == 0 || !d->findNote(NoteId(clampId(id.toDouble())), &note))
            continue;
        if (track < 0)
            track = note.engineTrack;
        if (note.engineTrack != track) {
            throwError(QStringLiteral("selection.setNotes: notes must all be on one track"));
            return;
        }
        keys.push_back({uint32_t(note.tick), note.key});
    }
    if (track >= 0 && track != v->selectedTrack())
        v->selectTrack(track);
    v->setSelection(std::move(keys));
}

void SelectionApi::clear()
{
    if (SongView *v = view())
        v->clearSelection();
}

void SelectionApi::selectTrack(int track)
{
    SongView *v = view();
    const SongDocument *d = doc();
    if (!v || !d)
        return;
    if (track < 0 || track >= d->engineTrackCount()) {
        throwError(QStringLiteral("selection.selectTrack: no such track"));
        return;
    }
    v->selectTrack(track);
}

// ---- CursorApi ----

double CursorApi::tick() const
{
    const SongView *v = view();
    return v ? double(v->editCursorTick()) : 0.0;
}

double CursorApi::snap(double tick, const QString &mode) const
{
    const SongView *v = view();
    if (!v)
        return tick;
    tick = double(clampTick(tick));
    if (mode == QLatin1String("down"))
        return double(v->snapTickDown(tick));
    if (mode == QLatin1String("up"))
        return double(v->snapTickUp(tick));
    if (mode != QLatin1String("nearest")) {
        throwError(QStringLiteral("cursor.snap: mode must be 'nearest', 'down' or 'up'"));
        return tick;
    }
    return double(v->snapTick(tick));
}

QVariant CursorApi::grid(double tick) const
{
    const SongView *v = view();
    if (!v)
        return jsNull();
    const SongView::GridSeg seg = v->gridSegAt(clampTick(tick));
    return QVariantMap{{QStringLiteral("start"), double(seg.start)},
                       {QStringLiteral("next"), double(seg.next)},
                       {QStringLiteral("beatTicks"), double(seg.beatTicks)},
                       {QStringLiteral("feel"), v->gridFeel() == SongView::GridFeel::Triplet
                                                    ? QStringLiteral("triplet")
                                                    : QStringLiteral("straight")},
                       {QStringLiteral("minDenom"), v->gridMinDenom()}};
}

void CursorApi::set(double tick)
{
    if (SongView *v = view())
        v->commitEditCursor(clampTick(tick));
}

// ---- TransportApi ----

QString TransportApi::state() const
{
    const AudioEngine *audio = m_host.bindings().audio;
    if (!audio || !audio->songLoaded())
        return QStringLiteral("stopped");
    switch (audio->transport()) {
    case Transport::Playing:
        return QStringLiteral("playing");
    case Transport::Paused:
        return QStringLiteral("paused");
    case Transport::Stopped:
        break;
    }
    return QStringLiteral("stopped");
}

double TransportApi::playheadTick() const
{
    const AudioEngine *audio = m_host.bindings().audio;
    if (audio && audio->songLoaded() && audio->timeline())
        return audio->timeline()->tickForSample(audio->playheadSamples());
    const SongView *v = view();
    return v ? double(v->editCursorTick()) : 0.0;
}

double TransportApi::sampleRate() const
{
    const AudioEngine *audio = m_host.bindings().audio;
    return audio ? audio->sampleRate() : 0.0;
}

bool TransportApi::loopEnabled() const
{
    const AudioEngine *audio = m_host.bindings().audio;
    return audio && audio->loopEnabled();
}

void TransportApi::play()
{
    if (m_host.bindings().play)
        m_host.bindings().play();
}

void TransportApi::pause()
{
    if (m_host.bindings().pause)
        m_host.bindings().pause();
}

void TransportApi::stop()
{
    if (m_host.bindings().stop)
        m_host.bindings().stop();
}

void TransportApi::seek(double tick)
{
    if (m_host.bindings().seekTick)
        m_host.bindings().seekTick(clampTick(tick));
}

// ---- ActionsApi ----

QString ActionsApi::registerAction(const QVariantMap &spec)
{
    const QString id = spec.value(QStringLiteral("id")).toString();
    const QString name = spec.value(QStringLiteral("name")).toString();
    const QString contextText = spec.value(QStringLiteral("context")).toString();
    const QString defaultKeys = spec.value(QStringLiteral("default")).toString();
    keymap::Context context;
    if (contextText == QLatin1String("global"))
        context = keymap::Context::Global;
    else if (contextText == QLatin1String("roll"))
        context = keymap::Context::PianoRoll;
    else if (contextText == QLatin1String("velocity"))
        context = keymap::Context::Velocity;
    else if (contextText == QLatin1String("range"))
        context = keymap::Context::TimeSelection;
    else {
        throwError(QStringLiteral("actions.register: context must be 'global', 'roll', "
                                  "'velocity' or 'range'"));
        return QString();
    }
    QString error;
    const QString fullId = m_host.registerAction(m_plugin, id, name, context, defaultKeys, &error);
    if (fullId.isEmpty())
        throwError(QStringLiteral("actions.register: ") + error);
    return fullId;
}

void ActionsApi::unregister(const QString &fullId)
{
    m_host.unregisterAction(m_plugin, fullId);
}

// ---- StorageApi ----

QJSValue StorageApi::get(const QString &key, const QJSValue &fallback) const
{
    const QSettings settings;
    const QString k = storageKey(m_plugin, key);
    if (!settings.contains(k))
        return fallback;
    const QJsonDocument json = QJsonDocument::fromJson(settings.value(k).toByteArray());
    if (!json.isObject())
        return fallback;
    QJSEngine *e = engine();
    return e ? e->toScriptValue(json.object().value(QLatin1String("v")).toVariant()) : fallback;
}

void StorageApi::set(const QString &key, const QJSValue &value)
{
    if (value.isUndefined()) {
        remove(key);
        return;
    }
    QSettings settings;
    settings.setValue(
        storageKey(m_plugin, key),
        QJsonDocument::fromVariant(QVariantMap{{QStringLiteral("v"), value.toVariant()}})
            .toJson(QJsonDocument::Compact));
}

void StorageApi::remove(const QString &key)
{
    QSettings settings;
    settings.remove(storageKey(m_plugin, key));
}

QStringList StorageApi::keys() const
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("plugins/") + m_plugin.manifest.id +
                        QStringLiteral("/data"));
    return settings.childKeys();
}

// ---- ProjectApi ----

bool ProjectApi::isOpen() const
{
    const DecompProject *p = m_host.bindings().project;
    return p && p->isOpen();
}

QString ProjectApi::root() const
{
    const DecompProject *p = m_host.bindings().project;
    return p && p->isOpen() ? p->root() : QString();
}

QVariantList ProjectApi::songs() const
{
    QVariantList out;
    const DecompProject *p = m_host.bindings().project;
    if (!p || !p->isOpen())
        return out;
    for (const SongInfo &song : p->songs()) {
        out.append(QVariantMap{{QStringLiteral("id"), song.id},
                               {QStringLiteral("label"), song.label},
                               {QStringLiteral("constant"), song.constant},
                               {QStringLiteral("player"), song.player},
                               {QStringLiteral("midPath"), song.midPath},
                               {QStringLiteral("hasMid"), song.hasMid},
                               {QStringLiteral("registered"), song.registered}});
    }
    return out;
}

// ---- installApi ----

bool installApi(ScriptHost &host, Plugin &plugin, QString *error)
{
    QJSEngine *engine = plugin.engine.get();
    QFile preludeFile(QStringLiteral(":/scripting/prelude.js"));
    if (!preludeFile.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("scripting prelude resource missing");
        return false;
    }
    const QJSValue factory = engine->evaluate(QString::fromUtf8(preludeFile.readAll()),
                                              QStringLiteral("porydaw:prelude.js"));
    if (factory.isError() || !factory.isCallable()) {
        *error = QStringLiteral("scripting prelude failed: ") + factory.toString();
        return false;
    }

    QJSValueList facades;
    const auto add = [&](ApiObject *object) {
        plugin.facades.emplace_back(object);
        QJSEngine::setObjectOwnership(object, QJSEngine::CppOwnership);
        facades.append(engine->newQObject(object));
    };
    add(new HostApi(host, plugin));
    add(new SongApi(host, plugin));
    add(new SelectionApi(host, plugin));
    add(new CursorApi(host, plugin));
    add(new TransportApi(host, plugin));
    add(new ActionsApi(host, plugin));
    add(new StorageApi(host, plugin));
    add(new ProjectApi(host, plugin));

    const QJSValue result = factory.call(facades);
    if (result.isError() || !result.isObject()) {
        *error = QStringLiteral("scripting prelude failed: ") + result.toString();
        return false;
    }
    plugin.dispatch = result.property(QStringLiteral("dispatch"));
    plugin.runAction = result.property(QStringLiteral("runAction"));
    engine->globalObject().setProperty(QStringLiteral("porydaw"),
                                       result.property(QStringLiteral("porydaw")));
    engine->globalObject().setProperty(QStringLiteral("console"),
                                       result.property(QStringLiteral("console")));
    return true;
}

} // namespace scripting
