#include "projectio.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QSaveFile>
#include <QThread>
#include <cstring>
#include <utility>
#include <vector>

namespace {

bool writeBytes(const QString &path, const QByteArray &bytes, QString *error)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        if (error)
            *error = QStringLiteral("Cannot write %1: %2").arg(path, file.errorString());
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        if (error)
            *error = QStringLiteral("Short write to %1: %2").arg(path, file.errorString());
        file.cancelWriting();
        return false;
    }
    if (!file.commit()) {
        if (error)
            *error = QStringLiteral("Cannot commit %1: %2").arg(path, file.errorString());
        return false;
    }
    return true;
}

QString previewDirFor(const QString &root)
{
    return QDir(root).filePath(QStringLiteral(".porydaw/vgpreview"));
}

} // namespace

class ProjectIo::Worker final : public QObject
{
  public:
    ProjectOpenResult prepareProject(const QString &root, uint64_t requestId)
    {
        if (QThread::currentThread() != thread())
            return {{}, QStringLiteral("Project open did not run on the project thread.")};
        m_candidate.reset();
        m_candidateRequestId = 0;
        auto candidate = DecompProject{};
        auto error = QString{};
        if (!candidate.open(root, &error))
            return {{}, std::move(error)};
        auto trackBudgets = QHash<QString, int>{};
        trackBudgets.reserve(candidate.songs().size());
        for (const auto &song : candidate.songs())
            trackBudgets.insert(song.label, candidate.trackBudgetFor(song));
        auto snapshot = ProjectSnapshot{candidate.root(), candidate.songs(), candidate.players(),
                                        std::move(trackBudgets)};
        m_candidate = std::move(candidate);
        m_candidateRequestId = requestId;
        return {std::move(snapshot), {}};
    }

    bool commitProject(uint64_t requestId)
    {
        Q_ASSERT(QThread::currentThread() == thread());
        if (!m_candidate || requestId != m_candidateRequestId)
            return false;
        m_project = std::move(*m_candidate);
        m_candidate.reset();
        m_candidateRequestId = 0;
        return true;
    }

