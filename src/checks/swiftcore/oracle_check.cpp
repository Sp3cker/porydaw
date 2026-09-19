#include "oracle_check.h"

#include <QByteArray>
#include <QFile>
#include <QString>
#include <QStringList>

#include <algorithm>
#include <array>
#include <bit>
#include <cstring>
#include <limits>
#include <memory>
#include <optional>
#include <span>
#include <vector>

#include "checks/playback/sustainvoicegroup.h"
#include "core/m4asemantics.h"
#include "core/mid2agbtables.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/timedefaults.h"
#include "core/timelineplayer.h"
#include "core/tracklimits.h"
#include "core/velocitymodel.h"
#include "project/songregistry.h"

struct OraclePlaybackEngine {
    M4AEngine engine{};
    checks::SustainVoicegroup bank;
    bool initialized = false;

    explicit OraclePlaybackEngine(double sampleRate)
    {
        initialized = m4a_engine_init(&engine, float(sampleRate));
        if (initialized)
            m4a_engine_set_voicegroup(&engine, bank.voices);
    }

    ~OraclePlaybackEngine()
    {
        if (initialized)
            m4a_engine_destroy(&engine);
    }
};

namespace {
QByteArray gFixtureRoot;

QString codecSummary(const SmfFile &file)
{
    QStringList parts{
        QStringLiteral("division=%1").arg(file.division),
        QStringLiteral("chunks=%1").arg(file.tracks.size()),
        QStringLiteral("was0=%1").arg(file.wasFormat0 ? 1 : 0),
    };
    for (size_t index = 0; index < file.tracks.size(); ++index) {
        const SmfTrack &track = file.tracks[index];
        parts.append(
            QStringLiteral("chunk%1=%2,%3").arg(index).arg(track.endTick).arg(track.events.size()));
    }
    const SmfEngineTrackMapping mapping = mapSmfEngineTracks(file);
    parts.append(
        QStringLiteral("map=%1,%2").arg(mapping.usedTrackCount).arg(mapping.droppedTracks));
    for (int index = 0; index < mapping.usedTrackCount; ++index) {
        parts.append(QStringLiteral("slot%1=%2,%3")
                         .arg(index)
                         .arg(mapping.tracks[size_t(index)].smfTrack)
                         .arg(mapping.tracks[size_t(index)].channel));
    }
    return parts.join(QLatin1Char(';'));
}

void copyBytes(const QByteArray &source, void *output, size_t capacity)
{
    if (!output || capacity == 0)
        return;
    std::memcpy(output, source.constData(), std::min(capacity, size_t(source.size())));
}

ToneData tone(uint8_t type)
{
    ToneData result{};
    result.type = type;
    return result;
}

VelocityMap velocityMap(int kind)
{
    switch (kind) {
    case 0:
        return VelocityMap::resolve(nullptr, std::nullopt);
    case 1: {
        const ToneData data = tone(VOICE_CRY);
        return VelocityMap::resolve(&data, 60);
    }
    case 2: {
        const ToneData data = tone(VOICE_KEYSPLIT);
        return VelocityMap::resolve(&data, std::nullopt);
    }
    case 3: {
        const ToneData data = tone(VOICE_DIRECTSOUND);
        return VelocityMap::resolve(&data, 60);
    }
    case 4: {
        const ToneData data = tone(VOICE_SQUARE_1);
        return VelocityMap::resolve(&data, 60);
    }
    case 5: {
        const ToneData data = tone(VOICE_SQUARE_2);
        return VelocityMap::resolve(&data, 60);
    }
    case 6: {
        const ToneData data = tone(VOICE_PROGRAMMABLE_WAVE);
        return VelocityMap::resolve(&data, 60);
    }
    default: {
        const ToneData data = tone(VOICE_NOISE);
        return VelocityMap::resolve(&data, 60);
    }
    }
}

QByteArray semanticText(uint32_t operation, int64_t a, int64_t b)
{
    QString text;
    switch (operation) {
    case ORACLE_CC_NAME:
        text = QString::fromLatin1(m4aClassifyCc(uint8_t(a)).name);
        break;
    case ORACLE_CC_DISPLAY:
        text = QString::fromLatin1(m4aClassifyCc(uint8_t(a)).display);
        break;
    case ORACLE_LANE_NAME:
        text = m4aLaneName(M4aLane(a));
        break;
    case ORACLE_CC_VALUE:
        text = m4aFormatCcValue(uint8_t(a), uint8_t(b));
        break;
    case ORACLE_ADVANCED_CC_LABEL:
        text = m4aAdvancedCcLabel(uint8_t(a), uint8_t(b));
        break;
    case ORACLE_BEND:
        text = m4aFormatBend(int(a));
        break;
    case ORACLE_VOICE_TYPE:
        text = m4aVoiceTypeName(uint8_t(a));
        break;
    case ORACLE_KEY_NAME:
        text = midiKeyName(int(a));
        break;
    case ORACLE_TIME_SIGNATURE:
        text = midiTimeSigLabel(int(a), int(b));
        break;
    case ORACLE_VELOCITY_NAME:
        text = QString::fromLatin1(velocityMap(int(a)).voiceName());
        break;
    default:
        return {};
    }
    return text.toUtf8();
}

} // namespace

