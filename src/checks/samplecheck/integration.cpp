#include "checks/samplecheck/fixtures.h"
#include "checks/samplecheck/samplecheck.h"

#include <QApplication>
#include <QFile>
#include <QIODevice>
#include <QLineEdit>
#include <QPushButton>
#include <QTemporaryDir>
#include <QUndoStack>
#include <QtTest>
#include <memory>

#include "audio/sampledoc.h"
#include "audio/sampleimport.h"
#include "audio/samplewav.h"
#include "project/samplereg.h"
#include "ui/sampleeditordialog.h"

extern "C" {
#include "voicegroup_loader.h"
}
namespace {

class EngineSession final
{
  public:
    explicit EngineSession(float rate) : initialized(m4a_engine_init(&engine, rate)) {}
    ~EngineSession()
    {
        if (initialized)
            m4a_engine_destroy(&engine);
    }

    M4AEngine engine{};
    bool initialized = false;
};

} // namespace

namespace samplecheck {

void SampleProcessingTest::engineLoop()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "engine-loop scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "engine-loop synthetic project is created");
    ImportedSample hiRes;
    QString importError;
    QVERIFY2(importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes,
                              &importError),
             qPrintable(importError));

    SampleEditParams params = SampleDocument::defaultParams(hiRes);
    params.targetRate = 13379.0;
    SampleDocument doc(hiRes);
    doc.setParams(params);
    const ProcessedSample &out = doc.processed();
    QVERIFY2(out.looped && out.size > out.loopStart + 100, "engine-loop fixture renders looped");
    QString error;
    QVERIFY2(SampleRegistrar::registerSample(root, QStringLiteral("engineloop_tone"),
                                             writeSampleWav(out), &error),
             "engine-loop sample registers");
    QVERIFY(writeFile(root + QStringLiteral("/sound/voicegroups/voicegroup_engineloop.inc"),
                      "voicegroup_engineloop::\n"
                      "\tvoice_directsound 60, 0, "
                      "DirectSoundWaveData_engineloop_tone, 255, 0, 255, 0\n"));
    const QByteArray rootUtf8 = root.toLocal8Bit();
    auto voicegroup = std::unique_ptr<LoadedVoiceGroup, decltype(&voicegroup_free)>{
        voicegroup_load(rootUtf8.constData(), "voicegroup_engineloop", nullptr), voicegroup_free};
    QVERIFY2(voicegroup, "engine-loop voicegroup resolves");

    const float hostRate = float(std::round(double(out.freq) / 1024.0));
    EngineSession session(hostRate);
    M4AEngine *engine = &session.engine;
    QVERIFY2(session.initialized, "engine-loop initializes at an integral host rate");
    m4a_engine_set_pcm_mix_rate(engine, 0.0f);
    m4a_engine_set_voicegroup(engine, voicegroup->voices);
    m4a_engine_program_change(engine, 0, 0);
    m4a_engine_note_on(engine, 0, 60, 127);
    const M4APCMChannel *channel = nullptr;
    for (int i = 0; i < MAX_PCM_CHANNELS; ++i) {
        if (engine->pcmChannels[i].status & CHN_ON)
            channel = &engine->pcmChannels[i];
    }
    QVERIFY2(channel, "engine-loop note keys a channel");
    const quint64 loopLength = quint64(out.size) - out.loopStart;
    const quint64 measurementStart = quint64(out.size) + 4 * loopLength;
    const quint64 renderFrames = measurementStart + loopLength;
    constexpr quint64 kMaxRenderFrames = 400000;
    QVERIFY2(renderFrames <= kMaxRenderFrames, "engine-loop fixture fits render window");
    float left = 0.0f;
    float right = 0.0f;
    double previous = 0.0;
    double maxRenderedStep = 0.0;
    double peak = 0.0;
    for (quint64 i = 0; i < renderFrames; ++i) {
        m4a_engine_process(engine, &left, &right, 1);
        const double value = double(left);
        if (i >= measurementStart) {
            maxRenderedStep = qMax(maxRenderedStep, std::abs(value - previous));
            peak = qMax(peak, std::abs(value));
        }
        previous = value;
    }
    QVERIFY2((channel->status & CHN_ON) && peak > 0.0, "at least four full loop wraps render");

    int maxS8 = 1;
    int maxSourceStep = 0;
    for (quint32 i = out.loopStart; i < out.size; ++i) {
        const int sample = int(qint8(out.s8.at(qsizetype(i))));
        const quint32 nextIndex = i + 1 < out.size ? i + 1 : out.loopStart;
        const int next = int(qint8(out.s8.at(qsizetype(nextIndex))));
        maxS8 = qMax(maxS8, std::abs(sample));
        maxSourceStep = qMax(maxSourceStep, std::abs(next - sample));
    }
    const double lsb = peak / double(maxS8);
    QVERIFY2(maxRenderedStep <= double(maxSourceStep) * lsb + 2.0 * lsb + 1e-9,
             "loop-wrap steps stay within source steps plus two LSB");
}

