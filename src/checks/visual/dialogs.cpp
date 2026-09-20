// Visual baselines for the modal dialog family: SettingsDialog (engine and
// song tabs), ThemeDialog, Sf2ZonePicker (grouped rows), and NewSongWizard
// (new-song and MIDI-import pages). The Sample Editor's state matrix lives
// in sampleeditor.cpp. Every scenario shows the real dialog in the
// canonical check environment and compares the actual render against
// frozen geometry + PNG baselines recorded from the unmodified UI
// (PORYDAW_RECORD_VISUAL_BASELINES=1). Nothing here exec()s a modal loop,
// opens a file dialog, or touches audio playback.
//
// Mock data comes from the prototype's canonical fixture catalog
// (widget_window_fixtures.h), so the standalone prototype windows and these
// baselines pin one set of values.

#include "checks/visual/visualbaseline.h"
#include "checks/visual/visualfixture.h"

#include <QApplication>
#include <QDialogButtonBox>
#include <QLineEdit>
#include <QPushButton>
#include <QSettings>
#include <QTabBar>
#include <QTabWidget>
#include <QTemporaryDir>
#include <QTreeWidget>
#include <QWizard>
#include <QtTest>

#include <span>

#include "audio/sf2reader.h"
#include "ui/newsongwizard.h"
#include "ui/settingsdialog.h"
#include "ui/sf2zonepicker.h"
#include "ui/theme/themecontroller.h"
#include "ui/theme/themedialog.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "widget_window_fixtures.h"

namespace {

// A region of the settings dialog that is never optional: a form field
// identified by its row label, or a checkbox / push button identified by its
// text. `kind` selects how the row's widget is found.
struct SettingsRegionRow {
    enum Kind { FormField, CheckBox, PushButton };

    Kind kind;
    const char *name;
    const char *text;
};

// The engine tab pins polyphony/mixer/rate/filter/defaults; the song tab pins
// voicegroup/volume/reverb/priority and the three flag checkboxes. Fields on
// the hidden tab are never pinned.
const SettingsRegionRow kEngineRows[] = {
    {SettingsRegionRow::FormField, "engine.polyphony", "&PCM polyphony:"},
    {SettingsRegionRow::FormField, "engine.mixer", "PCM &mixer:"},
    {SettingsRegionRow::FormField, "engine.mix-rate", "PCM &mix rate:"},
    {SettingsRegionRow::CheckBox, "engine.analog-filter", "GBA analog output filter (low-pass)"},
    {SettingsRegionRow::PushButton, "engine.restore-defaults", "Restore Defaults"},
};

const SettingsRegionRow kSongRows[] = {
    {SettingsRegionRow::FormField, "song.voicegroup", "&Voicegroup:"},
    {SettingsRegionRow::FormField, "song.volume", "&Master volume (-V):"},
    {SettingsRegionRow::FormField, "song.reverb", "&Reverb (-R):"},
    {SettingsRegionRow::FormField, "song.priority", "&Priority (-P):"},
    {SettingsRegionRow::CheckBox, "song.exact-gate", "Exact gate time (-E)"},
    {SettingsRegionRow::CheckBox, "song.extended-clocks", "48 clocks per beat (-X)"},
    {SettingsRegionRow::CheckBox, "song.no-compression", "Disable compression (-N)"},
};

// Settings dialog chrome plus the visible tab's rows. False when a required
// region renders nothing, with `error` naming the first missing field.
bool settingsRegions(QDialog &dialog, QList<checks::visual::Region> &regions, QString *error)
{
    const auto fail = [error](const QString &what) {
        *error = QStringLiteral("settings dialog: %1 renders nothing").arg(what);
        return false;
    };
    auto *tabs = dialog.findChild<QTabWidget *>();
    if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("tabs"), dialog, tabs))
        return fail(QStringLiteral("tabs"));
    if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("tab-bar"), dialog,
                                              dialog.findChild<QTabBar *>()))
        return fail(QStringLiteral("tab bar"));
    if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("button-box"), dialog,
                                              dialog.findChild<QDialogButtonBox *>()))
        return fail(QStringLiteral("button box"));
    QWidget *page = tabs->currentWidget();
    if (!page)
        return fail(QStringLiteral("current tab page"));

    const bool engineTab = tabs->currentIndex() == 0;
    const std::span<const SettingsRegionRow> rows =
        engineTab ? std::span<const SettingsRegionRow>(kEngineRows)
                  : std::span<const SettingsRegionRow>(kSongRows);
    for (const SettingsRegionRow &row : rows) {
        const QString name = QString::fromLatin1(row.name);
        const QString text = QString::fromLatin1(row.text);
        bool appended = false;
        switch (row.kind) {
        case SettingsRegionRow::FormField:
            appended = checks::visual::appendFieldRegion(regions, name, dialog, *page, text);
            break;
        case SettingsRegionRow::CheckBox:
            appended = checks::visual::appendCheckRegion(regions, name, dialog, *page, text);
            break;
        case SettingsRegionRow::PushButton:
            for (QPushButton *button : page->findChildren<QPushButton *>())
                if (button->text() == text) {
                    appended = checks::visual::appendRequiredRegion(regions, name, dialog, button);
                    break;
                }
            break;
        }
        if (!appended)
            return fail(QStringLiteral("%1 (\"%2\")").arg(name, text));
    }
    return true;
}