extern "C" void oracle_check_set_fixture_root(const char *path)
{
    gFixtureRoot = path ? QByteArray(path) : QByteArray();
}

extern "C" const char *oracle_check_fixture_root()
{
    return gFixtureRoot.isEmpty() ? nullptr : gFixtureRoot.constData();
}

extern "C" int64_t oracle_codec_roundtrip(const uint8_t *input, size_t inputCount, uint8_t *output,
                                          size_t outputCapacity, uint8_t *wasFormatZero,
                                          char *summary, size_t summaryCapacity,
                                          size_t *summarySize, char *errorOut, size_t errorCapacity,
                                          size_t *errorSize)
{
    const QByteArray bytes(reinterpret_cast<const char *>(input), int(inputCount));
    SmfFile file;
    QString error;
    if (!SmfFile::read(bytes, &file, &error)) {
        const QByteArray errorBytes = error.toUtf8();
        if (wasFormatZero)
            *wasFormatZero = 0;
        if (summarySize)
            *summarySize = 0;
        if (errorSize)
            *errorSize = size_t(errorBytes.size());
        copyBytes(errorBytes, errorOut, errorCapacity);
        return -1;
    }

    const QByteArray encoded = file.write();
    const QByteArray summaryBytes = codecSummary(file).toUtf8();
    if (wasFormatZero)
        *wasFormatZero = file.wasFormat0 ? 1 : 0;
    if (summarySize)
        *summarySize = size_t(summaryBytes.size());
    if (errorSize)
        *errorSize = 0;
    copyBytes(encoded, output, outputCapacity);
    copyBytes(summaryBytes, summary, summaryCapacity);
    return encoded.size();
}

extern "C" int64_t oracle_blank_song(uint8_t *output, size_t outputCapacity)
{
    const QByteArray bytes = SongRegistry::blankSong().write();
    copyBytes(bytes, output, outputCapacity);
    return bytes.size();
}