void SampleProcessingTest::sidecarRoundtrip()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sidecar-roundtrip scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sidecar-roundtrip synthetic project is created");
    const QByteArray sourceBytes = hiResSampleWav();
    ImportedSample hiRes;
    QString error;
    QVERIFY2(importAudioBytes(sourceBytes, QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
             qPrintable(error));
    const QString sourcePath = scratch.filePath(QStringLiteral("sources/hires_tone.wav"));
    QVERIFY(writeFile(sourcePath, sourceBytes));
    SampleEditParams params = SampleDocument::defaultParams(hiRes);
    params.cropStart = 150;
    params.targetRate = 13379.0;
    params.baseKey = 59;
    params.fineTuneCents = 25.0;
    SampleDocument doc(hiRes);
    doc.setParams(params);
    QVERIFY2(SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"),
                                             writeSampleWav(doc.processed()), &error),
             "provenance sample registers");
    SampleSidecar sidecar;
    sidecar.sourcePath = sourcePath;
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.params = params;
    QVERIFY2(SampleRegistrar::writeSampleSidecar(root, QStringLiteral("provenance_tone"), sidecar,
                                                 &error),
             "sidecar writes");

    SampleSidecar back;
    QVERIFY2(SampleRegistrar::readSampleSidecar(root, QStringLiteral("provenance_tone"), &back),
             "sidecar reads back");
    QVERIFY2(back.version == 1 && back.sourcePath == sidecar.sourcePath &&
                 back.sourceSha256 == sidecar.sourceSha256 && back.leftOnly == sidecar.leftOnly &&
                 back.sf2Zone == sidecar.sf2Zone && back.params == sidecar.params,
             "sidecar round-trips every field");
}

void SampleProcessingTest::sidecarRerender()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sidecar-rerender scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sidecar-rerender synthetic project is created");
    const QByteArray sourceBytes = hiResSampleWav();
    ImportedSample hiRes;
    QString error;
    QVERIFY2(importAudioBytes(sourceBytes, QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
             qPrintable(error));
    const QString sourcePath = scratch.filePath(QStringLiteral("sources/hires_tone.wav"));
    QVERIFY(writeFile(sourcePath, sourceBytes));
    SampleEditParams params = SampleDocument::defaultParams(hiRes);
    params.cropStart = 150;
    params.targetRate = 13379.0;
    params.baseKey = 59;
    params.fineTuneCents = 25.0;
    SampleDocument doc(hiRes);
    doc.setParams(params);
    const QByteArray committed = writeSampleWav(doc.processed());
    QVERIFY2(
        SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"), committed, &error),
        "provenance sample registers");
    SampleSidecar sidecar;
    sidecar.sourcePath = sourcePath;
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.params = params;
    QVERIFY2(SampleRegistrar::writeSampleSidecar(root, QStringLiteral("provenance_tone"), sidecar,
                                                 &error),
             "sidecar writes");
    SampleSidecar back;
    QVERIFY2(SampleRegistrar::readSampleSidecar(root, QStringLiteral("provenance_tone"), &back),
             "sidecar reads back");

    const QByteArray reread = readFileBytes(back.sourcePath);
    QCOMPARE(SampleRegistrar::sourceHashHex(reread), back.sourceSha256);
    ImportedSample reopened;
    QVERIFY2(importAudioBytes(reread, back.sourcePath, &reopened, &error, back.leftOnly),
             "sidecar source re-imports");
    SampleDocument redoc(reopened);
    redoc.setParams(back.params);
    QCOMPARE(writeSampleWav(redoc.processed()), committed);
}

