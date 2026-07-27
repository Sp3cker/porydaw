#include <QAction>
#include <QCheckBox>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QListWidget>
#include <QProcess>
#include <QSettings>
#include <QString>
#include <QTemporaryDir>
#include <cstdio>

#include "core/midiimport.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "mainwindow.h"
#include "project/decompproject.h"
#include "project/songregistry.h"
#include "ui/newsongwizard.h"
#include "ui/songlistpanel.h"

// --onboardcheck <projectRoot> [mid2agbPath]: M3 onboarding check. Exercises
// the New Song and Import backends headlessly against a scratch copy of a
// project — it writes into it. Creates a song, verifies its files and sidecar,
// registers it (porydaw writes song_table.inc / songs.h / ld_script.ld /
// charmap.txt directly), verifies idempotency and stale-ID correction, and
// runs an external-MIDI import (analysis + division rescale),
// compiling both songs through the project's real mid2agb.

namespace {

int g_failures = 0;

void check(bool ok, const char *what)
{
    if (!ok) {
        std::fprintf(stderr, "onboardcheck: FAIL: %s\n", what);
        g_failures++;
    }
}

QByteArray readAllBytes(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

bool compilesThroughMid2agb(const QString &mid2agb, const QString &midPath,
                            const QStringList &flags)
{
    QProcess proc;
    const QString outS = midPath.left(midPath.size() - 4) + ".s";
    proc.start(mid2agb, QStringList() << flags << midPath << outS);
    proc.waitForFinished(15000);
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        std::fprintf(stderr, "onboardcheck: mid2agb: %s\n",
                     qUtf8Printable(QString::fromLocal8Bit(proc.readAllStandardError())));
        return false;
    }
    return QFileInfo(outS).size() > 0;
}

// A plausible external MIDI: format 1, division 400 (not a multiple of 24, to
// trip the quantization warning), tempo track plus two instrument tracks with
// programs, audible + inert CCs, and a chord thick enough to trip the
// polyphony warning.
SmfFile makeExternalMidi()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = 400;

    SmfTrack tempo;
    SmfEvent t;
    t.status = 0xFF;
    t.metaType = 0x51;
    t.blob = QByteArray("\x06\x1A\x80", 3); // 150 BPM
    tempo.events.push_back(t);
    tempo.endTick = 480 * 8;
    smf.tracks.push_back(tempo);

    const auto channelEvent = [](uint8_t status, uint64_t tick, uint8_t d0, uint8_t d1) {
        SmfEvent ev;
        ev.status = status;
        ev.tick = tick;
        ev.data0 = d0;
        ev.data1 = d1;
        return ev;
    };

    SmfTrack lead; // channel 0: program 5, mod + volume + an inert CC 91
    lead.events.push_back(channelEvent(0xC0, 0, 5, 0));
    lead.events.push_back(channelEvent(0xB0, 0, 7, 110));
    lead.events.push_back(channelEvent(0xB0, 0, 1, 20));
    lead.events.push_back(channelEvent(0xB0, 0, 91, 64));
    // A 7-note chord: peak polyphony above the 5-channel PCM budget. Ticks
    // must be non-decreasing within the track, so all ons precede all offs.
    for (int i = 0; i < 7; i++)
        lead.events.push_back(channelEvent(0x90, 480, uint8_t(60 + i), 100));
    for (int i = 0; i < 7; i++)
        lead.events.push_back(channelEvent(0x80, 960, uint8_t(60 + i), 0));
    lead.endTick = 480 * 8;
    smf.tracks.push_back(lead);

    SmfTrack bass; // channel 1: two programs, so the mapping table has rows
    bass.events.push_back(channelEvent(0xC1, 0, 20, 0));
    bass.events.push_back(channelEvent(0x91, 0, 36, 90));
    bass.events.push_back(channelEvent(0x81, 480, 36, 0));
    bass.events.push_back(channelEvent(0xC1, 960, 33, 0));
    bass.events.push_back(channelEvent(0x91, 960, 40, 90));
    bass.events.push_back(channelEvent(0x81, 1440, 40, 0));
    bass.endTick = 480 * 8;
    smf.tracks.push_back(bass);
    return smf;
}

} // namespace