extern "C" int64_t oracle_semantic_value(uint32_t operation, int64_t a, int64_t b, int64_t c,
                                         int64_t d)
{
    switch (operation) {
    case ORACLE_CC_CLASS:
        return int64_t(m4aClassifyCc(uint8_t(a)).eventClass);
    case ORACLE_CC_LANE:
        return int64_t(m4aClassifyCc(uint8_t(a)).lane);
    case ORACLE_CC_EXPORT:
        return int64_t(m4aExportSupport(uint8_t(a)));
    case ORACLE_XCMD_LANE:
        return int64_t(m4aLaneForXcmdSelector(uint8_t(a)));
    case ORACLE_EFFECTIVE_VELOCITY:
        return mid2agbEffectiveVelocity(int(a));
    case ORACLE_EFFECTIVE_DURATION:
        return mid2agbEffectiveDuration(int(a), uint32_t(b), c != 0, d != 0);
    case ORACLE_VELOCITY_IS_PSG:
        return velocityMap(int(a)).isPsg();
    case ORACLE_VELOCITY_COMPATIBLE:
        return velocityMap(int(a)).compatibleWith(velocityMap(int(b)));
    case ORACLE_VELOCITY_LEVEL_COUNT:
        return int64_t(velocityMap(int(a)).levelCount());
    case ORACLE_VELOCITY_LEVEL_RANGE: {
        const VelocityLevelRange range = velocityMap(int(a)).levelRange(int(b));
        return (int64_t(range.first) << 8) | int64_t(range.last);
    }
    case ORACLE_VELOCITY_LEVEL:
        if (const std::optional<size_t> level = velocityMap(int(a)).levelOf(int(b)))
            return int64_t(*level);
        return -1;
    case ORACLE_VELOCITY_REPRESENTATIVE:
        return velocityMap(int(a)).representative(int(b));
    case ORACLE_VELOCITY_CANONICALIZE:
        return velocityMap(int(a)).canonicalize(int(b));
    case ORACLE_VELOCITY_MOVE_LEVELS:
        return velocityMap(int(a)).moveLevels(uint8_t(b), int(c));
    case ORACLE_CONTROLLER_DEFAULT:
        return CoreTimeDefaults::controllerDefault(uint8_t(a));
    case ORACLE_LANE_MINIMUM:
        return CoreTimeDefaults::laneDomain(uint8_t(a)).minimum;
    case ORACLE_LANE_MAXIMUM:
        return CoreTimeDefaults::laneDomain(uint8_t(a)).maximum;
    case ORACLE_LANE_CENTERED:
        return CoreTimeDefaults::laneDomain(uint8_t(a)).centered;
    case ORACLE_LANE_ZOOMABLE:
        return CoreTimeDefaults::laneDomain(uint8_t(a)).zoomable;
    case ORACLE_HAS_ENGINE_DEFAULT:
        return CoreTimeDefaults::hasEngineDefaultNode(uint8_t(a));
    case ORACLE_TEMPO_FROM_BPM:
        return CoreTimeDefaults::microsecondsPerQuarterNoteForBpm(int(a));
    case ORACLE_BPM_FROM_TEMPO:
        return std::bit_cast<int64_t>(CoreTimeDefaults::tempoBpm(uint32_t(a)));
    case ORACLE_CLAMP_TEMPO:
        return CoreTimeDefaults::clampTempoUspqn(uint32_t(a));
    case ORACLE_SHIFT_TICK:
        return CoreTimeDefaults::shiftTickClamped(Tick(a), b);
    case ORACLE_TICK_FROM_DOUBLE:
        return CoreTimeDefaults::tickFromDouble(std::bit_cast<double>(a));
    case ORACLE_TRACK_CAPACITY:
        return track_limits::kHardwareCapacity;
    case ORACLE_NOTE_ID_ASSIGNED:
        return NoteId(uint64_t(a)).isAssigned();
    case ORACLE_NOTE_ID_STORAGE: {
        SmfEvent plain;
        plain.tick = 12;
        plain.status = 0x90;
        plain.data0 = 60;
        plain.data1 = 100;
        SmfEvent stamped = plain;
        stamped.noteId = NoteId(42);
        SmfTrack plainTrack;
        plainTrack.events = {plain};
        plainTrack.endTick = 24;
        SmfFile plainFile;
        plainFile.division = 24;
        plainFile.tracks = {plainTrack};
        SmfTrack stampedTrack;
        stampedTrack.events = {stamped};
        stampedTrack.endTick = 24;
        SmfFile stampedFile;
        stampedFile.division = 24;
        stampedFile.tracks = {stampedTrack};
        return plain == stamped && plainFile.write() == stampedFile.write();
    }
    default:
        return std::numeric_limits<int64_t>::min();
    }
}

extern "C" int64_t oracle_semantic_text(uint32_t operation, int64_t a, int64_t b, char *output,
                                        size_t outputCapacity)
{
    const QByteArray bytes = semanticText(operation, a, b);
    if (bytes.isEmpty() && operation > ORACLE_VELOCITY_NAME)
        return -1;
    copyBytes(bytes, output, outputCapacity);
    return bytes.size();
}

