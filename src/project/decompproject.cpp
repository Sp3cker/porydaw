#include "decompproject.h"

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

bool DecompProject::open(const QString &rootDir, QString *error)
{
    close();

    const QDir dir(rootDir);
    if (!dir.exists()) {
        if (error)
            *error = QStringLiteral("Directory does not exist: %1").arg(rootDir);
        return false;
    }
    m_root = dir.absolutePath();
    const QString cacheStoreDir =
        m_cacheStoreDir.isEmpty() ? ProjectIndex::defaultStoreDir(m_root) : m_cacheStoreDir;

    // Persistent-index fast path: a store whose fingerprint still matches
    // every input replaces the scan entirely; anything else falls through
    // to the full rescan and is rewritten below.
    QByteArray indexFinger;
    QStringList midiFiles;
    if (!cacheStoreDir.isEmpty()) {
        // Listing feeds the fingerprint, and the scan below reuses it —
        // sound/songs/midi is never walked twice.
        midiFiles = ProjectIndex::listFileNames(m_root + QStringLiteral("/sound/songs/midi"),
                                                QStringLiteral(".mid"));
        const QStringList sidecarFiles = ProjectIndex::listFileNames(
            m_root + QStringLiteral("/.porydaw"), QStringLiteral(".json"));
        indexFinger = ProjectIndex::fingerprint(m_root, midiFiles, sidecarFiles);
        if (ProjectIndex::load(cacheStoreDir, m_root, indexFinger, &m_songs, &m_players)) {
            for (SongInfo &song : m_songs) {
                if (!song.registered) {
                    song.constant = SongRegistry::constantForLabel(song.label);
                    song.player = QStringLiteral("MUSIC_PLAYER_BGM");
                    QString constant, player;
                    if (SongRegistry::loadRegistrationMeta(m_root, song.label, &constant,
                                                           &player)) {
                        if (!constant.isEmpty())
                            song.constant = constant;
                        if (!player.isEmpty())
                            song.player = player;
                    }
                }
            }
            m_playerTrackBudgets = playerTrackBudgets(m_players);
            return true;
        }
    }
    const QDir midiDir(m_root + QStringLiteral("/sound/songs/midi"));
    // Bare names-only walk: QDir::entryList's per-entry metadata stat
    // dominates the scan on large FAT32 checkouts (see ProjectIndex::
    // listFileNames). Listed only when the cache fast path above did not.
    if (midiFiles.isEmpty())
        midiFiles = ProjectIndex::listFileNames(m_root + QStringLiteral("/sound/songs/midi"),
                                                QStringLiteral(".mid"));
    QSet<QString> midiFileNames;
    for (const QString &fileName : midiFiles)
        midiFileNames.insert(fileName);
    if (!parseSongTable(midiDir, midiFileNames, error)) {
        m_root.clear();
        return false;
    }
    parseSongConstants();
    discoverUnregisteredSongs(midiDir, midiFiles);
    // Which registration files still miss each song's entry — one pass over
    // the registration files for the whole project (checkRegistration per
    // song would reopen them hundreds of times).
    const QHash<QString, RegistrationStatus> statuses =
        SongRegistry::checkRegistrations(m_root, m_songs);
    for (SongInfo &song : m_songs) {
        const RegistrationStatus status = statuses.value(song.label);
        song.registrationGaps.clear();
        if (!status.inSongTable)
            song.registrationGaps.append(QStringLiteral("song_table.inc"));
        if (!status.inSongsH)
            song.registrationGaps.append(QStringLiteral("songs.h"));
        if (status.ldApplicable && !status.inLdScript)
            song.registrationGaps.append(QStringLiteral("ld_script.ld"));
        if (status.charmapApplicable && !status.inCharmap)
            song.registrationGaps.append(QStringLiteral("charmap.txt"));
        if (status.debugApplicable && !status.inDebugMenu)
            song.registrationGaps.append(QStringLiteral("src/debug.c"));
    }
    if (!parseMidiCfg())
        parseSongsMk();
    m_players = SongRegistry::musicPlayers(m_root);
    m_playerTrackBudgets = playerTrackBudgets(m_players);
    if (!cacheStoreDir.isEmpty())
        ProjectIndex::save(cacheStoreDir, m_root, indexFinger, m_songs, m_players);
    return true;
}