int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath)
{
    QString error;
    DecompProject project;
    if (!project.open(projectRoot, &error)) {
        std::fprintf(stderr, "onboardcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    // Only song_table entries count toward the proposed ID; the project may
    // already contain stray unregistered .mid files.
    int registeredCount = 0;
    for (const SongInfo &s : project.songs())
        registeredCount += s.registered ? 1 : 0;
    const QString midiDir = projectRoot + QStringLiteral("/sound/songs/midi");

    QString mid2agb = mid2agbPath;
    if (mid2agb.isEmpty())
        mid2agb = projectRoot + QStringLiteral("/tools/mid2agb/mid2agb");
    const bool haveMid2agb = QFileInfo::exists(mid2agb);
    if (!haveMid2agb)
        std::printf("onboardcheck: note: mid2agb not found, compile checks skipped\n");

    // ---- Project enumeration ------------------------------------------------
    const QStringList vgArgs = SongRegistry::voicegroupArgs(projectRoot);
    check(!vgArgs.isEmpty(), "no voicegroups enumerated");
    std::printf("onboardcheck: %d voicegroups, e.g. %s\n", int(vgArgs.size()),
                vgArgs.isEmpty() ? "-" : qUtf8Printable(vgArgs.first()));
    const QVector<MusicPlayer> players = SongRegistry::musicPlayers(projectRoot);
    check(!players.isEmpty(), "no music players parsed from song_table.inc");

    // ---- Music-player track budgets -----------------------------------------
    // Deterministic fixture regardless of the checkout: swap in a known
    // music_player_table.inc, assert parsing + budget resolution, restore.
    {
        const QString tablePath =
            projectRoot + QStringLiteral("/sound/music_player_table.inc");
        const QByteArray original = readAllBytes(tablePath);
        QFile table(tablePath);
        check(table.open(QIODevice::WriteOnly | QIODevice::Truncate),
              "rewrite music_player_table.inc fixture");
        // BGM overridden to 12 via equiv, SE1 literal, SE2 clamped from a
        // NUM_TRACKS beyond the engine's 16, SE3 via an unknown symbol.
        table.write("\t.equiv NUM_TRACKS_BGM, 12\n"
                    "\t.equiv NUM_TRACKS_SE2, 20\n\n"
                    "gMPlayTable::\n"
                    "\tmusic_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0\n"
                    "\tmusic_player gMPlayInfo_SE1, gMPlayTrack_SE1, 3, 1\n"
                    "\tmusic_player gMPlayInfo_SE2, gMPlayTrack_SE2, NUM_TRACKS_SE2, 1\n"
                    "\tmusic_player gMPlayInfo_SE3, gMPlayTrack_SE3, NUM_TRACKS_WHO, 0\n");
        table.close();

        const QVector<MusicPlayer> budgeted = SongRegistry::musicPlayers(projectRoot);
        auto countFor = [&budgeted](const QString &name) {
            for (const MusicPlayer &p : budgeted) {
                if (p.name == name)
                    return p.trackCount;
            }
            return -2;
        };
        check(countFor(QStringLiteral("MUSIC_PLAYER_BGM")) == 12,
              "BGM budget follows the project's NUM_TRACKS override");
        check(countFor(QStringLiteral("MUSIC_PLAYER_SE1")) == 3,
              "literal track count parsed");
        check(countFor(QStringLiteral("MUSIC_PLAYER_SE2")) == 16,
              "budget clamped to the engine's 16 like MPlayOpen");
        check(countFor(QStringLiteral("MUSIC_PLAYER_SE3")) == -1,
              "unresolvable count stays unknown");

        DecompProject budgetProject;
        check(budgetProject.open(projectRoot, &error), "reopen for budgets");
        SongInfo bgmSong;
        bgmSong.player = QStringLiteral("MUSIC_PLAYER_BGM");
        check(budgetProject.trackBudgetFor(bgmSong) == 12,
              "trackBudgetFor resolves the song's player");
        bgmSong.player = QStringLiteral("MUSIC_PLAYER_SE3");
        check(budgetProject.trackBudgetFor(bgmSong) == 16,
              "unknown budget falls back to the engine ceiling");

        if (original.isEmpty()) {
            QFile::remove(tablePath);
        } else {
            check(table.open(QIODevice::WriteOnly | QIODevice::Truncate),
                  "restore music_player_table.inc");
            table.write(original);
            table.close();
        }
    }

    // ---- New Song flow ------------------------------------------------------
    const QString label = QStringLiteral("mus_onboardcheck");
    const QString constant = SongRegistry::constantForLabel(label);
    check(constant == QStringLiteral("MUS_ONBOARDCHECK"), "constantForLabel");

    SongCfg cfg;
    cfg.exactGate = true;
    cfg.reverb = 50;
    cfg.masterVolume = 100;
    cfg.voicegroupArg = vgArgs.isEmpty() ? QStringLiteral("_dummy") : vgArgs.first();
    cfg.rawFlags = SongRegistry::mergeCfgFlags(cfg);

    const SmfFile blank = SongRegistry::blankSong();
    const QString midPath = midiDir + QStringLiteral("/%1.mid").arg(label);
    check(blank.writeFile(midPath, &error), "write blank .mid");
    check(SongRegistry::writeMidiCfgLine(midiDir, label, cfg.rawFlags, &error),
          "write midi.cfg line");
    check(SongRegistry::saveRegistrationMeta(projectRoot, label, constant,
                                             QStringLiteral("MUSIC_PLAYER_BGM")),
          "save sidecar meta");

    // The new song must surface on reload: unregistered, playable, cfg parsed.
    check(project.reload(&error), "project reload after create");
    const SongInfo *created = nullptr;
    for (const SongInfo &s : project.songs()) {
        if (s.label == label)
            created = &s;
    }
    check(created != nullptr, "created song not discovered on reload");
    if (created) {
        check(!created->registered, "created song should be unregistered");
        check(created->isPlayable(), "created song not playable");
        check(created->hasCfg && created->cfg.voicegroupArg == cfg.voicegroupArg,
              "created song cfg line not parsed back");
        check(created->constant == constant && created->player == QStringLiteral("MUSIC_PLAYER_BGM"),
              "sidecar registration meta not recalled");

        SongDocument doc;
        check(doc.load(*created, &error), "created song fails to open as a document");
    }

    RegistrationStatus status = SongRegistry::checkRegistration(projectRoot, label, constant);
    check(!status.inSongTable && !status.inSongsH && !status.inCharmap
              && !status.complete(),
          "fresh song already looks registered");

    RegistrationPlan plan = SongRegistry::makePlan(projectRoot, label, constant,
                                                   QStringLiteral("MUSIC_PLAYER_BGM"));
    check(plan.songId == registeredCount, "proposed song ID != registered song count");
    check(plan.songTableLine.contains(QStringLiteral("song mus_onboardcheck, MUSIC_PLAYER_BGM, 0")),
          "song_table line malformed");
    check(plan.songsHLine.startsWith(QStringLiteral("#define MUS_ONBOARDCHECK"))
              && plan.songsHLine.endsWith(QString::number(plan.songId)),
          "songs.h line malformed");

    // charmap.txt: the constant maps to the ID as little-endian hex bytes.
    const QString charmapPath = projectRoot + QStringLiteral("/charmap.txt");
    const QString charmapBytes =
        QStringLiteral("%1 %2")
            .arg(plan.songId & 0xFF, 2, 16, QLatin1Char('0'))
            .arg((plan.songId >> 8) & 0xFF, 2, 16, QLatin1Char('0'))
            .toUpper();
    check(plan.charmapApplicable, "charmap.txt song section not detected");
    check(plan.charmapLine.startsWith(constant)
              && plan.charmapLine.endsWith(QStringLiteral("= ") + charmapBytes),
          "charmap line malformed");

    // A column-aligned sound section (pokeruby, pokefirered) pads "=" into a
    // shared column, and non-song two-byte entries don't disturb the anchor
    // or the alignment. Fixture-swap a tiny aligned charmap and re-plan.
    {
        const QByteArray original = readAllBytes(charmapPath);
        const QByteArray fixtureLine = "MUS_DUMMY                 = 00 00";
        QFile cm(charmapPath);
        check(cm.open(QIODevice::WriteOnly | QIODevice::Truncate),
              "rewrite charmap.txt fixture");
        cm.write(fixtureLine + "\n"
                 "MUS_LITTLEROOT_TEST       = 5E 01\n"
                 "PKMN = 53 54\n");
        cm.close();
        const RegistrationPlan aligned = SongRegistry::makePlan(
            projectRoot, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
        check(aligned.charmapApplicable, "aligned fixture: section not detected");
        const int equalsColumn = fixtureLine.indexOf('=');
        check(aligned.charmapLine
                  == constant + QString(equalsColumn - constant.size(), QLatin1Char(' '))
                         + QStringLiteral("= ") + charmapBytes,
              "aligned fixture: charmap line not padded to the '=' column");
        check(cm.open(QIODevice::WriteOnly | QIODevice::Truncate),
              "restore charmap.txt");
        cm.write(original);
        cm.close();
    }

    // porydaw writes the registration files itself.
    QString regError;
    int songId = -1;
    check(SongRegistry::registerSong(projectRoot, label, constant,
                                     QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                     &songId),
          "registerSong failed");
    if (!regError.isEmpty())
        std::fprintf(stderr, "onboardcheck: registerSong: %s\n", qUtf8Printable(regError));
    check(songId == registeredCount, "registered song ID != registered song count");

    status = SongRegistry::checkRegistration(projectRoot, label, constant);
    check(status.complete(), "registration incomplete after registerSong");

    const QString tablePath = projectRoot + QStringLiteral("/sound/song_table.inc");
    const QString songsHPath = projectRoot + QStringLiteral("/include/constants/songs.h");
    const QString ldPath = projectRoot + QStringLiteral("/ld_script.ld");
    if (plan.ldApplicable)
        check(readAllBytes(ldPath).contains(
                  QStringLiteral("sound/songs/midi/%1.o").arg(label).toUtf8()),
              "ld_script.ld missing the song's object line");
    if (plan.charmapApplicable)
        check(readAllBytes(charmapPath).contains(plan.charmapLine.toUtf8()),
              "charmap.txt missing the song's ID mapping");

    // Registering again must be a byte-level no-op.
    const QByteArray tableBefore = readAllBytes(tablePath);
    const QByteArray songsHBefore = readAllBytes(songsHPath);
    const QByteArray ldBefore = readAllBytes(ldPath);
    const QByteArray charmapBefore = readAllBytes(charmapPath);
    check(SongRegistry::registerSong(projectRoot, label, constant,
                                     QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                     &songId),
          "second registerSong failed");
    check(songId == registeredCount, "song ID drifted on re-register");
    check(readAllBytes(tablePath) == tableBefore
              && readAllBytes(songsHPath) == songsHBefore
              && readAllBytes(ldPath) == ldBefore
              && readAllBytes(charmapPath) == charmapBefore,
          "re-register was not byte-identical");

    // A songs.h define whose ID drifted from the table index gets corrected.
    {
        QByteArray tampered = songsHBefore;
        const QByteArray goodDefine =
            QStringLiteral("#define %1").arg(constant).toUtf8();
        const int at = tampered.indexOf(goodDefine);
        check(at >= 0, "tamper: define not found");
        int digits = tampered.indexOf('\n', at);
        QByteArray line = tampered.mid(at, digits - at);
        line.replace(QByteArray::number(songId), QByteArray::number(songId + 500));
        tampered.replace(at, digits - at, line);
        QFile out(songsHPath);
        check(out.open(QIODevice::WriteOnly) && out.write(tampered) == tampered.size(),
              "tamper: rewrite songs.h");
        out.close();

        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(!status.inSongsH, "stale define not detected");
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                         &songId),
              "registerSong after tamper failed");
        check(readAllBytes(songsHPath) == songsHBefore, "stale define not corrected");
    }

    // Likewise a charmap.txt entry whose ID bytes drifted.
    if (plan.charmapApplicable) {
        QByteArray tampered = charmapBefore;
        const int at = tampered.indexOf(plan.charmapLine.toUtf8());
        check(at >= 0, "charmap tamper: entry not found");
        QByteArray line = plan.charmapLine.toUtf8();
        line.replace(charmapBytes.toUtf8(), QByteArrayLiteral("FF 7F"));
        tampered.replace(at, plan.charmapLine.size(), line);
        QFile out(charmapPath);
        check(out.open(QIODevice::WriteOnly) && out.write(tampered) == tampered.size(),
              "charmap tamper: rewrite charmap.txt");
        out.close();

        status = SongRegistry::checkRegistration(projectRoot, label, constant);
        check(!status.inCharmap, "stale charmap bytes not detected");
        check(SongRegistry::registerSong(projectRoot, label, constant,
                                         QStringLiteral("MUSIC_PLAYER_BGM"), &regError,
                                         &songId),
              "registerSong after charmap tamper failed");
        check(readAllBytes(charmapPath) == charmapBefore,
              "stale charmap bytes not corrected");
    }

    check(project.reload(&error), "project reload after registration");
    const SongInfo *registered = nullptr;
    for (const SongInfo &s : project.songs()) {
        if (s.label == label)
            registered = &s;
    }
    check(registered && registered->registered, "song not registered after registerSong");
    check(registered && registered->id == registeredCount, "registered song ID wrong");
    check(registered && registered->constant == constant,
          "constant not matched from songs.h");

    // ---- charmap ID-ordered backfill -----------------------------------------
    // A mid-table song whose charmap line went missing gets it reinserted at
    // its ID position between its neighbors, not appended — proven by the
    // file round-tripping byte-identically through strip + re-register.
    if (plan.charmapApplicable) {
        const QByteArray original = readAllBytes(charmapPath);
        QList<QByteArray> lines = original.split('\n');
        const SongInfo *midSong = nullptr;
        int lineAt = -1;
        for (int id = registeredCount / 2; id < registeredCount && !midSong; id++) {
            const SongInfo &s = project.songs().at(id);
            if (!s.registered || s.constant.isEmpty())
                continue;
            // The song's own line, and only one of it (alias constants that
            // share an ID would make the strip ambiguous).
            int found = -1, hits = 0;
            for (int i = 0; i < lines.size(); i++) {
                if (lines[i].startsWith(s.constant.toUtf8() + ' ')) {
                    found = i;
                    hits++;
                }
            }
            if (hits == 1) {
                midSong = &s;
                lineAt = found;
            }
        }
        check(midSong != nullptr, "ordered backfill: no mid-table candidate song");
        if (midSong) {
            lines.removeAt(lineAt);
            QFile out(charmapPath);
            check(out.open(QIODevice::WriteOnly), "ordered backfill: rewrite charmap.txt");
            out.write(lines.join('\n'));
            out.close();
            check(readAllBytes(charmapPath) != original,
                  "ordered backfill: strip was a no-op");
            check(SongRegistry::registerSong(
                      projectRoot, midSong->label, midSong->constant,
                      midSong->player.isEmpty() ? QStringLiteral("MUSIC_PLAYER_BGM")
                                                : midSong->player,
                      &regError, &songId),
                  "ordered backfill: registerSong failed");
            check(readAllBytes(charmapPath) == original,
                  "backfilled charmap line not restored at its ID position");
        }
    }

    // ---- Register Song action wiring ----------------------------------------
    // Strip the song's charmap line — the state of any song registered before
    // porydaw wrote charmap entries. The song still reads as registered from
    // the song table, but File → Register Song must stay enabled, and running
    // it must backfill the line byte-identically.
    if (plan.charmapApplicable) {
        const QByteArray full = readAllBytes(charmapPath);
        QByteArray stripped = full;
        const int at = stripped.indexOf(plan.charmapLine.toUtf8());
        check(at >= 0, "action check: charmap entry not found");
        int end = stripped.indexOf('\n', at);
        end = end < 0 ? stripped.size() : end + 1;
        stripped.remove(at, end - at);
        QFile out(charmapPath);
        check(out.open(QIODevice::WriteOnly) && out.write(stripped) == stripped.size(),
              "action check: rewrite charmap.txt");
        out.close();

        // Redirected settings: the user's real session is never touched.
        QTemporaryDir settingsDir;
        check(settingsDir.isValid(), "action check: no temp dir for settings");
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope,
                           settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                           settingsDir.path());
        MainWindow window;
        check(window.runRegisterActionCheck(projectRoot, label),
              "register-action check did not run");
        check(readAllBytes(charmapPath) == full,
              "backfill did not restore charmap.txt byte-identically");
    }

    if (haveMid2agb)
        check(compilesThroughMid2agb(mid2agb, midPath, cfg.rawFlags),
              "blank new song does not compile through mid2agb");

    // ---- Import flow --------------------------------------------------------
    const SmfFile external = makeExternalMidi();
    ImportAnalysis analysis = analyzeForImport(external);
    check(analysis.mappedTracks == 2, "import: mapped track count");
    check(analysis.peakConcurrentNotes == 7, "import: peak polyphony");
    bool sawDivisionWarning = false, sawPolyWarning = false;
    for (const QString &w : analysis.warnings) {
        if (w.contains(QStringLiteral("Division")))
            sawDivisionWarning = true;
        if (w.contains(QStringLiteral("at once")))
            sawPolyWarning = true;
    }
    check(sawDivisionWarning, "import: no division warning for 480 ppqn");
    check(sawPolyWarning, "import: no polyphony warning for 7-note chord");
    bool sawMod = false, sawInert = false;
    for (const ImportCcUsage &cc : analysis.ccs) {
        if (cc.cc == 1)
            sawMod = cc.audible;
        if (cc.cc == 91)
            sawInert = !cc.audible;
    }
    check(sawMod, "import: CC1 not classified audible");
    check(sawInert, "import: CC91 not classified inert");
    check(analysis.tracks.size() == 2 && analysis.tracks[1].programs.size() == 2,
          "import: per-track program usage");
    check(analysis.silentTracks == 0, "import: no budget warning at default 16");

    // Track-budget warning: with a 1-track player, the second mapped track is
    // silent in-game and the warning names the player and its allocation.
    {
        const ImportAnalysis tight =
            analyzeForImport(external, 1, QStringLiteral("MUSIC_PLAYER_BGM"));
        check(tight.silentTracks == 1, "import: silent track counted");
        bool sawBudgetWarning = false;
        for (const QString &w : tight.warnings) {
            if (w.contains(QStringLiteral("MUSIC_PLAYER_BGM"))
                && w.contains(QStringLiteral("silent in-game")))
                sawBudgetWarning = true;
        }
        check(sawBudgetWarning, "import: budget warning names the player");
        check(analyzeForImport(external, -1).silentTracks == 0,
              "import: unknown budget warns about nothing");
    }

    SmfFile imported = external;

    // Division rescale onto the 24-clock grid (the wizard's default for a
    // non-multiple-of-24 file). Floor arithmetic matches mid2agb, so the
    // chord's onset lands where an as-is import would have played it:
    // 480 * 24 / 400 = 28.8 -> 28, offs 960 -> 57, EOT 3840 -> 230.
    rescaleDivision(&imported, 24);
    check(imported.division == 24, "rescale: division not rewritten");
    check(imported.tracks[1].events[4].tick == 28, "rescale: note-on tick");
    check(imported.tracks[1].events[11].tick == 57, "rescale: note-off tick");
    check(imported.tracks[1].endTick == 230, "rescale: end-of-track tick");
    check(imported.tracks[2].events[0].tick == 0, "rescale: tick-0 event moved");
    for (const SmfTrack &track : imported.tracks) {
        uint64_t prev = 0;
        for (const SmfEvent &ev : track.events) {
            check(ev.tick >= prev, "rescale: tick order regressed");
            prev = ev.tick;
        }
    }

    // The wizard end of the same option: the analysis page offers the rescale
    // (default on) and songFile() applies it with the Sound page's clock base.
    {
        NewSongWizard wizard(&project, external, QStringLiteral("ext.mid"), vgArgs);
        auto *rescale = wizard.page(0)->findChild<QCheckBox *>();
        check(rescale && rescale->isChecked(),
              "wizard: rescale checkbox missing or off for division 400");
        check(wizard.songFile().division == 24,
              "wizard: songFile() not rescaled by default");
        if (rescale) {
            rescale->setChecked(false);
            check(wizard.songFile().division == 400,
                  "wizard: opting out of the rescale still rescaled");
        }
    }

    const QString importLabel = QStringLiteral("mus_onboardcheck_import");
    const QString importMid = midiDir + QStringLiteral("/%1.mid").arg(importLabel);
    check(imported.writeFile(importMid, &error), "write imported .mid");
    check(SongRegistry::writeMidiCfgLine(midiDir, importLabel, cfg.rawFlags, &error),
          "write imported midi.cfg line");

    SmfFile reread;
    check(SmfFile::readFile(importMid, &reread, &error)
              && reread.tracks.size() == imported.tracks.size()
              && reread.division == 24,
          "imported .mid does not re-read cleanly");

    check(project.reload(&error), "project reload after import");
    const SongInfo *importedSong = nullptr;
    for (const SongInfo &s : project.songs()) {
        if (s.label == importLabel)
            importedSong = &s;
    }
    check(importedSong && importedSong->isPlayable() && !importedSong->registered,
          "imported song not discovered");
    if (importedSong) {
        SongDocument doc;
        check(doc.load(*importedSong, &error), "imported song fails to open");
        check(doc.engineTrackCount() == 2, "imported song engine track count");
    }

    if (haveMid2agb)
        check(compilesThroughMid2agb(mid2agb, importMid, cfg.rawFlags),
              "imported song does not compile through mid2agb");

    // ---- Delete Song --------------------------------------------------------
    // The inverse of the flows above. A full create→register→delete cycle
    // must leave every file byte-identical; a mid-table delete leaves a
    // marked free slot that keeps later IDs stable and is reused by the next
    // registration; entry 0 (the fallback song) is untouchable either way.
    const QString cfgPath = midiDir + QStringLiteral("/midi.cfg");
    QString firstLabel; // the song table's entry 0
    {
        const QByteArray table0 = readAllBytes(tablePath);
        const QByteArray songsH0 = readAllBytes(songsHPath);
        const QByteArray ld0 = readAllBytes(ldPath);
        const QByteArray charmap0 = readAllBytes(charmapPath);
        const QByteArray cfg0 = readAllBytes(cfgPath);

        static const QRegularExpression firstSongRe(
            QStringLiteral(R"(^\s*song\s+(\w+))"));
        int firstSongLine = -1;
        const QList<QByteArray> tableLines = table0.split('\n');
        for (int i = 0; i < tableLines.size() && firstLabel.isEmpty(); i++) {
            const QRegularExpressionMatch m =
                firstSongRe.match(QString::fromUtf8(tableLines[i]));
            if (m.hasMatch()) {
                firstLabel = m.captured(1);
                firstSongLine = i;
            }
        }
        check(!firstLabel.isEmpty(), "delete: no entry 0 in song_table.inc");

        const QString labelA = QStringLiteral("mus_onboardcheck_del_a");
        const QString labelB = QStringLiteral("mus_onboardcheck_del_b");
        const QString labelC = QStringLiteral("mus_onboardcheck_del_c");
        const auto createAndRegister = [&](const QString &lab, int *id) {
            const SmfFile smf = SongRegistry::blankSong();
            check(smf.writeFile(midiDir + QStringLiteral("/%1.mid").arg(lab), &error),
                  "delete: write .mid");
            check(SongRegistry::writeSongFlags(midiDir, lab, cfg.rawFlags, &error),
                  "delete: write flags");
            check(SongRegistry::registerSong(projectRoot, lab,
                                             SongRegistry::constantForLabel(lab),
                                             QStringLiteral("MUSIC_PLAYER_BGM"),
                                             &regError, id),
                  "delete: registerSong failed");
        };
        const auto deleteSong = [&](const QString &lab) {
            QString err;
            check(SongRegistry::unregisterSong(projectRoot, lab,
                                               SongRegistry::constantForLabel(lab),
                                               &err),
                  "delete: unregisterSong failed");
            check(SongRegistry::removeSongFlags(midiDir, lab, &err),
                  "delete: removeSongFlags failed");
            check(QFile::remove(midiDir + QStringLiteral("/%1.mid").arg(lab)),
                  "delete: remove .mid");
        };

        int idA = -1, idB = -1, idC = -1;
        createAndRegister(labelA, &idA);
        createAndRegister(labelB, &idB);
        check(idB == idA + 1, "delete: fresh registrations not sequential");

        // Mid-table delete: A leaves a marked free slot; B keeps its ID.
        deleteSong(labelA);
        const QByteArray marker = SongRegistry::freeSlotMarker().toUtf8();
        check(readAllBytes(tablePath).contains(marker),
              "mid-table delete left no free-slot marker");
        check(!readAllBytes(songsHPath).contains("MUS_ONBOARDCHECK_DEL_A"),
              "deleted song's define still in songs.h");
        check(!readAllBytes(ldPath).contains("mus_onboardcheck_del_a.o"),
              "deleted song's object line still in ld_script.ld");
        check(!readAllBytes(charmapPath).contains("MUS_ONBOARDCHECK_DEL_A"),
              "deleted song's charmap entry still present");
        check(!readAllBytes(cfgPath).contains("mus_onboardcheck_del_a.mid"),
              "deleted song's midi.cfg line still present");
        RegistrationStatus after = SongRegistry::checkRegistration(
            projectRoot, labelB, SongRegistry::constantForLabel(labelB));
        check(after.complete(), "surviving song's registration broke on delete");
        // The free slot borrows entry 0's label without impersonating it:
        // the fallback song must still read as correctly registered.
        after = SongRegistry::checkRegistration(
            projectRoot, firstLabel, SongRegistry::constantForLabel(firstLabel));
        check(after.inSongTable && after.inSongsH,
              "free slot misattributed the fallback song's table entry");

        // Reuse: the next song is offered the freed ID, and its lines land
        // in ID order (songs.h sorted like the charmap insertion).
        const RegistrationPlan planC =
            SongRegistry::makePlan(projectRoot, labelC,
                                   SongRegistry::constantForLabel(labelC),
                                   QStringLiteral("MUSIC_PLAYER_BGM"));
        check(planC.songId == idA, "free slot not proposed for the next song");
        createAndRegister(labelC, &idC);
        check(idC == idA, "free slot not reused on registration");
        check(!readAllBytes(tablePath).contains(marker), "reused slot kept its marker");
        {
            const QByteArray songsH = readAllBytes(songsHPath);
            const auto defineAt = [&songsH](const char *constant) {
                return songsH.indexOf(QByteArray("#define ") + constant);
            };
            check(defineAt("MUS_ONBOARDCHECK_DEL_C") >= 0
                      && defineAt("MUS_ONBOARDCHECK_DEL_C")
                             < defineAt("MUS_ONBOARDCHECK_DEL_B"),
                  "reused ID's define not inserted in songs.h ID order");
        }
        if (plan.charmapApplicable) {
            const QByteArray charmap = readAllBytes(charmapPath);
            check(charmap.indexOf("MUS_ONBOARDCHECK_DEL_C") >= 0
                      && charmap.indexOf("MUS_ONBOARDCHECK_DEL_C")
                             < charmap.indexOf("MUS_ONBOARDCHECK_DEL_B"),
                  "reused ID's charmap entry not in ID order");
        }

        // Deleting an already-deleted song is a byte-level no-op success.
        {
            const QByteArray t = readAllBytes(tablePath);
            const QByteArray h = readAllBytes(songsHPath);
            QString err;
            check(SongRegistry::unregisterSong(projectRoot, labelA,
                                               SongRegistry::constantForLabel(labelA),
                                               &err),
                  "second unregister failed");
            check(readAllBytes(tablePath) == t && readAllBytes(songsHPath) == h,
                  "second unregister was not byte-identical");
        }

        // Wind back down: C leaves the slot again; B's last-entry delete then
        // collapses the trailing free slot. Everything must round-trip to the
        // pre-cycle bytes.
        deleteSong(labelC);
        check(readAllBytes(tablePath).contains(marker), "re-deleted slot lost its marker");
        deleteSong(labelB);
        check(readAllBytes(tablePath) == table0, "song_table.inc did not round-trip");
        check(readAllBytes(songsHPath) == songsH0, "songs.h did not round-trip");
        check(readAllBytes(ldPath) == ld0, "ld_script.ld did not round-trip");
        check(readAllBytes(charmapPath) == charmap0, "charmap.txt did not round-trip");
        check(readAllBytes(cfgPath) == cfg0, "midi.cfg did not round-trip");

        // Entry 0 is never deletable...
        {
            QString err;
            check(!SongRegistry::unregisterSong(projectRoot, firstLabel,
                                                SongRegistry::constantForLabel(firstLabel),
                                                &err)
                      && !err.isEmpty(),
                  "unregisterSong deleted the fallback song");
            check(readAllBytes(tablePath) == table0, "refused delete still wrote");
        }
        // ...and never a free slot, marker or not.
        if (firstSongLine >= 0) {
            const RegistrationPlan before = SongRegistry::makePlan(
                projectRoot, QStringLiteral("mus_onboardcheck_probe"),
                QStringLiteral("MUS_ONBOARDCHECK_PROBE"),
                QStringLiteral("MUSIC_PLAYER_BGM"));
            QList<QByteArray> tampered = tableLines;
            tampered[firstSongLine] += " " + marker;
            QFile out(tablePath);
            check(out.open(QIODevice::WriteOnly), "tamper: rewrite song_table.inc");
            out.write(tampered.join('\n'));
            out.close();
            const RegistrationPlan probed = SongRegistry::makePlan(
                projectRoot, QStringLiteral("mus_onboardcheck_probe"),
                QStringLiteral("MUS_ONBOARDCHECK_PROBE"),
                QStringLiteral("MUSIC_PLAYER_BGM"));
            check(probed.songId == before.songId && probed.songId != 0,
                  "a marked entry 0 was offered as a free slot");
            QFile restore(tablePath);
            check(restore.open(QIODevice::WriteOnly), "tamper: restore song_table.inc");
            restore.write(table0);
        }

        // An unregistered stray (the imported song): no table entry at all,
        // so deletion is just the .mid and the cfg line.
        {
            QString err;
            check(SongRegistry::unregisterSong(projectRoot, importLabel,
                                               SongRegistry::constantForLabel(importLabel),
                                               &err),
                  "stray unregister failed");
            check(readAllBytes(tablePath) == table0,
                  "stray unregister touched song_table.inc");
            check(SongRegistry::removeSongFlags(midiDir, importLabel, &err),
                  "stray removeSongFlags failed");
            check(!readAllBytes(cfgPath).contains(importLabel.toUtf8() + ".mid"),
                  "stray's midi.cfg line still present");
        }
    }

    // ---- Delete voicegroup --------------------------------------------------
    // deletableVoicegroup gates the offer: sole song user, per-file layout,
    // no keysplit/drumkit reference, no C reference. deleteVoicegroup then
    // inverts createVoicegroup + appendIncludeLine byte-identically.
    {
        const QString hubPath = projectRoot + QStringLiteral("/sound/voice_groups.inc");
        const QByteArray hub0 = readAllBytes(hubPath);
        const QString vgName = QStringLiteral("onboardcheckvg");
        const bool created =
            VoicegroupSource::createVoicegroup(projectRoot, vgName, QString(),
                                               QString(), &error)
            && VoicegroupSource::appendIncludeLine(projectRoot, vgName, &error);
        check(created, "vg delete: createVoicegroup/appendIncludeLine failed");
        if (created) {
            QVector<SongInfo> songs = project.songs();
            SongInfo user;
            user.label = QStringLiteral("mus_vg_user");
            user.cfg.voicegroupArg = QStringLiteral("_onboardcheckvg");
            songs.append(user);
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label)
                      == vgName,
                  "sole-user voicegroup not deletable");

            SongInfo second = user;
            second.label = QStringLiteral("mus_vg_user2");
            songs.append(second);
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label)
                      .isEmpty(),
                  "shared voicegroup offered for deletion");
            songs.removeLast();

            // A keysplit reference from another voicegroup is load-bearing.
            const QString subName = QStringLiteral("onboardchecksub");
            check(VoicegroupSource::createVoicegroup(projectRoot, subName, QString(),
                                                     QString(), &error),
                  "vg delete: create sub voicegroup");
            {
                QFile host(projectRoot
                           + QStringLiteral("/sound/voicegroups/onboardcheckvg.inc"));
                check(host.open(QIODevice::Append), "vg delete: append keysplit line");
                host.write("\tvoice_keysplit voicegroup_onboardchecksub, "
                           "KeySplitTable1\n");
            }
            SongInfo subUser = user;
            subUser.label = QStringLiteral("mus_vg_sub_user");
            subUser.cfg.voicegroupArg = QStringLiteral("_onboardchecksub");
            QVector<SongInfo> subSongs = songs;
            subSongs.append(subUser);
            check(SongRegistry::deletableVoicegroup(projectRoot, subSongs,
                                                    subUser.label)
                      .isEmpty(),
                  "keysplit sub-voicegroup offered for deletion");
            check(VoicegroupSource::deleteVoicegroup(projectRoot, subName, &error),
                  "vg delete: remove sub voicegroup");

            // A C reference would break the link, not merely dangle.
            const QString refPath = projectRoot
                                    + QStringLiteral("/src/onboardcheck_ref.c");
            {
                QFile ref(refPath);
                check(ref.open(QIODevice::WriteOnly), "vg delete: write C ref");
                ref.write("extern int voicegroup_onboardcheckvg[];\n");
            }
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label)
                      .isEmpty(),
                  "C-referenced voicegroup offered for deletion");
            QFile::remove(refPath);
            check(SongRegistry::deletableVoicegroup(projectRoot, songs, user.label)
                      == vgName,
                  "vg delete: dropped C reference not re-detected");

            check(VoicegroupSource::deleteVoicegroup(projectRoot, vgName, &error),
                  "deleteVoicegroup failed");
            check(!QFile::exists(
                      projectRoot
                      + QStringLiteral("/sound/voicegroups/onboardcheckvg.inc")),
                  "voicegroup file survived deletion");
            check(readAllBytes(hubPath) == hub0, "voice_groups.inc did not round-trip");
            check(VoicegroupSource::deleteVoicegroup(projectRoot, vgName, &error),
                  "second deleteVoicegroup failed");
        }
    }

    // ---- Delete action wiring ----------------------------------------------
    // The MainWindow path: deleting an open song closes its tab, drops it
    // from the model and browser, and moves the .mid to .porydaw/trash/.
    {
        const QString delLabel = QStringLiteral("mus_onboardcheck_del_ui");
        const SmfFile smf = SongRegistry::blankSong();
        check(smf.writeFile(midiDir + QStringLiteral("/%1.mid").arg(delLabel), &error),
              "action delete: write .mid");
        check(SongRegistry::writeSongFlags(midiDir, delLabel, cfg.rawFlags, &error),
              "action delete: write flags");
        int id = -1;
        check(SongRegistry::registerSong(projectRoot, delLabel,
                                         SongRegistry::constantForLabel(delLabel),
                                         QStringLiteral("MUSIC_PLAYER_BGM"),
                                         &regError, &id),
              "action delete: registerSong failed");

        QTemporaryDir settingsDir;
        check(settingsDir.isValid(), "action delete: no temp dir for settings");
        QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope,
                           settingsDir.path());
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                           settingsDir.path());
        MainWindow window;
        check(window.runDeleteActionCheck(projectRoot, delLabel),
              "delete-action check did not run");
    }

    std::printf("onboardcheck: %s (%d failures)\n", g_failures ? "FAIL" : "PASS",
                g_failures);
    return g_failures ? 1 : 0;
}

