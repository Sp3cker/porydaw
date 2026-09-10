#include <QAction>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontInfo>
#include <QIODevice>
#include <QKeyEvent>
#include <QListWidget>
#include <QPushButton>
#include <QSettings>
#include <QSlider>
#include <QSpinBox>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTreeWidget>
#include <cstdio>

#include "mainwindow.h"
#include "ui/appearancesettingspage.h"
#include "ui/audiosettingspage.h"
#include "ui/keyboardshortcutspage.h"
#include "ui/settingsdialog.h"
#include "ui/typography.h"
#ifdef PORYDAW_SCRIPTING
#include <QLineEdit>

#include "scripting/plugininstaller.h"
#include "scripting/scripthost.h"
#endif

// --settingscheck: the Settings window (Edit → Settings…). Self-contained —
// no project needed; QSettings is redirected into a temp dir first so the
// user's real preferences are never read or written. Verifies that the
// menu action opens the window, the section list drives the page stack and
// the last section is remembered across a close/reopen and a relaunch,
// that the Audio page's controls apply immediately (engine knobs persist
// as they change; the output level reaches the engine) and Restore
// Defaults returns them all, that the Appearance page's font choice lands
// in typography and persists, that the Shortcuts page is the real
// editor, and — with scripting — that the Plugins page's folder row is a
// setting, its Add Plugin button is present, and plugin installation copies
// the full source tree without overwriting an existing plugin.
// With a shot path, each page is also saved as <shot>-<page>.png.

