#include "checks/onboardcheck/onboardingtest.h"

#include <QAbstractButton>
#include <QApplication>
#include <QFile>
#include <QFileInfo>
#include <QMessageBox>
#include <QProcess>
#include <QWidget>
#include <optional>

#include "checks/support/asyncwait.h"
#include "checks/support/songfixture.h"
#include "mainwindow.h"
#include "ui/songtab.h"
#include "ui/workspaceui.h"

OnboardingTest::OnboardingTest(QString projectRoot, QString mid2agbPath)
    : m_projectRoot(std::move(projectRoot))
    , m_mid2agbPath(std::move(mid2agbPath))
{}

OnboardingTest::~OnboardingTest() = default;

std::unique_ptr<checks::ProjectFixture> OnboardingTest::copyProject(QString &error)
{
    return checks::ProjectFixture::copyOf(m_projectRoot, error);
}

QByteArray OnboardingTest::readFile(const QString &path, QString &error) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        error = path + QStringLiteral(": ") + file.errorString();
        return {};
    }
    error.clear();
    return file.readAll();
}

bool OnboardingTest::writeFile(const QString &path, const QByteArray &bytes, QString &error) const
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        error = path + QStringLiteral(": ") + file.errorString();
        return false;
    }
    if (file.write(bytes) != bytes.size()) {
        error = path + QStringLiteral(": ") + file.errorString();
        return false;
    }
    error.clear();
    return true;
}

bool OnboardingTest::midiFixture(const QString &name, SmfFile &midi, QString &error) const
{
    const QString path = m_projectRoot + QStringLiteral("/test_midis/") + name;
    return SmfFile::readFile(path, &midi, &error);
}

int OnboardingTest::registeredCount(const DecompProject &project) const
{
    int count = 0;
    for (const SongInfo &song : project.songs())
        count += song.registered ? 1 : 0;
    return count;
}

QString OnboardingTest::midiDirectory(const QString &root) const
{
    return root + QStringLiteral("/sound/songs/midi");
}

bool OnboardingTest::defaultCfg(const QString &root, SongCfg &cfg, QString &error) const
{
    const QStringList voicegroups = SongRegistry::voicegroupArgs(root);
    if (voicegroups.isEmpty()) {
        error = QStringLiteral("project has no voicegroups");
        return false;
    }
    cfg = {};
    cfg.exactGate = true;
    cfg.reverb = 50;
    cfg.masterVolume = 100;
    cfg.voicegroupArg = voicegroups.first();
    cfg.rawFlags = SongRegistry::mergeCfgFlags(cfg);
    error.clear();
    return true;
}

bool OnboardingTest::compile(const QString &root, const QString &midPath, const QStringList &flags,
                             QString &error) const
{
    const QString binary =
        m_mid2agbPath.isEmpty() ? root + QStringLiteral("/tools/mid2agb/mid2agb") : m_mid2agbPath;
    if (!QFileInfo(binary).isExecutable()) {
        error = QStringLiteral("mid2agb is not executable: ") + binary;
        return false;
    }
    if (!midPath.endsWith(QStringLiteral(".mid"))) {
        error = QStringLiteral("expected a .mid file: ") + midPath;
        return false;
    }
    const QString out = midPath.left(midPath.size() - 4) + QStringLiteral(".s");
    QProcess process;
    process.start(binary, QStringList(flags) << midPath << out);
    if (!process.waitForFinished(15000)) {
        error = QStringLiteral("mid2agb timed out: ") + process.errorString();
        return false;
    }
    const QString detail = QString::fromLocal8Bit(process.readAllStandardOutput()) +
                           QString::fromLocal8Bit(process.readAllStandardError());
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 ||
        QFileInfo(out).size() <= 0) {
        error = QStringLiteral("mid2agb failed: ") + detail;
        return false;
    }
    error.clear();
    return true;
}

bool OnboardingTest::openSong(MainWindow &window, const QString &root, const QString &label,
                              QString &error) const
{
    window.m_persistSession = false;
    window.m_workspace->restoreSongFilters({});
    const std::optional<SongName> name = SongName::create(label);
    if (!name) {
        error = QStringLiteral("invalid song label: ") + label;
        return false;
    }
    window.m_workspace->requestProjectOpenAt(root);
    if (checks::async_wait::waitUntil([] { return true; },
                                      [&window] {
                                          const ProjectOpenState state =
                                              window.m_workspace->projectState().state;
                                          return state == ProjectOpenState::Ready ||
                                                 state == ProjectOpenState::Failed;
                                      }) != checks::async_wait::Result::Ready ||
        window.m_workspace->projectState().state != ProjectOpenState::Ready) {
        error = QStringLiteral("project did not open");
        return false;
    }
    window.m_workspace->requestSongOpen(*name);
    if (checks::async_wait::waitUntil(
            [&window] {
                return window.m_workspace->projectState().state == ProjectOpenState::Ready;
            },
            [&window, &name] {
                SongTab *tab = window.m_workspace->songTabFor(*name);
                return tab && tab->isReady() && window.m_workspace->selectedSongTab() == tab;
            }) != checks::async_wait::Result::Ready) {
        error = QStringLiteral("song tab did not become ready: ") + label;
        return false;
    }
    SongTab *tab = window.m_workspace->songTabFor(*name);
    if (!tab || tab->document().label() != label) {
        error = QStringLiteral("opened wrong song tab: ") + label;
        return false;
    }
    error.clear();
    return true;
}

