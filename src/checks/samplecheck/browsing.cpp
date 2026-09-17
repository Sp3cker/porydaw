#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QTemporaryDir>
#include <QtTest>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

#include "audio/audioengine.h"
#include "checks/support/audioengineaccess.h"
#include "project/decompproject.h"
#include "project/samplereg.h"
#include "project/voicegroupsource.h"
#include "ui/soundbrowser/soundbrowser.h"

extern "C" {
#include "voicegroup_loader.h"
}

namespace {

class ScopedNullAudioBackend final
{
  public:
    ScopedNullAudioBackend()
        : m_wasSet(qEnvironmentVariableIsSet("PORYDAW_AUDIO_BACKEND"))
        , m_previous(qgetenv("PORYDAW_AUDIO_BACKEND"))
    {
        qputenv("PORYDAW_AUDIO_BACKEND", "null");
    }

    ~ScopedNullAudioBackend()
    {
        if (m_wasSet)
            qputenv("PORYDAW_AUDIO_BACKEND", m_previous);
        else
            qunsetenv("PORYDAW_AUDIO_BACKEND");
    }

  private:
    bool m_wasSet;
    QByteArray m_previous;
};

double peakOf(const std::vector<float> &pcm)
{
    double result = 0.0;
    for (const float sample : pcm)
        result = std::max(result, std::abs(double(sample)));
    return result;
}

std::vector<float> renderSeconds(AudioEngine &engine, double seconds)
{
    const auto frames = std::max(uint32_t{1}, uint32_t(std::ceil(seconds * engine.sampleRate())));
    std::vector<float> pcm(static_cast<std::size_t>(frames) * 2);
    checks::AudioEngineTestAccess::renderParked(engine, std::span<float>(pcm));
    return pcm;
}

double tailPeak(AudioEngine &engine, double seconds)
{
    return peakOf(renderSeconds(engine, seconds));
}

// The synthetic browse project: one registered sample, one CGB wave, two
// keysplit tables (a sounding DirectSound sub-voice and a square one), and
// the minimal song table the real loader needs. Mirrors the checked-in
// decomp fixture syntax without depending on it.
bool stageBrowseProject(const QString &root, QString *error)
{
    const auto fail = [error](const QString &message) {
        if (error)
            *error = message;
        return false;
    };
    if (!samplecheck::createWav2AgbProject(root))
        return fail(QStringLiteral("synthetic browse project is created"));
    // The seed's placeholder sample files must parse: give them real bytes.
    if (!writeFile(root + QStringLiteral("/sound/direct_sound_samples/existing.wav"),
                   samplecheck::preparedSampleWav()) ||
        !writeFile(root + QStringLiteral("/sound/direct_sound_samples/orphan.wav"),
                   samplecheck::preparedSampleWav()))
        return fail(QStringLiteral("seed sample files parse"));
    if (!SampleRegistrar::registerSample(root, QStringLiteral("browse_tone"),
                                         samplecheck::preparedSampleWav(), error))
        return fail(QStringLiteral("browse sample registers: %1").arg(*error));
    if (!writeFile(root + QStringLiteral("/sound/programmable_wave_samples/browse_pulse.pcm"),
                   QByteArray::fromHex("0f0f0f0ff0f0f0f00f0f0f0ff0f0f0f0")))
        return fail(QStringLiteral("browse wave bytes stage"));
    if (!writeFile(root + QStringLiteral("/sound/programmable_wave_data.inc"),
                   "ProgrammableWaveData_browse_pulse:\n"
                   "\t.incbin \"sound/programmable_wave_samples/browse_pulse.pcm\"\n"))
        return fail(QStringLiteral("browse wave data stages"));
    if (!writeFile(root + QStringLiteral("/sound/keysplit_tables.inc"),
                   "\t.align 2\nkeysplit browsetone, 0\n"
                   "\tsplit 0, 48\n\tsplit 1, 96\n\tsplit 2, 128\n"
                   "\n\t.align 2\nkeysplit browsesquare, 0\n"
                   "\tsplit 0, 128\n"))
        return fail(QStringLiteral("browse keysplit tables stage"));
    if (!writeFile(root + QStringLiteral("/sound/voicegroups/browse_keys.inc"),
                   "\t.align 2\nbrowse_keys::\nvoice_group browse_keys\n"
                   "\tvoice_square_2 60, 0, 2, 2, 2, 12, 4\n"
                   "\tvoice_directsound 60, 0, DirectSoundWaveData_browse_tone, 255, 160, 192, "
                   "64\n"
                   "\tvoice_programmable_wave 60, 0, ProgrammableWaveData_browse_pulse, 2, 2, 11, "
                   "3\n"))
        return fail(QStringLiteral("browse keysplit sub-voices stage"));
    if (!writeFile(root + QStringLiteral("/sound/voicegroups/browse_squares.inc"),
                   "\t.align 2\nbrowse_squares::\nvoice_group browse_squares\n"
                   "\tvoice_square_2 60, 0, 2, 2, 2, 12, 4\n"))
        return fail(QStringLiteral("browse square sub-voice stages"));
    if (!writeFile(root + QStringLiteral("/sound/voicegroups/browse.inc"),
                   "voicegroup_browse::\n"
                   "\tvoice_directsound 60, 0, DirectSoundWaveData_browse_tone, 255, 165, 90, "
                   "178\n"
                   "\tvoice_programmable_wave 60, 0, ProgrammableWaveData_browse_pulse, 2, 3, 12, "
                   "4\n"
                   "\tvoice_keysplit browse_keys, keysplit_browsetone\n"
                   "\tvoice_keysplit browse_squares, keysplit_browsesquare\n"))
        return fail(QStringLiteral("browse voicegroup stages"));
    if (!writeFile(root + QStringLiteral("/sound/song_table.inc"),
                   "\tsong mus_browse, MUSIC_PLAYER_BGM, 0\n"))
        return fail(QStringLiteral("browse song table stages"));
    return true;
}

struct BrowseRig {
    QTemporaryDir scratch;
    DecompProject project;
    VoicegroupLease bank;
    SampleSetLease samples;
    VoicegroupCatalog catalog;
    QString error;
};

bool openBrowseRig(BrowseRig &rig)
{
    if (!rig.scratch.isValid()) {
        rig.error = QStringLiteral("browse scratch directory is available");
        return false;
    }
    const QString root = rig.scratch.filePath(QStringLiteral("browseproj"));
    if (!stageBrowseProject(root, &rig.error))
        return false;
    if (!rig.project.open(root, &rig.error))
        return false;
    SongInfo song;
    song.cfg.voicegroupArg = QStringLiteral("_browse");
    const std::optional<LoadedBankView> view = rig.project.loadBank(song, &rig.error);
    if (!view) {
        if (rig.error.isEmpty())
            rig.error = QStringLiteral("browse voicegroup bank loads");
        return false;
    }
    rig.bank = view->bank;
    rig.catalog.directSound = VoicegroupSource::directSoundSymbols(root);
    rig.catalog.progWave = VoicegroupSource::progWaveSymbols(root);
    rig.catalog.keysplits = VoicegroupSource::keysplitInstruments(root);
    QList<QByteArray> storage;
    storage.reserve(rig.catalog.directSound.size() + rig.catalog.progWave.size() +
                    rig.catalog.keysplits.size() * 2);
    const auto utf8 = [&storage](const QString &value) {
        storage.append(value.toUtf8());
        return storage.last().constData();
    };
    std::vector<const char *> sampleChars, waveChars, keysplitChars, tableChars;
    for (const QString &symbol : rig.catalog.directSound)
        sampleChars.push_back(utf8(symbol));
    for (const QString &symbol : rig.catalog.progWave)
        waveChars.push_back(utf8(symbol));
    for (const auto &pair : rig.catalog.keysplits) {
        keysplitChars.push_back(utf8(pair.first));
        tableChars.push_back(utf8(pair.second));
    }
    LoadedSampleSet *raw = rig.project.loadSampleSet(
        sampleChars.data(), int(sampleChars.size()), waveChars.data(), int(waveChars.size()),
        keysplitChars.data(), tableChars.data(), int(keysplitChars.size()));
    if (!raw) {
        rig.error = QStringLiteral("browse sample set loads");
        return false;
    }
    rig.samples = SampleSetLease(raw, &voicegroup_free_samples);
    return true;
}

bool startParkedEngine(AudioEngine &engine, const VoicegroupLease &bank, QString *error)
{
    if (!engine.init(error))
        return false;
    if (!engine.nullBackendForced() || !engine.usingNullBackend()) {
        *error = QStringLiteral("browse tests use the required production null backend");
        return false;
    }
    if (!checks::AudioEngineTestAccess::parkDevice(engine)) {
        *error = QStringLiteral("browse tests park the null device for deterministic capture");
        return false;
    }
    // Binds the preview engine's voicegroup the way the shell's selected-tab
    // handoff does; the coordinator itself never binds banks.
    engine.updateVoicegroup(bank);
    return true;
}

} // namespace