int runSettingsCheck(const QString &shotPath)
{
    QTemporaryDir settingsDir;
    if (!settingsDir.isValid()) {
        std::fprintf(stderr, "settingscheck: no temp dir for settings\n");
        return 1;
    }
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, settingsDir.path());
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir.path());
    QSettings::setDefaultFormat(QSettings::IniFormat);
    // The plugins-folder check returns to the *default* folder, which must
    // not be the user's real app data (their plugins would load and run).
    QStandardPaths::setTestModeEnabled(true);

    int failures = 0;
    const auto check = [&failures](bool ok, const char *what) {
        if (!ok) {
            std::fprintf(stderr, "settingscheck: FAIL: %s\n", what);
            failures++;
        }
        return ok;
    };

    {
        MainWindow window;
        SettingsDialog *dialog = window.settingsDialog();
        if (!check(dialog != nullptr, "main window has no Settings window"))
            return 1;
        auto *action = window.findChild<QAction *>(QStringLiteral("editSettingsAction"));
        auto *sections = dialog->findChild<QListWidget *>(QStringLiteral("settingsSections"));
        auto *stack = dialog->findChild<QStackedWidget *>(QStringLiteral("settingsStack"));
        auto *closeButton = dialog->findChild<QPushButton *>(QStringLiteral("settingsCloseButton"));
        if (!check(action && sections && stack && closeButton, "Settings window chrome not found"))
            return 1;

        // 1. Merely building the window never writes QSettings.
        check(!QSettings().contains(QStringLiteral("settings/lastPage")),
              "constructing the Settings window wrote the remembered section");

        // 2. The menu action shows it, on Audio the first time.
        check(!dialog->isVisible(), "Settings window was visible before being opened");
        action->trigger();
        QApplication::processEvents();
        check(dialog->isVisible(), "Edit → Settings did not open the window");
#ifdef PORYDAW_SCRIPTING
        check(sections->count() == 4, "Settings window does not have four sections");
#else
        check(sections->count() == 3, "Settings window does not have three sections");
#endif
        check(dialog->currentPage() == SettingsDialog::Page::Audio &&
                  stack->currentWidget() == dialog->audioPage(),
              "Settings window did not open on Audio first");

        const auto shoot = [&](const char *page) {
            if (shotPath.isEmpty())
                return;
            QApplication::processEvents();
            QString path = shotPath;
            const int dot = path.lastIndexOf(QLatin1Char('.'));
            const QString suffix = QStringLiteral("-%1").arg(QLatin1String(page));
            path = dot > 0 ? path.left(dot) + suffix + path.mid(dot) : path + suffix;
            dialog->grab().save(path);
        };
        shoot("audio");

        // 3. The section list drives the stack; the choice is remembered
        // across close/reopen.
        sections->setCurrentRow(1);
        check(dialog->currentPage() == SettingsDialog::Page::Appearance &&
                  stack->currentWidget() == dialog->appearancePage(),
              "selecting Appearance did not switch the page");
        shoot("appearance");
        sections->setCurrentRow(2);
        check(stack->currentWidget() == dialog->shortcutsPage() &&
                  dialog->shortcutsPage()->findChild<QTreeWidget *>() != nullptr,
              "selecting Keyboard Shortcuts did not show the shortcuts editor");
        shoot("shortcuts");
#ifdef PORYDAW_SCRIPTING
        sections->setCurrentRow(3);
        check(dialog->currentPage() == SettingsDialog::Page::Plugins &&
                  stack->currentWidget() == dialog->pluginsPage() &&
                  dialog->pluginsPage()->findChild<QTreeWidget *>() != nullptr,
              "selecting Plugins did not show the plugins page");
        shoot("plugins");

        // The plugins folder is a setting: the row shows the folder in
        // use, a changed folder persists and reloads the host at once, Use
        // Default clears it, and PORYDAW_PLUGINS_DIR beats the setting for
        // a run without touching it.
        {
            QTemporaryDir customDir;
            scripting::ScriptHost *host = window.scriptHost();
            auto *folder = dialog->pluginsPage()->findChild<QLineEdit *>(
                QStringLiteral("settingsPluginsFolder"));
            auto *change = dialog->pluginsPage()->findChild<QPushButton *>(
                QStringLiteral("settingsPluginsChangeFolder"));
            auto *useDefault = dialog->pluginsPage()->findChild<QPushButton *>(
                QStringLiteral("settingsPluginsDefaultFolder"));
            const bool envSet = !scripting::ScriptHost::environmentPluginsDir().isEmpty();
            if (envSet)
                std::fprintf(stderr, "settingscheck: PORYDAW_PLUGINS_DIR is set; skipping the "
                                     "plugins-folder setting check\n");
            if (check(host && folder && change && useDefault && customDir.isValid(),
                      "Plugins page folder row not found") &&
                !envSet) {
                const QString defaultDir = scripting::ScriptHost::defaultPluginsDir();
                check(QDir::cleanPath(host->pluginsDir()) == QDir::cleanPath(defaultDir) &&
                          folder->text() == QDir::toNativeSeparators(defaultDir) &&
                          !useDefault->isEnabled() && change->isEnabled(),
                      "Plugins page did not start on the default folder");
                host->setPluginsDirSetting(customDir.path());
                host->loadAll();
                QApplication::processEvents();
                check(QSettings().value(QStringLiteral("pluginsDir")).toString() ==
                          customDir.path(),
                      "changed plugins folder was not persisted");
                check(host->pluginsDir() == customDir.path() &&
                          folder->text() == QDir::toNativeSeparators(customDir.path()) &&
                          useDefault->isEnabled(),
                      "changed plugins folder did not reach the host and the page");
                check(scripting::ScriptHost::resolvePluginsDir() == customDir.path(),
                      "a fresh host would not start on the saved folder");
                QSettings().setValue(QStringLiteral("pluginsDir"), QStringLiteral("plugins"));
                check(scripting::ScriptHost::configuredPluginsDir() == defaultDir,
                      "a relative saved folder must fall back to the default");
                QSettings().setValue(QStringLiteral("pluginsDir"), customDir.path() + "/./");
                check(scripting::ScriptHost::configuredPluginsDir() == customDir.path(),
                      "the saved folder was not normalised");
                host->setPluginsDirSetting(customDir.path());
                qputenv("PORYDAW_PLUGINS_DIR", "/nonexistent/env-plugins");
                check(scripting::ScriptHost::resolvePluginsDir() ==
                              QStringLiteral("/nonexistent/env-plugins") &&
                          scripting::ScriptHost::configuredPluginsDir() == customDir.path(),
                      "PORYDAW_PLUGINS_DIR did not override the saved folder");
                host->setPluginsDirSetting(defaultDir);
                check(host->pluginsDir() == customDir.path() &&
                          !QSettings().contains(QStringLiteral("pluginsDir")),
                      "with the environment override, the setting must persist without moving "
                      "the host");
                qunsetenv("PORYDAW_PLUGINS_DIR");
                host->setPluginsDirSetting(customDir.path());
                host->loadAll();
                QApplication::processEvents();
                check(useDefault->isEnabled(),
                      "Use Default was not re-enabled after the folder changed");
                useDefault->click();
                QApplication::processEvents();
                check(QDir::cleanPath(host->pluginsDir()) == QDir::cleanPath(defaultDir) &&
                          !QSettings().contains(QStringLiteral("pluginsDir")) &&
                          !useDefault->isEnabled() &&
                          folder->text() == QDir::toNativeSeparators(defaultDir),
                      "Use Default did not return to the default folder");
            }
        }

        // Add Plugin… is a small UI wrapper around the installer. Keep the
        // settings check at that boundary: the button must exist, while the
        // filesystem behavior is exercised directly without automating a
        // platform file dialog.
        {
            QTemporaryDir sourceRoot;
            QTemporaryDir installDir;
            QTemporaryDir manifestInstallDir;
            scripting::ScriptHost *host = window.scriptHost();
            auto *page = dialog->pluginsPage();
            auto *add = page != nullptr
                            ? page->findChild<QPushButton *>(QStringLiteral("settingsPluginsAdd"))
                            : nullptr;
            auto *list = page != nullptr
                             ? page->findChild<QTreeWidget *>(QStringLiteral("settingsPluginsTree"))
                             : nullptr;
            const QString fixtureId = QStringLiteral("add-plugin-fixture");
            const QString source =
                sourceRoot.isValid() ? sourceRoot.path() + QLatin1Char('/') + fixtureId : QString();
            const QString manifest = QStringLiteral(
                R"({ "id": "add-plugin-fixture", "name": "Add Plugin Fixture", )"
                R"("version": "1.0.0", "api": 1, "description": "settingscheck fixture" })");
            const QString main = QStringLiteral("export function activate(ctx) {}\n");
            const auto write = [](const QString &path, const QString &text) {
                QDir().mkpath(QFileInfo(path).absolutePath());
                QFile file(path);
                if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
                    return false;
                const QByteArray bytes = text.toUtf8();
                return file.write(bytes) == bytes.size();
            };
            const auto read = [](const QString &path) {
                QFile file(path);
                return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll())
                                                      : QString();
            };
            const auto listShows = [list](const QString &name) {
                for (int i = 0; i < list->topLevelItemCount(); ++i) {
                    if (list->topLevelItem(i)->text(0) == name)
                        return true;
                }
                return false;
            };
            if (check(add && host && list && installDir.isValid() && manifestInstallDir.isValid() &&
                          !source.isEmpty() &&
                          write(source + QStringLiteral("/plugin.json"), manifest) &&
                          write(source + QStringLiteral("/main.js"), main) &&
                          write(source + QStringLiteral("/assets/data.txt"),
                                QStringLiteral("nested v1\n")),
                      "could not prepare the Add Plugin fixture")) {
                const QString previousDir = host->pluginsDir();
                const QString dest = installDir.path() + QLatin1Char('/') + fixtureId;
                host->setPluginsDir(installDir.path());

                QString error;
                const bool installed = scripting::installPlugin(source, host->pluginsDir(), &error);
                check(installed && error.isEmpty(), "the plugin installer rejected a valid folder");
                check(read(dest + QStringLiteral("/plugin.json")) == manifest &&
                          read(dest + QStringLiteral("/main.js")) == main &&
                          read(dest + QStringLiteral("/assets/data.txt")) ==
                              QStringLiteral("nested v1\n"),
                      "the plugin installer did not copy the complete source tree");
                check(read(source + QStringLiteral("/assets/data.txt")) ==
                          QStringLiteral("nested v1\n"),
                      "the plugin installer changed its source folder");

                QString manifestError;
                const QString manifestSelection = source + QStringLiteral("/plugin.json");
                const QString manifestDest =
                    manifestInstallDir.path() + QLatin1Char('/') + fixtureId;
                check(scripting::installPlugin(manifestSelection, manifestInstallDir.path(),
                                               &manifestError) &&
                          manifestError.isEmpty() &&
                          read(manifestDest + QStringLiteral("/assets/data.txt")) ==
                              QStringLiteral("nested v1\n"),
                      "the plugin installer rejected a valid plugin.json");

                if (installed)
                    host->loadAll();
                QApplication::processEvents();
                const scripting::Plugin *plugin = host->plugin(fixtureId);
                check(plugin != nullptr && plugin->state == scripting::PluginState::Loaded &&
                          plugin->error.isEmpty() &&
                          listShows(QStringLiteral("Add Plugin Fixture")),
                      "the installed plugin did not load and appear in the list");

                check(write(source + QStringLiteral("/assets/data.txt"),
                            QStringLiteral("nested v2\n")),
                      "could not update the Add Plugin fixture");
                QString collision;
                check(!scripting::installPlugin(source, host->pluginsDir(), &collision) &&
                          !collision.isEmpty() &&
                          read(dest + QStringLiteral("/assets/data.txt")) ==
                              QStringLiteral("nested v1\n"),
                      "the plugin installer overwrote an existing plugin");

                host->setPluginsDir(previousDir);
                host->loadAll();
                QApplication::processEvents();
            }
        }
