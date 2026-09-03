#include "scriptapi.h"

#include <QAction>
#include <QFile>
#include <QJSEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

#include <algorithm>
#include <cmath>
#include <map>

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

int clampInt(const QVariant &v, int lo, int hi)
{
    const double d = v.toDouble();
    if (!std::isfinite(d))
        return lo;
    return int(std::clamp(d, double(lo), double(hi)));
}

// Script tick deltas: NaN/Infinity read as 0, otherwise clamped to a span
// the document's clamps can absorb.
int64_t clampDelta(double value)
{
    if (!std::isfinite(value))
        return 0;
    return int64_t(std::clamp(value, -kMaxTick, kMaxTick));
}

// A track argument must be an actual integer: JS undefined/NaN/null would
// otherwise coerce to 0 and silently target track 0.
bool variantTrack(const QVariant &v, int *out)
{
    if (!v.isValid() || v.isNull() || v.userType() == QMetaType::QString ||
        v.userType() == QMetaType::Bool)
        return false;
    bool ok = false;
    const double d = v.toDouble(&ok);
    if (!ok || !std::isfinite(d) || d != std::floor(d) || d < -1.0 || d > 1e6)
        return false;
    *out = int(d);
    return true;
}

bool isLaneCc(int cc)
{
    return (cc >= 0 && cc <= 127) || cc == DOC_CC_BEND || cc == DOC_CC_TEMPO || cc == DOC_CC_VOICE;
}