    SongFileResult loadSongFile(SongInfo song, uint64_t requestId)
    {
        auto result = SongFileResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Song load did not run on the project thread.");
            return result;
        }
        SmfFile::readFile(song.midPath, &result.smf, &result.error);
        return result;
    }

    VoicegroupLoadResult loadVoicegroup(QString root, SongCfg cfg, uint64_t requestId)
    {
        auto result = VoicegroupLoadResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Voicegroup load did not run on the project thread.");
            return result;
        }
        const auto candidates = DecompProject::voicegroupCandidates(cfg);
        const auto tried = candidates.join(QStringLiteral(", "));
        const auto rootUtf8 = root.toLocal8Bit();
        auto *voicegroup = static_cast<LoadedVoiceGroup *>(nullptr);
        for (const auto &name : candidates) {
            const auto nameUtf8 = name.toLocal8Bit();
            voicegroup = voicegroup_load(rootUtf8.constData(), nameUtf8.constData(), nullptr);
            if (voicegroup)
                break;
        }
        if (!voicegroup) {
            result.error = QStringLiteral("Could not load voicegroup (tried: %1).").arg(tried);
            return result;
        }
        auto source = std::make_unique<VoicegroupSource>();
        auto error = QString{};
        if (!source->open(root, cfg.voicegroupArg, &error)) {
            voicegroup_free(voicegroup);
            result.error = std::move(error);
            if (result.error.isEmpty())
                result.error = QStringLiteral("Could not open the voicegroup source.");
            return result;
        }
        result.filePath = source->filePath();
        result.fileTime = QFileInfo(result.filePath).lastModified();
        result.voicegroup = voicegroup;
        result.source = std::move(source);
        return result;
    }

    VoicegroupProbeResult probeVoicegroup(QString root, SongCfg cfg, uint64_t requestId)
    {
        auto result = VoicegroupProbeResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Voicegroup probe did not run on the project thread.");
            return result;
        }
        auto source = std::make_unique<VoicegroupSource>();
        if (!source->open(root, cfg.voicegroupArg, &result.error))
            return result;
        result.filePath = source->filePath();
        result.fileTime = QFileInfo(result.filePath).lastModified();
        return result;
    }

    VoicegroupSaveResult saveVoicegroup(VoicegroupSaveRequest request, uint64_t requestId)
    {
        auto result = VoicegroupSaveResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Voicegroup save did not run on the project thread.");
            return result;
        }
        result.synthOk = true;
        if (!request.synthDefinitions.isEmpty() &&
            !VoicegroupSource::writeSynthDefinitions(request.projectRoot, request.synthDefinitions,
                                                     &result.error))
            return result;
        if (!writeBytes(request.filePath, request.sourceBytes, &result.error))
            return result;
        result.sourceOk = true;
        result.fileTime = QFileInfo(request.filePath).lastModified();
        return result;
    }

    SaveSongResult saveSong(SongSaveSnapshot snapshot, uint64_t requestId)
    {
        auto result = SaveSongResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Song save did not run on the project thread.");
            return result;
        }
        if (!snapshot.smf.writeFile(snapshot.midPath, &result.error))
            return result;
        result.midiOk = true;
        result.flagsOk = true;
        if (!snapshot.flagsNeeded)
            return result;
        const QStringList flags = SongRegistry::mergeCfgFlags(snapshot.cfg);
        result.flagsOk = SongRegistry::writeSongFlags(QFileInfo(snapshot.midPath).path(),
                                                      snapshot.label, flags, &result.error);
        result.flagsWritten = result.flagsOk;
        return result;
    }

    SidecarLoadResult readSidecar(SidecarLoadRequest request, uint64_t requestId)
    {
        auto result = SidecarLoadResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Sidecar load did not run on the project thread.");
            return result;
        }
        result.loaded = ViewSidecar::load(request.projectRoot, request.songLabel, &result.snapshot);
        return result;
    }

    SidecarSaveResult writeSidecar(SidecarSaveRequest request, uint64_t requestId)
    {
        auto result = SidecarSaveResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Sidecar save did not run on the project thread.");
            return result;
        }
        result.saved = ViewSidecar::save(request.projectRoot, request.songLabel, request.snapshot);
        return result;
    }

    RegistrationPlanResult registrationPlan(RegistrationPlanRequest request, uint64_t requestId)
    {
        auto result = RegistrationPlanResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Registration plan did not run on the project thread.");
            return result;
        }
        result.plan = SongRegistry::makePlan(request.projectRoot, request.label, request.constant,
                                             request.player);
        result.status =
            SongRegistry::checkRegistration(request.projectRoot, request.label, request.constant);
        return result;
    }

    RegisterSongResult registerSong(RegisterSongRequest request, uint64_t requestId)
    {
        auto result = RegisterSongResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Song registration did not run on the project thread.");
            return result;
        }
        // SongRegistry::registerSong rederives its plan internally immediately
        // before applying the registration writes; the GUI plan is only for
        // the confirmation dialog and is never trusted as a commit.
        result.registered =
            SongRegistry::registerSong(request.projectRoot, request.label, request.constant,
                                       request.player, &result.error, &result.songId);
        if (result.registered)
            SongRegistry::clearRegistrationMeta(request.projectRoot, request.label);
        return result;
    }

    DeletionPlanResult deletionPlan(DeletionPlanRequest request, uint64_t requestId)
    {
        auto result = DeletionPlanResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Deletion plan did not run on the project thread.");
            return result;
        }
        result.plan =
            SongRegistry::makeRemovalPlan(request.projectRoot, request.label, request.constant);
        result.deletableVoicegroupName =
            SongRegistry::deletableVoicegroup(request.projectRoot, request.songs, request.label);
        return result;
    }

    DeleteSongResult deleteSong(DeleteSongRequest request, uint64_t requestId)
    {
        auto result = DeleteSongResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Song deletion did not run on the project thread.");
            return result;
        }
        auto project = DecompProject{};
        auto projectError = QString{};
        if (!project.open(request.projectRoot, &projectError)) {
            result.error = std::move(projectError);
            return result;
        }
        const auto plan =
            SongRegistry::makeRemovalPlan(request.projectRoot, request.label, request.constant);
        if (plan.tableIndex == 0) {
            result.error = QStringLiteral("%1 is the engine's fallback song (song ID 0) and cannot "
                                          "be deleted.")
                               .arg(request.label);
            return result;
        }
        QStringList problems;
        QString error;
        QString deleteVoicegroupName = request.deleteVoicegroupName;
        if (!deleteVoicegroupName.isEmpty() &&
            SongRegistry::deletableVoicegroup(request.projectRoot, project.songs(),
                                              request.label) != deleteVoicegroupName) {
            problems << QStringLiteral("Voicegroup %1 is no longer unused; it was kept.")
                            .arg(deleteVoicegroupName);
            deleteVoicegroupName.clear();
        }
        const QString midiDir = request.projectRoot + QStringLiteral("/sound/songs/midi");
        const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(request.label);
        if (QFile::exists(midPath)) {
            if (!Sidecar::ensureDir(request.projectRoot, QStringLiteral("trash")))
                problems << QStringLiteral("Could not create .porydaw/trash.");
            QString target =
                request.projectRoot + QStringLiteral("/.porydaw/trash/%1.mid").arg(request.label);
            for (int n = 2; QFile::exists(target); n++)
                target = request.projectRoot +
                         QStringLiteral("/.porydaw/trash/%1-%2.mid").arg(request.label).arg(n);
            if (!QFile::rename(midPath, target))
                problems << QStringLiteral("Could not move %1 to %2").arg(midPath, target);
        }
        QFile::remove(midiDir + QStringLiteral("/%1.s").arg(request.label));
        if (!SongRegistry::removeSongFlags(midiDir, request.label, &error))
            problems << error;
        if (!SongRegistry::unregisterSong(request.projectRoot, request.label, request.constant,
                                          &error))
            problems << error;
        SongRegistry::removeSongSidecar(request.projectRoot, request.label);
        if (!deleteVoicegroupName.isEmpty() &&
            !VoicegroupSource::deleteVoicegroup(request.projectRoot, deleteVoicegroupName, &error))
            problems << error;
        result.error = problems.join(QLatin1Char('\n'));
        return result;
    }

    PreviewPlanResult previewPlan(PreviewPlanRequest request, uint64_t requestId)
    {
        auto result = PreviewPlanResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Preview plan did not run on the project thread.");
            return result;
        }
        const QString previewDir = previewDirFor(request.projectRoot);
        result.shadowSourcePath = previewDir;
        result.targetIncPath = QDir(previewDir).filePath(request.loadName + QStringLiteral(".inc"));
        return result;
    }

    PreviewResult preview(PreviewRequest request, uint64_t requestId)
    {
        auto result = PreviewResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Voicegroup preview did not run on the project thread.");
            return result;
        }
        const QString previewDir = previewDirFor(request.projectRoot);
        QDir(previewDir).removeRecursively();
        if (!QDir().mkpath(previewDir)) {
            result.error = QStringLiteral("Cannot create voicegroup preview directory.");
            return result;
        }
        const QString path = QDir(previewDir).filePath(request.loadName + QStringLiteral(".inc"));
        if (!writeBytes(path, request.sourceBytes, &result.error)) {
            QDir(previewDir).removeRecursively();
            return result;
        }
        VoicegroupLoaderConfig config;
        std::memset(&config, 0, sizeof(config));
        std::strncpy(config.voicegroupPaths[0], ".porydaw/vgpreview", VG_MAX_PATH_LEN - 1);
        config.voicegroupPathCount = 1;
        const auto rootUtf8 = request.projectRoot.toLocal8Bit();
        const auto loadNameUtf8 = request.loadName.toLocal8Bit();
        result.voicegroup =
            voicegroup_load(rootUtf8.constData(), loadNameUtf8.constData(), &config);
        QDir(previewDir).removeRecursively();
        if (!result.voicegroup)
            result.error = QStringLiteral("Edited voicegroup failed to load.");
        return result;
    }

    PreviewCleanupResult cleanupPreview(const QString &root, uint64_t requestId)
    {
        auto result = PreviewCleanupResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error =
                QStringLiteral("Voicegroup preview cleanup did not run on the project thread.");
            return result;
        }
        result.cleaned = QDir(previewDirFor(root)).removeRecursively();
        return result;
    }

    CatalogResult refreshVgCatalog(const QString &root, uint64_t requestId)
    {
        auto result = CatalogResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error =
                QStringLiteral("Voicegroup catalog scan did not run on the project thread.");
            return result;
        }
        result.catalog = VoicegroupSource::catalogScan(root);
        result.directSound = VoicegroupSource::directSoundCatalog(root);
        result.progWave = VoicegroupSource::progWaveSymbols(root);
        result.perFileVoicegroups =
            QDir(QDir(root).filePath(QStringLiteral("sound/voicegroups"))).exists();
        return result;
    }

    SampleSetResult loadSampleSet(SampleSetRequest request, uint64_t requestId)
    {
        auto result = SampleSetResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Sample batch load did not run on the project thread.");
            return result;
        }
        // The C loader reads these pointers during the call; reserve every
        // QByteArray slot before taking addresses so the container cannot
        // relocate them while the symbol vectors are assembled.
        QList<QByteArray> storage;
        storage.reserve(request.samples.size() + request.waves.size() +
                        request.keysplits.size() * 2);
        const auto utf8 = [&storage](const QString &value) {
            storage.append(value.toUtf8());
            return storage.last().constData();
        };
        std::vector<const char *> samples;
        std::vector<const char *> waves;
        std::vector<const char *> keysplits;
        std::vector<const char *> tables;
        samples.reserve(request.samples.size());
        waves.reserve(request.waves.size());
        keysplits.reserve(request.keysplits.size());
        tables.reserve(request.keysplits.size());
        for (const auto &value : request.samples)
            samples.push_back(utf8(value));
        for (const auto &value : request.waves)
            waves.push_back(utf8(value));
        for (const auto &pair : request.keysplits) {
            keysplits.push_back(utf8(pair.first));
            tables.push_back(utf8(pair.second));
        }
        const auto rootUtf8 = request.projectRoot.toLocal8Bit();
        result.sampleSet = voicegroup_load_samples(
            rootUtf8.constData(), samples.data(), int(samples.size()), waves.data(),
            int(waves.size()), keysplits.data(), tables.data(), int(keysplits.size()), nullptr);
        if (!result.sampleSet)
            result.error = QStringLiteral("Could not load project samples.");
        return result;
    }

    SampleProbeResult probeSamples(const QString &root, uint64_t requestId)
    {
        auto result = SampleProbeResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Sample format probe did not run on the project thread.");
            return result;
        }
        result.probe = SampleRegistrar::probeSampleFormat(root);
        result.error = result.probe.refusal;
        return result;
    }

    SampleProjectResult readProjectSample(const QString &root, const QString &name,
                                          uint64_t requestId)
    {
        auto result = SampleProjectResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Project sample read did not run on the project thread.");
            return result;
        }
        result.probe = SampleRegistrar::probeSampleFormat(root);
        if (!result.probe.ok()) {
            result.error = result.probe.refusal;
            return result;
        }
        result.wavPath = QDir(result.probe.samplesDir).filePath(name + QStringLiteral(".wav"));
        QFile wav(result.wavPath);
        if (!wav.open(QIODevice::ReadOnly)) {
            result.error =
                QStringLiteral("%1.wav does not exist in sound/direct_sound_samples.").arg(name);
            return result;
        }
        result.wavBytes = wav.readAll();
        result.sidecarLoaded = SampleRegistrar::readSampleSidecar(root, name, &result.sidecar);
        if (result.wavBytes.isEmpty())
            result.error = QStringLiteral("Cannot read %1.").arg(result.wavPath);
        return result;
    }

    SampleCommitResult commitSample(SampleCommitRequest request, uint64_t requestId)
    {
        auto result = SampleCommitResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Sample commit did not run on the project thread.");
            return result;
        }
        if (request.update)
            result.committed = SampleRegistrar::updateSample(request.projectRoot, request.name,
                                                             request.wavBytes, &result.error);
        else
            result.committed = SampleRegistrar::registerSample(request.projectRoot, request.name,
                                                               request.wavBytes, &result.error);
        if (!result.committed)
            return result;
        if (request.sidecar) {
            QString sidecarError;
            result.sidecarSaved = SampleRegistrar::writeSampleSidecar(
                request.projectRoot, request.name, *request.sidecar, &sidecarError);
            result.sidecarError = std::move(sidecarError);
        } else if (request.removeSidecar) {
            SampleRegistrar::removeSampleSidecar(request.projectRoot, request.name);
            result.sidecarSaved = true;
        }
        return result;
    }

    CreateSongResult createSong(CreateSongRequest request, uint64_t requestId)
    {
        auto result = CreateSongResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Song creation did not run on the project thread.");
            return result;
        }
        const QString midiDir = request.projectRoot + QStringLiteral("/sound/songs/midi");
        const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(request.label);
        if (QFile::exists(midPath)) {
            result.error = QStringLiteral("MIDI file already exists: %1").arg(midPath);
            return result;
        }
        if (!request.newVoicegroup.isEmpty()) {
            result.voicegroupOk = VoicegroupSource::createVoicegroup(
                request.projectRoot, request.newVoicegroup, QString(), QString(), &result.error);
            if (result.voicegroupOk)
                result.voicegroupOk = VoicegroupSource::appendIncludeLine(
                    request.projectRoot, request.newVoicegroup, &result.error);
            if (!result.voicegroupOk)
                return result;
        }
        if (!request.smf.writeFile(midPath, &result.error))
            return result;
        result.midiOk = true;
        result.flagsOk = SongRegistry::writeSongFlags(
            midiDir, request.label, SongRegistry::mergeCfgFlags(request.cfg), &result.error);
        if (!result.flagsOk)
            return result;
        result.registered =
            SongRegistry::registerSong(request.projectRoot, request.label, request.constant,
                                       request.player, &result.error, &result.songId);
        if (!result.registered)
            SongRegistry::saveRegistrationMeta(request.projectRoot, request.label, request.constant,
                                               request.player);
        else
            SongRegistry::clearRegistrationMeta(request.projectRoot, request.label);
        return result;
    }

    CreateVoicegroupResult createVoicegroup(CreateVoicegroupRequest request, uint64_t requestId)
    {
        auto result = CreateVoicegroupResult{};
        result.requestId = requestId;
        if (QThread::currentThread() != thread()) {
            result.error = QStringLiteral("Voicegroup creation did not run on the project thread.");
            return result;
        }
        result.created = VoicegroupSource::createVoicegroup(
            request.projectRoot, request.name, request.copyFromFile, request.copySectionLabel,
            &result.error);
        if (result.created)
            result.created = VoicegroupSource::appendIncludeLine(request.projectRoot, request.name,
                                                                 &result.error);
        return result;
    }

  private:
    DecompProject m_project;
    std::optional<DecompProject> m_candidate;
    uint64_t m_candidateRequestId = 0;
};

