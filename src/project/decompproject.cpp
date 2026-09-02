#include "decompproject.h"
#include "voicegroupprojectcontext.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QTextStream>
#include <array>
#include <cstring>
#include <utility>
#include <vector>

#include "project/songregistry.h"
#include "project/songsmk.h"

namespace {

QHash<QString, int> playerTrackBudgets(const QVector<MusicPlayer> &players)
{
    QHash<QString, int> budgets;
    budgets.reserve(players.size());
    for (const MusicPlayer &player : players) {
        if (!budgets.contains(player.name))
            budgets.insert(player.name, player.trackCount >= 0 ? player.trackCount : 16);
    }
    return budgets;
}

// Stamps each song with the registration files still missing (or
// mis-stating) its entry, from the one-pass registry statuses computed at
// open. Reuses each list's existing buffer across opens.
void applyRegistrationGaps(QVector<SongInfo> &songs,
                           const QHash<QString, RegistrationStatus> &statuses)
{
    for (SongInfo &song : songs) {
        const RegistrationStatus status = statuses.value(song.label);
        QStringList &gaps = song.registrationGaps;
        gaps.clear();
        if (!status.inSongTable)
            gaps.append(QStringLiteral("song_table.inc"));
        if (!status.inSongsH)
            gaps.append(QStringLiteral("songs.h"));
        if (status.ldApplicable && !status.inLdScript)
            gaps.append(QStringLiteral("ld_script.ld"));
        if (status.charmapApplicable && !status.inCharmap)
            gaps.append(QStringLiteral("charmap.txt"));
        if (status.debugApplicable && !status.inDebugMenu)
            gaps.append(QStringLiteral("src/debug.c"));
    }
}

// Caches the project's music-player table and each player's track budget
// at open.
void loadPlayerConfiguration(const QString &root, QVector<MusicPlayer> &players,
                             QHash<QString, int> &trackBudgets)
{
    players = SongRegistry::musicPlayers(root);
    trackBudgets = playerTrackBudgets(players);
}

QString normalizedVoicegroupArg(const QString &voicegroupArg)
{
    return voicegroupArg.isEmpty() ? QStringLiteral("_dummy") : voicegroupArg;
}

} // namespace

ProjectSnapshot::ProjectSnapshot(QString root, QVector<SongInfo> songs,
                                 QVector<MusicPlayer> players, QHash<QString, int> trackBudgets)
    : m_root(std::move(root))
    , m_songs(std::move(songs))
    , m_players(std::move(players))
    , m_trackBudgets(std::move(trackBudgets))
{}

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
    return file.commit();
}

QString previewDirFor(const QString &root)
{
    return QDir(root).filePath(QStringLiteral(".porydaw/vgpreview"));
}

// Shadow-loads an edited source without touching the project's real files:
// the rendered bytes are staged under the preview directory and the C loader
// resolves the voicegroup through the path override. Returns null on
// failure, with the loader's error (or a fallback message) through error.
LoadedVoiceGroup *loadPreviewedSource(const QString &root, const QString &loadName,
                                      const QByteArray &sourceBytes, QString *error)
{
    const QString previewDir = previewDirFor(root);
    QDir(previewDir).removeRecursively();
    if (!QDir().mkpath(previewDir)) {
        if (error)
            *error = QStringLiteral("Cannot create voicegroup preview directory.");
        return nullptr;
    }
    const QString path = QDir(previewDir).filePath(loadName + QStringLiteral(".inc"));
    if (!writeBytes(path, sourceBytes, error)) {
        QDir(previewDir).removeRecursively();
        return nullptr;
    }
    VoicegroupLoaderConfig config;
    std::memset(&config, 0, sizeof(config));
    std::strncpy(config.voicegroupPaths[0], ".porydaw/vgpreview", VG_MAX_PATH_LEN - 1);
    config.voicegroupPathCount = 1;
    const auto rootUtf8 = root.toLocal8Bit();
    const auto nameUtf8 = loadName.toLocal8Bit();
    auto *bank = voicegroup_load(rootUtf8.constData(), nameUtf8.constData(), &config);
    QDir(previewDir).removeRecursively();
    if (!bank && error && error->isEmpty())
        *error = QStringLiteral("Edited voicegroup failed to load.");
    return bank;
}