bool MainWindow::runRegisterActionCheck(const QString &projectRoot, const QString &label)
{
    m_persistSession = false;
    if (!openProjectDir(projectRoot, /*interactive=*/false)) {
        std::fprintf(stderr, "onboardcheck: project failed to open in MainWindow\n");
        return false;
    }
    loadSongByLabel(label);
    if (!m_active || m_active->doc.label() != label) {
        std::fprintf(stderr, "onboardcheck: '%s' did not load in MainWindow\n",
                     qUtf8Printable(label));
        return false;
    }
    check(m_registerAction->isEnabled(),
          "Register Song disabled for a song missing its charmap entry");

    // The model carries the gap and the song browser badges it.
    const auto findSong = [this](const QString &wanted) -> const SongInfo * {
        for (const SongInfo &s : m_project.songs()) {
            if (s.label == wanted)
                return &s;
        }
        return nullptr;
    };
    const SongInfo *info = findSong(label);
    check(info && info->registered,
          "partially registered song no longer counts as table-registered");
    check(info
              && info->registrationGaps
                     == QStringList{QStringLiteral("charmap.txt")},
          "registrationGaps does not name the stripped charmap entry");
    auto *list = m_songList->findChild<QListWidget *>();
    const auto itemFor = [list](int id) -> QListWidgetItem * {
        for (int i = 0; list && i < list->count(); i++) {
            if (list->item(i)->data(Qt::UserRole).toInt() == id)
                return list->item(i);
        }
        return nullptr;
    };
    QListWidgetItem *item = info ? itemFor(info->id) : nullptr;
    check(item && item->text().contains(QStringLiteral("not fully registered")),
          "song list shows no badge for a partial registration");

    // The context menu's Register Song path heals the registration.
    if (info)
        registerSongById(info->id);
    check(!m_registerAction->isEnabled(), "Register Song still enabled after backfill");
    info = findSong(label);
    check(info && info->registrationGaps.isEmpty(),
          "registration gaps not cleared by the backfill");
    item = info ? itemFor(info->id) : nullptr;
    check(item && item->text() == label, "badge not cleared after the backfill");
    // A fresh activation recomputes the enable state from the reloaded songs.
    activateSession(m_active, /*force=*/true);
    check(!m_registerAction->isEnabled(),
          "re-activation re-enabled Register Song for a complete registration");
    return true;
}

