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

#include "sidecar.h"
#include "songregistry.h"

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

// The loader name voicegroup_load() resolves a preview identity as: the
// section label for a monolithic voicegroup, otherwise the per-file base
// name.
QString previewLoadName(const VoicegroupId &id)
{
    return id.sectionLabel().isEmpty() ? QFileInfo(id.sourceRelativePath()).completeBaseName()
                                       : id.sectionLabel();
}

bool isSongCommand(const ProjectCommand &command)
{
    return std::holds_alternative<OpenSongInput>(command) ||
           std::holds_alternative<ReloadSongInput>(command) ||
           std::holds_alternative<LoadSongCommand>(command) ||
           std::holds_alternative<LoadVoicegroupCommand>(command) ||
           std::holds_alternative<SaveSongInput>(command);
}
// One overload per ProjectCommand alternative and no generic fallback in
// the open-project dispatch, so an unhandled alternative fails it to
// compile. The closed-state dispatch adds a generic fallback: while
// closed, every non-song command fails the same way.
template <typename... Ts>
struct CommandVisitor : Ts... {
    using Ts::operator()...;
};
template <typename... Ts>
CommandVisitor(Ts...) -> CommandVisitor<Ts...>;

} // namespace

class ProjectIo::Worker final : public QObject
{
  public:
    explicit Worker(std::atomic_bool &catalogCancellation)
        : m_catalogCancellation(catalogCancellation)
    {}

    using StageSink = std::function<void(ProjectResult)>;
    // One terminal ProjectResult per command. The command travels by
    // reference so the caller keeps ownership: the handlers move only the
    // pieces they consume, leaving the keyed fields (song, voicegroup,
    // label, name) intact for the owner's terminal delivery. Staged values
    // (song-load stages, the semantic save's early bank view, and successful
    // song-mutation events before their refreshed snapshot) go through the sink.
    ProjectResult execute(ProjectCommand &command, const StageSink &stage)
    {
        Q_ASSERT(QThread::currentThread() == thread());
        // Only opening a project makes progress while closed; everything
        // else fails against the closed state.
        if (!requireOpen())
            return closedCommand(command);
        return std::visit(
            CommandVisitor{
                [this](OpenProjectInput &input) { return acceptProject(input.root); },
                [this](RefreshProjectInput &) { return acceptProject(m_project.root()); },
                [this, &stage](OpenSongInput &input) { return loadSong(input.song, stage); },
                [this, &stage](ReloadSongInput &input) {
                    return input.voicegroupArg
                               ? rebindVoicegroup(input.song, *input.voicegroupArg, stage)
                               : loadSong(input.song, stage);
                },
                [this, &stage](LoadSongCommand &input) { return loadSong(input.song, stage); },
                [this, &stage](LoadVoicegroupCommand &input) {
                    return loadVoicegroup(input.song, input.voicegroup, stage);
                },
                [this, &stage](SaveSongInput &input) { return saveSong(std::move(input), stage); },
                [this](VoicegroupEditInput &input) {
                    return applyVoicegroupEdit(std::move(input));
                },
                [this, &stage](CreateSongInput &input) {
                    return createSong(std::move(input), stage);
                },
                [this](CreateVoicegroupInput &input) { return createVoicegroup(std::move(input)); },
                [this](const RegistrationPlanInput &input) { return registrationPlan(input); },
                [this, &stage](const RegisterSongInput &input) {
                    return registerSong(input, stage);
                },
                [this](const DeletionPlanInput &input) { return deletionPlan(input); },
                [this](DeleteSongInput &input) { return deleteSong(std::move(input)); },
                [this](const PreviewPlanInput &input) { return previewPlan(input); },
                [this](PreviewInput &input) { return preview(std::move(input)); },
                [this](const CleanupPreviewInput &) { return cleanupPreview(); },
                [this](const RefreshCatalogInput &) { return refreshCatalog(); },
                [this](LoadSampleSetInput &input) { return loadSampleSet(std::move(input)); },
                [this](const ProbeSamplesInput &) { return probeSamples(); },
                [this](const ReadSampleInput &input) { return readSample(input); },
                [this](CommitSampleInput &input) { return commitSample(std::move(input)); },
            },
            command);
    }

