#include "checks/onboardcheck/onboardingtest.h"

#include <QFile>
#include <QRegularExpression>

#include "checks/support/songfixture.h"
#include "project/voicegroupsource.h"

namespace {
QString songMid(const QString &root, const QString &label)
{
    return root + QStringLiteral("/sound/songs/midi/%1.mid").arg(label);
}

QString songCfg(const QString &root)
{
    return root + QStringLiteral("/sound/songs/midi/midi.cfg");
}

QString songTable(const QString &root)
{
    return root + QStringLiteral("/sound/song_table.inc");
}
} // namespace

void OnboardingTest::songDeletion_data()
{
    QTest::addColumn<QString>("caseName");
    QTest::newRow("mid-delete-and-reuse") << QStringLiteral("reuse");
    QTest::newRow("double-delete-six-files") << QStringLiteral("double");
    QTest::newRow("entry-zero-refused") << QStringLiteral("entry-zero");
    QTest::newRow("stray-unregistered") << QStringLiteral("stray");
}

void OnboardingTest::songDeletion()
{
    QFETCH(QString, caseName);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    const QString midiDir = midiDirectory(root);
    SongCfg cfg;
    QVERIFY2(defaultCfg(root, cfg, error), qPrintable(error));
    const QStringList snapshots = {songTable(root),
                                   root + QStringLiteral("/include/constants/songs.h"),
                                   root + QStringLiteral("/ld_script.ld"),
                                   root + QStringLiteral("/charmap.txt"),
                                   songCfg(root),
                                   root + QStringLiteral("/src/debug.c")};
    QList<QByteArray> original;
    for (const QString &path : snapshots) {
        QVERIFY2(QFile::exists(path), qPrintable(path));
        original.append(readFile(path, error));
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
    const QByteArray table0 = original[0];
    QRegularExpression entry(QStringLiteral(R"(^\s*song\s+(\w+))"));
    QString fallback;
    int tableEntries = 0;
    int originalDummies = 0;
    for (const QByteArray &line : table0.split('\n')) {
        const QRegularExpressionMatch match = entry.match(QString::fromUtf8(line));
        if (!match.hasMatch())
            continue;
        if (fallback.isEmpty())
            fallback = match.captured(1);
        ++tableEntries;
    }
    QVERIFY(!fallback.isEmpty());
    for (const QByteArray &line : table0.split('\n')) {
        const QRegularExpressionMatch match = entry.match(QString::fromUtf8(line));
        originalDummies += match.hasMatch() && match.captured(1) == fallback;
    }
    const RegistrationPlan probe = SongRegistry::makePlan(
        root, QStringLiteral("mus_onboardcheck_probe"), QStringLiteral("MUS_ONBOARDCHECK_PROBE"),
        QStringLiteral("MUSIC_PLAYER_BGM"));
    QVERIFY(probe.songId != 0);
    if (originalDummies == 1)
        QCOMPARE(probe.songId, tableEntries);
    if (caseName == QStringLiteral("entry-zero")) {
        QVERIFY(!SongRegistry::unregisterSong(root, fallback,
                                              SongRegistry::constantForLabel(fallback), &error));
        QVERIFY(!error.isEmpty());
        for (int i = 0; i < snapshots.size(); ++i) {
            QCOMPARE(readFile(snapshots[i], error), original[i]);
            QVERIFY2(error.isEmpty(), qPrintable(error));
        }
        return;
    }

    const QString label = caseName == QStringLiteral("stray")
                              ? QStringLiteral("mus_onboardcheck_stray")
                              : QStringLiteral("mus_onboardcheck_del_a");
    QVERIFY2(SongRegistry::blankSong().writeFile(songMid(root, label), &error), qPrintable(error));
    QVERIFY2(SongRegistry::writeSongFlags(midiDir, label, cfg.rawFlags, &error), qPrintable(error));
    if (caseName == QStringLiteral("stray")) {
        QVERIFY2(SongRegistry::unregisterSong(root, label, SongRegistry::constantForLabel(label),
                                              &error),
                 qPrintable(error));
        QCOMPARE(readFile(songTable(root), error), table0);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY2(SongRegistry::removeSongFlags(midiDir, label, &error), qPrintable(error));
        const QByteArray cfgBytes = readFile(songCfg(root), error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(!cfgBytes.contains(label.toUtf8() + ".mid"));
        return;
    }
    int id = -1;
    QVERIFY2(SongRegistry::registerSong(root, label, SongRegistry::constantForLabel(label),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
             qPrintable(error));
    const QString second = QStringLiteral("mus_onboardcheck_del_b");
    QVERIFY2(SongRegistry::blankSong().writeFile(songMid(root, second), &error), qPrintable(error));
    QVERIFY2(SongRegistry::writeSongFlags(midiDir, second, cfg.rawFlags, &error),
             qPrintable(error));
    int secondId = -1;
    QVERIFY2(SongRegistry::registerSong(root, second, SongRegistry::constantForLabel(second),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &secondId),
             qPrintable(error));
    QCOMPARE(secondId, id + 1);
    QVERIFY2(
        SongRegistry::unregisterSong(root, label, SongRegistry::constantForLabel(label), &error),
        qPrintable(error));
    QVERIFY2(SongRegistry::removeSongFlags(midiDir, label, &error), qPrintable(error));
    QVERIFY(QFile::remove(songMid(root, label)));
    int dummiesAfterDelete = 0;
    for (const QByteArray &line : readFile(songTable(root), error).split('\n')) {
        const QRegularExpressionMatch match = entry.match(QString::fromUtf8(line));
        dummiesAfterDelete += match.hasMatch() && match.captured(1) == fallback;
    }
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QCOMPARE(dummiesAfterDelete, originalDummies + 1);
    const RegistrationPlan replacementPlan = SongRegistry::makePlan(
        root, QStringLiteral("mus_onboardcheck_del_c"), QStringLiteral("MUS_ONBOARDCHECK_DEL_C"),
        QStringLiteral("MUSIC_PLAYER_BGM"));
    QCOMPARE(replacementPlan.songId, id);
    for (int index = 1; index < snapshots.size(); ++index) {
        const QByteArray bytes = readFile(snapshots[index], error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY(!bytes.contains("MUS_ONBOARDCHECK_DEL_A"));
    }
    QVERIFY(SongRegistry::checkRegistration(root, second, SongRegistry::constantForLabel(second))
                .complete());
    if (caseName == QStringLiteral("double")) {
        QList<QByteArray> before;
        for (const QString &path : snapshots) {
            before.append(readFile(path, error));
            QVERIFY2(error.isEmpty(), qPrintable(error));
        }
        QVERIFY2(SongRegistry::unregisterSong(root, label, SongRegistry::constantForLabel(label),
                                              &error),
                 qPrintable(error));
        for (int i = 0; i < snapshots.size(); ++i) {
            QCOMPARE(readFile(snapshots[i], error), before[i]);
            QVERIFY2(error.isEmpty(), qPrintable(error));
        }
        return;
    }
    const QString replacement = QStringLiteral("mus_onboardcheck_del_c");
    QVERIFY2(SongRegistry::blankSong().writeFile(songMid(root, replacement), &error),
             qPrintable(error));
    QVERIFY2(SongRegistry::writeSongFlags(midiDir, replacement, cfg.rawFlags, &error),
             qPrintable(error));
    int replacementId = -1;
    QVERIFY2(SongRegistry::registerSong(root, replacement,
                                        SongRegistry::constantForLabel(replacement),
                                        QStringLiteral("MUSIC_PLAYER_BGM"), &error, &replacementId),
             qPrintable(error));
    QCOMPARE(replacementId, id);
    const QByteArray header = readFile(snapshots[1], error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(header.indexOf("MUS_ONBOARDCHECK_DEL_C") < header.indexOf("MUS_ONBOARDCHECK_DEL_B"));
    const QByteArray charmap = readFile(snapshots[3], error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY(charmap.indexOf("MUS_ONBOARDCHECK_DEL_C") < charmap.indexOf("MUS_ONBOARDCHECK_DEL_B"));
    QVERIFY2(SongRegistry::unregisterSong(root, replacement,
                                          SongRegistry::constantForLabel(replacement), &error),
             qPrintable(error));
    QVERIFY2(SongRegistry::removeSongFlags(midiDir, replacement, &error), qPrintable(error));
    QVERIFY(QFile::remove(songMid(root, replacement)));
    QVERIFY2(
        SongRegistry::unregisterSong(root, second, SongRegistry::constantForLabel(second), &error),
        qPrintable(error));
    QVERIFY2(SongRegistry::removeSongFlags(midiDir, second, &error), qPrintable(error));
    QVERIFY(QFile::remove(songMid(root, second)));
    for (int i = 0; i < snapshots.size(); ++i) {
        QCOMPARE(readFile(snapshots[i], error), original[i]);
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
}

void OnboardingTest::voicegroupDeletion_data()
{
    QTest::addColumn<QString>("gate");
    QTest::newRow("sole-user") << QStringLiteral("sole");
    QTest::newRow("shared-user") << QStringLiteral("shared");
    QTest::newRow("keysplit-reference") << QStringLiteral("keysplit");
    QTest::newRow("c-reference") << QStringLiteral("c-reference");
}

void OnboardingTest::voicegroupDeletion()
{
    QFETCH(QString, gate);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    const QString name = QStringLiteral("onboardcheckvg");
    const QString hub = root + QStringLiteral("/sound/voice_groups.inc");
    const QByteArray hubBefore = readFile(hub, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(VoicegroupSource::createVoicegroup(root, name, {}, {}, &error), qPrintable(error));
    QVERIFY2(VoicegroupSource::appendIncludeLine(root, name, &error), qPrintable(error));
    SongInfo user;
    user.label = QStringLiteral("mus_vg_user");
    user.cfg.voicegroupArg = QStringLiteral("_onboardcheckvg");
    QVector<SongInfo> songs{user};
    if (gate == QStringLiteral("shared")) {
        SongInfo second = user;
        second.label = QStringLiteral("mus_vg_user_2");
        songs.append(second);
        QVERIFY(SongRegistry::deletableVoicegroup(root, songs, user.label).isEmpty());
        return;
    }
    const QString ref = root + QStringLiteral("/src/onboardcheck_ref.c");
    if (gate == QStringLiteral("c-reference")) {
        QVERIFY2(
            writeFile(ref, QByteArrayLiteral("extern int voicegroup_onboardcheckvg[];\n"), error),
            qPrintable(error));
        QVERIFY(SongRegistry::deletableVoicegroup(root, songs, user.label).isEmpty());
        QVERIFY(QFile::remove(ref));
    }
    if (gate == QStringLiteral("keysplit")) {
        const QString sub = QStringLiteral("onboardchecksub");
        QVERIFY2(VoicegroupSource::createVoicegroup(root, sub, {}, {}, &error), qPrintable(error));
        const QString host = root + QStringLiteral("/sound/voicegroups/onboardcheckvg.inc");
        const QByteArray hostBefore = readFile(host, error);
        QVERIFY2(error.isEmpty(), qPrintable(error));
        QVERIFY2(writeFile(host,
                           hostBefore +
                               QByteArrayLiteral(
                                   "\tvoice_keysplit voicegroup_onboardchecksub, KeySplitTable1\n"),
                           error),
                 qPrintable(error));
        SongInfo subUser = user;
        subUser.label = QStringLiteral("mus_vg_sub_user");
        subUser.cfg.voicegroupArg = QStringLiteral("_onboardchecksub");
        songs.append(subUser);
        QVERIFY(SongRegistry::deletableVoicegroup(root, songs, subUser.label).isEmpty());
        return;
    }
    QCOMPARE(SongRegistry::deletableVoicegroup(root, songs, user.label), name);
    QVERIFY2(VoicegroupSource::deleteVoicegroup(root, name, &error), qPrintable(error));
    QVERIFY(!QFile::exists(root + QStringLiteral("/sound/voicegroups/onboardcheckvg.inc")));
    QCOMPARE(readFile(hub, error), hubBefore);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    QVERIFY2(VoicegroupSource::deleteVoicegroup(root, name, &error), qPrintable(error));
}