namespace samplecheck {

void SampleProcessingTest::browseOwnership()
{
    BrowseRig rig;
    QVERIFY2(openBrowseRig(rig), qPrintable(rig.error));

    ScopedNullAudioBackend nullBackend;
    AudioEngine engine;
    QString audioError;
    QVERIFY2(startParkedEngine(engine, rig.bank, &audioError), qPrintable(audioError));
    QVERIFY2(peakOf(renderSeconds(engine, 0.1)) <= 1.0e-7,
             "parked engine is silent before any browse request");

    soundbrowser::SoundBrowser browser(engine);
    QObject ownerA, ownerB;
    const QString sampleSymbol = QStringLiteral("DirectSoundWaveData_browse_tone");

    // Null/out-of-range requests never change playback.
    browser.previewVoice(nullptr, 0, 60, 112);
    browser.previewVoice(&ownerA, 200, 60, 112);
    browser.previewVoice(&ownerA, 0, 60, 0);
    QCOMPARE(browser.auditionSymbol(nullptr, sampleSymbol, VgAuditionKind::Sample, {}).status,
             soundbrowser::AuditionStatus::Unsupported);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) <= 1.0e-7, "invalid requests stay silent");

    // A symbol request with no loaded set is NotReady without starting audio.
    QCOMPARE(browser.auditionSymbol(&ownerA, sampleSymbol, VgAuditionKind::Sample, {}).status,
             soundbrowser::AuditionStatus::NotReady);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) <= 1.0e-7, "NotReady starts no audio");

    browser.setProjectSamples(rig.samples, rig.catalog);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) <= 1.0e-7,
             "initial sample delivery must not replay the unresolved request");

    // Same program/key supersession: B takes A, A's late release is a no-op.
    browser.previewVoice(&ownerA, 0, 60, 112);
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01, "program preview sounds");
    browser.previewVoice(&ownerB, 0, 60, 112);
    browser.previewVoice(&ownerA, 0, 60, 0); // stale: must not cut B
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01,
             "stale program release leaves the newer owner sounding");
    browser.stop(&ownerB);
    renderSeconds(engine, 4.0); // drain the real release envelope
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7,
             "owner stop drains to silence after its release tail");

    // Cross-lane supersession: a sample request releases B's program lane,
    // and B's matching release afterwards cannot cut the sample.
    const AuditionSlots::Adsr fast{255, 0, 255, 165};
    browser.previewVoice(&ownerB, 0, 60, 112);
    QCOMPARE(browser.auditionSymbol(&ownerA, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    browser.previewVoice(&ownerB, 0, 60, 0); // displaced: must not cut A
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01, "displaced program release leaves the sample sounding");
    browser.stop(&ownerB); // a non-owner stop is a no-op
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01, "non-owner stop leaves the owner sounding");
    browser.stop(&ownerA);
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "symbol stop drains to silence");

    // Owner destruction releases its audition; destroying a displaced owner
    // does nothing.
    auto *displaced = new QObject;
    QCOMPARE(browser.auditionSymbol(displaced, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    auto *gone = new QObject;
    QCOMPARE(browser.auditionSymbol(gone, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    delete displaced;
    QVERIFY2(tailPeak(engine, 0.1) >= 0.01,
             "destroying the displaced owner leaves the current owner sounding");
    delete gone;
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "destroyed owner releases its audition");

    // stopAll clears a held request.
    QCOMPARE(browser.auditionSymbol(&ownerA, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    browser.stopAll();
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "stopAll drains a held request");

    // Clearing the snapshot releases a project-symbol request but leaves a
    // program request sounding; initial delivery never auto-starts.
    QCOMPARE(browser.auditionSymbol(&ownerA, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    browser.clearProjectSamples();
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "snapshot invalidation releases the symbol request");
    browser.setProjectSamples(rig.samples, rig.catalog);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) <= 1.0e-7, "delivery never auto-starts a request");
    QCOMPARE(browser.auditionSymbol(&ownerA, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    browser.setProjectSamples(rig.samples, rig.catalog);
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7,
             "replacing a sample snapshot releases the old symbol request without replay");
    browser.clearProjectSamples();
    browser.previewVoice(&ownerA, 0, 60, 112);
    browser.setProjectSamples(rig.samples, rig.catalog); // initial delivery keeps programs
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01, "initial delivery leaves a program request sounding");
    browser.setProjectSamples(rig.samples, rig.catalog); // replacement keeps programs too
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01,
             "snapshot replacement leaves a program request sounding");
    browser.stopAll();
    renderSeconds(engine, 4.0);

    // Browser destruction releases its held request while the required
    // engine is still alive.
    {
        soundbrowser::SoundBrowser scopedBrowser(engine);
        scopedBrowser.previewVoice(&ownerA, 0, 60, 112);
        QVERIFY2(tailPeak(engine, 0.3) >= 0.01, "request held by a scoped browser sounds");
    }
    renderSeconds(engine, 4.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "browser destruction releases the held request");
}

void SampleProcessingTest::browseProjectResolution()
{
    BrowseRig rig;
    QVERIFY2(openBrowseRig(rig), qPrintable(rig.error));

    ScopedNullAudioBackend nullBackend;
    AudioEngine engine;
    QString audioError;
    QVERIFY2(startParkedEngine(engine, rig.bank, &audioError), qPrintable(audioError));

    soundbrowser::SoundBrowser browser(engine);
    browser.setProjectSamples(rig.samples, rig.catalog);
    QObject owner;
    const QString sampleSymbol = QStringLiteral("DirectSoundWaveData_browse_tone");
    const QString waveSymbol = QStringLiteral("ProgrammableWaveData_browse_pulse");
    const QString keysplitSymbol = QStringLiteral("browse_keys");
    const QString squareSplitSymbol = QStringLiteral("browse_squares");

    // Metadata resolves without copying PCM.
    const SamplePickInfo info = browser.sampleInfo(sampleSymbol);
    QVERIFY(info.known && info.looped);
    QCOMPARE(info.rateHz, 15000000 / 1024);
    QVERIFY(std::abs(info.seconds - 64.0 / double(15000000 / 1024)) < 1.0e-9);
    QVERIFY(!browser.sampleInfo(QStringLiteral("DirectSoundWaveData_missing")).known);

    // PCM resolution: looped pitch at the sample's own rate.
    const AuditionSlots::Adsr fast{255, 0, 255, 165};
    QCOMPARE(browser.auditionSymbol(&owner, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    QVERIFY2(tailPeak(engine, 0.5) >= 0.01, "sample audition sounds");
    QVERIFY2(tailPeak(engine, 1.0) >= 0.01, "looped sample sustains across loop wraps");
    const std::vector<float> held = renderSeconds(engine, 1.0);
    // The looped region is the period: the engine wraps size→loopStart, so
    // the fundamental is the wave rate over the loop length, not the whole
    // buffer. Derive it from the loaded wave rather than the fixture's
    // frame count.
    const int toneIndex = rig.catalog.directSound.indexOf(sampleSymbol);
    QVERIFY(toneIndex >= 0 && toneIndex < rig.samples->count);
    const WaveData *toneWave = rig.samples->waves[toneIndex];
    QVERIFY(toneWave && toneWave->size > toneWave->loopStart);
    const double toneRate = double(toneWave->freq) / 1024.0;
    const double toneLoop = (toneWave->status & 0x4000u) != 0
                                ? double(toneWave->size - toneWave->loopStart)
                                : double(toneWave->size);
    const double expectedPitch = toneRate / toneLoop;
    double bestFrequency = 0.0;
    double bestAmplitude = -1.0;
    for (double frequency = expectedPitch - 20.0; frequency <= expectedPitch + 20.0;
         frequency += 0.5) {
        const double amplitude = toneAmp(held, engine.sampleRate(), frequency, 0, held.size() / 2);
        if (amplitude > bestAmplitude) {
            bestAmplitude = amplitude;
            bestFrequency = frequency;
        }
    }
    QVERIFY2(bestAmplitude >= 0.005, "sample audition carries measurable pitch");
    QVERIFY2(std::abs(bestFrequency - expectedPitch) <= 5.0, "sample audition holds its rate");

    // Programmable-wave resolution renders through the wave lane.
    QCOMPARE(browser
                 .auditionSymbol(&owner, waveSymbol, VgAuditionKind::Wave,
                                 AuditionSlots::Adsr{2, 3, 12, 4})
                 .status,
             soundbrowser::AuditionStatus::Started);
    QVERIFY2(tailPeak(engine, 0.5) >= 0.01, "wave audition sounds");
    browser.stopAll();
    renderSeconds(engine, 3.0);

    // Keysplit resolution: key 60 lands on the DirectSound sub-voice with
    // its own envelope and base key.
    QCOMPARE(browser.auditionSymbol(&owner, keysplitSymbol, VgAuditionKind::Keysplit, {}).status,
             soundbrowser::AuditionStatus::Started);
    QVERIFY2(tailPeak(engine, 0.5) >= 0.01, "keysplit audition sounds");
    const std::vector<float> split = renderSeconds(engine, 1.0);
    // The keysplit audition keys the resolved sub-voice's wave at the
    // audition note around the sub-voice's own base key.
    const LoadedKeysplit *loadedSplit = nullptr;
    for (int i = 0; i < rig.catalog.keysplits.size() && i < rig.samples->keysplitCount; i++) {
        if (rig.catalog.keysplits.at(i).first == keysplitSymbol &&
            rig.samples->keysplits[i].subGroup && rig.samples->keysplits[i].table) {
            loadedSplit = &rig.samples->keysplits[i];
            break;
        }
    }
    QVERIFY(loadedSplit);
    const ToneData &subVoice = loadedSplit->subGroup[loadedSplit->table[60]];
    QVERIFY(subVoice.wav && subVoice.wav->size > subVoice.wav->loopStart);
    const double splitRate = double(subVoice.wav->freq) / 1024.0;
    const double splitLoop = (subVoice.wav->status & 0x4000u) != 0
                                 ? double(subVoice.wav->size - subVoice.wav->loopStart)
                                 : double(subVoice.wav->size);
    const double expectedSplit =
        (splitRate / splitLoop) * std::pow(2.0, (60.0 - double(subVoice.key)) / 12.0);
    bestFrequency = 0.0;
    bestAmplitude = -1.0;
    for (double frequency = expectedSplit - 20.0; frequency <= expectedSplit + 20.0;
         frequency += 0.5) {
        const double amplitude =
            toneAmp(split, engine.sampleRate(), frequency, 0, split.size() / 2);
        if (amplitude > bestAmplitude) {
            bestAmplitude = amplitude;
            bestFrequency = frequency;
        }
    }
    QVERIFY2(bestAmplitude >= 0.005, "keysplit audition carries measurable pitch");
    QVERIFY2(std::abs(bestFrequency - expectedSplit) <= 6.0,
             "keysplit audition pitches around the sub-voice base key");

    // Unsupported resolutions never replace a sounding request.
    QCOMPARE(browser.auditionSymbol(&owner, squareSplitSymbol, VgAuditionKind::Keysplit, {}).status,
             soundbrowser::AuditionStatus::Unsupported);
    QCOMPARE(browser
                 .auditionSymbol(&owner, QStringLiteral("DirectSoundWaveData_missing"),
                                 VgAuditionKind::Sample, fast)
                 .status,
             soundbrowser::AuditionStatus::Unsupported);
    QCOMPARE(browser.auditionSymbol(&owner, sampleSymbol, VgAuditionKind::Wave, fast).status,
             soundbrowser::AuditionStatus::Unsupported);
    QCOMPARE(browser.auditionSymbol(&owner, waveSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Unsupported);
    QVERIFY2(tailPeak(engine, 0.3) >= 0.01, "failed resolutions leave the current audition alone");
    browser.stopAll();
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "keysplit stop drains to silence");

    // No callback can retire a slot between these publications.
    for (int i = 0; i < AuditionSlots::kSlots; ++i)
        QCOMPARE(browser.auditionSymbol(&owner, sampleSymbol, VgAuditionKind::Sample, fast).status,
                 soundbrowser::AuditionStatus::Started);
    QCOMPARE(browser.auditionSymbol(&owner, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Busy);
    QVERIFY2(peakOf(renderSeconds(engine, 0.2)) <= 1.0e-7,
             "a busy request must not replay after slots retire");
    QCOMPARE(browser.auditionSymbol(&owner, sampleSymbol, VgAuditionKind::Sample, fast).status,
             soundbrowser::AuditionStatus::Started);
    QVERIFY2(tailPeak(engine, 0.1) >= 0.01, "a later user request succeeds after retirement");
}

void SampleProcessingTest::browseExternalFile()
{
    BrowseRig rig;
    QVERIFY2(openBrowseRig(rig), qPrintable(rig.error));

    ScopedNullAudioBackend nullBackend;
    AudioEngine engine;
    QString audioError;
    QVERIFY2(startParkedEngine(engine, rig.bank, &audioError), qPrintable(audioError));

    const QString sourcePath = rig.scratch.filePath(QStringLiteral("sources/hires_tone.wav"));
    QVERIFY(writeFile(sourcePath, hiResSampleWav()));
    const QString badPath = rig.scratch.filePath(QStringLiteral("sources/bad_tone.wav"));
    QVERIFY(writeFile(badPath, QByteArray("not audio bytes")));

    // External preview works with no project set at all.
    soundbrowser::SoundBrowser browser(engine);
    QObject ownerA, ownerB;
    QCOMPARE(browser.auditionExternalFile(&ownerA, sourcePath, 60).status,
             soundbrowser::AuditionStatus::Started);
    QVERIFY2(tailPeak(engine, 0.1) >= 0.01, "external preview renders one-shot audio");
    // A failed decode never replaces a sounding request: the one-shot preview
    // keeps playing, a non-owner stop cannot cut it, and only the owner's stop
    // releases it.
    const soundbrowser::AuditionResult bad = browser.auditionExternalFile(&ownerB, badPath, 60);
    QCOMPARE(bad.status, soundbrowser::AuditionStatus::DecodeError);
    QVERIFY(!bad.message.isEmpty());
    browser.stop(&ownerB);
    QVERIFY2(tailPeak(engine, 0.1) >= 0.01, "decode failure leaves the current audition alone");
    browser.stop(&ownerA);
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "external stop drains to silence");

    // External requests survive snapshot invalidation.
    browser.setProjectSamples(rig.samples, rig.catalog);
    QCOMPARE(browser.auditionExternalFile(&ownerA, sourcePath, 60).status,
             soundbrowser::AuditionStatus::Started);
    browser.clearProjectSamples();
    QVERIFY2(tailPeak(engine, 0.5) >= 0.01, "external preview survives snapshot invalidation");
    renderSeconds(engine, 3.0);
    QVERIFY2(tailPeak(engine, 0.1) <= 1.0e-7, "an external one-shot ends without a stop request");
    browser.stopAll();
    renderSeconds(engine, 3.0);

    QCOMPARE(browser.auditionExternalFile(nullptr, sourcePath, 60).status,
             soundbrowser::AuditionStatus::Unsupported);
    QCOMPARE(browser.auditionExternalFile(&ownerA, QString(), 60).status,
             soundbrowser::AuditionStatus::Unsupported);
}

} // namespace samplecheck