  private:
    // The closed-state counterpart of execute(): only opening a project
    // makes progress; song commands fail keyed to their song, every other
    // command fails generically.
    ProjectResult closedCommand(ProjectCommand &command)
    {
        return std::visit(
            CommandVisitor{
                [this](OpenProjectInput &input) { return acceptProject(input.root); },
                [this](OpenSongInput &input) { return closedSong(input.song); },
                [this](ReloadSongInput &input) { return closedSong(input.song); },
                [this](LoadSongCommand &input) { return closedSong(input.song); },
                [this](LoadVoicegroupCommand &input) { return closedSong(input.song); },
                [this](SaveSongInput &input) { return closedSong(input.song); },
                [this](auto &) { return closedProject(); },
            },
            command);
    }

    // ---- project open / refresh --------------------------------------------

    // Opens the project, and on success installs it as the one canonical
    // worker state before publishing the detached snapshot. A failed open
    // leaves the previous project untouched.
    ProjectResult acceptProject(const QString &root)
    {
        auto candidate = DecompProject{};
        auto error = QString{};
        if (!candidate.open(root, &error))
            return CommandFailure{error.isEmpty() ? QStringLiteral("Could not open the project.")
                                                  : std::move(error)};
        auto trackBudgets = QHash<QString, int>{};
        trackBudgets.reserve(candidate.songs().size());
        for (const auto &song : candidate.songs())
            trackBudgets.insert(song.label, candidate.trackBudgetFor(song));
        auto snapshot = ProjectSnapshot{candidate.root(), candidate.songs(), candidate.players(),
                                        std::move(trackBudgets)};
        m_project = std::move(candidate);
        return ProjectResult{std::move(snapshot)};
    }

    // ---- ordered song load ---------------------------------------------------

    // The load stages run in a fixed order: MIDI, then the bank view, then
    // the terminal bound update. The first fatal failure stops the later
    // stages; there is no transaction or rollback.
    ProjectResult loadSong(const SongName &song, const StageSink &stage)
    {
        const auto resolved = m_project.playableSong(song);
        if (!resolved)
            return SongCommandFailure{
                song, SongStage::Reconcile,
                QStringLiteral("Song %1 is not a playable song in this project.")
                    .arg(song.value())};
        auto smf = SmfFile{};
        auto error = QString{};
        if (!SmfFile::readFile(resolved->midPath, &smf, &error))
            return SongCommandFailure{
                song, SongStage::Midi,
                error.isEmpty() ? QStringLiteral("Could not read %1.").arg(resolved->midPath)
                                : std::move(error)};
        stage(MidiStage{song, *resolved, std::move(smf), m_project.trackBudgetFor(*resolved)});
        auto view = m_project.loadBank(*resolved, &error);
        if (!view)
            return SongCommandFailure{
                song, SongStage::Voicegroup,
                error.isEmpty()
                    ? QStringLiteral("Could not load the voicegroup of %1.").arg(song.value())
                    : std::move(error)};
        auto id = view->id;
        stage(std::move(*view));
        return VoicegroupBound{song, std::move(id)};
    }

    ProjectResult publishVoicegroup(const SongName &song, const SongInfo &resolved,
                                    const VoicegroupId *expected, const StageSink &stage)
    {
        auto error = QString{};
        auto view = m_project.loadBank(resolved, &error);
        if (!view)
            return SongCommandFailure{
                song, SongStage::Voicegroup,
                error.isEmpty()
                    ? QStringLiteral("Could not load the voicegroup of %1.").arg(song.value())
                    : std::move(error)};
        if (expected && !(view->id == *expected))
            return SongCommandFailure{song, SongStage::Voicegroup,
                                      QStringLiteral("Song %1 resolved voicegroup %2, not %3.")
                                          .arg(song.value(), view->id.sourceRelativePath(),
                                               expected->sourceRelativePath())};
        auto id = view->id;
        stage(std::move(*view));
        return VoicegroupBound{song, std::move(id)};
    }