QMessageBox *OnboardingTest::waitForDialog(MainWindow &window, OnboardingDialog operation,
                                           QString &error) const
{
    QMessageBox *dialog = nullptr;
    const auto expectedRole = [operation] {
        switch (operation) {
        case OnboardingDialog::Register:
            return QMessageBox::AcceptRole;
        case OnboardingDialog::Delete:
            return QMessageBox::DestructiveRole;
        }
        return QMessageBox::InvalidRole;
    };
    const bool appeared = QTest::qWaitFor([&] {
        QWidget *const modal = QApplication::activeModalWidget();
        if (!modal)
            return false;
        auto *box = qobject_cast<QMessageBox *>(modal);
        if (!box || box->parent() != &window) {
            error = QStringLiteral("unexpected modal dialog: ") + modal->metaObject()->className();
            modal->close();
            return true;
        }
        for (QAbstractButton *button : box->buttons()) {
            if (box->buttonRole(button) == expectedRole()) {
                dialog = box;
                return true;
            }
        }
        error = QStringLiteral("unexpected modal button roles after requested operation");
        box->reject();
        return true;
    });
    if (!appeared && error.isEmpty())
        error = QStringLiteral("expected modal dialog did not appear");
    return dialog;
}

void OnboardingTest::closeWorkspace(MainWindow &window) const
{
    window.close();
    QCoreApplication::processEvents();
}

int runOnboardCheck(const QString &projectRoot, const QString &mid2agbPath,
                    const QStringList &qtArguments)
{
    OnboardingTest test(projectRoot, mid2agbPath);
    QStringList arguments{QStringLiteral("onboardcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

void OnboardingTest::projectEnumerationAndTrackBudgets()
{
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    QVERIFY(!SongRegistry::voicegroupArgs(root).isEmpty());
    QVERIFY(!SongRegistry::musicPlayers(root).isEmpty());
    const QString tablePath = root + QStringLiteral("/sound/music_player_table.inc");
    const QByteArray original = readFile(tablePath, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const QByteArray table =
        QByteArrayLiteral("\t.equiv NUM_TRACKS_BGM, 12\n\t.equiv NUM_TRACKS_SE2, 20\n\n"
                          "gMPlayTable::\n"
                          "\tmusic_player gMPlayInfo_BGM, gMPlayTrack_BGM, NUM_TRACKS_BGM, 0\n"
                          "\tmusic_player gMPlayInfo_SE1, gMPlayTrack_SE1, 3, 1\n"
                          "\tmusic_player gMPlayInfo_SE2, gMPlayTrack_SE2, NUM_TRACKS_SE2, 1\n"
                          "\tmusic_player gMPlayInfo_SE3, gMPlayTrack_SE3, NUM_TRACKS_WHO, 0\n");
    QVERIFY2(writeFile(tablePath, table, error), qPrintable(error));
    const QVector<MusicPlayer> players = SongRegistry::musicPlayers(root);
    const auto count = [&players](const QString &name) {
        for (const MusicPlayer &player : players)
            if (player.name == name)
                return player.trackCount;
        return -2;
    };
    QCOMPARE(count(QStringLiteral("MUSIC_PLAYER_BGM")), 12);
    QCOMPARE(count(QStringLiteral("MUSIC_PLAYER_SE1")), 3);
    QCOMPARE(count(QStringLiteral("MUSIC_PLAYER_SE2")), 16);
    QCOMPARE(count(QStringLiteral("MUSIC_PLAYER_SE3")), -1);
    DecompProject project;
    QVERIFY2(project.open(root, &error), qPrintable(error));
    SongInfo song;
    song.player = QStringLiteral("MUSIC_PLAYER_BGM");
    QCOMPARE(project.trackBudgetFor(song), 12);
    song.player = QStringLiteral("MUSIC_PLAYER_SE3");
    QCOMPARE(project.trackBudgetFor(song), 16);
    QVERIFY2(writeFile(tablePath, original, error), qPrintable(error));
}
