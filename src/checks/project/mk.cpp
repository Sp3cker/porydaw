#include <QtTest>

#include <QDir>
#include <QFile>

#include <memory>

#include "checks/support/songfixture.h"
#include "project/decompproject.h"
#include "project/songregistry.h"
#include "project/songsmk.h"

namespace {

QStringList readAllLines(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'));
}

QByteArray readAllBytes(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

const SongInfo *songByLabel(const DecompProject &project, const QString &label)
{
    for (const SongInfo &song : project.songs())
        if (song.label == label)
            return &song;
    return nullptr;
}

class SongsMkTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SongsMkTest)

  public:
    SongsMkTest(QString stagedRoot, QString songLabel)
        : m_stagedRoot(std::move(stagedRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void init();
    void cleanup();
    void parsesAndVolumeWriteChangesOnlyRecipe();
    void preservesStdReverbVariableSpelling();
    void appendRemoveRuleRoundsTripsByteExactly();

  private:
    bool mkOnly(QString &error) const;
    bool open(DecompProject &project, QString &error) const;
    QString mkPath() const;
    QString midiDirectory() const;

    QString m_stagedRoot;
    QString m_songLabel;
    std::unique_ptr<checks::ProjectFixture> m_project;
};

bool SongsMkTest::mkOnly(QString &error) const
{
    const QString midiCfg = QDir(midiDirectory()).filePath(QStringLiteral("midi.cfg"));
    if (QFile::exists(midiCfg)) {
        error = QStringLiteral("fixture must have no midi.cfg");
        return false;
    }
    if (!QFile::exists(mkPath())) {
        error = QStringLiteral("fixture is missing songs.mk");
        return false;
    }
    return true;
}

bool SongsMkTest::open(DecompProject &project, QString &error) const
{
    return project.open(m_project->root(), &error);
}

QString SongsMkTest::mkPath() const
{
    return SongsMk::path(m_project->root());
}

QString SongsMkTest::midiDirectory() const
{
    return m_project->root() + QStringLiteral("/sound/songs/midi");
}

void SongsMkTest::init()
{
    QString error;
    m_project = checks::ProjectFixture::copyOf(m_stagedRoot, error);
    QVERIFY2(m_project, qPrintable(error));
}

void SongsMkTest::cleanup()
{
    m_project.reset();
}

void SongsMkTest::parsesAndVolumeWriteChangesOnlyRecipe()
{
    QString error;
    QVERIFY2(mkOnly(error), qPrintable(error));
    DecompProject project;
    QVERIFY2(open(project, error), qPrintable(error));
    const SongInfo *const song = songByLabel(project, m_songLabel);
    QVERIFY2(song, qPrintable(QStringLiteral("fixture song '%1' is missing").arg(m_songLabel)));
    if (!song)
        return;
    QVERIFY(song->hasCfg);
    QVERIFY(!song->cfg.voicegroupArg.isEmpty());
    QVERIFY(!song->cfg.rawFlags.join(QLatin1Char(' ')).contains(QLatin1Char('$')));

    const QString preservedVoicegroup = song->cfg.voicegroupArg;
    const int preservedReverb = song->cfg.reverb;
    const QStringList before = readAllLines(mkPath());
    SongCfg updated = song->cfg;
    updated.masterVolume = 111;
    QVERIFY2(SongRegistry::writeSongFlags(midiDirectory(), m_songLabel,
                                          SongRegistry::mergeCfgFlags(updated), &error),
             qPrintable(error));
    QVERIFY(!QFile::exists(QDir(midiDirectory()).filePath(QStringLiteral("midi.cfg"))));

    const QStringList after = readAllLines(mkPath());
    QCOMPARE(after.size(), before.size());
    if (after.size() == before.size()) {
        const QString target = QStringLiteral("/%1.s").arg(m_songLabel);
        int changed = 0;
        for (qsizetype index = 0; index < before.size(); ++index) {
            if (before[index] == after[index])
                continue;
            ++changed;
            QVERIFY(index > 0);
            if (index > 0) {
                QVERIFY(before[index - 1].contains(target));
                QVERIFY(after[index].contains(QStringLiteral("$(MID)")));
            }
        }
        QCOMPARE(changed, 1);
    }

    DecompProject reopened;
    QVERIFY2(open(reopened, error), qPrintable(error));
    const SongInfo *const reloaded = songByLabel(reopened, m_songLabel);
    QVERIFY(reloaded);
    if (reloaded) {
        QCOMPARE(reloaded->cfg.masterVolume, 111);
        QCOMPARE(reloaded->cfg.voicegroupArg, preservedVoicegroup);
        QCOMPARE(reloaded->cfg.reverb, preservedReverb);
    }
}

void SongsMkTest::preservesStdReverbVariableSpelling()
{
    QString error;
    QVERIFY2(mkOnly(error), qPrintable(error));
    const QStringList before = readAllLines(mkPath());
    QString variableLabel;
    for (qsizetype index = 0; index + 1 < before.size(); ++index) {
        if (!before[index + 1].contains(QStringLiteral("-R$(STD_REVERB)")))
            continue;
        const int slash = before[index].indexOf(QStringLiteral(")/"));
        const int extension = before[index].indexOf(QStringLiteral(".s:"));
        if (slash >= 0 && extension > slash) {
            variableLabel = before[index].mid(slash + 2, extension - slash - 2);
            break;
        }
    }
    if (variableLabel.isEmpty())
        QSKIP("fixture has no -R$(STD_REVERB) recipe");

    DecompProject project;
    QVERIFY2(open(project, error), qPrintable(error));
    const SongInfo *const variableSong = songByLabel(project, variableLabel);
    QVERIFY2(variableSong, qPrintable(QStringLiteral("no song for '%1'").arg(variableLabel)));
    if (!variableSong)
        return;
    SongCfg updated = variableSong->cfg;
    updated.masterVolume = 99;
    QVERIFY2(SongRegistry::writeSongFlags(midiDirectory(), variableLabel,
                                          SongRegistry::mergeCfgFlags(updated), &error),
             qPrintable(error));

    bool preserved = false;
    const QStringList after = readAllLines(mkPath());
    for (qsizetype index = 0; index + 1 < after.size(); ++index) {
        if (after[index].contains(QStringLiteral("/%1.s").arg(variableLabel)) &&
            after[index + 1].contains(QStringLiteral("-R$(STD_REVERB)")) &&
            after[index + 1].contains(QStringLiteral("-V099"))) {
            preserved = true;
            break;
        }
    }
    QVERIFY(preserved);
}

void SongsMkTest::appendRemoveRuleRoundsTripsByteExactly()
{
    QString error;
    QVERIFY2(mkOnly(error), qPrintable(error));
    DecompProject project;
    QVERIFY2(open(project, error), qPrintable(error));
    const SongInfo *const song = songByLabel(project, m_songLabel);
    QVERIFY(song);
    if (!song)
        return;
    QVERIFY(!song->cfg.voicegroupArg.isEmpty());

    const QByteArray before = readAllBytes(mkPath());
    const QString newLabel = QStringLiteral("mus_mkcheck_new");
    const QStringList newFlags{QStringLiteral("-E"), QStringLiteral("-R50"),
                               QStringLiteral("-G%1").arg(song->cfg.voicegroupArg),
                               QStringLiteral("-V100")};
    QVERIFY2(SongRegistry::writeSongFlags(midiDirectory(), newLabel, newFlags, &error),
             qPrintable(error));
    QCOMPARE(SongsMk::parseFlags(mkPath()).value(newLabel), newFlags);

    QVERIFY2(SongRegistry::removeSongFlags(midiDirectory(), newLabel, &error), qPrintable(error));
    QVERIFY(!SongsMk::parseFlags(mkPath()).contains(newLabel));
    QCOMPARE(readAllBytes(mkPath()), before);
    QVERIFY2(SongRegistry::removeSongFlags(midiDirectory(), newLabel, &error), qPrintable(error));
    QCOMPARE(readAllBytes(mkPath()), before);
}

} // namespace

int runMkCheck(const QString &stagedRoot, const QString &songLabel, const QStringList &qtArguments)
{
    SongsMkTest test(stagedRoot, songLabel);
    QStringList arguments{QStringLiteral("songs-mk")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "mk.moc"