void SampleProcessingTest::sidecarTouchedSource()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sidecar-touch scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sidecar-touch synthetic project is created");
    const QByteArray sourceBytes = hiResSampleWav();
    ImportedSample hiRes;
    QString error;
    QVERIFY2(importAudioBytes(sourceBytes, QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
             qPrintable(error));
    const QString sourcePath = scratch.filePath(QStringLiteral("sources/hires_tone.wav"));
    QVERIFY(writeFile(sourcePath, sourceBytes));
    SampleSidecar sidecar;
    SampleDocument doc(hiRes);
    doc.setParams(SampleDocument::defaultParams(hiRes));
    QVERIFY2(SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"),
                                             writeSampleWav(doc.processed()), &error),
             "provenance sample registers");
    sidecar.sourcePath = sourcePath;
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.params = SampleDocument::defaultParams(hiRes);
    QVERIFY2(SampleRegistrar::writeSampleSidecar(root, QStringLiteral("provenance_tone"), sidecar,
                                                 &error),
             "sidecar writes");

    QVERIFY(writeFile(sourcePath, sourceBytes + QByteArray(4, '\0')));
    QVERIFY2(SampleRegistrar::sourceHashHex(readFileBytes(sourcePath)) != sidecar.sourceSha256,
             "a touched source no longer matches the sidecar hash");
}

void SampleProcessingTest::sidecarFallback()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sidecar-fallback scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sidecar-fallback synthetic project is created");
    ImportedSample hiRes;
    QString error;
    QVERIFY2(
        importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
        qPrintable(error));
    SampleEditParams params = SampleDocument::defaultParams(hiRes);
    params.cropStart = 150;
    params.targetRate = 13379.0;
    params.baseKey = 59;
    params.fineTuneCents = 25.0;
    SampleDocument doc(hiRes);
    doc.setParams(params);
    const QByteArray committed = writeSampleWav(doc.processed());
    QVERIFY2(
        SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"), committed, &error),
        "provenance sample registers");

    ImportedSample fallback;
    QVERIFY2(
        importAudioBytes(committed, QStringLiteral("x/provenance_tone.wav"), &fallback, &error),
        "committed .wav re-imports");
    QVERIFY2(fallback.gbaReady, "committed .wav re-imports GBA-ready");
    SampleDocument fallbackDocument(fallback);
    fallbackDocument.setParams(SampleDocument::defaultParams(fallback));
    QCOMPARE(writeSampleWav(fallbackDocument.processed()), committed);
}

void SampleProcessingTest::sampleUpdate()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sample-update scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sample-update synthetic project is created");
    ImportedSample hiRes;
    QString error;
    QVERIFY2(
        importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
        qPrintable(error));
    SampleEditParams params = SampleDocument::defaultParams(hiRes);
    params.cropStart = 150;
    params.targetRate = 13379.0;
    params.baseKey = 59;
    params.fineTuneCents = 25.0;
    SampleDocument doc(hiRes);
    doc.setParams(params);
    const QByteArray committed = writeSampleWav(doc.processed());
    QVERIFY2(
        SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"), committed, &error),
        "provenance sample registers");
    params.fineTuneCents = 40.0;
    doc.setParams(params);
    const QByteArray updated = writeSampleWav(doc.processed());
    QVERIFY(updated != committed);
    const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
    const QByteArray incBefore = readFileBytes(incPath);
    QVERIFY2(
        SampleRegistrar::updateSample(root, QStringLiteral("provenance_tone"), updated, &error),
        "updateSample succeeds");
    QCOMPARE(readFileBytes(incPath), incBefore);
    QCOMPARE(
        readFileBytes(root + QStringLiteral("/sound/direct_sound_samples/provenance_tone.wav")),
        updated);
}

void SampleProcessingTest::sampleUpdateRefusals_data()
{
    QTest::addColumn<bool>("binOnly");
    QTest::newRow("unregistered") << false;
    QTest::newRow("bin-only") << true;
}

