#include <cstdio>
#include <memory>
#include <optional>
#include <utility>

#include <QDir>
#include <QElapsedTimer>
#include <QtTest>

#include "checks/support/songfixture.h"
#include "checks/voicegroup/voicegrouploadfixture.h"
#include "project/decompproject.h"

namespace {

class VoicegroupLoaderTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicegroupLoaderTest)

  public:
    explicit VoicegroupLoaderTest(QString stagedRoot) : m_stagedRoot(std::move(stagedRoot)) {}

  private slots:
    void init();
    void exactTargetParityWarmReuseAndSampleSets();
    void serialAndFourWideBatchAdaptersPreserveBankAndOwnership();
    void failedTransportReleasesPartialBatchAndContextHeals();

  private:
    QByteArray targetPath(const QString &name) const;
    std::unique_ptr<checks::ProjectFixture> m_copy;
    QString m_stagedRoot;
};

void VoicegroupLoaderTest::init()
{
    QString error;
    m_copy = checks::ProjectFixture::copyOf(m_stagedRoot, error);
    QVERIFY2(m_copy, qPrintable(error));
    QVERIFY2(voicegroup_load_test::stageBatchVoicegroup(m_copy->root(), error), qPrintable(error));
}

QByteArray VoicegroupLoaderTest::targetPath(const QString &name) const
{
    return QDir(m_copy->root())
        .absoluteFilePath(QStringLiteral("sound/voicegroups/%1.inc").arg(name))
        .toLocal8Bit();
}

void VoicegroupLoaderTest::exactTargetParityWarmReuseAndSampleSets()
{
    const QByteArray root = m_copy->root().toLocal8Bit();
    LoadedVoiceGroup *const rich = voicegroup_load(root.constData(), "fixture_rich", nullptr);
    LoadedVoiceGroup *const batch = voicegroup_load(root.constData(), "check_batch", nullptr);
    QVERIFY(rich);
    QVERIFY(batch);
    voicegroup_load_test::BatchAdapter adapter;
    VoicegroupProject *const project = voicegroup_load_test::openContext(m_copy->root(), adapter);
    QVERIFY(project);
    const QByteArray richPath = targetPath(QStringLiteral("fixture_rich"));
    const QByteArray batchPath = targetPath(QStringLiteral("check_batch"));
    const VoicegroupTarget richTarget{richPath.constData(), ""};
    const VoicegroupTarget batchTarget{batchPath.constData(), ""};
    LoadedVoiceGroup *const contextRich = voicegroup_project_load(project, &richTarget);
    QVERIFY(contextRich);
    QVERIFY(voicegroup_load_test::sameBank(*contextRich, *rich));
    voicegroup_free(contextRich);
    adapter.reset();
    LoadedVoiceGroup *const contextBatch = voicegroup_project_load(project, &batchTarget);
    QVERIFY(contextBatch);
    QVERIFY(voicegroup_load_test::sameBank(*contextBatch, *batch));
    voicegroup_free(contextBatch);
    adapter.reset();
    LoadedVoiceGroup *const warm = voicegroup_project_load(project, &batchTarget);
    QVERIFY(warm);
    QVERIFY(voicegroup_load_test::sameBank(*warm, *batch));
    QCOMPARE(adapter.requestedCount("direct_sound_data.inc"), 0);
    QCOMPARE(adapter.requestedCount("programmable_wave_data.inc"), 0);
    QCOMPARE(adapter.requestedCount("keysplit_tables.inc"), 0);
    voicegroup_free(warm);

    const char *samples[] = {"DirectSoundWaveData_fixture_loop"};
    const char *waves[] = {"ProgrammableWaveData_fixture_pulse"};
    const char *keysplits[] = {"fixture_keys"};
    const char *tables[] = {"keysplit_fixture"};
    LoadedSampleSet *const oneShot = voicegroup_load_samples(root.constData(), samples, 1, waves, 1,
                                                             keysplits, tables, 1, nullptr);
    LoadedSampleSet *const contextual =
        voicegroup_project_load_samples(project, samples, 1, waves, 1, keysplits, tables, 1);
    QVERIFY(oneShot);
    QCOMPARE(oneShot->count, 1);
    QVERIFY(oneShot->waves[0]);
    QVERIFY(contextual);
    QVERIFY(voicegroup_load_test::sameSampleSet(*contextual, *oneShot));
    voicegroup_free_samples(contextual);
    voicegroup_free_samples(oneShot);
    voicegroup_project_free(project);
    voicegroup_free(batch);
    voicegroup_free(rich);
}