struct SynthToneBuffer {
    WaveData wave;
    uint8_t bytes[17];
};

struct SynthToneStorage {
    std::array<std::optional<SynthToneBuffer>, VOICEGROUP_SIZE> tones;
};

std::optional<VgSynthDesc> mintedSynthDesc(const QString &symbol)
{
    static const QRegularExpression pulse(
        QStringLiteral("^DirectSoundSynth_GoldenSun_([0-9A-F]{8})(?:_[0-9]+)?$"));
    static const QRegularExpression saw(
        QStringLiteral("^DirectSoundSynth_GoldenSun_Saw(?:_[0-9]+)?$"));
    static const QRegularExpression triangle(
        QStringLiteral("^DirectSoundSynth_GoldenSun_Triangle(?:_[0-9]+)?$"));
    const auto pulseMatch = pulse.match(symbol);
    if (pulseMatch.hasMatch()) {
        bool ok = false;
        const uint32_t packed = pulseMatch.capturedView(1).toUInt(&ok, 16);
        if (!ok)
            return std::nullopt;
        return VgSynthDesc{0, int((packed >> 24) & 0xff), int((packed >> 16) & 0xff),
                           int((packed >> 8) & 0xff), int(packed & 0xff)};
    }
    if (saw.match(symbol).hasMatch())
        return VgSynthDesc{1};
    if (triangle.match(symbol).hasMatch())
        return VgSynthDesc{2};
    return std::nullopt;
}

VoicegroupLease leaseWithMintedSynths(LoadedVoiceGroup *raw, const VoicegroupSource &source)
{
    std::shared_ptr<SynthToneStorage> storage;
    for (int slot = 0; slot < VOICEGROUP_SIZE; ++slot) {
        const VgVoice *const voice = source.voiceAt(slot);
        if (!voice || raw->voices[slot].wav ||
            (voice->macro != VgMacro::DirectSound &&
             voice->macro != VgMacro::DirectSoundNoResample &&
             voice->macro != VgMacro::DirectSoundAlt))
            continue;
        const auto desc = mintedSynthDesc(voice->symbol);
        if (!desc)
            continue;
        if (!storage)
            storage = std::make_shared<SynthToneStorage>();
        SynthToneBuffer &tone = storage->tones[slot].emplace();
        std::memset(&tone, 0, sizeof(tone));
        tone.wave.status = 0x4000;
        tone.wave.freq = 0x01058920;
        tone.wave.data = reinterpret_cast<int8_t *>(tone.bytes);
        tone.bytes[0] = 0x80;
        tone.bytes[1] = uint8_t(desc->waveform);
        tone.bytes[2] = uint8_t(desc->baseDuty);
        tone.bytes[3] = uint8_t(desc->dutyStep);
        tone.bytes[4] = uint8_t(desc->modDepth);
        tone.bytes[5] = uint8_t(desc->phase);
        raw->voices[slot].wav = &tone.wave;
    }
    if (!storage)
        return wrapVoicegroupLease(raw);
    return wrapVoicegroupLease(raw, std::move(storage));
}

// The published slot views: each slot's exact source-line kind plus the
// parsed voice when the line is editable.
QVector<VoicegroupSlotView> sourceSlotViews(const VoicegroupSource &source)
{
    QVector<VoicegroupSlotView> slotViews(VOICEGROUP_SIZE);
    for (int slot = 0; slot < VOICEGROUP_SIZE; slot++) {
        VoicegroupSlotView &slotView = slotViews[slot];
        slotView.kind = source.kindAt(slot);
        if (const VgVoice *voice = source.voiceAt(slot))
            slotView.voice = *voice;
    }
    return slotViews;
}