int clampLaneValue(int cc, const QVariant &v)
{
    if (cc == DOC_CC_BEND)
        return clampInt(v, -8192, 8191);
    if (cc == DOC_CC_TEMPO)
        return clampInt(v, SongDocument::kTempoMin, SongDocument::kTempoMax);
    return clampInt(v, 0, 127);
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
    m_host.log(m_plugin, LogLevel::Error, m_host.formatError(error));
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

void SelectionApi::setTime(const QVariantMap &spec)
{
    SongView *v = view();
    const SongDocument *d = doc();
    if (!v || !d)
        return;
    SongView::TimeSelection sel;
    sel.startTick = clampTick(spec.value(QStringLiteral("start")).toDouble());
    sel.endTick = clampTick(spec.value(QStringLiteral("end")).toDouble());
    if (sel.endTick <= sel.startTick) {
        throwError(QStringLiteral("selection.setTime: end must be greater than start"));
        return;
    }
    const QString scope = spec.value(QStringLiteral("scope"), QStringLiteral("tracks")).toString();
    if (scope == QLatin1String("lanes")) {
        sel.scope = SongView::TimeSelection::Lanes;
        for (const QVariant &entry : spec.value(QStringLiteral("lanes")).toList()) {
            const QVariantMap lane = entry.toMap();
            int track = -1;
            const int cc = lane.value(QStringLiteral("cc"), -1).toInt();
            const bool tempo = cc == DOC_CC_TEMPO;
            if (!isLaneCc(cc) || !variantTrack(lane.value(QStringLiteral("track"), -1), &track) ||
                (tempo && track != -1) ||
                (!tempo && (track < 0 || track >= d->engineTrackCount()))) {
                throwError(QStringLiteral("selection.setTime: bad lane"));
                return;
            }
            sel.lanes.emplace_back(track, uint8_t(cc));
        }
        if (sel.lanes.empty()) {
            throwError(QStringLiteral("selection.setTime: lanes scope needs at least one lane"));
            return;
        }
    } else if (scope != QLatin1String("tracks")) {
        throwError(QStringLiteral("selection.setTime: scope must be 'tracks' or 'lanes'"));
        return;
    }
    v->setTimeSelection(sel);
}

void SelectionApi::clearTime()
{
    if (SongView *v = view())
        v->clearTimeSelection();
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

// ---- EditApi ----

bool EditApi::active() const
{
    const EditTransaction &tx = m_host.transaction();
    return tx.open() && tx.owner == &m_plugin;
}

void EditApi::begin(const QString &name)
{
    QString error;
    if (!m_host.beginTransaction(m_plugin, name, &error))
        throwError(QStringLiteral("edit.transaction: ") + error);
}

void EditApi::commit()
{
    QString error;
    if (!m_host.commitTransaction(m_plugin, &error))
        throwError(QStringLiteral("edit.transaction: ") + error);
}

void EditApi::rollback()
{
    m_host.rollbackTransaction(m_plugin);
}

SongDocument *EditApi::begin()
{
    QString error;
    SongDocument *d = m_host.transactionDocument(m_plugin, &error);
    if (!d)
        throwError(QStringLiteral("porydaw.edit: ") + error);
    return d;
}

void EditApi::done()
{
    m_host.transactionEdited();
}

// One sweep of the document, not one findNote per id (which rebuilds
// every track's note list each time).
std::vector<DocNote> EditApi::resolveNotes(const SongDocument *d, const QVariantList &ids) const
{
    std::vector<DocNote> notes;
    if (ids.isEmpty())
        return notes;
    std::map<uint64_t, DocNote> byId;
    for (int t = 0; t < d->engineTrackCount(); ++t) {
        for (const DocNote &note : d->notesForTrack(t))
            byId.emplace(note.noteId.token(), note);
    }
    for (const QVariant &id : ids) {
        const auto it = byId.find(clampId(id.toDouble()));
        if (it != byId.end())
            notes.push_back(it->second);
    }
    return notes;
}

bool EditApi::checkTrack(const SongDocument *d, int track, const char *api)
{
    if (track >= 0 && track < d->engineTrackCount())
        return true;
    throwError(QStringLiteral("edit.%1: no such track").arg(QLatin1String(api)));
    return false;
}

int EditApi::laneTrack(const SongDocument *d, int track, int cc, const char *api)
{
    if (!isLaneCc(cc)) {
        throwError(QStringLiteral("edit.%1: cc must be 0-127 or a porydaw.song.CC value")
                       .arg(QLatin1String(api)));
        return -2;
    }
    if (cc == DOC_CC_TEMPO)
        return -1;
    return checkTrack(d, track, api) ? track : -2;
}

QVariantList EditApi::addNotes(int track, const QVariantList &notes)
{
    QVariantList ids;
    SongDocument *d = begin();
    if (!d)
        return ids;
    if (!checkTrack(d, track, "addNotes")) {
        done();
        return ids;
    }
    std::vector<SongDocument::NewNote> batch;
    for (const QVariant &entry : notes) {
        if (entry.userType() != QMetaType::QVariantMap) {
            throwError(QStringLiteral("edit.addNotes: each note must be an object "
                                      "{tick, key, len, vel}"));
            done();
            return QVariantList();
        }
        const QVariantMap n = entry.toMap();
        SongDocument::NewNote note;
        note.tick = clampTick(n.value(QStringLiteral("tick")).toDouble());
        note.key = uint8_t(clampInt(n.value(QStringLiteral("key")), 0, 127));
        note.duration = uint32_t(clampInt(n.value(QStringLiteral("len"), 1), 1, INT32_MAX));
        note.velocity = uint8_t(clampInt(n.value(QStringLiteral("vel"), 127), 1, 127));
        batch.push_back(note);
    }
    // Two entries on one (tick, key) can't both exist (the pairing rule);
    // the later one wins and the earlier reports id 0.
    std::vector<bool> shadowed(batch.size(), false);
    std::vector<SongDocument::NewNote> written;
    for (size_t i = 0; i < batch.size(); ++i) {
        for (size_t j = i + 1; j < batch.size() && !shadowed[i]; ++j)
            shadowed[i] = batch[j].tick == batch[i].tick && batch[j].key == batch[i].key;
        if (!shadowed[i])
            written.push_back(batch[i]);
    }
    if (!written.empty())
        d->addNotes(track, written);
    std::map<std::pair<uint64_t, uint8_t>, double> minted;
    for (const DocNote &note : d->notesForTrack(track))
        minted.emplace(std::make_pair(note.tick, note.key), double(note.noteId.token()));
    for (size_t i = 0; i < batch.size(); ++i) {
        const auto it = minted.find({batch[i].tick, batch[i].key});
        ids.append(!shadowed[i] && it != minted.end() ? it->second : 0.0);
    }
    done();
    return ids;
}

int EditApi::deleteNotes(const QVariantList &ids)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    const std::vector<DocNote> notes = resolveNotes(d, ids);
    if (!notes.empty())
        d->deleteNotes(notes);
    done();
    return int(notes.size());
}

int EditApi::moveNotes(const QVariantList &ids, double dTick, int dKey)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    const std::vector<DocNote> notes = resolveNotes(d, ids);
    if (!notes.empty())
        d->moveNotes(notes, clampDelta(dTick), std::clamp(dKey, -127, 127));
    done();
    return int(notes.size());
}

