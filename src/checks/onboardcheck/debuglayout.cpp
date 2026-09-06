#include "checks/onboardcheck/onboardingtest.h"

#include <QFile>

#include "checks/support/songfixture.h"

namespace {
QByteArray debugLine(const char *text, bool continued)
{
    QByteArray line(text);
    if (continued)
        line += QByteArray(36 - line.size(), ' ') + "\\";
    return line + '\n';
}

QString debugPath(const QString &root)
{
    return root + QStringLiteral("/src/debug.c");
}
} // namespace

void OnboardingTest::debugLayouts_data()
{
    QTest::addColumn<QString>("operation");
    QTest::newRow("append") << QStringLiteral("append");
    QTest::newRow("se-route") << QStringLiteral("se-route");
    QTest::newRow("mid-backfill") << QStringLiteral("mid-backfill");
    QTest::newRow("before-first") << QStringLiteral("before-first");
    QTest::newRow("sole-remove-empty-insert") << QStringLiteral("sole-empty");
    QTest::newRow("named-form") << QStringLiteral("named");
}

void OnboardingTest::debugLayouts()
{
    QFETCH(QString, operation);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    const QString path = debugPath(root);
    const QString label = operation == QStringLiteral("se-route")
                              ? QStringLiteral("se_onboardcheck")
                              : QStringLiteral("mus_onboardcheck");
    const QString constant = SongRegistry::constantForLabel(label);
    QVERIFY(QFile::remove(path));
    QVERIFY(!SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"))
                 .debugApplicable);
    int id = -1;
    if (operation == QStringLiteral("append")) {
        QVERIFY2(SongRegistry::registerSong(root, label, constant,
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
    }
    const QByteArray base =
        debugLine("#define SOUND_LIST_BGM", true) + debugLine("    X(MUS_GSC_ROUTE38)", true) +
        debugLine("    X(MUS_CAUGHT)", true) + debugLine("    X(MUS_VICTORY_WILD)", false) + '\n' +
        debugLine("#define SOUND_LIST_SE", true) + debugLine("    X(SE_USE_ITEM)", true) +
        debugLine("    X(SE_PC_LOGIN)", false);
    QVERIFY2(writeFile(path, base, error), qPrintable(error));
    DecompProject project;
    QVERIFY2(project.open(root, &error), qPrintable(error));
    const auto gapsFor = [&project](const QString &wanted) {
        for (const SongInfo &song : project.songs())
            if (song.label == wanted)
                return song.registrationGaps;
        return QStringList{QStringLiteral("<absent>")};
    };
    QCOMPARE(gapsFor(QStringLiteral("mus_littleroot_test")),
             QStringList{QStringLiteral("src/debug.c")});
    QVERIFY(!gapsFor(QStringLiteral("mus_caught")).contains(QStringLiteral("src/debug.c")));
    if (operation == QStringLiteral("sole-empty")) {
        const QByteArray sole = QByteArrayLiteral(
            "#define SOUND_LIST_BGM\n#define SOUND_LIST_SE \\\n    X(SE_ONBOARDCHECK_GHOST)\n");
        QVERIFY2(writeFile(path, sole, error), qPrintable(error));
        QVERIFY2(SongRegistry::unregisterSong(root, QStringLiteral("se_onboardcheck_ghost"),
                                              QStringLiteral("SE_ONBOARDCHECK_GHOST"), &error),
                 qPrintable(error));
        QCOMPARE(readFile(path, error),
                 QByteArrayLiteral("#define SOUND_LIST_BGM\n#define SOUND_LIST_SE\n"));
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_caught"),
                                            QStringLiteral("MUS_CAUGHT"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(readFile(path, error),
                 QByteArrayLiteral(
                     "#define SOUND_LIST_BGM \\\n    X(MUS_CAUGHT)\n#define SOUND_LIST_SE\n"));
        QVERIFY2(error.isEmpty(), qPrintable(error));
        return;
    }
    if (operation == QStringLiteral("named")) {
        const auto named = [](const char *constant, int comma, int paren, int slash) {
            QByteArray line("    X(");
            line += constant;
            line += QByteArray(comma - line.size(), ' ') + ", \"";
            QByteArray display(constant);
            display.replace('_', '-');
            return line + display + "\"" +
                   QByteArray(paren - line.size() - display.size() - 1, ' ') + ")" +
                   QByteArray(slash - paren, ' ') + "\\\n";
        };
        const QByteArray namedBase = QByteArrayLiteral("#define SOUND_LIST_BGM \\\n") +
                                     named("MUS_GSC_ROUTE38", 34, 60, 62) +
                                     named("MUS_VICTORY_WILD", 34, 60, 62) + '\n' +
                                     QByteArrayLiteral("#define SOUND_LIST_SE \\\n") +
                                     named("SE_USE_ITEM", 28, 50, 52) + '\n';
        QVERIFY2(writeFile(path, namedBase, error), qPrintable(error));
        QVERIFY(SongRegistry::checkRegistration(root, QStringLiteral("mus_gsc_route38"),
                                                QStringLiteral("MUS_GSC_ROUTE38"))
                    .inDebugMenu);
        QVERIFY2(SongRegistry::registerSong(root, label, constant,
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QByteArray expected = namedBase;
        expected.replace(named("MUS_VICTORY_WILD", 34, 60, 62),
                         named("MUS_VICTORY_WILD", 34, 60, 62) +
                             named("MUS_ONBOARDCHECK", 34, 60, 62));
        QCOMPARE(readFile(path, error), expected);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY2(SongRegistry::registerSong(root, label, constant,
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(readFile(path, error), expected);
        const QByteArray namedCaught =
            QByteArrayLiteral("#define SOUND_LIST_BGM \\\n") +
            named("MUS_GSC_ROUTE38", 34, 60, 62) + named("MUS_CAUGHT", 34, 60, 62) +
            named("MUS_VICTORY_WILD", 34, 60, 62) + named("MUS_ONBOARDCHECK", 34, 60, 62) + '\n' +
            QByteArrayLiteral("#define SOUND_LIST_SE \\\n") + named("SE_USE_ITEM", 28, 50, 52) +
            '\n';
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_caught"),
                                            QStringLiteral("MUS_CAUGHT"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(readFile(path, error), namedCaught);
        const QByteArray namedSe =
            namedCaught.chopped(named("SE_USE_ITEM", 28, 50, 52).size() + 1) +
            named("SE_USE_ITEM", 28, 50, 52) + named("SE_ONBOARDCHECK", 28, 50, 52) + '\n';
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("se_onboardcheck"),
                                            QStringLiteral("SE_ONBOARDCHECK"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(readFile(path, error), namedSe);
        QVERIFY2(SongRegistry::unregisterSong(root, QStringLiteral("se_onboardcheck"),
                                              QStringLiteral("SE_ONBOARDCHECK"), &error),
                 qPrintable(error));
        QCOMPARE(readFile(path, error), namedCaught);
        QVERIFY2(SongRegistry::unregisterSong(root, QStringLiteral("mus_caught"),
                                              QStringLiteral("MUS_CAUGHT"), &error),
                 qPrintable(error));
        QCOMPARE(readFile(path, error), expected);
        QVERIFY2(SongRegistry::unregisterSong(root, label, constant, &error), qPrintable(error));
        QCOMPARE(readFile(path, error), namedBase);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        return;
    }
    const RegistrationStatus before = SongRegistry::checkRegistration(root, label, constant);
    QVERIFY(before.debugApplicable && !before.inDebugMenu && !before.complete());
    if (operation == QStringLiteral("mid-backfill")) {
        QByteArray stripped = base;
        stripped.replace(debugLine("    X(MUS_CAUGHT)", true), QByteArray());
        QVERIFY2(writeFile(path, stripped, error), qPrintable(error));
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_caught"),
                                            QStringLiteral("MUS_CAUGHT"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        QCOMPARE(readFile(path, error), base);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        return;
    }
    if (operation == QStringLiteral("before-first")) {
        QVERIFY2(SongRegistry::registerSong(root, QStringLiteral("mus_littleroot_test"),
                                            QStringLiteral("MUS_LITTLEROOT_TEST"),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
        const QByteArray expected =
            debugLine("#define SOUND_LIST_BGM", true) +
            debugLine("    X(MUS_LITTLEROOT_TEST)", true) +
            debugLine("    X(MUS_GSC_ROUTE38)", true) + debugLine("    X(MUS_CAUGHT)", true) +
            debugLine("    X(MUS_VICTORY_WILD)", false) + '\n' +
            debugLine("#define SOUND_LIST_SE", true) + debugLine("    X(SE_USE_ITEM)", true) +
            debugLine("    X(SE_PC_LOGIN)", false);
        QCOMPARE(readFile(path, error), expected);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        return;
    }
    const QByteArray tableBefore = readFile(root + QStringLiteral("/sound/song_table.inc"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray headerBefore =
        readFile(root + QStringLiteral("/include/constants/songs.h"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray charmapBefore = readFile(root + QStringLiteral("/charmap.txt"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray linkerBefore = readFile(root + QStringLiteral("/ld_script.ld"), error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    const QByteArray after = readFile(path, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray expected =
        operation == QStringLiteral("se-route")
            ? debugLine("#define SOUND_LIST_BGM", true) +
                  debugLine("    X(MUS_GSC_ROUTE38)", true) + debugLine("    X(MUS_CAUGHT)", true) +
                  debugLine("    X(MUS_VICTORY_WILD)", false) + '\n' +
                  debugLine("#define SOUND_LIST_SE", true) + debugLine("    X(SE_USE_ITEM)", true) +
                  debugLine("    X(SE_PC_LOGIN)", true) + debugLine("    X(SE_ONBOARDCHECK)", false)
            : debugLine("#define SOUND_LIST_BGM", true) +
                  debugLine("    X(MUS_GSC_ROUTE38)", true) + debugLine("    X(MUS_CAUGHT)", true) +
                  debugLine("    X(MUS_VICTORY_WILD)", true) +
                  debugLine("    X(MUS_ONBOARDCHECK)", false) + '\n' +
                  debugLine("#define SOUND_LIST_SE", true) + debugLine("    X(SE_USE_ITEM)", true) +
                  debugLine("    X(SE_PC_LOGIN)", false);
    QCOMPARE(after, expected);
    if (operation == QStringLiteral("append")) {
        QCOMPARE(readFile(root + QStringLiteral("/sound/song_table.inc"), error), tableBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/include/constants/songs.h"), error),
                 headerBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/charmap.txt"), error), charmapBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/ld_script.ld"), error), linkerBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    QCOMPARE(readFile(path, error), after);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const RegistrationStatus afterStatus = SongRegistry::checkRegistration(root, label, constant);
    QVERIFY(afterStatus.inDebugMenu && afterStatus.complete());
    QVERIFY(SongRegistry::makeRemovalPlan(root, label, constant).inDebugMenu);
    if (operation == QStringLiteral("se-route")) {
        QVERIFY2(SongRegistry::unregisterSong(root, label, constant, &error), qPrintable(error));
        QCOMPARE(readFile(path, error), base);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/sound/song_table.inc"), error), tableBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/include/constants/songs.h"), error),
                 headerBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/charmap.txt"), error), charmapBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QCOMPARE(readFile(root + QStringLiteral("/ld_script.ld"), error), linkerBefore);
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
}
