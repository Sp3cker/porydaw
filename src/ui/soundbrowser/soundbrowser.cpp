#include "ui/soundbrowser/soundbrowser.h"

#include <QByteArray>

#include "audio/audioengine.h"
#include "audio/sampledoc.h"
#include "audio/sampleimport.h"
#include <algorithm>
#include <utility>

namespace soundbrowser {
namespace {

// The audition key every symbol audition plays at (middle C, matching the
// slot-list audition); program auditions carry their own key.
constexpr int kAuditionKey = 60;
constexpr int kLoopStatusFlag = 0x4000;

int sampleSetIndex(const QStringList &symbols, int limit, const QString &symbol)
{
    const int index = symbols.indexOf(symbol);
    return index >= 0 && index < limit ? index : -1;
}

} // namespace

SoundBrowser::SoundBrowser(AudioEngine &engine, QObject *parent) : QObject(parent), m_engine(engine)
{}

SoundBrowser::~SoundBrowser()
{
    // The owner constructs this coordinator after the engine and destroys it
    // before engine shutdown, so active lanes can always be released here.
    releaseActive();
}

void SoundBrowser::setProjectSamples(SampleSetLease samples, const VoicegroupCatalog &catalog)
{
    // Replacing an existing snapshot invalidates a live project-symbol
    // request (its metadata indexed the old catalog); initial delivery
    // never stops a program or external-file request.
    if (m_samples && m_hasActive && m_kind == RequestKind::Symbol)
        releaseActive();
    m_samples = std::move(samples);
    m_directSound = catalog.directSound;
    m_progWave = catalog.progWave;
    m_keysplits = catalog.keysplits;
}

void SoundBrowser::clearProjectSamples()
{
    // A reset cannot leave metadata indexed against another catalog: a live
    // project-symbol request is released before the lease drops. Program
    // and external-file requests are unaffected.
    if (m_hasActive && m_kind == RequestKind::Symbol)
        releaseActive();
    m_samples.reset();
    m_directSound.clear();
    m_progWave.clear();
    m_keysplits.clear();
}

SamplePickInfo SoundBrowser::sampleInfo(const QString &symbol) const
{
    SamplePickInfo info;
    if (!m_samples)
        return info;
    const int index = sampleSetIndex(m_directSound, m_samples->count, symbol);
    if (index < 0)
        return info;
    const WaveData *const wave = m_samples->waves[index];
    if (!wave || !wave->data || wave->size == 0)
        return info;
    info.known = true;
    info.looped = (wave->status & kLoopStatusFlag) != 0;
    info.rateHz = int(wave->freq / 1024);
    info.seconds = info.rateHz > 0 ? double(wave->size) / info.rateHz : 0.0;
    return info;
}

void SoundBrowser::previewVoice(QObject *owner, int program, int key, int velocity)
{
    if (!owner || program < 0 || program >= VOICEGROUP_SIZE || key < 0 || key >= 128 ||
        velocity < 0 || velocity >= 128)
        return;
    if (velocity == 0) {
        // Releases match the active program/key: a late release from one
        // surface must not cut another surface's note, even for the same
        // program.
        if (m_hasActive && m_kind == RequestKind::Program && m_owner && m_owner.data() == owner &&
            m_program == program && m_key == key)
            releaseActive();
        return;
    }
    releaseActive();
    m_engine.previewVoice(uint8_t(program), uint8_t(key), uint8_t(velocity));
    takeOwnership(owner, RequestKind::Program);
    m_program = program;
    m_key = key;
}

AuditionResult SoundBrowser::auditionSymbol(QObject *owner, const QString &symbol,
                                            VgAuditionKind kind, const AuditionSlots::Adsr &adsr)
{
    if (!owner || symbol.isEmpty())
        return {AuditionStatus::Unsupported, tr("Nothing to audition.")};
    if (!m_samples)
        return {AuditionStatus::NotReady, tr("Samples are still loading.")};

    // Resolve fully before replacing the current owner: a preparation
    // failure leaves the current audition alone.
    struct Resolved {
        QByteArray bytes;
        uint32_t freq = 0;
        uint32_t loopStart = 0;
        bool looped = false;
        uint8_t toneKey = kAuditionKey;
        bool wave = false;
    };
    Resolved resolved;
    AuditionSlots::Adsr useAdsr = adsr;
    if (kind == VgAuditionKind::Wave) {
        const int index = sampleSetIndex(m_progWave, m_samples->progWaveCount, symbol);
        const uint32_t *wave = index < 0 ? nullptr : m_samples->progWaves[index];
        if (!wave)
            return {AuditionStatus::Unsupported, tr("Wave \"%1\" is not loaded.").arg(symbol)};
        resolved.bytes = QByteArray::fromRawData(reinterpret_cast<const char *>(wave), 16);
        resolved.wave = true;
    } else if (kind == VgAuditionKind::Keysplit) {
        const LoadedKeysplit *keysplit = nullptr;
        for (int i = 0; i < m_keysplits.size() && i < m_samples->keysplitCount; i++) {
            if (m_keysplits.at(i).first == symbol && m_samples->keysplits[i].subGroup &&
                m_samples->keysplits[i].table) {
                keysplit = &m_samples->keysplits[i];
                break;
            }
        }
        if (!keysplit)
            return {AuditionStatus::Unsupported, tr("Keysplit \"%1\" is not loaded.").arg(symbol)};
        const uint8_t index = keysplit->table[kAuditionKey];
        if (index >= VOICEGROUP_SIZE)
            return {AuditionStatus::Unsupported,
                    tr("Keysplit \"%1\" has nothing loaded at the audition key.").arg(symbol)};
        const ToneData &sub = keysplit->subGroup[index];
        if (sub.type & (VOICE_KEYSPLIT | VOICE_KEYSPLIT_ALL))
            return {AuditionStatus::Unsupported,
                    tr("Keysplit \"%1\" nests another split.").arg(symbol)};
        const AuditionSlots::Adsr subAdsr{sub.attack, sub.decay, sub.sustain, sub.release};
        const int cgbType = sub.type & 0x07;
        if (cgbType == 0 && sub.wav && sub.wav->data && sub.wav->size > 0) {
            resolved.bytes = QByteArray::fromRawData(reinterpret_cast<const char *>(sub.wav->data),
                                                     int(sub.wav->size));
            resolved.freq = sub.wav->freq;
            resolved.loopStart = sub.wav->loopStart;
            resolved.looped = (sub.wav->status & kLoopStatusFlag) != 0;
            resolved.toneKey = sub.key;
            useAdsr = subAdsr;
        } else if (cgbType == VOICE_PROGRAMMABLE_WAVE && sub.wavePointer) {
            resolved.bytes =
                QByteArray::fromRawData(reinterpret_cast<const char *>(sub.wavePointer), 16);
            resolved.wave = true;
            useAdsr = subAdsr;
        } else {
            // Square/noise sub-voices stay unsupported; synthesis is not extended.
            return {AuditionStatus::Unsupported,
                    tr("Keysplit \"%1\" resolves to an unsupported sub-voice.").arg(symbol)};
        }
    } else {
        const int index = sampleSetIndex(m_directSound, m_samples->count, symbol);
        const WaveData *wave = index < 0 ? nullptr : m_samples->waves[index];
        if (!wave || !wave->data || wave->size == 0)
            return {AuditionStatus::Unsupported, tr("Sample \"%1\" is not loaded.").arg(symbol)};
        resolved.bytes =
            QByteArray::fromRawData(reinterpret_cast<const char *>(wave->data), int(wave->size));
        resolved.freq = wave->freq;
        resolved.loopStart = wave->loopStart;
        resolved.looped = (wave->status & kLoopStatusFlag) != 0;
    }

    releaseActive();
    const bool published =
        resolved.wave
            ? m_engine.auditionWave(resolved.bytes, kAuditionKey, useAdsr)
            : m_engine.auditionSample(resolved.bytes, resolved.freq, resolved.loopStart,
                                      resolved.looped, kAuditionKey, useAdsr, resolved.toneKey);
    if (!published)
        return {AuditionStatus::Busy, tr("The audition engine is busy.")};
    takeOwnership(owner, RequestKind::Symbol);
    return {AuditionStatus::Started, {}};
}

AuditionResult SoundBrowser::auditionExternalFile(QObject *owner, const QString &path, uint8_t key)
{
    if (!owner || path.isEmpty() || key >= 128)
        return {AuditionStatus::Unsupported, tr("Nothing to audition.")};
    // External preview works without an open project or sample set.
    ImportedSample imported;
    QString importError;
    if (!importAudioFile(path, &imported, &importError)) {
        return {AuditionStatus::DecodeError,
                importError.isEmpty() ? tr("Could not decode \"%1\".").arg(path) : importError};
    }
    SampleDocument document(std::move(imported));
    SampleEditParams params = SampleDocument::defaultParams(document.source());
    params.loopOn = false;
    document.setParams(params);
    const ProcessedSample &rendered = document.processed();
    if (rendered.size == 0 || rendered.s8.isEmpty())
        return {AuditionStatus::Unsupported, tr("\"%1\" renders no audio.").arg(path)};
    releaseActive();
    const uint8_t toneKey = uint8_t(std::clamp(rendered.unityNote, 0, 127));
    const bool published =
        m_engine.auditionSample(rendered.s8, rendered.freq, 0,
                                /*looped=*/false, key, AuditionSlots::Adsr{}, toneKey);
    if (!published)
        return {AuditionStatus::Busy, tr("The audition engine is busy.")};
    takeOwnership(owner, RequestKind::External);
    return {AuditionStatus::Started, {}};
}

void SoundBrowser::stop(QObject *owner)
{
    if (!owner || !m_hasActive || !m_owner || m_owner.data() != owner)
        return;
    releaseActive();
}

void SoundBrowser::stopAll()
{
    releaseActive();
}

void SoundBrowser::takeOwnership(QObject *owner, RequestKind kind)
{
    clearActive();
    m_hasActive = true;
    m_kind = kind;
    m_owner = owner;
    m_ownerIdentity = owner;
    // Qt clears the QPointer before destroyed() is delivered, so the match
    // below compares the captured identity, never the cleared pointer.
    m_ownerGone =
        connect(owner, &QObject::destroyed, this, [this, owner] { onOwnerDestroyed(owner); });
}

void SoundBrowser::clearActive()
{
    disconnect(m_ownerGone);
    m_ownerGone = QMetaObject::Connection{};
    m_owner.clear();
    m_ownerIdentity = nullptr;
    m_hasActive = false;
    m_program = -1;
    m_key = -1;
}

void SoundBrowser::releaseActive()
{
    if (!m_hasActive) {
        clearActive();
        return;
    }
    const bool hadProgram = m_kind == RequestKind::Program;
    const int program = m_program;
    const int key = m_key;
    // Ownership clears before the engine release methods run.
    clearActive();
    if (hadProgram)
        m_engine.previewVoice(uint8_t(program), uint8_t(key), 0);
    m_engine.auditionSampleOff();
}

void SoundBrowser::onOwnerDestroyed(QObject *dead)
{
    // Destruction of a displaced owner does nothing; only the current owner
    // releases its audition.
    if (!m_hasActive || m_ownerIdentity != dead)
        return;
    releaseActive();
}

} // namespace soundbrowser