    ProjectResult loadVoicegroup(const SongName &song, const VoicegroupId &voicegroup,
                                 const StageSink &stage)
    {
        const auto resolved = m_project.playableSong(song);
        if (!resolved)
            return SongCommandFailure{
                song, SongStage::Reconcile,
                QStringLiteral("Song %1 is not a playable song in this project.")
                    .arg(song.value())};
        return publishVoicegroup(song, *resolved, &voicegroup, stage);
    }

    ProjectResult rebindVoicegroup(const SongName &song, const QString &voicegroupArg,
                                   const StageSink &stage)
    {
        auto resolved = m_project.playableSong(song);
        if (!resolved)
            return SongCommandFailure{
                song, SongStage::Reconcile,
                QStringLiteral("Song %1 is not a playable song in this project.")
                    .arg(song.value())};
        resolved->cfg.voicegroupArg = voicegroupArg;
        return publishVoicegroup(song, *resolved, nullptr, stage);
    }

    // ---- semantic save --------------------------------------------------------

    // SaveSongInput owns the semantic save ordering: the optional voicegroup
    // source/synth writes plus the bank refresh first (delivering the
    // resulting LoadedBankView while the command is still active), then MIDI,
    // then flags. A fatal voicegroup, refresh, MIDI, or flags failure stops
    // the later stages while earlier writes remain.
    ProjectResult saveSong(SaveSongInput &&input, const StageSink &stage)
    {
        if (input.voicegroup) {
            auto error = QString{};
            auto view = m_project.saveVoicegroup(*input.voicegroup, &error);
            if (!view)
                return SongCommandFailure{
                    input.song, SongStage::Save,
                    error.isEmpty() ? QStringLiteral("Could not save the voicegroup of %1.")
                                          .arg(input.song.value())
                                    : std::move(error)};
            stage(std::move(*view));
        }
        auto error = QString{};
        if (!input.snapshot.smf.writeFile(input.snapshot.midPath, &error))
            return SongCommandFailure{
                input.song, SongStage::Save,
                error.isEmpty() ? QStringLiteral("Could not write %1.").arg(input.snapshot.midPath)
                                : std::move(error)};
        auto flagsWritten = false;
        if (input.snapshot.flagsNeeded) {
            const auto flags = SongRegistry::mergeCfgFlags(input.snapshot.cfg);
            if (!SongRegistry::writeSongFlags(QFileInfo(input.snapshot.midPath).path(),
                                              input.snapshot.label, flags, &error))
                return SongCommandFailure{
                    input.song, SongStage::Save,
                    error.isEmpty()
                        ? QStringLiteral("Could not write the flags of %1.").arg(input.song.value())
                        : std::move(error)};
            flagsWritten = true;
        }
        return SongSaved{input.song, std::move(input.snapshot), flagsWritten};
    }

    // ---- voicegroup edit --------------------------------------------------------

    // Dispatches directly to the canonical bank record: a present result is
    // the applied outcome (with the complete candidate already installed) or
    // the confirmed conflict for an expected mismatch or validation no-op; a
    // hard error is std::nullopt, mapped here to CommandFailure.
    ProjectResult applyVoicegroupEdit(VoicegroupEditInput &&input)
    {
        auto error = QString{};
        auto result = m_project.applyVoicegroupEdit(
            // The identity is copied so the moved-out operation still leaves
            // the delivered terminal command keyed for the owner.
            VoicegroupEditInput{input.id, std::move(input.operation)}, &error);
        if (result)
            return ProjectResult{std::move(*result)};
        return CommandFailure{error.isEmpty() ? QStringLiteral("The voicegroup edit failed.")
                                              : std::move(error)};
    }

    // ---- song creation / registration / deletion -------------------------------

