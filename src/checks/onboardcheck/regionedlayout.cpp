#include "checks/onboardcheck/onboardingtest.h"

#include <QFile>

#include <algorithm>

#include "checks/support/songfixture.h"

namespace {
QByteArray define(const char *name, const char *value)
{
    QByteArray line("#define ");
    line += name;
    return line + QByteArray(std::max(1, 28 - int(line.size())), ' ') + value + '\n';
}

QByteArray song(const char *label, const char *player, int playerNumber = 0)
{
    return QByteArray("\tsong ") + label + ", " + player + ", " + QByteArray::number(playerNumber) +
           '\n';
}

bool regionFixture(const QString &root, bool alias, QString &error)
{
    const QByteArray table =
        QByteArrayLiteral(
            "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n") +
        song("mus_dummy", "MUSIC_PLAYER_BGM") + song("se_use_item", "MUSIC_PLAYER_SE1", 1) +
        song("se_last", "MUSIC_PLAYER_SE1", 1) + song("dummy_song_header", "MUSIC_PLAYER_BGM") +
        song("dummy_song_header", "MUSIC_PLAYER_BGM") + song("mus_first", "MUSIC_PLAYER_BGM") +
        song("mus_last", "MUSIC_PLAYER_BGM") + song("ph_one", "MUSIC_PLAYER_SE1", 1) +
        song("ph_two", "MUSIC_PLAYER_SE1", 1);
    const QByteArray header =
        define("MUS_DUMMY", "0") + define("SE_USE_ITEM", "1") + define("SE_LAST", "2") +
        (alias ? define("END_SE", "SE_LAST") : QByteArray()) + define("START_MUS", "5") +
        define("MUS_FIRST", "5") + define("MUS_LAST", "6") +
        define("END_MUS", alias ? "MUS_LAST" : "6") + define("PH_ONE", "7") +
        define("PH_TWO", "8") + define("MUS_NONE", "0xFFFF");
    const auto write = [&error](const QString &path, const QByteArray &bytes) {
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate) ||
            file.write(bytes) != bytes.size()) {
            error = path + QStringLiteral(": ") + file.errorString();
            return false;
        }
        return true;
    };
    return write(root + QStringLiteral("/sound/song_table.inc"), table) &&
           write(root + QStringLiteral("/include/constants/songs.h"), header) &&
           write(root + QStringLiteral("/charmap.txt"),
                 QByteArrayLiteral("MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\n"
                                   "MUS_FIRST = 05 00\nMUS_LAST = 06 00\nPH_ONE = 07 00\n"
                                   "PH_TWO = 08 00\n")) &&
           write(root + QStringLiteral("/src/debug.c"),
                 (alias ? QByteArrayLiteral(
                              "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n")
                        : QByteArray()) +
                     QByteArrayLiteral("#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n"
                                       "    X(MUS_LAST)\n\n#define SOUND_LIST_SE \\\n"
                                       "    X(SE_USE_ITEM) \\\n    X(SE_LAST)\n"));
}
} // namespace

void OnboardingTest::regionedValueLayouts_data()
{
    QTest::addColumn<QString>("operation");
    QTest::newRow("markerless-appends") << QStringLiteral("markerless");
    QTest::newRow("music-insert") << QStringLiteral("music");
    QTest::newRow("se-gap") << QStringLiteral("se");
    QTest::newRow("delete-repoints") << QStringLiteral("delete");
}