ProjectIo::ProjectIo(QObject *parent) : QObject(parent), m_thread(new QThread(this))
{
    m_worker = new Worker;
    m_worker->moveToThread(m_thread);
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    m_thread->start();
}

ProjectIo::~ProjectIo()
{
    Q_ASSERT(QThread::currentThread() == thread());
    m_shuttingDown.store(true, std::memory_order_release);
    m_thread->quit();
    m_thread->wait();
    drainResults();
    m_active.reset();
    m_requests.clear();
}

uint64_t ProjectIo::openProject(QString root, OpenCompletion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    cancelOpenRequests();
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::OpenProject;
    request.root = std::move(root);
    request.openCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::loadSongFile(SongInfo song, std::function<void(SongFileResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::LoadSongFile;
    request.song = std::move(song);
    request.songCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::loadVoicegroup(QString root, SongCfg cfg,
                                   std::function<void(VoicegroupLoadResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::LoadVoicegroup;
    request.root = std::move(root);
    request.cfg = std::move(cfg);
    request.voicegroupCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::probeVoicegroup(QString root, SongCfg cfg,
                                    std::function<void(VoicegroupProbeResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::ProbeVoicegroup;
    request.root = std::move(root);
    request.cfg = std::move(cfg);
    request.voicegroupProbeCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::saveSong(SongSaveSnapshot snapshot, SaveCompletion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::SaveSong;
    request.saveSnapshot = std::move(snapshot);
    request.saveCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::saveVoicegroup(VoicegroupSaveRequest requestData,
                                   std::function<void(VoicegroupSaveResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::SaveVoicegroup;
    request.voicegroupSave = std::move(requestData);
    request.voicegroupSaveCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::readSidecar(SidecarLoadRequest requestData, SidecarLoadCompletion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::ReadSidecar;
    request.sidecarLoad = std::move(requestData);
    request.sidecarLoadCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::writeSidecar(SidecarSaveRequest requestData, SidecarSaveCompletion completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::WriteSidecar;
    request.sidecarSave = std::move(requestData);
    request.sidecarSaveCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::registrationPlan(RegistrationPlanRequest requestData,
                                     std::function<void(RegistrationPlanResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::RegistrationPlan;
    request.registrationPlan = std::move(requestData);
    request.registrationPlanCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::registerSong(RegisterSongRequest requestData,
                                 std::function<void(RegisterSongResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::RegisterSong;
    request.registerSong = std::move(requestData);
    request.registerSongCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::deletionPlan(DeletionPlanRequest requestData,
                                 std::function<void(DeletionPlanResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::DeletionPlan;
    request.deletionPlan = std::move(requestData);
    request.deletionPlanCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::deleteSong(DeleteSongRequest requestData,
                               std::function<void(DeleteSongResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::DeleteSong;
    request.deleteSong = std::move(requestData);
    request.deleteSongCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::previewPlan(PreviewPlanRequest requestData,
                                std::function<void(PreviewPlanResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::PreviewPlan;
    request.previewPlan = std::move(requestData);
    request.previewPlanCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::preview(PreviewRequest requestData,
                            std::function<void(PreviewResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::Preview;
    request.preview = std::move(requestData);
    request.previewCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::cleanupPreview(QString projectRoot,
                                   std::function<void(PreviewCleanupResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::CleanupPreview;
    request.root = std::move(projectRoot);
    request.previewCleanupCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::refreshVgCatalog(QString projectRoot,
                                     std::function<void(CatalogResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::RefreshVgCatalog;
    request.root = std::move(projectRoot);
    request.catalogCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::loadSampleSet(SampleSetRequest requestData,
                                  std::function<void(SampleSetResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::LoadSampleSet;
    request.sampleSet = std::move(requestData);
    request.sampleSetCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::probeSamples(QString projectRoot,
                                 std::function<void(SampleProbeResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::ProbeSamples;
    request.root = std::move(projectRoot);
    request.sampleProbeCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::readProjectSample(QString projectRoot, QString name,
                                      std::function<void(SampleProjectResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::ReadProjectSample;
    request.root = std::move(projectRoot);
    request.songLabel = std::move(name);
    request.sampleProjectCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::commitSample(SampleCommitRequest requestData,
                                 std::function<void(SampleCommitResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::CommitSample;
    request.sampleCommit = std::move(requestData);
    request.sampleCommitCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::createSong(CreateSongRequest requestData,
                               std::function<void(CreateSongResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::CreateSong;
    request.createSong = std::move(requestData);
    request.createSongCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

uint64_t ProjectIo::createVoicegroup(CreateVoicegroupRequest requestData,
                                     std::function<void(CreateVoicegroupResult)> completion)
{
    Q_ASSERT(QThread::currentThread() == thread());
    Q_ASSERT(m_thread->isRunning());
    Request request;
    request.id = ++m_nextRequestId;
    request.kind = RequestKind::CreateVoicegroup;
    request.createVoicegroup = std::move(requestData);
    request.createVoicegroupCompletion = std::move(completion);
    m_requests.push_back(std::move(request));
    dispatchNext();
    return m_nextRequestId;
}

void ProjectIo::cancel(uint64_t requestId)
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (m_shuttingDown.load(std::memory_order_acquire))
        return;
    if (m_active && m_active->id == requestId) {
        m_active->cancelled = true;
        clearCompletion(*m_active);
        return;
    }
    for (auto it = m_requests.begin(); it != m_requests.end(); ++it) {
        if (it->id != requestId)
            continue;
        clearCompletion(*it);
        m_requests.erase(it);
        return;
    }
}

void ProjectIo::dispatchNext()
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (m_shuttingDown.load(std::memory_order_acquire) || m_active)
        return;
    while (!m_requests.empty()) {
        auto request = std::move(m_requests.front());
        m_requests.pop_front();
        if (request.cancelled) {
            clearCompletion(request);
            continue;
        }
        m_active = std::move(request);
        break;
    }
    if (!m_active)
        return;
    const auto requestId = m_active->id;
    switch (m_active->kind) {
    case RequestKind::OpenProject: {
        auto root = std::move(m_active->root);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root)]() mutable {
                auto result = m_worker->prepareProject(root, requestId);
                postResult(WorkerResult{requestId, RequestKind::OpenProject, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::LoadSongFile: {
        auto song = std::move(m_active->song);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, song = std::move(song)]() mutable {
                auto result = m_worker->loadSongFile(std::move(song), requestId);
                postResult(WorkerResult{requestId, RequestKind::LoadSongFile, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::LoadVoicegroup: {
        auto root = std::move(m_active->root);
        auto cfg = std::move(m_active->cfg);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root), cfg = std::move(cfg)]() mutable {
                auto result = m_worker->loadVoicegroup(std::move(root), std::move(cfg), requestId);
                postResult(WorkerResult{requestId, RequestKind::LoadVoicegroup, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::ProbeVoicegroup: {
        auto root = std::move(m_active->root);
        auto cfg = std::move(m_active->cfg);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root), cfg = std::move(cfg)]() mutable {
                auto result = m_worker->probeVoicegroup(std::move(root), std::move(cfg), requestId);
                postResult(
                    WorkerResult{requestId, RequestKind::ProbeVoicegroup, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::SaveSong: {
        auto snapshot = std::move(m_active->saveSnapshot);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, snapshot = std::move(snapshot)]() mutable {
                auto result = m_worker->saveSong(std::move(snapshot), requestId);
                postResult(WorkerResult{requestId, RequestKind::SaveSong, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::SaveVoicegroup: {
        auto request = std::move(m_active->voicegroupSave);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->saveVoicegroup(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::SaveVoicegroup, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::ReadSidecar: {
        auto request = std::move(m_active->sidecarLoad);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->readSidecar(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::ReadSidecar, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::WriteSidecar: {
        auto request = std::move(m_active->sidecarSave);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->writeSidecar(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::WriteSidecar, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::RegistrationPlan: {
        auto request = std::move(m_active->registrationPlan);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->registrationPlan(std::move(request), requestId);
                postResult(
                    WorkerResult{requestId, RequestKind::RegistrationPlan, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::RegisterSong: {
        auto request = std::move(m_active->registerSong);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->registerSong(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::RegisterSong, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::DeletionPlan: {
        auto request = std::move(m_active->deletionPlan);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->deletionPlan(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::DeletionPlan, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::DeleteSong: {
        auto request = std::move(m_active->deleteSong);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->deleteSong(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::DeleteSong, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::PreviewPlan: {
        auto request = std::move(m_active->previewPlan);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->previewPlan(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::PreviewPlan, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::Preview: {
        auto request = std::move(m_active->preview);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->preview(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::Preview, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::CleanupPreview: {
        auto root = std::move(m_active->root);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root)]() mutable {
                auto result = m_worker->cleanupPreview(root, requestId);
                postResult(WorkerResult{requestId, RequestKind::CleanupPreview, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::RefreshVgCatalog: {
        auto root = std::move(m_active->root);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root)]() mutable {
                auto result = m_worker->refreshVgCatalog(root, requestId);
                postResult(
                    WorkerResult{requestId, RequestKind::RefreshVgCatalog, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::LoadSampleSet: {
        auto request = std::move(m_active->sampleSet);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->loadSampleSet(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::LoadSampleSet, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::ProbeSamples: {
        auto root = std::move(m_active->root);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root)]() mutable {
                auto result = m_worker->probeSamples(root, requestId);
                postResult(WorkerResult{requestId, RequestKind::ProbeSamples, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::ReadProjectSample: {
        auto root = std::move(m_active->root);
        auto name = std::move(m_active->songLabel);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, root = std::move(root), name = std::move(name)]() mutable {
                auto result = m_worker->readProjectSample(root, name, requestId);
                postResult(
                    WorkerResult{requestId, RequestKind::ReadProjectSample, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::CommitSample: {
        auto request = std::move(m_active->sampleCommit);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->commitSample(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::CommitSample, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::CreateSong: {
        auto request = std::move(m_active->createSong);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->createSong(std::move(request), requestId);
                postResult(WorkerResult{requestId, RequestKind::CreateSong, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    case RequestKind::CreateVoicegroup: {
        auto request = std::move(m_active->createVoicegroup);
        const auto invoked = QMetaObject::invokeMethod(
            m_worker,
            [this, requestId, request = std::move(request)]() mutable {
                auto result = m_worker->createVoicegroup(std::move(request), requestId);
                postResult(
                    WorkerResult{requestId, RequestKind::CreateVoicegroup, std::move(result)});
            },
            Qt::QueuedConnection);
        Q_ASSERT(invoked);
        break;
    }
    }
}

void ProjectIo::postResult(WorkerResult result)
{
    {
        const auto lock = std::lock_guard{m_resultMutex};
        m_results.push_back(std::move(result));
    }
    if (m_shuttingDown.load(std::memory_order_acquire))
        return;
    QMetaObject::invokeMethod(this, [this] { drainResults(); }, Qt::QueuedConnection);
}

void ProjectIo::drainResults()
{
    Q_ASSERT(QThread::currentThread() == thread());
    for (;;) {
        auto result = WorkerResult{};
        {
            const auto lock = std::lock_guard{m_resultMutex};
            if (m_results.empty())
                break;
            result = std::move(m_results.front());
            m_results.pop_front();
        }
        if (m_shuttingDown.load(std::memory_order_acquire))
            discardResult(result);
        else
            finishResult(std::move(result));
    }
}

void ProjectIo::finishResult(WorkerResult result)
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (!m_active || m_active->id != result.requestId) {
        discardResult(result);
        if (!m_active)
            dispatchNext();
        return;
    }
    auto request = std::move(*m_active);
    m_active.reset();
    if (request.cancelled || m_shuttingDown.load(std::memory_order_acquire)) {
        discardResult(result);
        dispatchNext();
        return;
    }
    switch (request.kind) {
    case RequestKind::OpenProject: {
        auto openResult = std::move(std::get<ProjectOpenResult>(result.payload));
        if (openResult.succeeded()) {
            auto committed = false;
            const auto invoked = QMetaObject::invokeMethod(
                m_worker,
                [this, requestId = request.id, &committed] {
                    committed = m_worker->commitProject(requestId);
                },
                Qt::BlockingQueuedConnection);
            if (!invoked || !committed)
                openResult = {{}, QStringLiteral("Project open result became stale.")};
        }
        auto completion = std::move(request.openCompletion);
        if (completion)
            completion(std::move(openResult));
        break;
    }
    case RequestKind::LoadSongFile: {
        auto payload = std::move(std::get<SongFileResult>(result.payload));
        auto completion = std::move(request.songCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::LoadVoicegroup: {
        auto payload = std::move(std::get<VoicegroupLoadResult>(result.payload));
        auto completion = std::move(request.voicegroupCompletion);
        if (completion)
            completion(std::move(payload));
        else if (payload.voicegroup) {
            voicegroup_free(payload.voicegroup);
            payload.voicegroup = nullptr;
        }
        break;
    }
    case RequestKind::ProbeVoicegroup: {
        auto payload = std::move(std::get<VoicegroupProbeResult>(result.payload));
        auto completion = std::move(request.voicegroupProbeCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::SaveSong: {
        auto payload = std::move(std::get<SaveSongResult>(result.payload));
        auto completion = std::move(request.saveCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::SaveVoicegroup: {
        auto payload = std::move(std::get<VoicegroupSaveResult>(result.payload));
        auto completion = std::move(request.voicegroupSaveCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::ReadSidecar: {
        auto payload = std::move(std::get<SidecarLoadResult>(result.payload));
        auto completion = std::move(request.sidecarLoadCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::WriteSidecar: {
        auto payload = std::move(std::get<SidecarSaveResult>(result.payload));
        auto completion = std::move(request.sidecarSaveCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::RegistrationPlan: {
        auto payload = std::move(std::get<RegistrationPlanResult>(result.payload));
        auto completion = std::move(request.registrationPlanCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::RegisterSong: {
        auto payload = std::move(std::get<RegisterSongResult>(result.payload));
        auto completion = std::move(request.registerSongCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::DeletionPlan: {
        auto payload = std::move(std::get<DeletionPlanResult>(result.payload));
        auto completion = std::move(request.deletionPlanCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::DeleteSong: {
        auto payload = std::move(std::get<DeleteSongResult>(result.payload));
        auto completion = std::move(request.deleteSongCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::PreviewPlan: {
        auto payload = std::move(std::get<PreviewPlanResult>(result.payload));
        auto completion = std::move(request.previewPlanCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::Preview: {
        auto payload = std::move(std::get<PreviewResult>(result.payload));
        auto completion = std::move(request.previewCompletion);
        if (completion)
            completion(std::move(payload));
        else if (payload.voicegroup) {
            voicegroup_free(payload.voicegroup);
            payload.voicegroup = nullptr;
        }
        break;
    }
    case RequestKind::CleanupPreview: {
        auto payload = std::move(std::get<PreviewCleanupResult>(result.payload));
        auto completion = std::move(request.previewCleanupCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::RefreshVgCatalog: {
        auto payload = std::move(std::get<CatalogResult>(result.payload));
        auto completion = std::move(request.catalogCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::LoadSampleSet: {
        auto payload = std::move(std::get<SampleSetResult>(result.payload));
        auto completion = std::move(request.sampleSetCompletion);
        if (completion)
            completion(std::move(payload));
        else if (payload.sampleSet) {
            voicegroup_free_samples(payload.sampleSet);
            payload.sampleSet = nullptr;
        }
        break;
    }
    case RequestKind::ProbeSamples: {
        auto payload = std::move(std::get<SampleProbeResult>(result.payload));
        auto completion = std::move(request.sampleProbeCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::ReadProjectSample: {
        auto payload = std::move(std::get<SampleProjectResult>(result.payload));
        auto completion = std::move(request.sampleProjectCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::CommitSample: {
        auto payload = std::move(std::get<SampleCommitResult>(result.payload));
        auto completion = std::move(request.sampleCommitCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::CreateSong: {
        auto payload = std::move(std::get<CreateSongResult>(result.payload));
        auto completion = std::move(request.createSongCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    case RequestKind::CreateVoicegroup: {
        auto payload = std::move(std::get<CreateVoicegroupResult>(result.payload));
        auto completion = std::move(request.createVoicegroupCompletion);
        if (completion)
            completion(std::move(payload));
        break;
    }
    }
    dispatchNext();
}

void ProjectIo::discardResult(WorkerResult &result)
{
    if (result.kind == RequestKind::LoadVoicegroup) {
        auto *payload = std::get_if<VoicegroupLoadResult>(&result.payload);
        if (payload && payload->voicegroup) {
            voicegroup_free(payload->voicegroup);
            payload->voicegroup = nullptr;
        }
    } else if (result.kind == RequestKind::Preview) {
        auto *payload = std::get_if<PreviewResult>(&result.payload);
        if (payload && payload->voicegroup) {
            voicegroup_free(payload->voicegroup);
            payload->voicegroup = nullptr;
        }
    } else if (result.kind == RequestKind::LoadSampleSet) {
        auto *payload = std::get_if<SampleSetResult>(&result.payload);
        if (payload && payload->sampleSet) {
            voicegroup_free_samples(payload->sampleSet);
            payload->sampleSet = nullptr;
        }
    }
}

void ProjectIo::clearCompletion(Request &request)
{
    request.openCompletion = {};
    request.songCompletion = {};
    request.voicegroupCompletion = {};
    request.voicegroupProbeCompletion = {};
    request.saveCompletion = {};
    request.voicegroupSaveCompletion = {};
    request.sidecarLoadCompletion = {};
    request.sidecarSaveCompletion = {};
    request.registrationPlanCompletion = {};
    request.registerSongCompletion = {};
    request.deletionPlanCompletion = {};
    request.deleteSongCompletion = {};
    request.previewPlanCompletion = {};
    request.previewCompletion = {};
    request.previewCleanupCompletion = {};
    request.catalogCompletion = {};
    request.sampleSetCompletion = {};
    request.sampleProbeCompletion = {};
    request.sampleProjectCompletion = {};
    request.sampleCommitCompletion = {};
    request.createSongCompletion = {};
    request.createVoicegroupCompletion = {};
}

void ProjectIo::cancelOpenRequests()
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (m_active && m_active->kind == RequestKind::OpenProject) {
        m_active->cancelled = true;
        clearCompletion(*m_active);
    }
    for (auto it = m_requests.begin(); it != m_requests.end();) {
        if (it->kind != RequestKind::OpenProject) {
            ++it;
            continue;
        }
        clearCompletion(*it);
        it = m_requests.erase(it);
    }
}