void SampleProcessingTest::sampleUpdateRefusals()
{
    QFETCH(bool, binOnly);
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sample-update refusal scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sample-update refusal synthetic project is created");
    ImportedSample hiRes;
    QString error;
    QVERIFY2(
        importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
        qPrintable(error));
    SampleDocument doc(hiRes);
    doc.setParams(SampleDocument::defaultParams(hiRes));
    const QByteArray updated = writeSampleWav(doc.processed());

    if (binOnly) {
        constexpr char binOnlyFixture[] = "\n\t.align 2\nDirectSoundWaveData_binonly::\n"
                                          "\t.incbin \"sound/direct_sound_samples/binonly.bin\"\n";
        const QString incPath = root + QStringLiteral("/sound/direct_sound_data.inc");
        QFile inc(incPath);
        QVERIFY2(inc.open(QIODevice::Append) &&
                     inc.write(binOnlyFixture) == qint64(sizeof(binOnlyFixture) - 1),
                 "append .bin-only sample fixture");
    }
    const QString sampleName =
        binOnly ? QStringLiteral("binonly") : QStringLiteral("never_registered");
    QVERIFY2(!SampleRegistrar::updateSample(root, sampleName, updated, &error),
             "updating a non-updatable sample refuses");
    QVERIFY2(!error.isEmpty(), "rejected input reports a refusal");
}

void SampleProcessingTest::sidecarEditDialog()
{
    ImportedSample hiRes;
    QString error;
    QVERIFY2(
        importAudioBytes(hiResSampleWav(), QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
        qPrintable(error));
    SampleEditParams params = SampleDocument::defaultParams(hiRes);
    params.cropStart = 150;
    params.targetRate = 13379.0;
    params.baseKey = 59;
    params.fineTuneCents = 25.0;

    const auto acceptsRegisteredName = [](const QString &candidate, QString *err) {
        if (candidate == QStringLiteral("provenance_tone"))
            return true;
        if (err)
            *err = QStringLiteral("the sample keeps its registered name.");
        return false;
    };
    SampleEditorDialog dialog(hiRes, acceptsRegisteredName);
    dialog.setEditTarget(QStringLiteral("provenance_tone"));
    dialog.applyParamsExternal(params);
    dialog.show();
    QApplication::processEvents();
    auto *nameEdit = dialog.findChild<QLineEdit *>(QStringLiteral("sampleNameEdit"));
    auto *addButton = dialog.findChild<QPushButton *>(QStringLiteral("sampleAddButton"));
    const auto *document = dialog.document();
    const auto *undoStack = dialog.undoStack();
    QVERIFY2(nameEdit && nameEdit->isReadOnly() &&
                 nameEdit->text() == QStringLiteral("provenance_tone"),
             "edit mode locks the name");
    QVERIFY2(addButton && addButton->isEnabled(), "edit mode exposes an enabled commit action");
    QVERIFY2(document && undoStack, "edit dialog provides its document and undo stack");
    QVERIFY2(document->params() == params && undoStack->count() == 0,
             "sidecar params are the baseline, not an undo entry");
}

void SampleProcessingTest::sidecarRemove()
{
    QTemporaryDir scratch;
    QVERIFY2(scratch.isValid(), "sidecar-remove scratch directory is available");
    const QString root = scratch.filePath(QStringLiteral("wavproj"));
    QVERIFY2(createWav2AgbProject(root), "sidecar-remove synthetic project is created");
    const QByteArray sourceBytes = hiResSampleWav();
    ImportedSample hiRes;
    QString error;
    QVERIFY2(importAudioBytes(sourceBytes, QStringLiteral("fix/hires_tone.wav"), &hiRes, &error),
             qPrintable(error));
    const QString sourcePath = scratch.filePath(QStringLiteral("sources/hires_tone.wav"));
    QVERIFY(writeFile(sourcePath, sourceBytes));
    SampleSidecar sidecar;
    sidecar.sourcePath = sourcePath;
    sidecar.sourceSha256 = SampleRegistrar::sourceHashHex(sourceBytes);
    sidecar.params = SampleDocument::defaultParams(hiRes);
    SampleDocument doc(hiRes);
    doc.setParams(SampleDocument::defaultParams(hiRes));
    QVERIFY2(SampleRegistrar::registerSample(root, QStringLiteral("provenance_tone"),
                                             writeSampleWav(doc.processed()), &error),
             "provenance sample registers");
    QVERIFY2(SampleRegistrar::writeSampleSidecar(root, QStringLiteral("provenance_tone"), sidecar,
                                                 &error),
             "sidecar writes");

    SampleRegistrar::removeSampleSidecar(root, QStringLiteral("provenance_tone"));
    SampleSidecar back;
    QVERIFY2(!SampleRegistrar::readSampleSidecar(root, QStringLiteral("provenance_tone"), &back),
             "removed sidecar no longer reads");
}

} // namespace samplecheck