// Freezes the shown settings page under `id`; a row that renders nothing
// fails the scenario under the row's own name.
void compareSettingsPage(QDialog &dialog, const QString &id)
{
    QList<checks::visual::Region> regions;
    QString error;
    QVERIFY2(settingsRegions(dialog, regions, &error), qPrintable(error));
    checks::visual::compareShown(id, dialog, regions);
}

// The settings dialog is pinned under each theme the prototype ships; the row
// name is the theme token the baseline IDs are built from.
struct SettingsTheme {
    const char *id;
    themes::Theme (*theme)();
};

const SettingsTheme kSettingsThemes[] = {
    {"vanilla", &themes::vanilla},
    {"darkneutralhigh", &themes::darkNeutralHigh},
};

// Applies the named theme; false when no row carries that id.
bool applyTheme(QApplication &application, const QString &id)
{
    for (const SettingsTheme &entry : kSettingsThemes)
        if (id == QLatin1String(entry.id)) {
            themes::apply(application, entry.theme());
            return true;
        }
    return false;
}

// Settle a dialog again after a change re-laid-out its pages: pump the
// relayout, re-park focus so no blinking caret lands in the grab, then pump
// once more.
void resettle(QWidget &widget)
{
    QApplication::processEvents();
    checks::visual::parkFocus(widget);
    QApplication::processEvents();
}

// Wizard chrome: current page area plus the button row, so page geometry and
// navigation buttons are pinned independently of page content.
bool wizardRegions(QWizard &wizard, QList<checks::visual::Region> &regions)
{
    if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("page"), wizard,
                                              wizard.currentPage()))
        return false;
    const struct {
        QWizard::WizardButton button;
        const char *name;
    } buttons[] = {{QWizard::BackButton, "button-back"},
                   {QWizard::NextButton, "button-next"},
                   {QWizard::FinishButton, "button-finish"},
                   {QWizard::CancelButton, "button-cancel"}};
    for (const auto &entry : buttons)
        if (QWidget *button = wizard.button(entry.button))
            if (button->isVisible() &&
                !checks::visual::appendRequiredRegion(regions, QString::fromLatin1(entry.name),
                                                      wizard, button))
                return false;
    return true;
}

// Advances the wizard one page and freezes it: next(), settle, assert the page
// the wizard actually landed on, then re-collect the new page's regions.
void advanceWizardPage(QWizard &wizard, const QString &id, int expectedPageId,
                       QList<checks::visual::Region> &regions)
{
    wizard.next();
    resettle(wizard);
    QCOMPARE(wizard.currentId(), expectedPageId);
    regions.clear();
    QVERIFY2(wizardRegions(wizard, regions), "wizard chrome not found");
    checks::visual::compareShown(id, wizard, regions);
}