// saveVoicegroup's write stage: the optional synth-definition write, then
// the source's byte-conservative write (which clears its dirty bit). No
// rollback: earlier writes remain when a later stage fails.
bool persistVoicegroupChanges(const QString &root,
                              const QList<QPair<QString, VgSynthDesc>> &synthDefinitions,
                              VoicegroupSource &source, QString *error)
{
    if (!synthDefinitions.isEmpty() &&
        !VoicegroupSource::writeSynthDefinitions(root, synthDefinitions, error))
        return false;
    return source.save(error);
}

// The context a saved bank reloads from: a freshly opened replacement after
// synth-definition changes (null on failure, error set), else the existing
// one. The caller swaps only after the reload succeeds.
std::unique_ptr<VoicegroupProjectContext> reopenedVoicegroupContext(const QString &root,
                                                                    QString *error)
{
    auto replacement = VoicegroupProjectContext::open(root);
    if (!replacement) {
        if (error)
            *error = QStringLiteral("Could not refresh the project voicegroup loader.");
    }
    return replacement;
}

// After a context swap every other bank's lease points into the discarded
// context, so only the just-saved record survives. Template because the
// bank map's entry type is private to DecompProject.
template <typename BankMap>
void pruneStaleBanks(BankMap &banks, const VoicegroupId &keepId)
{
    for (auto it = banks.begin(); it != banks.end();) {
        if (it->first == keepId)
            ++it;
        else
            it = banks.erase(it);
    }
}

// Without a swap the other records stay valid: point memo entries for the
// saved voicegroup at its path and fresh file time.
template <typename ArgMemo>
void refreshSavedVoicegroupMemos(ArgMemo &memo, const VoicegroupId &id, const QString &filePath,
                                 const QDateTime &fileTime)
{
    for (auto it = memo.begin(); it != memo.end(); ++it) {
        if (it.value().id == id) {
            it.value().filePath = filePath;
            it.value().sourceFileTime = fileTime;
        }
    }
}

} // namespace

bool ProjectSnapshot::isOpen() const
{
    return !m_root.isEmpty();
}

const QString &ProjectSnapshot::root() const
{
    return m_root;
}

const QVector<SongInfo> &ProjectSnapshot::songs() const
{
    return m_songs;
}

const QVector<MusicPlayer> &ProjectSnapshot::players() const
{
    return m_players;
}

int ProjectSnapshot::trackBudgetFor(const SongInfo &song) const
{
    return m_trackBudgets.value(song.label, 16);
}

DecompProject::DecompProject() = default;

DecompProject::~DecompProject() = default;

DecompProject::DecompProject(DecompProject &&) noexcept = default;

DecompProject &DecompProject::operator=(DecompProject &&) noexcept = default;

bool DecompProject::open(const QString &rootDir, QString *error)
{
    const QDir dir(rootDir);
    if (!dir.exists()) {
        if (error)
            *error = QStringLiteral("Directory does not exist: %1").arg(rootDir);
        return false;
    }

    auto candidate = DecompProject{};
    candidate.m_root = dir.absolutePath();
    candidate.m_voicegroupProject = VoicegroupProjectContext::open(candidate.m_root);
    if (!candidate.m_voicegroupProject) {
        if (error)
            *error = QStringLiteral("Could not initialize the project voicegroup loader.");
        return false;
    }
    if (!candidate.parseSongTable(error))
        return false;
    candidate.parseSongConstants();
    candidate.discoverUnregisteredSongs();
    // Which registration files still miss each song's entry — one pass over
    // the registration files for the whole project (checkRegistration per
    // song would reopen them hundreds of times).
    const QHash<QString, RegistrationStatus> statuses =
        SongRegistry::checkRegistrations(candidate.m_root, candidate.m_songs);
    applyRegistrationGaps(candidate.m_songs, statuses);
    if (!candidate.parseMidiCfg())
        candidate.parseSongsMk();
    loadPlayerConfiguration(candidate.m_root, candidate.m_players, candidate.m_playerTrackBudgets);

    *this = std::move(candidate);
    return true;
}

