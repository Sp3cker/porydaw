#include "checks/voicegroup/voicegrouptestfixture.h"

#include <cstring>
#include <optional>

#include <QFile>

#include "checks/support/songfixture.h"

namespace voicegroup_test {

ProjectSession::ProjectSession() = default;

ProjectSession::~ProjectSession()
{
    voicegroup_free(baseline);
}

const QString &ProjectSession::root() const noexcept
{
    return copy->root();
}

QByteArray ProjectSession::rootUtf8() const
{
    return root().toLocal8Bit();
}

QByteArray ProjectSession::loadNameUtf8() const
{
    return source.loadName().toLocal8Bit();
}

std::unique_ptr<checks::ProjectFixture> copyProject(const QString &stagedRoot, QString &error)
{
    return checks::ProjectFixture::copyOf(stagedRoot, error);
}

std::unique_ptr<ProjectSession> openSession(const QString &stagedRoot, const QString &songLabel,
                                            QString &error)
{
    auto session = std::make_unique<ProjectSession>();
    session->copy = copyProject(stagedRoot, error);
    if (!session->copy)
        return nullptr;
    if (!session->project.open(session->root(), &error))
        return nullptr;

    const std::optional<SongName> name = SongName::create(songLabel);
    if (!name) {
        error = QStringLiteral("invalid song label '%1'").arg(songLabel);
        return nullptr;
    }
    const std::optional<SongInfo> song = session->project.playableSong(*name);
    if (!song) {
        error = QStringLiteral("no playable song '%1'").arg(songLabel);
        return nullptr;
    }
    session->song = *song;
    if (!session->source.open(session->root(), session->song.cfg.voicegroupArg, &error))
        return nullptr;

    const QByteArray root = session->rootUtf8();
    const QByteArray loadName = session->loadNameUtf8();
    session->baseline = voicegroup_load(root.constData(), loadName.constData(), nullptr);
    if (!session->baseline) {
        error = QStringLiteral("could not load baseline voicegroup '%1'")
                    .arg(session->source.loadName());
        return nullptr;
    }
    return session;
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

bool writeFile(const QString &path, const QByteArray &contents, QString &error)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        error = file.errorString();
        return false;
    }
    if (file.write(contents) != contents.size()) {
        error = file.errorString();
        return false;
    }
    return true;
}

bool VoiceSnapshot::operator==(const VoiceSnapshot &other) const
{
    return type == other.type && key == other.key && panSweep == other.panSweep &&
           attack == other.attack && decay == other.decay && sustain == other.sustain &&
           release == other.release && name == other.name && packed == other.packed;
}

VoiceSnapshot snapshot(const LoadedVoiceGroup &group, int slot)
{
    const ToneData &tone = group.voices[slot];
    VoiceSnapshot result{
        tone.type,  tone.key,     tone.panSweep, tone.attack,
        tone.decay, tone.sustain, tone.release,  QByteArray(group.voiceNames[slot])};
    const uint8_t cgb = tone.type & VOICE_TYPE_CGB_MASK;
    if (tone.type != VOICE_KEYSPLIT && tone.type != VOICE_KEYSPLIT_ALL &&
        (cgb == VOICE_SQUARE_1 || cgb == VOICE_SQUARE_2 || cgb == VOICE_NOISE)) {
        result.packed = reinterpret_cast<uintptr_t>(tone.wavePointer);
    }
    return result;
}

QByteArray loaderVoiceName(const QString &symbol)
{
    QByteArray name = symbol.toUtf8();
    for (const char *prefix : {"DirectSoundWaveData_", "ProgrammableWaveData_", "voicegroup_"}) {
        if (name.startsWith(prefix) && name.size() > int(qstrlen(prefix))) {
            name = name.mid(int(qstrlen(prefix)));
            break;
        }
    }
    return name.left(VG_VOICE_NAME_LEN - 1);
}