bool MainWindow::runDeleteActionCheck(const QString &projectRoot, const QString &label)
{
    m_persistSession = false;
    if (!openProjectDir(projectRoot, /*interactive=*/false)) {
        std::fprintf(stderr, "onboardcheck: project failed to open in MainWindow\n");
        return false;
    }
    loadSongByLabel(label);
    if (!m_active || m_active->doc.label() != label) {
        std::fprintf(stderr, "onboardcheck: '%s' did not load in MainWindow\n",
                     qUtf8Printable(label));
        return false;
    }
    const SongInfo *info = nullptr;
    for (const SongInfo &s : m_project.songs()) {
        if (s.label == label)
            info = &s;
    }
    if (!info) {
        std::fprintf(stderr, "onboardcheck: '%s' not in the project model\n",
                     qUtf8Printable(label));
        return false;
    }
    const SongInfo song = *info; // survives the reload inside the deletion

    QString error;
    check(performSongDeletion(song, QString(), &error), "performSongDeletion failed");
    if (!error.isEmpty())
        std::fprintf(stderr, "onboardcheck: delete: %s\n", qUtf8Printable(error));
    check(!sessionForLabel(label), "deleted song's tab still open");
    bool inModel = false;
    for (const SongInfo &s : m_project.songs())
        inModel = inModel || s.label == label;
    check(!inModel, "deleted song still in the project model");
    auto *list = m_songList->findChild<QListWidget *>();
    bool listed = false;
    for (int i = 0; list && i < list->count(); i++)
        listed = listed || list->item(i)->text().startsWith(label);
    check(!listed, "deleted song still listed in the browser");
    check(!QFile::exists(projectRoot
                         + QStringLiteral("/sound/songs/midi/%1.mid").arg(label)),
          "deleted song's .mid still in sound/songs/midi");
    check(QFile::exists(projectRoot + QStringLiteral("/.porydaw/trash/%1.mid").arg(label)),
          "deleted song's .mid not moved to .porydaw/trash");

    // The fallback song refuses deletion end to end, before any file edit.
    const SongInfo *fallback = nullptr;
    for (const SongInfo &s : m_project.songs()) {
        if (s.registered && s.id == 0)
            fallback = &s;
    }
    if (fallback) {
        const QByteArray tableBefore = readAllBytes(
            projectRoot + QStringLiteral("/sound/song_table.inc"));
        const QString fallbackMid =
            projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(fallback->label);
        const bool hadMid = QFile::exists(fallbackMid);
        QString refuse;
        check(!performSongDeletion(*fallback, QString(), &refuse) && !refuse.isEmpty(),
              "performSongDeletion deleted the fallback song");
        check(readAllBytes(projectRoot + QStringLiteral("/sound/song_table.inc"))
                  == tableBefore,
              "refused fallback delete still edited song_table.inc");
        check(QFile::exists(fallbackMid) == hadMid,
              "refused fallback delete still moved the .mid");
    }
    return true;
}
