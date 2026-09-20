#include "oracle_check.h"

#include <QByteArray>
#include <QString>
#include <QStringList>

#include <algorithm>
#include <bit>
#include <cstring>
#include <limits>
#include <utility>

#include "core/m4asemantics.h"
#include "core/mid2agbtables.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "core/timedefaults.h"
#include "core/tracklimits.h"
#include "core/velocitymodel.h"
#include "project/decompproject.h"

namespace {

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

std::optional<QByteArray> semanticText(uint32_t operation, int64_t a, int64_t b)
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
        return std::nullopt;
    }
    return text.toUtf8();
}

} // namespace

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
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    const Tick oneBar = Tick(smf.division) * 4;
    SmfTrack sequence;
    sequence.events = {
        SmfEvent{.status = 0xFF, .metaType = 0x51, .blob = QByteArray("\x07\xA1\x20", 3)},
        SmfEvent{.status = 0xFF, .metaType = 0x58, .blob = QByteArray("\x04\x02\x18\x08", 4)},
    };
    sequence.endTick = oneBar;
    smf.tracks.push_back(sequence);
    SmfTrack track;
    track.events = {
        SmfEvent{.status = 0xC0, .data0 = 0},
        SmfEvent{.status = 0xB0, .data0 = 7, .data1 = 100},
    };
    track.endTick = oneBar;
    smf.tracks.push_back(track);
    const QByteArray bytes = smf.write();
    copyBytes(bytes, output, outputCapacity);
    return bytes.size();
}

extern "C" int64_t oracle_document_summary(const uint8_t *input, size_t inputCount, char *output,
                                           size_t outputCapacity)
{
    if ((!input && inputCount != 0) || inputCount > size_t(std::numeric_limits<qsizetype>::max()))
        return -1;
    SmfFile file;
    QString error;
    if (!SmfFile::read(QByteArray(reinterpret_cast<const char *>(input), qsizetype(inputCount)),
                       &file, &error))
        return -1;
    SongDocument document;
    SongInfo song;
    if (!document.adoptSmf(std::move(file), song, &error))
        return -1;

    QStringList parts{QStringLiteral("tempo=%1").arg(document.tempoPoints().size())};
    for (int track = 0; track < document.engineTrackCount(); ++track) {
        for (const DocNote &note : document.notesForTrack(track)) {
            parts.append(QStringLiteral("n=%1,%2,%3,%4,%5,%6")
                             .arg(track)
                             .arg(note.tick)
                             .arg(note.duration)
                             .arg(int(note.key))
                             .arg(int(note.velocity))
                             .arg(note.unterminated() ? 1 : 0));
        }
    }
    const QByteArray summary = parts.join(QLatin1Char(';')).toUtf8();
    copyBytes(summary, output, outputCapacity);
    return summary.size();
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
    const std::optional<QByteArray> bytes = semanticText(operation, a, b);
    if (!bytes)
        return -1;
    copyBytes(*bytes, output, outputCapacity);
    return bytes->size();
}