int EditApi::resizeNotes(const QVariantList &ids, double dLen, bool fromLeft)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    const std::vector<DocNote> notes = resolveNotes(d, ids);
    if (!notes.empty()) {
        if (fromLeft)
            d->resizeNotesLeft(notes, -clampDelta(dLen));
        else
            d->resizeNotes(notes, clampDelta(dLen));
    }
    done();
    return int(notes.size());
}

int EditApi::setVelocities(const QVariantList &pairs)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    QVariantList ids;
    for (const QVariant &entry : pairs)
        ids.append(entry.toMap().value(QStringLiteral("id")));
    const std::vector<DocNote> known = resolveNotes(d, ids);
    std::vector<NoteVelocity> velocities;
    for (const QVariant &entry : pairs) {
        const QVariantMap pair = entry.toMap();
        const uint64_t token = clampId(pair.value(QStringLiteral("id")).toDouble());
        const bool exists = std::any_of(known.begin(), known.end(), [token](const DocNote &n) {
            return n.noteId.token() == token;
        });
        if (!exists)
            continue;
        velocities.push_back(
            {NoteId(token), uint8_t(clampInt(pair.value(QStringLiteral("vel")), 1, 127))});
    }
    if (!velocities.empty())
        d->setNotesVelocities(d->revision(), velocities);
    done();
    return int(velocities.size());
}

int EditApi::nudgeVelocity(const QVariantList &ids, int delta)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    const std::vector<DocNote> notes = resolveNotes(d, ids);
    if (!notes.empty())
        d->nudgeNotesVelocity(notes, std::clamp(delta, -127, 127));
    done();
    return int(notes.size());
}

void EditApi::addLanePoint(int track, int cc, double tick, int value)
{
    SongDocument *d = begin();
    if (!d)
        return;
    const int engineTrack = laneTrack(d, track, cc, "addLanePoint");
    if (engineTrack != -2)
        d->addLanePoint(engineTrack, uint8_t(cc), clampTick(tick), clampLaneValue(cc, value));
    done();
}

void EditApi::writeLanePoints(int track, int cc, double from, double to, const QVariantList &points)
{
    SongDocument *d = begin();
    if (!d)
        return;
    const int engineTrack = laneTrack(d, track, cc, "writeLanePoints");
    if (engineTrack == -2) {
        done();
        return;
    }
    if (cc == DOC_CC_VOICE) {
        throwError(QStringLiteral("edit.writeLanePoints: use addLanePoint for the voice lane"));
        done();
        return;
    }
    const uint64_t begin = clampTick(from);
    const uint64_t end = clampTick(to);
    std::vector<SongDocument::LanePointValue> values;
    for (const QVariant &entry : points) {
        const QVariantMap p = entry.toMap();
        const uint64_t tick = clampTick(p.value(QStringLiteral("tick")).toDouble());
        if (tick < begin || tick > end)
            continue;
        values.push_back({tick, clampLaneValue(cc, p.value(QStringLiteral("value")))});
    }
    if (begin <= end)
        d->writeLanePoints(engineTrack, uint8_t(cc), begin, end, values);
    done();
}

int EditApi::moveLanePoints(int track, int cc, const QVariantList &moves)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    const int engineTrack = laneTrack(d, track, cc, "moveLanePoints");
    std::vector<SongDocument::LanePointMove> batch;
    if (engineTrack != -2) {
        for (const QVariant &entry : moves) {
            const QVariantMap m = entry.toMap();
            SongDocument::LanePointMove move;
            move.engineTrack = engineTrack;
            move.cc = uint8_t(cc);
            const uint64_t tick = clampTick(m.value(QStringLiteral("tick")).toDouble());
            if (!d->findLanePoint(engineTrack, uint8_t(cc), tick, &move.point))
                continue;
            move.newTick = m.contains(QStringLiteral("newTick"))
                               ? clampTick(m.value(QStringLiteral("newTick")).toDouble())
                               : tick;
            move.newValue = m.contains(QStringLiteral("newValue"))
                                ? clampLaneValue(cc, m.value(QStringLiteral("newValue")))
                                : move.point.value;
            batch.push_back(move);
        }
        if (!batch.empty())
            d->moveLanePoints(batch);
    }
    done();
    return int(batch.size());
}

