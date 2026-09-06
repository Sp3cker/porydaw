#include "checks/onboardcheck/onboardingtest.h"

#include <QAbstractButton>
#include <QApplication>
#include <QFile>
#include <QMessageBox>
#include <QSettings>
#include <QTimer>
#include <QVariant>
#include <QWidget>

#include "checks/support/asyncwait.h"
#include "checks/support/songfixture.h"
#include "mainwindow.h"
#include "ui/workspaceui.h"
#include <optional>
#include <utility>
#include <vector>

namespace {
QString midPath(const QString &root, const QString &label)
{
    return root + QStringLiteral("/sound/songs/midi/%1.mid").arg(label);
}

class SettingsGuard final
{
  public:
    SettingsGuard()
    {
        for (const QString &key : m_settings.allKeys())
            m_values.emplace_back(key, m_settings.value(key));
        m_settings.clear();
        m_settings.sync();
    }

    ~SettingsGuard()
    {
        m_settings.clear();
        for (const auto &[key, value] : m_values)
            m_settings.setValue(key, value);
        m_settings.sync();
    }

    SettingsGuard(const SettingsGuard &) = delete;
    SettingsGuard &operator=(const SettingsGuard &) = delete;

  private:
    QSettings m_settings;
    std::vector<std::pair<QString, QVariant>> m_values;
};

QAbstractButton *buttonWithRole(QMessageBox &dialog, QMessageBox::ButtonRole role)
{
    for (QAbstractButton *button : dialog.buttons())
        if (dialog.buttonRole(button) == role)
            return button;
    return nullptr;
}
} // namespace

void OnboardingTest::registerAction()
{
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    const QString label = QStringLiteral("mus_onboardcheck_action_register");
    const QString constant = SongRegistry::constantForLabel(label);
    SongCfg cfg;
    QVERIFY2(defaultCfg(root, cfg, error), qPrintable(error));
    QVERIFY2(SongRegistry::blankSong().writeFile(midPath(root, label), &error), qPrintable(error));
    QVERIFY2(SongRegistry::writeSongFlags(midiDirectory(root), label, cfg.rawFlags, &error),
             qPrintable(error));
    int id = -1;
    QVERIFY2(SongRegistry::registerSong(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"),
                                        &error, &id),
             qPrintable(error));
    const RegistrationPlan plan =
        SongRegistry::makePlan(root, label, constant, QStringLiteral("MUSIC_PLAYER_BGM"));
    QVERIFY(plan.charmapApplicable);
    const QString charmap = root + QStringLiteral("/charmap.txt");
    const QByteArray complete = readFile(charmap, error);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const int at = complete.indexOf(plan.charmapLine.toUtf8());
    QVERIFY(at >= 0);
    const int end = complete.indexOf('\n', at);
    QVERIFY(end >= at);
    QByteArray stripped = complete;
    stripped.remove(at, end - at + 1);
    QVERIFY2(writeFile(charmap, stripped, error), qPrintable(error));

    SettingsGuard settings;
    MainWindow window;
    QVERIFY2(openSong(window, root, label, error), qPrintable(error));
    QVERIFY(window.m_registerAction->isEnabled());
    const SongInfo *partial = nullptr;
    for (const SongInfo &song : window.m_workspace->projectState().snapshot.songs())
        if (song.label == label)
            partial = &song;
    QVERIFY(partial);
    QVERIFY(partial->registered);
    QCOMPARE(partial->registrationGaps, QStringList{QStringLiteral("charmap.txt")});
    QVERIFY(window.m_workspace->isSongListed(label));
    window.m_workspace->registerSelectedSong();
    QMessageBox *dialog = waitForDialog(window, OnboardingDialog::Register, error);
    QVERIFY2(dialog, qPrintable(error));
    QAbstractButton *button = buttonWithRole(*dialog, QMessageBox::AcceptRole);
    QVERIFY(button);
    button->click();
    QCOMPARE(checks::async_wait::waitUntil(
                 [&window] {
                     return window.m_workspace->projectState().state == ProjectOpenState::Ready;
                 },
                 [&window, &label] {
                     for (const SongInfo &song :
                          window.m_workspace->projectState().snapshot.songs())
                         if (song.label == label)
                             return song.registered && song.registrationGaps.isEmpty() &&
                                    window.m_workspace->isSongListed(label) &&
                                    !window.m_registerAction->isEnabled();
                     return false;
                 }),
             checks::async_wait::Result::Ready);
    QCOMPARE(readFile(charmap, error), complete);
    QVERIFY2(error.isEmpty(), qPrintable(error));
    const std::optional<SongName> name = SongName::create(label);
    QVERIFY(name.has_value());
    window.m_workspace->requestSongOpen(*name);
    QCOMPARE(
        checks::async_wait::waitUntil(
            [] { return true; }, [&window] { return window.m_workspace->openProjectEnabled(); }),
        checks::async_wait::Result::Ready);
    QVERIFY(!window.m_registerAction->isEnabled());
    closeWorkspace(window);
}