// Zone picker chrome plus the first group and zone rows, frozen at the rects
// the viewport actually paints.
bool zonePickerRegions(QDialog &dialog, QList<checks::visual::Region> &regions)
{
    if (!checks::visual::appendNamedRegion(regions, QStringLiteral("search"), dialog,
                                           QStringLiteral("sf2SearchEdit")))
        return false;
    auto *tree = dialog.findChild<QTreeWidget *>(QStringLiteral("sf2ZoneTree"));
    if (!checks::visual::appendRequiredRegion(regions, QStringLiteral("zone-tree"), dialog, tree))
        return false;
    const QRect viewportBounds =
        checks::visual::childRegion(QStringLiteral("zone-tree"), dialog, *tree).bounds;
    const auto itemRegion = [&dialog, tree, viewportBounds](const QString &name,
                                                            QTreeWidgetItem *item) {
        const QRect rect = tree->visualItemRect(item);
        return checks::visual::Region{
            name,
            QRect(tree->viewport()->mapTo(&dialog, rect.topLeft()), rect.size()) & viewportBounds};
    };
    QTreeWidgetItem *group = tree->topLevelItem(0);
    if (!group || group->childCount() == 0)
        return false;
    regions.append(itemRegion(QStringLiteral("zone-tree.group-row"), group));
    regions.append(itemRegion(QStringLiteral("zone-tree.zone-row"), group->child(0)));
    return checks::visual::appendNamedRegion(regions, QStringLiteral("button-box"), dialog,
                                             QStringLiteral("sf2ButtonBox"));
}

} // namespace

class VisualDialogsTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VisualDialogsTest)

  public:
    VisualDialogsTest() = default;

  private slots:
    void initTestCase();
    void cleanup();

    void settingsDialog_data();
    void settingsDialog();
    void themeDialog();
    void sf2ZonePicker();
    void newSongWizardPages();
    void midiImportWizardPages();

  private:
    QApplication *app() const;
    QTemporaryDir m_settingsDirectory;
};

QApplication *VisualDialogsTest::app() const
{
    return qobject_cast<QApplication *>(QCoreApplication::instance());
}

void VisualDialogsTest::initTestCase()
{
    QVERIFY2(m_settingsDirectory.isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory.path());
}

void VisualDialogsTest::cleanup()
{
    // Every scenario returns the app to the committed vanilla baseline so
    // theme state never leaks between tests.
    if (app())
        themes::apply(*app(), themes::vanilla());
}

void VisualDialogsTest::settingsDialog_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<QString>("engineId");
    QTest::addColumn<QString>("songId");
    for (const SettingsTheme &entry : kSettingsThemes) {
        const QString theme = QString::fromLatin1(entry.id);
        QTest::newRow(entry.id) << theme << QStringLiteral("settings/engine-%1").arg(theme)
                                << QStringLiteral("settings/song-%1").arg(theme);
    }
}

void VisualDialogsTest::settingsDialog()
{
    QFETCH(QString, theme);
    QFETCH(QString, engineId);
    QFETCH(QString, songId);
    QVERIFY2(applyTheme(*app(), theme),
             qPrintable(QStringLiteral("unknown theme '%1'").arg(theme)));

    SettingsDialog dialog(sgw_visualEngineSettings(), sgw_visualSongTarget(),
                          sgw_visualVoicegroups());
    auto *tabs = dialog.findChild<QTabWidget *>();
    QVERIFY(tabs);
    // Pin the constructor's requested size before show: Qt shrinks
    // first-show top-levels to available screen geometry, which would make
    // the baseline depend on the recording monitor.
    dialog.setFixedSize(560, 580); // SettingsDialog ctor resize(560, 580)

    tabs->setCurrentIndex(0);
    checks::visual::showSettled(dialog);
    compareSettingsPage(dialog, engineId);

    tabs->setCurrentIndex(1);
    resettle(dialog);
    compareSettingsPage(dialog, songId);
}