#endif
        sections->setCurrentRow(1);
        closeButton->click();
        QApplication::processEvents();
        check(!dialog->isVisible(), "Close did not hide the Settings window");
        check(QSettings().value(QStringLiteral("settings/lastPage")).toString() ==
                  QStringLiteral("appearance"),
              "the selected section was not remembered");
        action->trigger();
        check(dialog->isVisible() && dialog->currentPage() == SettingsDialog::Page::Appearance,
              "reopening did not return to the last section");

        // 4. Audio page: every control applies as it changes.
        dialog->showPage(SettingsDialog::Page::Audio);
        auto *output = dialog->findChild<QSlider *>(QStringLiteral("settingsOutputLevel"));
        auto *polyphony = dialog->findChild<QSpinBox *>(QStringLiteral("settingsPcmPolyphony"));
        auto *mixRate = dialog->findChild<QComboBox *>(QStringLiteral("settingsPcmMixRate"));
        auto *analog = dialog->findChild<QCheckBox *>(QStringLiteral("settingsAnalogFilter"));
        auto *defaults =
            dialog->findChild<QPushButton *>(QStringLiteral("settingsAudioRestoreDefaults"));
        if (check(output && polyphony && mixRate && analog && defaults,
                  "Audio page controls not found")) {
            check(output->value() == AudioSettingsPage::kOutputLevelDefault &&
                      window.audio().outputGain() == 1.0f,
                  "output level did not start at unity");
            output->setValue(150);
            check(window.audio().outputGain() == 1.5f, "output level did not reach the engine");
            check(QSettings().value(QStringLiteral("outputLevel")).toInt() == 150,
                  "output level was not persisted as it changed");

            polyphony->setValue(3);
            check(QSettings().value(QStringLiteral("engine/maxPcmChannels")).toInt() == 3,
                  "PCM polyphony was not persisted as it changed");
            mixRate->setCurrentIndex(mixRate->findData(0));
            check(QSettings().value(QStringLiteral("engine/pcmMixRate")).toDouble() == 0.0,
                  "PCM mix rate was not persisted as it changed");
            analog->setChecked(true);
            check(QSettings().value(QStringLiteral("engine/analogFilter")).toBool(),
                  "analog filter was not persisted as it changed");
            check(dialog->audioPage()->engineSettings().maxPcmChannels == 3 &&
                      dialog->audioPage()->engineSettings().pcmMixRate == 0.0f &&
                      dialog->audioPage()->engineSettings().analogFilter,
                  "Audio page does not report what its controls show");

            defaults->click();
            const EngineSettings factory;
            check(output->value() == AudioSettingsPage::kOutputLevelDefault &&
                      window.audio().outputGain() == 1.0f,
                  "Restore Defaults did not reset the output level");
            check(polyphony->value() == factory.maxPcmChannels &&
                      mixRate->currentData().toInt() == int(factory.pcmMixRate) &&
                      analog->isChecked() == factory.analogFilter,
                  "Restore Defaults did not reset the engine knobs");
            check(QSettings().value(QStringLiteral("engine/maxPcmChannels")).toInt() ==
                          factory.maxPcmChannels &&
                      QSettings().value(QStringLiteral("engine/pcmMixRate")).toDouble() ==
                          double(factory.pcmMixRate) &&
                      !QSettings().value(QStringLiteral("engine/analogFilter")).toBool(),
                  "Restore Defaults did not persist the factory engine settings");
            // Restore Defaults on factory knobs is a no-op: it must not
            // report (the owner restarts the audio device on every report).
            int reports = 0;
            QObject::connect(dialog, &SettingsDialog::engineSettingsChanged, dialog,
                             [&reports](const EngineSettings &) { ++reports; });
            defaults->click();
            check(reports == 0, "Restore Defaults reported unchanged engine settings");

            // Enter in the polyphony spinbox commits the typed value; it
            // must not also fire Restore Defaults (the window's only push
            // button would otherwise be its default button).
            polyphony->setValue(3);
            output->setValue(150);
            polyphony->setFocus();
            QKeyEvent press(QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier);
            QKeyEvent release(QEvent::KeyRelease, Qt::Key_Return, Qt::NoModifier);
            QApplication::sendEvent(polyphony, &press);
            QApplication::sendEvent(polyphony, &release);
            QApplication::processEvents();
            check(polyphony->value() == 3 && output->value() == 150,
                  "Enter in the polyphony spinbox triggered Restore Defaults");
            // Leaves polyphony 3 behind for the relaunch check.
        }

        // 5. Appearance page: the font choice lands and persists.
        auto *systemFont = dialog->findChild<QCheckBox *>(QStringLiteral("settingsSystemFont"));
        if (check(systemFont != nullptr, "system-font checkbox not found")) {
            check(!systemFont->isChecked(), "system font did not start off");
            systemFont->setChecked(true);
            check(QFontInfo(QApplication::font()).family() == typography::systemFontFamily(),
                  "system-font checkbox did not install the platform face");
            check(QSettings().value(QStringLiteral("systemFont")).toBool(),
                  "system font choice was not persisted");
            systemFont->setChecked(false);
        }

        // 6. Escape closes too (it is a dialog), and the window survives.
        action->trigger();
        dialog->reject();
        check(!dialog->isVisible(), "Escape did not close the Settings window");
    }

    // 7. A fresh window comes back with the persisted preferences loaded
    // into the page, and the remembered section selected.
    {
        MainWindow window;
        SettingsDialog *dialog = window.settingsDialog();
        auto *polyphony = dialog->findChild<QSpinBox *>(QStringLiteral("settingsPcmPolyphony"));
        check(polyphony && polyphony->value() == 3,
              "relaunch did not load the persisted PCM polyphony into the Audio page");
        check(dialog->currentPage() == SettingsDialog::Page::Audio,
              "relaunch did not remember the last section");
    }

    if (failures == 0)
        std::printf("settingscheck: OK\n");
    return failures ? 1 : 0;
}