void OnboardingTest::regionedValueLayouts()
{
    QFETCH(QString, operation);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    QVERIFY2(regionFixture(root, false, error), qPrintable(error));
    const QStringList fixturePaths = {
        root + QStringLiteral("/sound/song_table.inc"),
        root + QStringLiteral("/include/constants/songs.h"), root + QStringLiteral("/charmap.txt"),
        root + QStringLiteral("/src/debug.c"), root + QStringLiteral("/ld_script.ld")};
    QList<QByteArray> fixtureBytes;
    for (const QString &path : fixturePaths) {
        fixtureBytes.append(readFile(path, error));
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
    if (operation == QStringLiteral("markerless")) {
        QByteArray header = readFile(root + QStringLiteral("/include/constants/songs.h"), error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        header.replace(define("END_SE", "SE_LAST"), QByteArray());
        header.replace(define("START_MUS", "5"), QByteArray());
        header.replace(define("END_MUS", "6"), QByteArray());
        QVERIFY2(writeFile(root + QStringLiteral("/include/constants/songs.h"), header, error),
                 qPrintable(error));
        QCOMPARE(SongRegistry::makePlan(root, QStringLiteral("mus_markerless"),
                                        QStringLiteral("MUS_MARKERLESS"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"))
                     .songId,
                 9);
        return;
    }
    int id = -1;
    if (operation == QStringLiteral("se")) {
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("se_valcheck"),
                                            QStringLiteral("SE_VALCHECK"),
                                            QStringLiteral("MUSIC_PLAYER_SE1"), &error, &id),
                 qPrintable(error));
        QCOMPARE(id, 3);
        const QByteArray table = readFile(root + QStringLiteral("/sound/song_table.inc"), error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(table.contains(song("se_valcheck", "MUSIC_PLAYER_SE1", 1) +
                               song("dummy_song_header", "MUSIC_PLAYER_BGM")));
        QByteArray expectedHeader = fixtureBytes[1];
        expectedHeader.replace(define("START_MUS", "5"),
                               define("SE_VALCHECK", "3") + define("START_MUS", "5"));
        QCOMPARE(readFile(root + QStringLiteral("/include/constants/songs.h"), error),
                 expectedHeader);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        const QByteArray debug = readFile(root + QStringLiteral("/src/debug.c"), error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(debug.indexOf("X(SE_VALCHECK)") > debug.indexOf("#define SOUND_LIST_SE"));
        return;
    }
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_valcheck"),
                                        QStringLiteral("MUS_VALCHECK"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
             qPrintable(error));
    QCOMPARE(id, 7);
    const QString headerPath = root + QStringLiteral("/include/constants/songs.h");
    QVERIFY(readFile(headerPath, error).contains(define("END_MUS", "7")));
    QVERIFY2(error.isEmpty(), qPrintable(error));
    if (operation == QStringLiteral("delete")) {
        QVERIFY2(SongRegistry::unregisterSong(root, QStringLiteral("mus_valcheck"),
                                              QStringLiteral("MUS_VALCHECK"), &error),
                 qPrintable(error));
        QVERIFY(readFile(headerPath, error).contains(define("END_MUS", "6")));
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QByteArray expectedTable = fixtureBytes[0];
        const QByteArray firstPhoneme = song("ph_one", "MUSIC_PLAYER_SE1", 1);
        expectedTable.replace(firstPhoneme, song("mus_dummy", "MUSIC_PLAYER_BGM") + firstPhoneme);
        QByteArray expectedHeader = fixtureBytes[1];
        expectedHeader.replace(define("PH_ONE", "7") + define("PH_TWO", "8"),
                               define("PH_ONE", "8") + define("PH_TWO", "9"));
        QByteArray expectedCharmap = fixtureBytes[2];
        expectedCharmap.replace(QByteArrayLiteral("PH_ONE = 07 00\nPH_TWO = 08 00\n"),
                                QByteArrayLiteral("PH_ONE = 08 00\nPH_TWO = 09 00\n"));
        QCOMPARE(readFile(fixturePaths[0], error), expectedTable);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(fixturePaths[1], error), expectedHeader);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(fixturePaths[2], error), expectedCharmap);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(fixturePaths[3], error), fixtureBytes[3]);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(fixturePaths[4], error), fixtureBytes[4]);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(SongRegistry::makePlan(root, QStringLiteral("mus_reuse"),
                                        QStringLiteral("MUS_REUSE"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"))
                     .songId,
                 7);
    }
}

void OnboardingTest::regionedAliasLayouts_data()
{
    QTest::addColumn<QString>("operation");
    QTest::newRow("music-and-se") << QStringLiteral("insert");
    QTest::newRow("stranded-migrate") << QStringLiteral("stranded");
    QTest::newRow("reuse-and-overflow") << QStringLiteral("overflow");
}

void OnboardingTest::regionedAliasLayouts()
{
    QFETCH(QString, operation);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    QVERIFY2(regionFixture(root, true, error), qPrintable(error));
    int id = -1;
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_oldcheck"),
                                        QStringLiteral("MUS_OLDCHECK"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
             qPrintable(error));
    QCOMPARE(id, 7);
    QByteArray header = readFile(root + QStringLiteral("/include/constants/songs.h"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(header.contains(define("END_MUS", "MUS_OLDCHECK")));
    QVERIFY(
        readFile(root + QStringLiteral("/charmap.txt"), error).contains("MUS_OLDCHECK = 07 00"));
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(SongRegistry::checkRegistration(root, QStringLiteral("mus_oldcheck"),
                                            QStringLiteral("MUS_OLDCHECK"))
                .complete());
    if (operation == QStringLiteral("insert")) {
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("se_oldcheck"),
                                            QStringLiteral("SE_OLDCHECK"),
                                            QStringLiteral("MUSIC_PLAYER_SE1"), &error, &id),
                 qPrintable(error));
        QCOMPARE(id, 3);
        QVERIFY(readFile(root + QStringLiteral("/src/debug.c"), error).contains("X(SE_OLDCHECK)"));
        QVERIFY2(error.isEmpty(), qPrintable(error));
        return;
    }
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("se_oldcheck"),
                                        QStringLiteral("SE_OLDCHECK"),
                                        QStringLiteral("MUSIC_PLAYER_SE1"), &error, &id),
             qPrintable(error));
    if (operation == QStringLiteral("stranded")) {
        const QString tablePath = root + QStringLiteral("/sound/song_table.inc");
        const QString headerPath = root + QStringLiteral("/include/constants/songs.h");
        const QString charmapPath = root + QStringLiteral("/charmap.txt");
        const QString debugPath = root + QStringLiteral("/src/debug.c");
        const QByteArray table = readFile(tablePath, error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY2(writeFile(tablePath, table + song("mus_straggler", "MUSIC_PLAYER_BGM"), error),
                 qPrintable(error));
        header = readFile(headerPath, error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        header.replace(define("MUS_OLDCHECK", "7"),
                       define("MUS_OLDCHECK", "7") + define("MUS_STRAGGLER", "9"));
        QVERIFY2(writeFile(headerPath, header, error), qPrintable(error));
        const QByteArray charmap = readFile(charmapPath, error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY2(
            writeFile(charmapPath, charmap + QByteArrayLiteral("MUS_STRAGGLER = 09 00\n"), error),
            qPrintable(error));
        QByteArray debugBeforeMigration = readFile(debugPath, error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        debugBeforeMigration.replace(
            QByteArrayLiteral("    X(MUS_OLDCHECK)\n"),
            QByteArrayLiteral("    X(MUS_OLDCHECK) \\\n    X(MUS_STRAGGLER)\n"));
        QVERIFY2(writeFile(debugPath, debugBeforeMigration, error), qPrintable(error));
        QVERIFY(!SongRegistry::checkRegistration(root, QStringLiteral("mus_straggler"),
                                                 QStringLiteral("MUS_STRAGGLER"))
                     .inSongsH);
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_straggler"),
                                            QStringLiteral("MUS_STRAGGLER"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(id, 8);
        QCOMPARE(readFile(debugPath, error), debugBeforeMigration);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(SongRegistry::checkRegistration(root, QStringLiteral("mus_straggler"),
                                                QStringLiteral("MUS_STRAGGLER"))
                    .complete());
        QVERIFY2(SongRegistry::unregisterSong(root, QStringLiteral("mus_straggler"),
                                              QStringLiteral("MUS_STRAGGLER"), &error),
                 qPrintable(error));
        QVERIFY(readFile(headerPath, error).contains(define("END_MUS", "MUS_OLDCHECK")));
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(SongRegistry::makePlan(root, QStringLiteral("mus_refill"),
                                        QStringLiteral("MUS_REFILL"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"))
                     .songId,
                 8);
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_refill"),
                                            QStringLiteral("MUS_REFILL"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(id, 8);
        QVERIFY(readFile(headerPath, error)
                    .contains(define("MUS_REFILL", "8") + define("END_MUS", "MUS_REFILL")));
        QVERIFY2(error.isEmpty(), qPrintable(error));
        return;
    }
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_reuse_source"),
                                        QStringLiteral("MUS_REUSE_SOURCE"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
             qPrintable(error));
    QCOMPARE(id, 8);
    QVERIFY2(SongRegistry::unregisterSong(root, QStringLiteral("mus_reuse_source"),
                                          QStringLiteral("MUS_REUSE_SOURCE"), &error),
             qPrintable(error));
    QCOMPARE(SongRegistry::makePlan(root, QStringLiteral("mus_refill"),
                                    QStringLiteral("MUS_REFILL"),
                                    QStringLiteral("MUSIC_PLAYER_BGM"))
                 .songId,
             8);
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_refill"),
                                        QStringLiteral("MUS_REFILL"),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
             qPrintable(error));
    QCOMPARE(id, 8);
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("se_extra"),
                                        QStringLiteral("SE_EXTRA"),
                                        QStringLiteral("MUSIC_PLAYER_SE1"), &error, &id),
             qPrintable(error));
    QCOMPARE(id, 4);
    QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("se_over"), QStringLiteral("SE_OVER"),
                                        QStringLiteral("MUSIC_PLAYER_SE1"), &error, &id),
             qPrintable(error));
    QCOMPARE(id, 9);
    const QByteArray debug = readFile(root + QStringLiteral("/src/debug.c"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(debug.indexOf("X(SE_OVER)") < debug.indexOf("#define SOUND_LIST_SE"));
    header = readFile(root + QStringLiteral("/include/constants/songs.h"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(header.contains(define("END_MUS", "SE_OVER")));
}