void VisualDialogsTest::themeDialog()
{
    themes::apply(*app(), themes::vanilla());
    QSettings settings;
    themes::ThemeController controller(*app(), settings);
    controller.restore();
    themes::ThemeDialog dialog(controller);
    dialog.setFixedSize(dialog.size()); // ctor already resize(sizeHint())
    checks::visual::showSettled(dialog);

    QList<checks::visual::Region> regions;
    for (const auto &entry : {std::pair{"mode-vanilla", "vanillaModeButton"},
                              {"mode-dark", "darkNeutralHighModeButton"},
                              {"mode-immaterial", "immaterialModeButton"},
                              {"contrast-slider", "gridLineContrastSlider"},
                              {"apply", "themeApplyButton"},
                              {"close", "themeCloseButton"}})
        QVERIFY2(checks::visual::appendNamedRegion(regions, QString::fromLatin1(entry.first),
                                                   dialog, QString::fromLatin1(entry.second)),
                 entry.second);
    checks::visual::compareShown(QStringLiteral("theme/dialog-vanilla"), dialog, regions);
}

void VisualDialogsTest::sf2ZonePicker()
{
    themes::apply(*app(), themes::vanilla());
    const Sf2File font = sgw_visualSoundFont();
    Sf2ZonePicker picker(font);
    picker.setFixedSize(720, 480); // ctor resize(720, 480)
    checks::visual::showSettled(picker);
    QList<checks::visual::Region> regions;
    QVERIFY2(zonePickerRegions(picker, regions), "zone picker widgets not found");
    checks::visual::compareShown(QStringLiteral("sf2-zone-picker/dialog-vanilla"), picker, regions);
}

void VisualDialogsTest::newSongWizardPages()
{
    themes::apply(*app(), themes::vanilla());
    NewSongWizard wizard(sgw_visualProjectData());
    // Pin the size Qt would choose pre-screen-fit: sizeHint expanded to
    // the ctor's fontPx-derived minimum.
    wizard.setFixedSize(wizard.sizeHint().expandedTo(wizard.minimumSize()));
    // The blank wizard's identity page is incomplete until a name is typed;
    // fill it so Next advances deterministically.
    QLineEdit *name = nullptr;
    for (QLineEdit *edit : wizard.findChildren<QLineEdit *>())
        if (edit->placeholderText() == QStringLiteral("mus_my_song"))
            name = edit;
    QVERIFY2(name, "identity name field not found");
    name->setText(QStringLiteral("mus_visual_check"));
    checks::visual::showSettled(wizard);
    QCOMPARE(wizard.currentId(), 0);
    QList<checks::visual::Region> regions;
    QVERIFY2(wizardRegions(wizard, regions), "wizard chrome not found");
    checks::visual::compareShown(QStringLiteral("wizard/new-identity-vanilla"), wizard, regions);
    advanceWizardPage(wizard, QStringLiteral("wizard/new-sound-vanilla"), 1, regions);
}

void VisualDialogsTest::midiImportWizardPages()
{
    themes::apply(*app(), themes::vanilla());
    NewSongWizard wizard(sgw_visualProjectData(), sgw_visualImportSmf(),
                         QStringLiteral("fix/external_import.mid"));
    // Pin the size Qt would choose pre-screen-fit: sizeHint expanded to
    // the ctor's fontPx-derived minimum.
    wizard.setFixedSize(wizard.sizeHint().expandedTo(wizard.minimumSize()));
    checks::visual::showSettled(wizard);
    QCOMPARE(wizard.currentId(), 0);
    QList<checks::visual::Region> regions;
    QVERIFY2(wizardRegions(wizard, regions), "wizard chrome not found");
    checks::visual::compareShown(QStringLiteral("wizard/import-analysis-vanilla"), wizard, regions);
    advanceWizardPage(wizard, QStringLiteral("wizard/import-identity-vanilla"), 1, regions);
    advanceWizardPage(wizard, QStringLiteral("wizard/import-sound-vanilla"), 2, regions);
}

int runVisualDialogsCheck(QApplication &application, const QStringList &qtArguments)
{
    checks::visual::prepare(application); // canonical style, font, theme, app init
    VisualDialogsTest test;
    QStringList arguments{QStringLiteral("visual-dialogs")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "dialogs.moc"