void OnboardingTest::deleteAction_data()
{
    QTest::addColumn<bool>("fallback");
    QTest::newRow("delete-open-song") << false;
    QTest::newRow("fallback-refusal") << true;
}

void OnboardingTest::deleteAction()
{
    QFETCH(bool, fallback);
    QString error;
    std::unique_ptr<checks::ProjectFixture> fixture = copyProject(error);
    QVERIFY2(fixture, qPrintable(error));
    const QString root = fixture->root();
    SongCfg cfg;
    QVERIFY2(defaultCfg(root, cfg, error), qPrintable(error));
    QString label;
    if (!fallback) {
        label = QStringLiteral("mus_onboardcheck_action_delete");
        QVERIFY2(SongRegistry::blankSong().writeFile(midPath(root, label), &error),
                 qPrintable(error));
        QVERIFY2(SongRegistry::writeSongFlags(midiDirectory(root), label, cfg.rawFlags, &error),
                 qPrintable(error));
        int id = -1;
        QVERIFY2(SongRegistry::registerSong(root, label, SongRegistry::constantForLabel(label),
                                            QStringLiteral("MUSIC_PLAYER_BGM"), &error, &id),
                 qPrintable(error));
    } else {
        DecompProject project;
        QVERIFY2(project.open(root, &error), qPrintable(error));
        for (const SongInfo &song : project.songs())
            if (song.registered && song.id == 0)
                label = song.label;
        QVERIFY(!label.isEmpty());
        if (!QFile::exists(midPath(root, label)))
            QVERIFY2(SongRegistry::blankSong().writeFile(midPath(root, label), &error),
                     qPrintable(error));
    }

    SettingsGuard settings;
    MainWindow window;
    QVERIFY2(openSong(window, root, label, error), qPrintable(error));
    const QStringList files = {root + QStringLiteral("/sound/song_table.inc"),
                               root + QStringLiteral("/include/constants/songs.h"),
                               root + QStringLiteral("/ld_script.ld"),
                               root + QStringLiteral("/charmap.txt"),
                               midiDirectory(root) + QStringLiteral("/midi.cfg"),
                               root + QStringLiteral("/src/debug.c")};
    QList<QByteArray> before;
    for (const QString &path : files) {
        before.append(readFile(path, error));
        QVERIFY2(error.isEmpty(), qPrintable(error));
    }
    const qsizetype listed = window.m_workspace->listedSongCount();
    if (fallback) {
        bool refusalHandled = false;
        QTimer refusalCloser;
        refusalCloser.setInterval(0);
        connect(&refusalCloser, &QTimer::timeout, &window, [&] {
            QWidget *const modal = QApplication::activeModalWidget();
            if (!modal)
                return;
            auto *const dialog = qobject_cast<QMessageBox *>(modal);
            if (!dialog || dialog->parent() != &window) {
                error = QStringLiteral("unexpected modal dialog during fallback refusal");
                modal->close();
                refusalHandled = true;
                return;
            }
            if (!dialog->text().contains(label))
                error = QStringLiteral("fallback refusal did not identify the song");
            QAbstractButton *const button = buttonWithRole(*dialog, QMessageBox::AcceptRole);
            refusalHandled = true;
            if (button)
                button->click();
            else {
                error = QStringLiteral("fallback refusal has no accepting action");
                dialog->reject();
            }
        });
        refusalCloser.start();
        window.m_workspace->deleteSelectedSong();
        QVERIFY2(QTest::qWaitFor([&] { return refusalHandled; }),
                 "fallback refusal did not appear");
        refusalCloser.stop();
        QVERIFY2(error.isEmpty(), qPrintable(error));
        const std::optional<SongName> name = SongName::create(label);
        QVERIFY(name.has_value());
        QVERIFY(window.m_workspace->songTabFor(*name));
        for (int i = 0; i < files.size(); ++i) {
            QCOMPARE(readFile(files[i], error), before[i]);
            QVERIFY2(error.isEmpty(), qPrintable(error));
        }
        QVERIFY(QFile::exists(midPath(root, label)));
    } else {
        window.m_workspace->deleteSelectedSong();
        QMessageBox *dialog = waitForDialog(window, OnboardingDialog::Delete, error);
        QVERIFY2(dialog, qPrintable(error));
        QAbstractButton *button = buttonWithRole(*dialog, QMessageBox::DestructiveRole);
        QVERIFY(button);
        button->click();
        const std::optional<SongName> name = SongName::create(label);
        QVERIFY(name.has_value());
        QCOMPARE(checks::async_wait::waitUntil(
                     [&window] {
                         return window.m_workspace->projectState().state == ProjectOpenState::Ready;
                     },
                     [&window, &name] { return window.m_workspace->songTabFor(*name) == nullptr; }),
                 checks::async_wait::Result::Ready);
        QVERIFY(!window.m_workspace->isSongListed(label));
        QCOMPARE(window.m_workspace->listedSongCount(), listed - 1);
        QVERIFY(!QFile::exists(midPath(root, label)));
        QVERIFY(QFile::exists(root + QStringLiteral("/.porydaw/trash/%1.mid").arg(label)));
    }
    closeWorkspace(window);
}