    // Writes the new song's files in a fixed order: the optional voicegroup
    // source, the MIDI file, then the song flags. The first failure stops
    // the sequence and leaves the earlier writes in place. Returns the
    // failure, or nullopt when the song files are complete.
    static std::optional<ProjectResult> writeNewSongFiles(const QString &root,
                                                          const CreateSongInput &input)
    {
        const auto midiDir = root + QStringLiteral("/sound/songs/midi");
        const auto midPath = midiDir + QStringLiteral("/%1.mid").arg(input.label);
        if (QFile::exists(midPath))
            return CommandFailure{QStringLiteral("MIDI file already exists: %1").arg(midPath)};
        auto error = QString{};
        if (!input.newVoicegroup.isEmpty() &&
            !(VoicegroupSource::createVoicegroup(root, input.newVoicegroup, QString(), QString(),
                                                 &error) &&
              VoicegroupSource::appendIncludeLine(root, input.newVoicegroup, &error)))
            return CommandFailure{
                error.isEmpty() ? QStringLiteral("Could not create %1.").arg(input.newVoicegroup)
                                : std::move(error)};
        if (!input.smf.writeFile(midPath, &error))
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not write %1.").arg(midPath)
                                      : std::move(error)};
        if (!SongRegistry::writeSongFlags(midiDir, input.label,
                                          SongRegistry::mergeCfgFlags(input.cfg), &error))
            return CommandFailure{
                error.isEmpty()
                    ? QStringLiteral("Could not write the flags of %1.").arg(input.label)
                    : std::move(error)};
        return std::nullopt;
    }

    ProjectResult createSong(CreateSongInput &&input, const StageSink &stage)
    {
        const auto root = m_project.root();
        if (auto failure = writeNewSongFiles(root, input))
            return std::move(*failure);
        // SongRegistry::registerSong rederives its plan internally immediately
        // before applying the registration writes; the GUI plan is only for
        // the confirmation dialog and is never trusted as a commit.
        auto error = QString{};
        auto songId = -1;
        const auto registered = SongRegistry::registerSong(root, input.label, input.constant,
                                                           input.player, &error, &songId);
        if (registered)
            SongRegistry::clearRegistrationMeta(root, input.label);
        else
            SongRegistry::saveRegistrationMeta(root, input.label, input.constant, input.player);
        if (!registered)
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not register %1.").arg(input.label)
                                      : std::move(error)};
        auto song = SongName::create(input.label);
        if (!song)
            return CommandFailure{
                QStringLiteral("Song label %1 is not a valid identity.").arg(input.label)};
        auto refreshed = acceptProject(root);
        if (!std::holds_alternative<ProjectSnapshot>(refreshed))
            return refreshed;
        std::optional<VoicegroupCatalog> catalog;
        if (!input.newVoicegroup.isEmpty()) {
            auto scanned = refreshCatalog();
            if (!std::holds_alternative<VoicegroupCatalog>(scanned))
                return scanned;
            catalog = std::move(std::get<VoicegroupCatalog>(scanned));
        }
        stage(ProjectResult{SongCreated{std::move(*song), true, true, true, registered, songId}});
        if (catalog)
            stage(ProjectResult{std::move(*catalog)});
        return refreshed;
    }

    // Creates the voicegroup files, then returns the freshly scanned catalog
    // the browser needs after any voicegroup file change.
    ProjectResult createVoicegroup(CreateVoicegroupInput input)
    {
        const auto root = m_project.root();
        auto error = QString{};
        const auto created =
            VoicegroupSource::createVoicegroup(root, input.name, input.copyFromFile,
                                               input.copySectionLabel, &error) &&
            VoicegroupSource::appendIncludeLine(root, input.name, &error);
        if (!created)
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not create %1.").arg(input.name)
                                      : std::move(error)};
        if (!m_project.rebuildVoicegroupProject(&error))
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not refresh the voicegroup layout.")
                                      : std::move(error)};
        return refreshCatalog();
    }

    ProjectResult registrationPlan(const RegistrationPlanInput &input)
    {
        auto song = SongName::create(input.label);
        if (!song)
            return CommandFailure{
                QStringLiteral("Song label %1 is not a valid identity.").arg(input.label)};
        const auto root = m_project.root();
        return RegistrationPlanResult{
            std::move(*song),
            SongRegistry::makePlan(root, input.label, input.constant, input.player),
            SongRegistry::checkRegistration(root, input.label, input.constant)};
    }

    ProjectResult registerSong(const RegisterSongInput &input, const StageSink &stage)
    {
        const auto root = m_project.root();
        auto error = QString{};
        auto songId = -1;
        // registerSong rederives its plan internally before the writes; the
        // GUI plan is only for the confirmation dialog and is never trusted
        // as a commit.
        const auto registered = SongRegistry::registerSong(root, input.label, input.constant,
                                                           input.player, &error, &songId);
        if (!registered)
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not register %1.").arg(input.label)
                                      : std::move(error)};
        SongRegistry::clearRegistrationMeta(root, input.label);
        auto song = SongName::create(input.label);
        if (!song)
            return CommandFailure{
                QStringLiteral("Song label %1 is not a valid identity.").arg(input.label)};
        auto refreshed = acceptProject(root);
        if (!std::holds_alternative<ProjectSnapshot>(refreshed))
            return refreshed;
        stage(ProjectResult{SongCreated{std::move(*song), true, true, true, registered, songId}});
        return refreshed;
    }

    ProjectResult deletionPlan(const DeletionPlanInput &input)
    {
        const auto root = m_project.root();
        return DeletionPlanResult{
            input.song, SongRegistry::makeRemovalPlan(root, input.song.value(), input.constant),
            SongRegistry::deletableVoicegroup(root, m_project.songs(), input.song.value())};
    }

    // Moves the song's files aside, unregisters it, and returns the fresh
    // snapshot the GUI republishes after the song table changed. Reported
    // problems join into one failure message; earlier writes remain.
    ProjectResult deleteSong(DeleteSongInput &&input)
    {
        const auto root = m_project.root();
        auto project = DecompProject{};
        auto error = QString{};
        if (!project.open(root, &error))
            return CommandFailure{error.isEmpty() ? QStringLiteral("Could not re-read the project.")
                                                  : std::move(error)};
        const auto plan = SongRegistry::makeRemovalPlan(root, input.song.value(), input.constant);
        if (plan.tableIndex == 0)
            return CommandFailure{
                QStringLiteral("%1 is the engine's fallback song (song ID 0) and cannot "
                               "be deleted.")
                    .arg(input.song.value())};
        QStringList problems;
        QString problem;
        auto deleteVoicegroupName = input.deleteVoicegroupName;
        if (!deleteVoicegroupName.isEmpty() &&
            SongRegistry::deletableVoicegroup(root, project.songs(), input.song.value()) !=
                deleteVoicegroupName) {
            problems << QStringLiteral("Voicegroup %1 is no longer unused; it was kept.")
                            .arg(deleteVoicegroupName);
            deleteVoicegroupName.clear();
        }
        const QString midiDir = root + QStringLiteral("/sound/songs/midi");
        const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(input.song.value());
        if (QFile::exists(midPath)) {
            if (!Sidecar::ensureDir(root, QStringLiteral("trash")))
                problems << QStringLiteral("Could not create .porydaw/trash.");
            QString target =
                root + QStringLiteral("/.porydaw/trash/%1.mid").arg(input.song.value());
            for (int n = 2; QFile::exists(target); n++)
                target = root +
                         QStringLiteral("/.porydaw/trash/%1-%2.mid").arg(input.song.value()).arg(n);
            if (!QFile::rename(midPath, target))
                problems << QStringLiteral("Could not move %1 to %2").arg(midPath, target);
        }
        QFile::remove(midiDir + QStringLiteral("/%1.s").arg(input.song.value()));
        if (!SongRegistry::removeSongFlags(midiDir, input.song.value(), &problem))
            problems << problem;
        if (!SongRegistry::unregisterSong(root, input.song.value(), input.constant, &problem))
            problems << problem;
        SongRegistry::removeSongSidecar(root, input.song.value());
        if (!deleteVoicegroupName.isEmpty() &&
            !VoicegroupSource::deleteVoicegroup(root, deleteVoicegroupName, &problem))
            problems << problem;
        if (!problems.isEmpty())
            return CommandFailure{problems.join(QLatin1Char('\n'))};
        return acceptProject(root);
    }

    // ---- voicegroup preview -------------------------------------------------------

    ProjectResult previewPlan(const PreviewPlanInput &input)
    {
        const auto previewDir = previewDirFor(m_project.root());
        return PreviewPlan{
            input.voicegroup, previewDir,
            QDir(previewDir).filePath(previewLoadName(input.voicegroup) + QStringLiteral(".inc"))};
    }

    // Loads the edited bytes as a shadow .inc under .porydaw/vgpreview, then
    // removes the directory either way; the loaded bank travels as a lease.
    ProjectResult preview(PreviewInput &&input)
    {
        const auto previewDir = previewDirFor(m_project.root());
        const auto loadName = previewLoadName(input.voicegroup);
        QDir(previewDir).removeRecursively();
        if (!QDir().mkpath(previewDir))
            return CommandFailure{QStringLiteral("Cannot create voicegroup preview directory.")};
        const auto path = QDir(previewDir).filePath(loadName + QStringLiteral(".inc"));
        auto error = QString{};
        if (!writeBytes(path, input.sourceBytes, &error)) {
            QDir(previewDir).removeRecursively();
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not write the preview source.")
                                      : std::move(error)};
        }
        VoicegroupLoaderConfig config;
        std::memset(&config, 0, sizeof(config));
        std::strncpy(config.voicegroupPaths[0], ".porydaw/vgpreview", VG_MAX_PATH_LEN - 1);
        config.voicegroupPathCount = 1;
        const auto rootUtf8 = m_project.root().toLocal8Bit();
        const auto loadNameUtf8 = loadName.toLocal8Bit();
        auto *bank = voicegroup_load(rootUtf8.constData(), loadNameUtf8.constData(), &config);
        QDir(previewDir).removeRecursively();
        if (!bank)
            return CommandFailure{QStringLiteral("Edited voicegroup failed to load.")};
        return PreviewReady{input.voicegroup, wrapVoicegroupLease(bank)};
    }

    // Best-effort cosmetic cleanup; a missing directory is still a success.
    ProjectResult cleanupPreview()
    {
        QDir(previewDirFor(m_project.root())).removeRecursively();
        return PreviewCleanupCompleted{};
    }

    // ---- catalog and samples --------------------------------------------------------

    ProjectResult refreshCatalog()
    {
        auto error = QString{};
        auto catalog = scanCatalog(m_project.root(), &error);
        if (m_catalogCancellation.load(std::memory_order_acquire))
            return CatalogScanCancelled{};
        if (!catalog)
            return CommandFailure{std::move(error)};
        return ProjectResult{std::move(*catalog)};
    }

    ProjectResult loadSampleSet(LoadSampleSetInput input)
    {
        // The C loader reads these pointers during the call; reserve every
        // QByteArray slot before taking addresses so the container cannot
        // relocate them while the symbol vectors are assembled.
        QList<QByteArray> storage;
        storage.reserve(input.samples.size() + input.waves.size() + input.keysplits.size() * 2);
        const auto utf8 = [&storage](const QString &value) {
            storage.append(value.toUtf8());
            return storage.last().constData();
        };
        std::vector<const char *> samples;
        std::vector<const char *> waves;
        std::vector<const char *> keysplits;
        std::vector<const char *> tables;
        samples.reserve(input.samples.size());
        waves.reserve(input.waves.size());
        keysplits.reserve(input.keysplits.size());
        tables.reserve(input.keysplits.size());
        for (const auto &value : input.samples)
            samples.push_back(utf8(value));
        for (const auto &value : input.waves)
            waves.push_back(utf8(value));
        for (const auto &pair : input.keysplits) {
            keysplits.push_back(utf8(pair.first));
            tables.push_back(utf8(pair.second));
        }
        auto *set = m_project.loadSampleSet(samples.data(), int(samples.size()), waves.data(),
                                            int(waves.size()), keysplits.data(), tables.data(),
                                            int(keysplits.size()));
        if (!set)
            return CommandFailure{QStringLiteral("Could not load project samples.")};
        return SampleSetReady{SampleSetLease(set, &voicegroup_free_samples)};
    }

    ProjectResult probeSamples()
    {
        return SamplesProbed{SampleRegistrar::probeSampleFormat(m_project.root())};
    }

    ProjectResult readSample(const ReadSampleInput &input)
    {
        const auto probe = SampleRegistrar::probeSampleFormat(m_project.root());
        if (!probe.ok())
            return CommandFailure{probe.refusal};
        const auto wavPath = QDir(probe.samplesDir).filePath(input.name + QStringLiteral(".wav"));
        QFile wav(wavPath);
        if (!wav.open(QIODevice::ReadOnly))
            return CommandFailure{
                QStringLiteral("%1.wav does not exist in sound/direct_sound_samples.")
                    .arg(input.name)};
        auto wavBytes = wav.readAll();
        if (wavBytes.isEmpty())
            return CommandFailure{QStringLiteral("Cannot read %1.").arg(wavPath)};
        auto sidecar = SampleSidecar{};
        const auto sidecarLoaded =
            SampleRegistrar::readSampleSidecar(m_project.root(), input.name, &sidecar);
        return SampleRead{input.name,          probe,  sidecarLoaded, std::move(sidecar),
                          std::move(wavBytes), wavPath};
    }

    // The sample registration itself is fatal on failure; the sidecar write
    // afterwards is cosmetic and reported by SampleCommitted.
    ProjectResult commitSample(CommitSampleInput &&input)
    {
        const auto root = m_project.root();
        auto error = QString{};
        const auto committed =
            input.update
                ? SampleRegistrar::updateSample(root, input.name, input.wavBytes, &error)
                : SampleRegistrar::registerSample(root, input.name, input.wavBytes, &error);
        if (!committed)
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not commit %1.").arg(input.name)
                                      : std::move(error)};
        if (!m_project.rebuildVoicegroupProject(&error))
            return CommandFailure{error.isEmpty()
                                      ? QStringLiteral("Could not refresh the project sample maps.")
                                      : std::move(error)};
        auto sidecarSaved = false;
        auto sidecarError = QString{};
        if (input.sidecar) {
            sidecarSaved = SampleRegistrar::writeSampleSidecar(root, input.name, *input.sidecar,
                                                               &sidecarError);
        } else if (input.removeSidecar) {
            SampleRegistrar::removeSampleSidecar(root, input.name);
            sidecarSaved = true;
        }
        return SampleCommitted{input.name, committed, sidecarSaved, sidecarError};
    }

    // ---- shared helpers ---------------------------------------------------------------

    std::optional<VoicegroupCatalog> scanCatalog(const QString &root, QString *error)
    {
        const QDir projectRoot(root);
        if (!projectRoot.exists() ||
            !QDir(projectRoot.filePath(QStringLiteral("sound"))).exists()) {
            *error = QStringLiteral("Project sound directory is unavailable.");
            return std::nullopt;
        }
        if (m_catalogCancellation.load(std::memory_order_acquire))
            return std::nullopt;

        auto catalog = VoicegroupCatalog{};
        const auto scan = VoicegroupSource::catalogScan(root, &m_catalogCancellation);
        if (m_catalogCancellation.load(std::memory_order_acquire))
            return std::nullopt;
        const auto directSound = VoicegroupSource::directSoundCatalog(root);
        if (m_catalogCancellation.load(std::memory_order_acquire))
            return std::nullopt;
        catalog.perFileVoicegroups =
            QDir(QDir(root).filePath(QStringLiteral("sound/voicegroups"))).exists();
        catalog.groupArgs = scan.groupArgs;
        catalog.keysplits = scan.keysplits;
        catalog.drumkits = scan.drumkits;
        catalog.typicalAdsr = scan.typicalAdsr;
        catalog.directSound = directSound.directSound;
        catalog.synths = directSound.synths;
        catalog.progWave = VoicegroupSource::progWaveSymbols(root);
        if (m_catalogCancellation.load(std::memory_order_acquire))
            return std::nullopt;
        return catalog;
    }

    bool requireOpen() const { return m_project.isOpen(); }
    static ProjectResult closedProject()
    {
        return CommandFailure{QStringLiteral("No project is open.")};
    }

    // A closed project never reconciled the song name.
    static ProjectResult closedSong(const SongName &song)
    {
        return SongCommandFailure{song, SongStage::Reconcile,
                                  QStringLiteral("No project is open.")};
    }

    std::atomic_bool &m_catalogCancellation;
    DecompProject m_project;
};