namespace {

void writePlaybackError(const QString &error, char *output, size_t capacity)
{
    if (!output || capacity == 0)
        return;
    const QByteArray bytes = error.toUtf8();
    const size_t count = std::min(capacity - 1, size_t(bytes.size()));
    std::memcpy(output, bytes.constData(), count);
    output[count] = '\0';
}

std::unique_ptr<MidiTimeline> loadPlaybackTimeline(const char *path, double sampleRate,
                                                   char *errorOut, size_t errorCapacity)
{
    if (!path) {
        writePlaybackError(QStringLiteral("missing playback fixture path"), errorOut,
                           errorCapacity);
        return {};
    }
    QString error;
    std::unique_ptr<MidiTimeline> timeline =
        MidiTimeline::load(QFile::decodeName(path), sampleRate, &error);
    if (!timeline)
        writePlaybackError(error, errorOut, errorCapacity);
    return timeline;
}

} // namespace

extern "C" int64_t oracle_playback_project_file(const char *path, double sampleRate,
                                                OraclePlaybackEvent *events, size_t eventCapacity,
                                                OraclePlaybackData *data, char *errorOut,
                                                size_t errorCapacity)
{
    if (errorOut && errorCapacity > 0)
        errorOut[0] = '\0';
    std::unique_ptr<MidiTimeline> timeline =
        loadPlaybackTimeline(path, sampleRate, errorOut, errorCapacity);
    if (!timeline)
        return -1;

    if (events) {
        const size_t count = std::min(eventCapacity, timeline->events.size());
        for (size_t index = 0; index < count; ++index) {
            const TimelineEvent &event = timeline->events[index];
            events[index] = OraclePlaybackEvent{
                event.samplePos,
                event.tick,
                event.type,
                event.track,
                event.data0,
                event.data1,
                std::bit_cast<uint64_t>(event.noteId),
            };
        }
    }
    if (data) {
        *data = OraclePlaybackData{
            timeline->events.size(),
            timeline->tempoMap.size(),
            timeline->sampleRate,
            timeline->lengthSamples,
            timeline->loopStartSample,
            timeline->loopEndSample,
            timeline->ticksPerBeat,
            timeline->lengthTicks,
            timeline->loopStartTick,
            timeline->loopEndTick,
            uint32_t(timeline->usedTrackCount),
            uint32_t(timeline->droppedTracks),
            false,
            timeline->extendedClocks,
        };
    }
    return int64_t(timeline->events.size());
}

extern "C" bool oracle_playback_render_files(const char *path, const char *replacementPath,
                                             double sampleRate, OraclePlaybackEngine *engine,
                                             float *left, float *right, size_t frames,
                                             size_t replacementFrame, bool looping,
                                             uint32_t muteMask, char *errorOut,
                                             size_t errorCapacity)
{
    if (!engine || !engine->initialized || !left || !right || replacementFrame > frames) {
        writePlaybackError(QStringLiteral("invalid playback render arguments"), errorOut,
                           errorCapacity);
        return false;
    }
    std::unique_ptr<MidiTimeline> timeline =
        loadPlaybackTimeline(path, sampleRate, errorOut, errorCapacity);
    if (!timeline)
        return false;
    std::unique_ptr<MidiTimeline> replacement;
    if (replacementPath) {
        replacement = loadPlaybackTimeline(replacementPath, sampleRate, errorOut, errorCapacity);
        if (!replacement)
            return false;
    }

    TimelinePlayer player;
    const size_t firstFrames = replacement ? replacementFrame : frames;
    if (firstFrames > 0) {
        player.render(&engine->engine, timeline.get(), std::span(left, firstFrames),
                      std::span(right, firstFrames), looping, muteMask);
    }
    if (replacement) {
        const uint64_t position = player.position();
        player.replaceTimeline(position, replacement.get());
        const size_t remaining = frames - firstFrames;
        if (remaining > 0) {
            player.render(&engine->engine, replacement.get(),
                          std::span(left + firstFrames, remaining),
                          std::span(right + firstFrames, remaining), looping, muteMask);
        }
    }
    return true;
}