void DecompProject::replaceWith(const ProjectSnapshot &snapshot)
{
    m_voicegroupProject.reset();
    m_voicegroupArgMemo.clear();
    m_banks.clear();
    m_root = snapshot.root();
    m_songs = snapshot.songs();
    m_players = snapshot.players();
    m_playerTrackBudgets = playerTrackBudgets(m_players);
}

int DecompProject::trackBudgetFor(const SongInfo &song) const
{
    return m_playerTrackBudgets.value(song.player, 16);
}

bool DecompProject::reload(QString *error)
{
    const QString root = m_root;
    return open(root, error);
}

bool DecompProject::rebuildVoicegroupProject(QString *error)
{
    if (m_root.isEmpty()) {
        if (error)
            *error = QStringLiteral("Project is not open.");
        return false;
    }
    auto replacement = VoicegroupProjectContext::open(m_root);
    if (!replacement) {
        if (error)
            *error = QStringLiteral("Could not refresh the project voicegroup loader.");
        return false;
    }
    std::vector<std::pair<LoadedBankEntry *, VoicegroupLease>> refreshed;
    refreshed.reserve(m_banks.size());
    for (auto &[id, entry] : m_banks) {
        LoadedVoiceGroup *raw = nullptr;
        QString reloadError;
        if (entry.source->dirty()) {
            raw = loadPreviewedSource(m_root, entry.loadName, entry.source->renderPreview(),
                                      &reloadError);
        } else {
            const QByteArray targetPath = entry.source->filePath().toLocal8Bit();
            const QByteArray sectionLabel = entry.source->sectionLabel().toLocal8Bit();
            const VoicegroupTarget target = {targetPath.constData(), sectionLabel.constData()};
            raw = replacement->load(target);
        }
        if (!raw) {
            if (error)
                *error = reloadError.isEmpty() ? QStringLiteral("Could not reload voicegroup %1.")
                                                     .arg(id.sourceRelativePath())
                                               : std::move(reloadError);
            return false;
        }
        refreshed.emplace_back(&entry, leaseWithMintedSynths(raw, *entry.source));
    }
    m_voicegroupProject.swap(replacement);
    m_voicegroupArgMemo.clear();
    for (auto &[entry, lease] : refreshed)
        entry->current = std::move(lease);
    return true;
}

void DecompProject::close()
{
    m_voicegroupProject.reset();
    m_voicegroupArgMemo.clear();
    m_banks.clear();
    m_root.clear();
    m_songs.clear();
    m_players.clear();
    m_playerTrackBudgets.clear();
}

bool DecompProject::parseSongTable(QString *error)
{
    const QString path = m_root + QStringLiteral("/sound/song_table.inc");
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (error)
            *error = QStringLiteral("Cannot open %1.\n\nIs this a pokeemerald/pokefirered/pokeruby "
                                    "project directory?")
                         .arg(path);
        return false;
    }

    // e.g. "	song mus_dummy, MUSIC_PLAYER_BGM, 0"
    static const QRegularExpression songRe(
        QStringLiteral(R"(^\s*song\s+(\w+)\s*,\s*(\w+)\s*,\s*(\w+))"));

    const QString midiDir = m_root + QStringLiteral("/sound/songs/midi/");
    QTextStream in(&file);
    while (!in.atEnd()) {
        const QString line = in.readLine();
        const QRegularExpressionMatch m = songRe.match(line);
        if (!m.hasMatch())
            continue;

        SongInfo song;
        song.id = m_songs.size();
        song.label = m.captured(1);
        song.player = m.captured(2);

        const QString midPath = midiDir + song.label + QStringLiteral(".mid");
        if (QFile::exists(midPath)) {
            song.midPath = midPath;
            song.hasMid = true;
        }
        m_songs.append(song);
    }

    if (m_songs.isEmpty()) {
        if (error)
            *error = QStringLiteral("No songs found in %1").arg(path);
        return false;
    }
    return true;
}