ProjectIo::ProjectIo(ResultSink sink, QObject *parent)
    : QObject(parent)
    , m_thread(new QThread(this))
    , m_sink(std::move(sink))
{
    m_worker = new Worker(m_cancelCatalog);
    m_worker->moveToThread(m_thread);
    connect(m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    m_thread->start();
}

ProjectIo::~ProjectIo()
{
    m_shuttingDown.store(true, std::memory_order_release);
    m_thread->quit();
    m_thread->wait();
    // The worker is gone; any command it still owned died with its queued
    // lambda. Whatever results landed unread is destroyed here, releasing
    // the bank leases and sample sets they carry.
    drainResults();
    m_queue.clear();
    m_active = false;
}

void ProjectIo::submit(ProjectCommand command)
{
    Q_ASSERT(QThread::currentThread() == thread());
    if (m_shuttingDown.load(std::memory_order_acquire))
        return;
    if (m_activeCatalog && isSongCommand(command))
        m_cancelCatalog.store(true, std::memory_order_release);
    m_queue.push_back(std::move(command));
    dispatchNext();
}

void ProjectIo::dispatchNext()
{
    if (m_shuttingDown.load(std::memory_order_acquire) || m_active || m_queue.empty())
        return;
    m_active = true;
    auto command = std::move(m_queue.front());
    m_queue.pop_front();
    m_activeCatalog = std::holds_alternative<RefreshCatalogInput>(command);
    if (m_activeCatalog)
        m_cancelCatalog.store(false, std::memory_order_release);
    const auto invoked = QMetaObject::invokeMethod(
        m_worker,
        [this, command = std::move(command)]() mutable {
            const auto stage = [this](ProjectResult staged) {
                postResult(std::move(staged), std::nullopt);
            };
            auto terminal = m_worker->execute(command, stage);
            postResult(std::move(terminal), std::move(command));
            completeCommand();
        },
        Qt::QueuedConnection);
    Q_ASSERT(invoked);
}

void ProjectIo::postResult(ProjectResult result, std::optional<ProjectCommand> command)
{
    {
        const auto lock = std::lock_guard(m_resultMutex);
        m_results.push_back(Delivery{std::move(result), std::move(command)});
    }
    if (m_shuttingDown.load(std::memory_order_acquire)) {
        // The destructor is draining synchronously; no queued turn is coming.
        drainResults();
        return;
    }
    QMetaObject::invokeMethod(this, [this] { drainResults(); }, Qt::QueuedConnection);
}

// Runs on the worker thread after a command's terminal result was posted;
// the queued completion is delivered after every result of the command, so
// the FIFO advances only on full delivery.
void ProjectIo::completeCommand()
{
    QMetaObject::invokeMethod(
        this,
        [this] {
            m_active = false;
            m_activeCatalog = false;
            dispatchNext();
        },
        Qt::QueuedConnection);
}

void ProjectIo::drainResults()
{
    // Runs on the owner thread, or inline on the worker thread while the
    // destructor is shutting the transport down.
    while (true) {
        auto delivery = std::optional<Delivery>{};
        {
            const auto lock = std::lock_guard(m_resultMutex);
            if (m_results.empty())
                return;
            delivery = std::move(m_results.front());
            m_results.pop_front();
        }
        finishResult(std::move(*delivery));
    }
}

void ProjectIo::finishResult(Delivery &&delivery)
{
    if (m_shuttingDown.load(std::memory_order_acquire))
        return; // the destroyed temporary releases any owning payloads
    const bool cancelledCatalog =
        std::holds_alternative<CatalogScanCancelled>(delivery.result) ||
        (m_cancelCatalog.load(std::memory_order_acquire) && delivery.command &&
         std::holds_alternative<RefreshCatalogInput>(*delivery.command) &&
         std::holds_alternative<VoicegroupCatalog>(delivery.result));
    if (cancelledCatalog) {
        Q_ASSERT(delivery.command &&
                 std::holds_alternative<RefreshCatalogInput>(*delivery.command));
        m_cancelCatalog.store(false, std::memory_order_release);
        m_queue.emplace_back(RefreshCatalogInput{});
        if (!m_active)
            dispatchNext();
        return;
    }
    if (m_sink)
        m_sink(std::move(delivery.result), std::move(delivery.command));
}
