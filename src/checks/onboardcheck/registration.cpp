#include "checks/onboardcheck/onboardingtest.h"

#include "checks/support/songfixture.h"
#include "core/songdocument.h"

namespace {
QString songPath(const QString &root, const QString &label)
{
    return root + QStringLiteral("/sound/songs/midi/%1.mid").arg(label);
}

QString cfgPath(const QString &root)
{
    return root + QStringLiteral("/sound/songs/midi/midi.cfg");
}

QString tablePath(const QString &root)
{
    return root + QStringLiteral("/sound/song_table.inc");
}

QString songsHeaderPath(const QString &root)
{
    return root + QStringLiteral("/include/constants/songs.h");
}

QByteArray define(const char *name, int value)
{
    return QByteArray("#define ") + name + ' ' + QByteArray::number(value) + '\n';
}

QByteArray song(const char *label)
{
    return QByteArray("\tsong ") + label + ", MUSIC_PLAYER_BGM, 0\n";
}
} // namespace

void OnboardingTest::newSongRegistration_data()
{
    QTest::addColumn<bool>("alignedCharmap");
    QTest::addColumn<QString>("healing");
    QTest::newRow("normal") << false << QString();
    QTest::newRow("aligned") << true << QString();
    QTest::newRow("heal-songs-h") << false << QStringLiteral("songs.h");
    QTest::newRow("heal-charmap") << false << QStringLiteral("charmap");
    QTest::newRow("reregister") << false << QStringLiteral("reregister");
}