void DecompProject::replaceWith(const ProjectSnapshot &snapshot)
{
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

void DecompProject::close()
{
    m_root.clear();
    m_songs.clear();
    m_players.clear();
    m_playerTrackBudgets.clear();
    m_banks.clear();
}

void DecompProject::setIndexCache(const QString &storeDir)
{
    m_cacheStoreDir = storeDir;
}

bool DecompProject::parseSongTable(const QDir &midiDir, const QSet<QString> &midiFiles,
                                   QString *error)
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

        const QString midiFileName = song.label + QStringLiteral(".mid");
        if (midiFiles.contains(midiFileName)) {
            song.midPath = midiDir.filePath(midiFileName);
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

void DecompProject::discoverUnregisteredSongs(const QDir &midiDir, const QStringList &midiFiles)
{
    // .mid files with no song_table.inc entry: songs whose registration
    // never ran (dropped-in files) or failed. Listing them keeps the badge
    // visible across project reopens so Register Song can finish the job.
    // Identity chosen in the wizard comes back from the sidecar; the
    // constant falls back to the label-derived default.
    QSet<QString> known;
    for (const SongInfo &song : m_songs)
        known.insert(song.label);

    for (const QString &fileName : midiFiles) {
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
        QString constant, player;
        if (SongRegistry::loadRegistrationMeta(m_root, label, &constant, &player)) {
            if (!constant.isEmpty())
                song.constant = constant;
            if (!player.isEmpty())
                song.player = player;
        }
        m_songs.append(song);
    }
}

// mid2agb parses option letters case-insensitively (-v080 == -V080).
SongCfg SongCfg::fromFlags(const QStringList &flags)
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

        byLabel.insert(name, SongCfg::fromFlags(
                                 line.mid(colon + 1).split(QLatin1Char(' '), Qt::SkipEmptyParts)));
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
            song.cfg = SongCfg::fromFlags(it.value());
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

std::optional<LoadedBankView> DecompProject::loadBank(const SongInfo &song, QString *error)
{
    const auto fail = [error](QString message) {
        if (error)
            *error = std::move(message);
        return std::optional<LoadedBankView>{};
    };
    if (m_root.isEmpty())
        return fail(QStringLiteral("Project is not open."));

    // Identity comes from the resolved source location, never from the song
    // or the loader alias: songs sharing a voicegroup share one record.
    auto source = std::make_unique<VoicegroupSource>();
    QString openError;
    if (!source->open(m_root, song.cfg.voicegroupArg, &openError))
        return fail(openError.isEmpty() ? QStringLiteral("Could not open the voicegroup source.")
                                        : std::move(openError));
    auto id = VoicegroupId::create(QDir(m_root).relativeFilePath(source->filePath()),
                                   source->sectionLabel());
    if (!id)
        return fail(QStringLiteral("Could not identify the voicegroup source."));
    const QDateTime fileTime = QFileInfo(source->filePath()).lastModified();

    // Unchanged record: publish the current lease without re-running the
    // C loader (and without disturbing the record's own source model).
    const auto existing = m_banks.find(*id);
    if (existing != m_banks.end() && existing->second.sourceFileTime == fileTime)
        return publishView(existing->second);

    // Cache miss or modified file: load the complete candidate before the
    // record changes, so a failure leaves the previous record untouched.
    const QStringList candidates = voicegroupCandidates(song.cfg);
    LoadedVoiceGroup *raw = nullptr;
    for (const QString &candidate : candidates) {
        const auto rootUtf8 = m_root.toLocal8Bit();
        const auto nameUtf8 = candidate.toLocal8Bit();
        raw = voicegroup_load(rootUtf8.constData(), nameUtf8.constData(), nullptr);
        if (raw)
            break;
    }
    if (!raw) {
        return fail(QStringLiteral("Could not load voicegroup (tried: %1).")
                        .arg(candidates.join(QStringLiteral(", "))));
    }

    // Replace the record (or insert the first one) with the fresh candidate
    // only now that the complete bank has loaded.
    LoadedBankEntry fresh{*id, source->loadName(), std::move(source), wrapVoicegroupLease(raw),
                          fileTime};
    auto [entryIt, inserted] = m_banks.try_emplace(*id, std::move(fresh));
    if (!inserted)
        entryIt->second = std::move(fresh);
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
    if (m_root.isEmpty())
        return fail(QStringLiteral("Project is not open."));
    const auto existing = m_banks.find(input.voicegroup);
    if (existing == m_banks.end()) {
        return fail(QStringLiteral("Voicegroup is not loaded: %1")
                        .arg(input.voicegroup.sourceRelativePath()));
    }
    LoadedBankEntry &entry = existing->second;

    // Save ordering: optional synth definitions, then the source's own
    // byte-conservative write (which clears its dirty bit), then the bank
    // refresh from the saved bytes. No rollback: earlier writes remain when
    // a later stage fails.
    if (!input.synthDefinitions.isEmpty() &&
        !VoicegroupSource::writeSynthDefinitions(m_root, input.synthDefinitions, error))
        return std::nullopt;
    if (!entry.source->save(error))
        return std::nullopt;
    entry.sourceFileTime = QFileInfo(entry.source->filePath()).lastModified();

    const auto rootUtf8 = m_root.toLocal8Bit();
    const auto nameUtf8 = entry.loadName.toLocal8Bit();
    LoadedVoiceGroup *raw = voicegroup_load(rootUtf8.constData(), nameUtf8.constData(), nullptr);
    if (!raw)
        return fail(QStringLiteral("Saved voicegroup failed to reload."));
    entry.current = wrapVoicegroupLease(raw);
    return publishView(entry);
}