int EditApi::deleteLanePoints(int track, int cc, const QVariantList &ticks)
{
    SongDocument *d = begin();
    if (!d)
        return 0;
    const int engineTrack = laneTrack(d, track, cc, "deleteLanePoints");
    std::vector<DocLanePoint> points;
    if (engineTrack != -2) {
        for (const QVariant &tick : ticks) {
            DocLanePoint p;
            if (d->findLanePoint(engineTrack, uint8_t(cc), clampTick(tick.toDouble()), &p))
                points.push_back(p);
        }
        if (!points.empty())
            d->deleteLanePoints(engineTrack, uint8_t(cc), points);
    }
    done();
    return int(points.size());
}

void EditApi::setStartTempo(int bpm)
{
    SongDocument *d = begin();
    if (!d)
        return;
    d->setStartTempo(std::clamp(bpm, SongDocument::kTempoMin, SongDocument::kTempoMax));
    done();
}

void EditApi::setLoop(const QJSValue &start, const QJSValue &end)
{
    SongDocument *d = begin();
    if (!d)
        return;
    const auto marker = [](const QJSValue &v) -> int64_t {
        if (v.isNull() || v.isUndefined())
            return -1;
        return int64_t(clampTick(v.toNumber()));
    };
    d->setLoopTick(false, marker(start));
    d->setLoopTick(true, marker(end));
    done();
}

void EditApi::setTimeSig(double tick, int numerator, int denominator)
{
    SongDocument *d = begin();
    if (!d)
        return;
    int pow2 = -1;
    for (int p = 0; p <= 7; ++p) {
        if (denominator == (1 << p))
            pow2 = p;
    }
    if (pow2 < 0 || numerator < 1 || numerator > 255) {
        throwError(QStringLiteral("edit.setTimeSig: numerator must be 1-255 and the denominator "
                                  "a power of two up to 128"));
    } else {
        d->setTimeSig(clampTick(tick), numerator, pow2);
    }
    done();
}

void EditApi::deleteTimeSig(double tick)
{
    SongDocument *d = begin();
    if (!d)
        return;
    d->deleteTimeSig(clampTick(tick));
    done();
}

namespace {

bool parseScope(const SongDocument *d, const QVariantMap &spec, RippleScope *scope, QString *error)
{
    scope->wholeSong = spec.value(QStringLiteral("wholeSong")).toBool();
    for (const QVariant &t : spec.value(QStringLiteral("tracks")).toList()) {
        int track = -1;
        if (!variantTrack(t, &track) || track < 0 || track >= d->engineTrackCount()) {
            *error = QStringLiteral("scope.tracks names a track that does not exist");
            return false;
        }
        scope->tracks.push_back(track);
    }
    for (const QVariant &entry : spec.value(QStringLiteral("lanes")).toList()) {
        const QVariantMap lane = entry.toMap();
        int track = -1;
        const int cc = lane.value(QStringLiteral("cc"), -1).toInt();
        const bool tempo = cc == DOC_CC_TEMPO;
        if (!isLaneCc(cc) ||
            (!tempo && (!variantTrack(lane.value(QStringLiteral("track")), &track) || track < 0 ||
                        track >= d->engineTrackCount()))) {
            *error = QStringLiteral("scope.lanes has a bad lane");
            return false;
        }
        scope->lanes.emplace_back(tempo ? -1 : track, uint8_t(cc));
    }
    if (!scope->wholeSong && scope->tracks.empty() && scope->lanes.empty()) {
        *error = QStringLiteral("scope needs tracks, lanes, or wholeSong: true");
        return false;
    }
    return true;
}

} // namespace

bool EditApi::removeTimeRange(double start, double end, const QVariantMap &scopeSpec)
{
    SongDocument *d = begin();
    if (!d)
        return false;
    RippleScope scope;
    QString error;
    bool changed = false;
    if (!parseScope(d, scopeSpec, &scope, &error))
        throwError(QStringLiteral("edit.removeTimeRange: ") + error);
    else if (clampTick(end) > clampTick(start))
        changed = d->removeTimeRange(clampTick(start), clampTick(end), scope);
    done();
    return changed;
}

bool EditApi::insertTimeRange(double at, double span, const QVariantMap &scopeSpec)
{
    SongDocument *d = begin();
    if (!d)
        return false;
    RippleScope scope;
    QString error;
    bool changed = false;
    if (!parseScope(d, scopeSpec, &scope, &error))
        throwError(QStringLiteral("edit.insertTimeRange: ") + error);
    else if (clampTick(span) > 0)
        changed = d->insertTimeRange(clampTick(at), clampTick(span), scope);
    done();
    return changed;
}