void OnboardingTest::newSongRegistration()
{
    QFETCH(bool, alignedCharmap);
    QFETCH(QString, healing);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    DecompProject project;
    QVERIFY2(project.open(root, &error), qPrintable(error));
    const int baseline = registeredCount(project);
    SongCfg cfg;
    QVERIFY2(defaultCfg(root, cfg, error), qPrintable(error));
    const QString label = QStringLiteral("mus_onboardcheck");
    const QString constant = SongRegistry::constantForLabel(label);
    QCOMPARE(constant, QStringLiteral("MUS_ONBOARDCHECK"));
    QVERIFY2(SongRegistry::blankSong().writeFile(songPath(root, label), &error), qPrintable(error));
    QVERIFY2(SongRegistry::writeMidiCfgLine(midiDirectory(root), label, cfg.rawFlags, &error),
             qPrintable(error));
    QVERIFY2(project.reload(&error), qPrintable(error));

    const SongInfo *created = nullptr;
    for (const SongInfo &song : project.songs())
        if (song.label == label)
            created = &song;
    QVERIFY(created);
    QVERIFY(!created->registered);
    QVERIFY(created->isPlayable());
    QVERIFY(created->hasCfg);
    QCOMPARE(created->cfg.voicegroupArg, cfg.voicegroupArg);
    QCOMPARE(created->constant, constant);
    QCOMPARE(created->player, QStringLiteral("MUSIC_PLAYER_BGM"));
    SongDocument document;
    QVERIFY2(document.load(*created, &error), qPrintable(error));

    RegistrationStatus status = SongRegistry::checkRegistration(root, label, constant);
    QVERIFY(!status.inSongTable && !status.inSongsH && !status.inCharmap && !status.complete());
    RegistrationPlan plan =
        SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
    QCOMPARE(plan.songId, baseline);
    QCOMPARE(plan.songTableLine, QStringLiteral("\tsong mus_onboardcheck, MUSIC_PLAYER_BGM, 0"));
    QVERIFY(plan.songsHLine.startsWith(QStringLiteral("#define MUS_ONBOARDCHECK")));
    QVERIFY(plan.songsHLine.endsWith(QString::number(baseline)));

    const QString charmap = root + QStringLiteral("/charmap.txt");
    const QByteArray originalCharmap = readFile(charmap, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(plan.charmapApplicable);
    const QString bytes = QStringLiteral("%1 %2")
                              .arg(baseline & 0xff, 2, 16, QLatin1Char('0'))
                              .arg((baseline >> 8) & 0xff, 2, 16, QLatin1Char('0'))
                              .toUpper();
    QCOMPARE(plan.charmapLine, constant + QStringLiteral(" = ") + bytes);
    if (alignedCharmap) {
        const QByteArray aligned = QByteArrayLiteral("MUS_DUMMY                 = 00 00\n"
                                                     "MUS_LITTLEROOT_TEST       = 5E 01\n"
                                                     "PKMN = 53 54\n");
        QVERIFY2(writeFile(charmap, aligned, error), qPrintable(error));
        const RegistrationPlan alignedPlan =
            SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
        QCOMPARE(alignedPlan.charmapLine, constant +
                                              QString(26 - constant.size(), QLatin1Char(' ')) +
                                              QStringLiteral("= ") + bytes);
        QVERIFY2(writeFile(charmap, originalCharmap, error), qPrintable(error));
        plan = SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
    }

    int id = -1;
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    QCOMPARE(id, baseline);
    QVERIFY(SongRegistry::checkRegistration(root, label, constant).complete());
    if (plan.ldApplicable) {
        const QByteArray linker = readFile(root + QStringLiteral("/ld_script.ld"), error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(linker.contains("sound/songs/midi/mus_onboardcheck.o"));
    }
    const QByteArray registeredCharmap = readFile(charmap, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(registeredCharmap.contains(plan.charmapLine.toUtf8()));

    const QByteArray table = readFile(tablePath(root), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray header = readFile(songsHeaderPath(root), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray linker =
        plan.ldApplicable ? readFile(root + QStringLiteral("/ld_script.ld"), error) : QByteArray{};
    QVERIFY2(error.isEmpty(), qPrintable(error));
    if (healing == QStringLiteral("songs.h")) {
        QByteArray corrupted = header;
        const int at = corrupted.indexOf("#define MUS_ONBOARDCHECK");
        QVERIFY(at >= 0);
        const int end = corrupted.indexOf('\n', at);
        QVERIFY(end >= at);
        corrupted.replace(at, end - at, QByteArrayLiteral("#define MUS_ONBOARDCHECK 9999"));
        QVERIFY2(writeFile(songsHeaderPath(root), corrupted, error), qPrintable(error));
        QVERIFY(!SongRegistry::checkRegistration(root, label, constant).inSongsH);
    } else if (healing == QStringLiteral("charmap")) {
        QByteArray corrupted = registeredCharmap;
        QByteArray replacement = plan.charmapLine.toUtf8();
        replacement.replace(bytes.toUtf8(), "FF 7F");
        QVERIFY(corrupted.contains(plan.charmapLine.toUtf8()));
        corrupted.replace(plan.charmapLine.toUtf8(), replacement);
        QVERIFY2(writeFile(charmap, corrupted, error), qPrintable(error));
        QVERIFY(!SongRegistry::checkRegistration(root, label, constant).inCharmap);
    }
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    QCOMPARE(id, baseline);
    QCOMPARE(readFile(tablePath(root), error), table);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(readFile(songsHeaderPath(root), error), header);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    if (plan.ldApplicable) {
        QCOMPARE(readFile(root + QStringLiteral("/ld_script.ld"), error), linker);
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
    QCOMPARE(readFile(charmap, error), registeredCharmap);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(project.reload(&error), qPrintable(error));
    const SongInfo *registered = nullptr;
    for (const SongInfo &song : project.songs())
        if (song.label == label)
            registered = &song;
    QVERIFY(registered && registered->registered);
    QCOMPARE(registered->id, baseline);
    QCOMPARE(registered->constant, constant);
}

void OnboardingTest::registrationBackfill_data()
{
    QTest::addColumn<QString>("file");
    QTest::newRow("charmap") << QStringLiteral("charmap");
    QTest::newRow("songs-h") << QStringLiteral("songs.h");
}

void OnboardingTest::registrationBackfill()
{
    QFETCH(QString, file);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    const QString table = root + QStringLiteral("/sound/song_table.inc");
    const QString header = songsHeaderPath(root);
    const QString charmap = root + QStringLiteral("/charmap.txt");
    const QByteArray tableBytes = QByteArrayLiteral("gSongTable::\n") + song("mus_zero") +
                                  song("mus_first") + song("mus_last");
    const QByteArray headerBytes = define("MUS_ZERO", 0) + define("MUS_FIRST", 1) +
                                   define("MUS_LAST", 2) +
                                   QByteArrayLiteral("#define MUS_NONE 0xFFFF\n");
    const QByteArray charmapBytes =
        QByteArrayLiteral("MUS_ZERO = 00 00\nMUS_FIRST = 01 00\nMUS_LAST = 02 00\n");
    QVERIFY2(writeFile(table, tableBytes, error), qPrintable(error));
    QVERIFY2(writeFile(header, headerBytes, error), qPrintable(error));
    QVERIFY2(writeFile(charmap, charmapBytes, error), qPrintable(error));
    const QString label = QStringLiteral("mus_first");
    const QString constant = QStringLiteral("MUS_FIRST");
    const QString path = file == QStringLiteral("charmap") ? charmap : header;
    const QByteArray original = readFile(path, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray needle = file == QStringLiteral("charmap")
                                  ? constant.toUtf8()
                                  : QByteArray("#define ") + constant.toUtf8();
    const int start = original.indexOf(needle);
    QVERIFY(start > 0);
    const int end = original.indexOf('\n', start);
    QVERIFY(end >= start && end < original.size() - 1);
    QByteArray stripped = original;
    stripped.remove(start, end - start + 1);
    QVERIFY2(writeFile(path, stripped, error), qPrintable(error));
    const RegistrationStatus status = SongRegistry::checkRegistration(root, label, constant);
    QVERIFY(file == QStringLiteral("charmap") ? !status.inCharmap : !status.inSongsH);
    int id = -1;
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    QCOMPARE(id, 1);
    QCOMPARE(readFile(path, error), original);
    QVERIFY2(error.isEmpty(), qPrintable(error));
}

void OnboardingTest::registrationAliases_data()
{
    QTest::addColumn<bool>("drift");
    QTest::newRow("complete-alias") << false;
    QTest::newRow("drift-heals-first") << true;
}

void OnboardingTest::registrationAliases()
{
    QFETCH(bool, drift);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    const QString label = QStringLiteral("mus_onboardcheck_alias");
    const QString constant = SongRegistry::constantForLabel(label);
    QVERIFY2(SongRegistry::blankSong().writeFile(songPath(root, label), &error), qPrintable(error));
    int firstId = -1;
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &firstId),
             qPrintable(error));
    const RegistrationPlan plan =
        SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
    const QByteArray beforeTable = readFile(tablePath(root), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray header = readFile(songsHeaderPath(root), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray charmap = readFile(root + QStringLiteral("/charmap.txt"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(writeFile(tablePath(root), beforeTable + plan.songTableLine.toUtf8() + '\n', error),
             qPrintable(error));
    QVERIFY(SongRegistry::checkRegistration(root, label, constant).complete());
    QCOMPARE(
        SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM")).songId,
        firstId);
    if (drift) {
        QByteArray corrupted = header;
        const int at = corrupted.indexOf(QByteArray("#define ") + constant.toUtf8());
        QVERIFY(at >= 0);
        const int end = corrupted.indexOf('\n', at);
        corrupted.replace(at, end - at, QByteArray("#define ") + constant.toUtf8() + " 9999");
        QVERIFY2(writeFile(songsHeaderPath(root), corrupted, error), qPrintable(error));
        QVERIFY(!SongRegistry::checkRegistration(root, label, constant).inSongsH);
    }
    int id = -1;
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    QCOMPARE(id, firstId);
    QCOMPARE(readFile(songsHeaderPath(root), error), header);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(readFile(root + QStringLiteral("/charmap.txt"), error), charmap);
    QVERIFY2(error.isEmpty(), qPrintable(error));
}