void VoicegroupLoaderTest::serialAndFourWideBatchAdaptersPreserveBankAndOwnership()
{
    const QByteArray root = m_copy->root().toLocal8Bit();
    LoadedVoiceGroup *const expected = voicegroup_load(root.constData(), "check_batch", nullptr);
    QVERIFY(expected);
    const QByteArray path = targetPath(QStringLiteral("check_batch"));
    const VoicegroupTarget target{path.constData(), ""};
    for (const int width : {1, 4}) {
        voicegroup_load_test::BatchAdapter adapter;
        adapter.width = width;
        adapter.delayMs = 5;
        VoicegroupProject *const project =
            voicegroup_load_test::openContext(m_copy->root(), adapter);
        QVERIFY(project);
        LoadedVoiceGroup *const loaded = voicegroup_project_load(project, &target);
        QVERIFY(loaded);
        QVERIFY(voicegroup_load_test::sameBank(*loaded, *expected));
        // The adapter's start gate holds every reader of a slice in flight
        // until the whole slice has arrived, so the observed concurrency is
        // deterministic: exactly `width` for the 16-asset batch. A loader
        // that serialized the batch into one-at-a-time transport reads would
        // never have more than a single reader in flight, so the wide run
        // trips this comparison with no wall-clock measurement involved.
        QCOMPARE(adapter.maxInFlight, width);
        QCOMPARE(adapter.populated, adapter.released);
        QVERIFY(adapter.requestedOnce());
        voicegroup_free(loaded);
        voicegroup_project_free(project);
    }
    voicegroup_free(expected);
}

void VoicegroupLoaderTest::failedTransportReleasesPartialBatchAndContextHeals()
{
    const QByteArray root = m_copy->root().toLocal8Bit();
    LoadedVoiceGroup *const expected = voicegroup_load(root.constData(), "check_batch", nullptr);
    QVERIFY(expected);
    const QByteArray path = targetPath(QStringLiteral("check_batch"));
    const VoicegroupTarget target{path.constData(), ""};
    voicegroup_load_test::BatchAdapter adapter;
    adapter.width = 4;
    adapter.failureSuffix = "check_batch_07.bin";
    VoicegroupProject *const project = voicegroup_load_test::openContext(m_copy->root(), adapter);
    QVERIFY(project);
    LoadedVoiceGroup *const failed = voicegroup_project_load(project, &target);
    QVERIFY(!failed);
    QVERIFY(adapter.populated >= 1);
    QCOMPARE(adapter.populated, adapter.released);
    adapter.failureSuffix = nullptr;
    adapter.reset();
    LoadedVoiceGroup *const healed = voicegroup_project_load(project, &target);
    QVERIFY(healed);
    QVERIFY(voicegroup_load_test::sameBank(*healed, *expected));
    voicegroup_free(healed);
    voicegroup_project_free(project);
    voicegroup_free(expected);
}

class VoicegroupLoadBenchTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VoicegroupLoadBenchTest)

  public:
    VoicegroupLoadBenchTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void songLoadBenchmark();

  private:
    QString m_projectRoot;
    QString m_songLabel;
};

// The legacy vgloadbench branch kept as a real Qt runner: open/load/warm
// timings are the reported signal, while the deterministic contracts (open,
// song locate, first load, warm lease reuse) assert through QTest like every
// other suite.
void VoicegroupLoadBenchTest::songLoadBenchmark()
{
    DecompProject project;
    QString error;
    QElapsedTimer timer;
    timer.start();
    QVERIFY2(project.open(m_projectRoot, &error), qPrintable(error));
    const double openMs = double(timer.nsecsElapsed()) / 1'000'000.0;
    const std::optional<SongName> name = SongName::create(m_songLabel);
    QVERIFY2(name.has_value(), qPrintable(m_songLabel));
    const std::optional<SongInfo> song = project.playableSong(*name);
    QVERIFY2(song.has_value(), qPrintable(m_songLabel));
    timer.restart();
    const std::optional<LoadedBankView> first = project.loadBank(*song, &error);
    const double loadMs = double(timer.nsecsElapsed()) / 1'000'000.0;
    QVERIFY2(first.has_value(), qPrintable(error));
    error.clear();
    timer.restart();
    const std::optional<LoadedBankView> warm = project.loadBank(*song, &error);
    const double warmMs = double(timer.nsecsElapsed()) / 1'000'000.0;
    QVERIFY2(warm && warm->bank.get() == first->bank.get(), qPrintable(error));
    std::printf("vgloadbench: song=%s open_ms=%.3f load_ms=%.3f warm_ms=%.3f\n",
                qUtf8Printable(m_songLabel), openMs, loadMs, warmMs);
}

} // namespace

int runVgLoadCheck(const QString &projectRoot, const QString &songLabel,
                   const QStringList &qtArguments)
{
    if (!songLabel.isEmpty()) {
        VoicegroupLoadBenchTest bench(projectRoot, songLabel);
        QStringList benchArguments{QStringLiteral("voicegroup-load-bench")};
        benchArguments.append(qtArguments);
        return QTest::qExec(&bench, benchArguments);
    }
    VoicegroupLoaderTest test(projectRoot);
    QStringList arguments{QStringLiteral("voicegroup-loader")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_voicegrouploader.moc"