int EditApi::addTrack(int voice)
{
    SongDocument *d = begin();
    if (!d)
        return -1;
    const int index = d->canAddTrack() ? d->addTrack(std::clamp(voice, 0, 127)) : -1;
    done();
    return index;
}

int EditApi::duplicateTrack(int track)
{
    SongDocument *d = begin();
    if (!d)
        return -1;
    int index = -1;
    if (checkTrack(d, track, "duplicateTrack"))
        index = d->duplicateTrack(track);
    done();
    return index;
}

void EditApi::deleteTrack(int track)
{
    SongDocument *d = begin();
    if (!d)
        return;
    if (checkTrack(d, track, "deleteTrack"))
        d->deleteTrack(track);
    done();
}

bool EditApi::moveTrack(int track, int target)
{
    SongDocument *d = begin();
    if (!d)
        return false;
    bool moved = false;
    if (checkTrack(d, track, "moveTrack") && checkTrack(d, target, "moveTrack"))
        moved = d->moveTrack(track, target);
    done();
    return moved;
}

void EditApi::renameTrack(int track, const QString &name)
{
    SongDocument *d = begin();
    if (!d)
        return;
    if (checkTrack(d, track, "renameTrack")) {
        if (nameIsLoopMarker(name))
            throwError(QStringLiteral("edit.renameTrack: mid2agb would read that name as a "
                                      "loop marker"));
        else
            d->renameTrack(track, name);
    }
    done();
}

bool EditApi::transposeSelection(int dKey)
{
    SongDocument *d = begin();
    if (!d)
        return false;
    SongView *v = view();
    const bool moved = v && v->transposeSelection(std::clamp(dKey, -127, 127), false);
    done();
    return moved;
}

bool EditApi::nudgeSelection(bool right)
{
    SongDocument *d = begin();
    if (!d)
        return false;
    SongView *v = view();
    const bool moved = v && v->nudgeSelection(right, false);
    done();
    return moved;
}

// ---- ViewApi ----

bool ViewApi::velocityLane() const
{
    const SongView *v = view();
    return v && v->velocityLaneVisible();
}

void ViewApi::setVelocityLane(bool on)
{
    if (SongView *v = view())
        v->setVelocityLaneVisible(on);
}

bool ViewApi::automationLanes() const
{
    const SongView *v = view();
    return v && v->automationLanesVisible();
}

void ViewApi::setAutomationLanes(bool on)
{
    if (SongView *v = view())
        v->setAutomationLanesVisible(on);
}

bool ViewApi::tempoLane() const
{
    const SongView *v = view();
    return v && v->tempoLaneVisible();
}

void ViewApi::setTempoLane(bool on)
{
    if (SongView *v = view())
        v->setTempoLaneVisible(on);
}

bool ViewApi::eventList() const
{
    const SongView *v = view();
    return v && v->eventListVisible();
}

void ViewApi::setEventList(bool on)
{
    if (SongView *v = view())
        v->setEventListVisible(on);
}

double ViewApi::pxPerBeat() const
{
    const SongView *v = view();
    return v ? v->pxPerBeat() : 0.0;
}

double ViewApi::keyHeight() const
{
    const SongView *v = view();
    return v ? v->keyHeight() : 0.0;
}

QVariant ViewApi::visibleTicks() const
{
    const SongView *v = view();
    if (!v)
        return jsNull();
    uint64_t from, to;
    v->visibleTickRange(&from, &to);
    return QVariantMap{{QStringLiteral("from"), double(from)}, {QStringLiteral("to"), double(to)}};
}

void ViewApi::revealTick(double tick)
{
    if (SongView *v = view())
        v->ensureTickVisible(clampTick(tick));
}

void ViewApi::revealRange(double from, double to)
{
    SongView *v = view();
    if (!v)
        return;
    const uint64_t a = clampTick(from);
    const uint64_t b = clampTick(to);
    v->ensureRangeVisible(std::min(a, b), std::max(a, b), false);
}

bool ViewApi::revealNote(double id)
{
    SongView *v = view();
    const SongDocument *d = doc();
    DocNote note;
    if (!v || !d || clampId(id) == 0 || !d->findNote(NoteId(clampId(id)), &note))
        return false;
    return v->revealNote(note.engineTrack, note.key, note.tick);
}

void ViewApi::revealKey(int key)
{
    if (SongView *v = view())
        v->ensureKeyVisible(std::clamp(key, 0, 127));
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
    add(new EditApi(host, plugin));
    add(new ViewApi(host, plugin));

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