extern "C" bool oracle_playback_prepare_file(const char *path, double sampleRate,
                                             OraclePlaybackEngine *engine, uint64_t position,
                                             bool chase, bool prime, char *errorOut,
                                             size_t errorCapacity)
{
    if (!engine || !engine->initialized) {
        writePlaybackError(QStringLiteral("invalid playback engine"), errorOut, errorCapacity);
        return false;
    }
    std::unique_ptr<MidiTimeline> timeline =
        loadPlaybackTimeline(path, sampleRate, errorOut, errorCapacity);
    if (!timeline)
        return false;
    if (chase)
        TimelinePlayer::chase(&engine->engine, timeline.get(), position);
    if (prime)
        TimelinePlayer::primeVoices(&engine->engine, timeline.get(), position);
    return true;
}

extern "C" OraclePlaybackEngine *oracle_playback_engine_create(double sampleRate)
{
    std::unique_ptr<OraclePlaybackEngine> engine =
        std::make_unique<OraclePlaybackEngine>(sampleRate);
    if (!engine->initialized)
        return nullptr;
    return engine.release();
}

extern "C" void oracle_playback_engine_destroy(OraclePlaybackEngine *engine)
{
    delete engine;
}

extern "C" void *oracle_playback_engine_pointer(OraclePlaybackEngine *engine)
{
    return engine ? &engine->engine : nullptr;
}

extern "C" void oracle_playback_engine_set_features(OraclePlaybackEngine *engine, bool portamento,
                                                    bool pwm)
{
    if (!engine)
        return;
    m4a_engine_set_portamento_enabled(&engine->engine, portamento);
    m4a_engine_set_pwm_enabled(&engine->engine, pwm);
}

extern "C" void oracle_playback_engine_note_on(OraclePlaybackEngine *engine, uint8_t track,
                                               uint8_t key, uint8_t velocity)
{
    if (engine)
        m4a_engine_note_on(&engine->engine, track, key, velocity);
}

extern "C" bool oracle_playback_engine_renders_audibly(OraclePlaybackEngine *engine)
{
    if (!engine)
        return false;
    constexpr size_t kChunkFrames = 512;
    constexpr size_t kMaximumFrames = 4096;
    std::array<float, kChunkFrames> left{};
    std::array<float, kChunkFrames> right{};
    for (size_t rendered = 0; rendered < kMaximumFrames; rendered += kChunkFrames) {
        m4a_engine_process(&engine->engine, left.data(), right.data(), int(kChunkFrames));
        for (size_t frame = 0; frame < kChunkFrames; ++frame) {
            if (left[frame] != 0.0f || right[frame] != 0.0f)
                return true;
        }
    }
    return false;
}

extern "C" int oracle_playback_engine_track_program(const OraclePlaybackEngine *engine, int track)
{
    if (!engine || track < 0 || track >= track_limits::kHardwareCapacity)
        return std::numeric_limits<int>::min();
    return engine->engine.tracks[track].currentProgram;
}

extern "C" bool oracle_playback_engine_track_has_voice(const OraclePlaybackEngine *engine,
                                                       int track)
{
    if (!engine || track < 0 || track >= track_limits::kHardwareCapacity)
        return false;
    return engine->engine.tracks[track].currentVoice.wav != nullptr;
}

extern "C" int oracle_playback_engine_controller(const OraclePlaybackEngine *engine, int track,
                                                 uint8_t controller)
{
    if (!engine || track < 0 || track >= track_limits::kHardwareCapacity)
        return std::numeric_limits<int>::min();
    const M4ATrack &value = engine->engine.tracks[track];
    switch (controller) {
    case CoreTimeDefaults::kCcModulation:
        return value.mod;
    case CoreTimeDefaults::kCcPortamento:
        return value.portamentoDuration;
    case CoreTimeDefaults::kCcVolume:
        return value.rawVolume;
    case CoreTimeDefaults::kCcPan:
        return value.pan;
    case CoreTimeDefaults::kCcBendRange:
        return value.bendRange;
    case CoreTimeDefaults::kCcLfoSpeed:
        return value.lfoSpeed;
    case CoreTimeDefaults::kCcModType:
        return value.modT;
    case CoreTimeDefaults::kCcPwmCycle:
        return value.pwmPattern;
    case CoreTimeDefaults::kCcFineTune:
        return value.tune;
    case CoreTimeDefaults::kCcPwmWidth:
        return value.pwmSpeed;
    case CoreTimeDefaults::kCcLfoDelay:
        return value.lfoDelay;
    default:
        return std::numeric_limits<int>::min();
    }
}