bool isDirectSound(VgMacro macro)
{
    return macro == VgMacro::DirectSound || macro == VgMacro::DirectSoundNoResample ||
           macro == VgMacro::DirectSoundAlt;
}

bool isSquare1(VgMacro macro)
{
    return macro == VgMacro::Square1 || macro == VgMacro::Square1Alt;
}

bool isNoise(VgMacro macro)
{
    return macro == VgMacro::Noise || macro == VgMacro::NoiseAlt;
}

bool isProgWave(VgMacro macro)
{
    return macro == VgMacro::ProgWave || macro == VgMacro::ProgWaveAlt;
}

bool sameVoiceFields(const VgVoice &actual, const VgVoice &expected)
{
    if (actual.macro != expected.macro)
        return false;
    if (actual.macro == VgMacro::Keysplit)
        return actual.symbol == expected.symbol && actual.keysplitTable == expected.keysplitTable;
    if (actual.macro == VgMacro::KeysplitAll)
        return actual.symbol == expected.symbol;
    return actual.key == expected.key && actual.pan == expected.pan &&
           actual.symbol == expected.symbol && actual.sweep == expected.sweep &&
           actual.duty == expected.duty && actual.period == expected.period &&
           actual.attack == expected.attack && actual.decay == expected.decay &&
           actual.sustain == expected.sustain && actual.release == expected.release;
}

namespace {

const ToneData *resolvedTone(const ToneData &aggregate, int midiKey)
{
    if (midiKey < 0 || midiKey >= VOICEGROUP_SIZE)
        return nullptr;
    const auto *const subgroup = static_cast<const ToneData *>(aggregate.subGroup);
    const ToneData *resolved = nullptr;
    if (aggregate.type & VOICE_KEYSPLIT_ALL) {
        if (!subgroup)
            return nullptr;
        resolved = &subgroup[midiKey];
    } else if (aggregate.type & VOICE_KEYSPLIT) {
        if (!subgroup || !aggregate.keySplitTable)
            return nullptr;
        resolved = &subgroup[aggregate.keySplitTable[midiKey]];
    } else {
        resolved = &aggregate;
    }
    return resolved->type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL) ? nullptr : resolved;
}

bool sameWave(const WaveData *actual, const WaveData *expected)
{
    return actual == expected ||
           (actual && expected && actual->type == expected->type &&
            actual->status == expected->status && actual->freq == expected->freq &&
            actual->loopStart == expected->loopStart && actual->size == expected->size &&
            (!actual->size || (actual->data && expected->data &&
                               std::memcmp(actual->data, expected->data, actual->size) == 0)));
}

bool samePlayableTone(const ToneData &actual, const ToneData &expected)
{
    if (actual.type != expected.type || actual.key != expected.key ||
        actual.length != expected.length || actual.panSweep != expected.panSweep ||
        actual.attack != expected.attack || actual.decay != expected.decay ||
        actual.sustain != expected.sustain || actual.release != expected.release)
        return false;
    const uint8_t family = actual.type & VOICE_TYPE_CGB_MASK;
    if (family == VOICE_SQUARE_1 || family == VOICE_SQUARE_2 || family == VOICE_NOISE)
        return reinterpret_cast<uintptr_t>(actual.wavePointer) ==
               reinterpret_cast<uintptr_t>(expected.wavePointer);
    if (family == VOICE_PROGRAMMABLE_WAVE)
        return actual.wavePointer == expected.wavePointer ||
               (actual.wavePointer && expected.wavePointer &&
                std::memcmp(actual.wavePointer, expected.wavePointer, 16) == 0);
    return sameWave(actual.wav, expected.wav);
}

} // namespace

bool sameResolvedTone(const ToneData &actualAggregate, const ToneData &expectedAggregate,
                      int midiKey)
{
    const ToneData *const actual = resolvedTone(actualAggregate, midiKey);
    const ToneData *const expected = resolvedTone(expectedAggregate, midiKey);
    return actual && expected && samePlayableTone(*actual, *expected);
}

} // namespace voicegroup_test