void DecompProject::parseSongConstants()
{
    QFile file(m_root + QStringLiteral("/include/constants/songs.h"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;

    // e.g. "#define MUS_ABANDONED_SHIP 381"
    static const QRegularExpression defineRe(
        QStringLiteral(R"(^\s*#define\s+([A-Z0-9_]+)\s+(\d+)\s*$)"));

    QHash<int, QString> byId;
    QTextStream in(&file);
    while (!in.atEnd()) {
        const QRegularExpressionMatch m = defineRe.match(in.readLine());
        if (!m.hasMatch())
            continue;
        const int id = m.captured(2).toInt();
        // First definition wins (later defines like PH_* aliases share IDs).
        if (!byId.contains(id))
            byId.insert(id, m.captured(1));
    }

    for (SongInfo &song : m_songs) {
        const auto it = byId.constFind(song.id);
        if (it != byId.constEnd())
            song.constant = it.value();
    }
}

void DecompProject::discoverUnregisteredSongs()
{
    // .mid files with no song_table.inc entry: songs whose registration
    // never ran (dropped-in files) or failed. Listing them keeps the badge
    // visible across project reopens so Register Song can finish the job.
    // Unregistered files use the label-derived constant and default player
    // until the user completes registration.
    QSet<QString> known;
    for (const SongInfo &song : m_songs)
        known.insert(song.label);

    const QDir midiDir(m_root + QStringLiteral("/sound/songs/midi"));
    const QStringList mids = midiDir.entryList({QStringLiteral("*.mid")}, QDir::Files, QDir::Name);
    for (const QString &fileName : mids) {
        const QString label = fileName.chopped(4);
        if (known.contains(label))
            continue;
        SongInfo song;
        song.id = m_songs.size();
        song.label = label;
        song.registered = false;
        song.midPath = midiDir.filePath(fileName);
        song.hasMid = true;
        song.constant = SongRegistry::constantForLabel(label);
        song.player = QStringLiteral("MUSIC_PLAYER_BGM");
        m_songs.append(song);
    }
}

// mid2agb parses option letters case-insensitively (-v080 == -V080).
static SongCfg cfgFromFlags(const QStringList &flags)
{
    SongCfg cfg;
    cfg.rawFlags = flags;
    for (const QString &flag : flags) {
        if (flag.size() < 2 || flag[0] != QLatin1Char('-'))
            continue;
        const QChar opt = flag[1].toUpper();
        const QString arg = flag.mid(2);
        switch (opt.toLatin1()) {
        case 'G':
            cfg.voicegroupArg = arg;
            break;
        case 'V':
            cfg.masterVolume = qBound(0, arg.toInt(), 127);
            break;
        case 'R':
            cfg.reverb = qBound(0, arg.toInt(), 127);
            break;
        case 'P':
            cfg.priority = arg.toInt();
            break;
        case 'E':
            cfg.exactGate = true;
            break;
        case 'X':
            cfg.extendedClocks = true;
            break;
        case 'N':
            cfg.noCompression = true;
            break;
        default:
            break; // -L and unknown flags: irrelevant for playback
        }
    }
    return cfg;
}

bool DecompProject::parseMidiCfg()
{
    QFile file(m_root + QStringLiteral("/sound/songs/midi/midi.cfg"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;

    // e.g. "mus_abandoned_ship.mid: -E -R50 -G_abandoned_ship -V080"
    QHash<QString, SongCfg> byLabel;
    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        const int hash = line.indexOf(QLatin1Char('#'));
        if (hash >= 0)
            line = line.left(hash).trimmed();
        const int colon = line.indexOf(QLatin1Char(':'));
        if (colon <= 0)
            continue;

        QString name = line.left(colon).trimmed();
        if (name.endsWith(QStringLiteral(".mid"), Qt::CaseInsensitive))
            name.chop(4);

        byLabel.insert(
            name, cfgFromFlags(line.mid(colon + 1).split(QLatin1Char(' '), Qt::SkipEmptyParts)));
    }

    for (SongInfo &song : m_songs) {
        const auto it = byLabel.constFind(song.label);
        if (it != byLabel.constEnd()) {
            song.hasCfg = true;
            song.cfg = it.value();
        }
    }
    return true;
}

void DecompProject::parseSongsMk()
{
    // Pre-midi.cfg projects: per-song make rules in <root>/songs.mk.
    const QHash<QString, QStringList> byLabel = SongsMk::parseFlags(SongsMk::path(m_root));
    for (SongInfo &song : m_songs) {
        const auto it = byLabel.constFind(song.label);
        if (it != byLabel.constEnd()) {
            song.hasCfg = true;
            song.cfg = cfgFromFlags(it.value());
        }
    }
}

QStringList DecompProject::voicegroupCandidates(const SongInfo &song)
{
    return voicegroupCandidates(song.cfg);
}

void DecompProject::setSongCfg(int id, const SongCfg &cfg)
{
    if (id >= 0 && id < m_songs.size()) {
        m_songs[id].cfg = cfg;
        m_songs[id].hasCfg = true;
    }
}

QStringList DecompProject::voicegroupCandidates(const SongCfg &cfg)
{
    // mid2agb's default -G argument is "_dummy" (symbol voicegroup_dummy).
    const QString arg = cfg.voicegroupArg.isEmpty() ? QStringLiteral("_dummy") : cfg.voicegroupArg;
    const QString symbol = QStringLiteral("voicegroup") + arg;

    QStringList candidates;
    if (symbol.startsWith(QStringLiteral("voicegroup_")))
        candidates << symbol.mid(11); // e.g. "abandoned_ship"
    candidates << symbol;             // e.g. "voicegroup000" (pokefirered labels)
    if (!arg.isEmpty() && !candidates.contains(arg))
        candidates << arg;
    return candidates;
}

// ---- Worker-side voicegroup bank ownership ----

std::optional<SongInfo> DecompProject::playableSong(SongName name) const
{
    for (const SongInfo &song : m_songs) {
        if (song.isPlayable() && song.label == name.value())
            return song;
    }
    return std::nullopt;
}

LoadedBankView DecompProject::publishView(const LoadedBankEntry &entry) const
{
    return LoadedBankView{entry.id, entry.current, entry.loadName, entry.source->dirty(),
                          sourceSlotViews(*entry.source)};
}

LoadedSampleSet *DecompProject::loadSampleSet(const char *const *sampleSymbols, int sampleCount,
                                              const char *const *waveSymbols, int waveCount,
                                              const char *const *keysplitSymbols,
                                              const char *const *keysplitTableSymbols,
                                              int keysplitCount)
{
    if (!m_voicegroupProject)
        return nullptr;
    return m_voicegroupProject->loadSamples(sampleSymbols, sampleCount, waveSymbols, waveCount,
                                            keysplitSymbols, keysplitTableSymbols, keysplitCount);
}

std::optional<LoadedBankView> DecompProject::loadBank(const SongInfo &song, QString *error)
{
    const auto fail = [error](QString message) {
        if (error)
            *error = std::move(message);
        return std::optional<LoadedBankView>{};
    };
    if (m_root.isEmpty() || !m_voicegroupProject)
        return fail(QStringLiteral("Project is not open."));

    const QString voicegroupArg = normalizedVoicegroupArg(song.cfg.voicegroupArg);
    const auto memo = m_voicegroupArgMemo.constFind(voicegroupArg);
    if (memo != m_voicegroupArgMemo.constEnd()) {
        const auto existing = m_banks.find(memo->id);
        if (existing != m_banks.end() &&
            QFileInfo(memo->filePath).lastModified() == memo->sourceFileTime) {
            return publishView(existing->second);
        }
    }

    // Identity comes from the resolved source location, never from the song
    // or the loader alias: songs sharing a voicegroup share one record.
    auto source = std::make_unique<VoicegroupSource>();
    QString openError;
    if (!source->open(m_root, voicegroupArg, &openError))
        return fail(openError.isEmpty() ? QStringLiteral("Could not open the voicegroup source.")
                                        : std::move(openError));
    auto id = VoicegroupId::create(QDir(m_root).relativeFilePath(source->filePath()),
                                   source->sectionLabel());
    if (!id)
        return fail(QStringLiteral("Could not identify the voicegroup source."));
    const QString sourcePath = source->filePath();
    const QDateTime fileTime = QFileInfo(sourcePath).lastModified();

    // A different song may resolve to the same canonical source. Recheck
    // after source resolution, then memoize the argument without a C load.
    const auto existing = m_banks.find(*id);
    if (existing != m_banks.end() && existing->second.sourceFileTime == fileTime) {
        m_voicegroupArgMemo.insert(voicegroupArg, VoicegroupArgMemo{*id, sourcePath, fileTime});
        return publishView(existing->second);
    }

    const QByteArray targetPath = sourcePath.toLocal8Bit();
    const QByteArray sectionLabel = source->sectionLabel().toLocal8Bit();
    const VoicegroupTarget target = {targetPath.constData(), sectionLabel.constData()};
    LoadedVoiceGroup *raw = m_voicegroupProject->load(target);
    if (!raw)
        return fail(QStringLiteral("Could not load voicegroup source %1.").arg(sourcePath));

    // Replace the record (or insert the first one) only after the complete
    // pinned candidate has loaded, retaining any prior canonical record on
    // source or loader failure.
    VoicegroupLease lease = leaseWithMintedSynths(raw, *source);
    LoadedBankEntry fresh{*id, source->loadName(), std::move(source), std::move(lease), fileTime};
    auto entryIt = m_banks.find(*id);
    if (entryIt == m_banks.end())
        entryIt = m_banks.emplace(*id, std::move(fresh)).first;
    else
        entryIt->second = std::move(fresh);
    m_voicegroupArgMemo.insert(voicegroupArg, VoicegroupArgMemo{*id, sourcePath, fileTime});
    return publishView(entryIt->second);
}

std::optional<VoicegroupEditResult> DecompProject::applyVoicegroupEdit(VoicegroupEditInput input,
                                                                       QString *error)
{
    const auto fail = [error](QString message) {
        if (error)
            *error = std::move(message);
        return std::optional<VoicegroupEditResult>{};
    };
    const auto notApplied = [id = input.id]() {
        return std::optional<VoicegroupEditResult>{VoicegroupEditConflictResult{id}};
    };
    if (m_root.isEmpty())
        return fail(QStringLiteral("Project is not open."));
    const auto existing = m_banks.find(input.id);
    if (existing == m_banks.end()) {
        return fail(
            QStringLiteral("Voicegroup is not loaded: %1").arg(input.id.sourceRelativePath()));
    }
    LoadedBankEntry &entry = existing->second;
    VoicegroupSource &source = *entry.source;

    // Captured before any mutation: a hard error after the loader rejects
    // the candidate restores exactly these bytes.
    const QByteArray before = source.sourceBytes();

    VoicegroupSource::BlankSlotMaterialization materialization;
    if (const auto *slotEdit = std::get_if<SetVoicegroupSlot>(&input.operation)) {
        if (slotEdit->slot < 0 || slotEdit->slot >= VOICEGROUP_SIZE)
            return notApplied(); // validation no-op
        const VgVoice *current = source.voiceAt(slotEdit->slot);
        if (!slotEdit->expected) {
            // Blank expected state: the slot must still be undefined, and the
            // edit materializes it under a revertable token.
            if (current)
                return notApplied();
            auto token = source.materializeBlankSlot(slotEdit->slot, slotEdit->value);
            if (!token)
                return notApplied();
            materialization = std::move(*token);
        } else {
            if (!current || !(*current == *slotEdit->expected))
                return notApplied();
            if (!source.setVoice(slotEdit->slot, slotEdit->value))
                return notApplied();
        }
    } else if (const auto *revert = std::get_if<RevertBlankSlot>(&input.operation)) {
        if (!source.revertBlankSlotMaterialization(revert->materialization))
            return notApplied();
    } else {
        return fail(QStringLiteral("Unknown voicegroup edit operation."));
    }

    // The mutation stays provisional until the loader validates a complete
    // candidate built from the rendered source; a hard error restores the
    // source bytes so the old record survives untouched.
    QString loadError;
    LoadedVoiceGroup *raw =
        loadPreviewedSource(m_root, entry.loadName, source.renderPreview(), &loadError);
    if (!raw) {
        source.restoreSourceBytes(before);
        return fail(loadError.isEmpty() ? QStringLiteral("Edited voicegroup failed to load.")
                                        : std::move(loadError));
    }
    entry.current = leaseWithMintedSynths(raw, source);
    VoicegroupEditAppliedResult applied{publishView(entry), std::nullopt};
    if (materialization.firstAddedSlot >= 0)
        applied.materialization = std::move(materialization);
    return std::optional<VoicegroupEditResult>{std::move(applied)};
}

std::optional<LoadedBankView> DecompProject::saveVoicegroup(SaveVoicegroupInput input,
                                                            QString *error)
{
    const auto fail = [error](QString message) {
        if (error)
            *error = std::move(message);
        return std::optional<LoadedBankView>{};
    };
    if (m_root.isEmpty() || !m_voicegroupProject)
        return fail(QStringLiteral("Project is not open."));
    const auto existing = m_banks.find(input.voicegroup);
    if (existing == m_banks.end()) {
        return fail(QStringLiteral("Voicegroup is not loaded: %1")
                        .arg(input.voicegroup.sourceRelativePath()));
    }
    LoadedBankEntry &entry = existing->second;

    // Save ordering: the writes, then the bank refresh from the saved
    // bytes. No rollback: earlier writes remain when a later stage fails.
    const bool mapsChanged = !input.synthDefinitions.isEmpty();
    if (!persistVoicegroupChanges(m_root, input.synthDefinitions, *entry.source, error))
        return std::nullopt;

    std::unique_ptr<VoicegroupProjectContext> replacement;
    VoicegroupProjectContext *context = m_voicegroupProject.get();
    if (mapsChanged) {
        replacement = reopenedVoicegroupContext(m_root, error);
        if (!replacement)
            return std::nullopt;
        context = replacement.get();
    }

    const QString sourcePath = entry.source->filePath();
    const QDateTime fileTime = QFileInfo(sourcePath).lastModified();
    const QByteArray targetPath = sourcePath.toLocal8Bit();
    const QByteArray sectionLabel = entry.source->sectionLabel().toLocal8Bit();
    const VoicegroupTarget target = {targetPath.constData(), sectionLabel.constData()};
    LoadedVoiceGroup *raw = context->load(target);
    if (!raw)
        return fail(QStringLiteral("Saved voicegroup failed to reload."));
    VoicegroupLease lease = leaseWithMintedSynths(raw, *entry.source);

    if (replacement) {
        m_voicegroupProject.swap(replacement);
        pruneStaleBanks(m_banks, entry.id);
        m_voicegroupArgMemo.clear();
    } else {
        refreshSavedVoicegroupMemos(m_voicegroupArgMemo, entry.id, sourcePath, fileTime);
    }
    entry.sourceFileTime = fileTime;
    entry.current = std::move(lease);
    return publishView(entry);
}
