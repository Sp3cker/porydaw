// Visual baseline check: freezes the voicegroup browser's rendered geometry
// and colors (tree rows, type icons, selection, used-voice tint, editor form
// states) plus the sample picker popup (search, section headers, rows, loop
// badge) as image + semantic-region baselines via checks::visual.
//
// Everything rendered comes from the checked-in decomp fixture project
// (fixture_rich covers every voice family, keysplits, drumkits, and a
// read-only cry voice) through the same production calls WorkspaceUi makes:
// DecompProject::loadBank, the VoicegroupSource catalog scans, a real
// LoadedSampleSet for loop badges, and SongView::usedVoices for row tints.
// No widget is recreated for the snapshot.

#include "checks/visual/visualbaseline.h"

#include "checks/support/songfixture.h"

#include "project/decompproject.h"
#include "project/projectworkspace.h"
#include "project/voicegroupsource.h"

#include "ui/dragspinbox.h"
#include "ui/samplepicker.h"
#include "ui/songview.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/voicegroupbrowser.h"

#include <QApplication>
#include <QComboBox>
#include <QDir>
#include <QFileInfo>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QModelIndex>
#include <QPushButton>
#include <QSet>
#include <QSpinBox>
#include <QToolButton>
#include <QTreeWidget>
#include <QTreeWidgetItemIterator>
#include <QtTest>

#include <cstdio>
#include <memory>
#include <optional>

namespace {

// The fixture song bound to fixture_rich, the voicegroup that exercises every
// editor family the browser renders.
constexpr char kSongLabel[] = "mus_route101";

// Canonical capture size: the dock adapts to whatever width the user picks,
// so the baseline pins one deterministic size instead.
constexpr QSize kBrowserSize{420, 680};

// fixture_rich slot map (see sound/voicegroups/fixture_rich.inc):
constexpr int kDirectSoundSlot = 0; // voice_directsound, looped sample
constexpr int kSquare1Slot = 4;     // sweep/duty editor rows
constexpr int kCrySlot = 12;        // read-only notice + disabled editor

struct ThemeVariant {
    const char *id;
    themes::Theme (*theme)();
};

const ThemeVariant kThemeVariants[] = {
    {"vanilla", &themes::vanilla},
    {"darkneutralhigh", &themes::darkNeutralHigh},
};

QRect mappedRect(const QWidget &root, const QWidget &child)
{
    return QRect(child.mapTo(const_cast<QWidget *>(&root), QPoint()), child.size());
}

// A tree cell's rect in captured-root coordinates (visualRect is viewport
// coordinates; the grabbed image is the browser/popup widget's).
QRect treeCellRect(const QWidget &root, QTreeWidget &tree, QTreeWidgetItem *item, int column)
{
    const QModelIndex index = tree.indexFromItem(item, column);
    if (!index.isValid())
        return QRect();
    const QRect rect = tree.visualRect(index);
    if (!rect.isValid())
        return QRect();
    // A partially scrolled row is not a stable bound: only cells fully inside
    // the tree's own rect become regions.
    const QRect inTree{tree.viewport()->mapTo(&tree, rect.topLeft()), rect.size()};
    if (!tree.rect().contains(inTree))
        return QRect();
    return {tree.viewport()->mapTo(&root, rect.topLeft()), rect.size()};
}

void addTreeRowRegions(QList<checks::visual::Region> &regions, const QWidget &root,
                       QTreeWidget &tree, QTreeWidgetItem *item, const QString &name)
{
    const QRect row = treeCellRect(root, tree, item, 0);
    if (!row.isValid())
        return;
    regions.append(
        {name,
         row.united(treeCellRect(root, tree, item, 1)).united(treeCellRect(root, tree, item, 2))});
    const QRect icon = treeCellRect(root, tree, item, 1);
    if (icon.isValid())
        regions.append({name + QStringLiteral(".type-icon"), icon});
    const QRect adsr = treeCellRect(root, tree, item, 2);
    if (adsr.isValid())
        regions.append({name + QStringLiteral(".adsr"), adsr});
}

void addWidgetRegion(QList<checks::visual::Region> &regions, const QWidget &root,
                     const QWidget *widget, const QString &name)
{
    if (widget && widget->isVisible())
        regions.append({name, mappedRect(root, *widget)});
}

// The editor's unnamed rows are reachable through their field widgets; the
// enclosing form row is the semantic unit a QML port must reproduce.
QWidget *rowOf(QWidget *field)
{
    return field ? field->parentWidget() : nullptr;
}

DragSpinBox *adsrSpin(VoicegroupBrowser &browser, const QString &tooltip)
{
    for (DragSpinBox *spin : browser.findChildren<DragSpinBox *>()) {
        if (spin->toolTip() == tooltip)
            return spin;
    }
    return nullptr;
}

QComboBox *editorTypeCombo(VoicegroupBrowser &browser)
{
    for (QComboBox *combo : browser.findChildren<QComboBox *>()) {
        if (combo->findData(int(VgMacro::Square1)) >= 0)
            return combo;
    }
    return nullptr;
}

// Semantic regions for the whole browser: named widgets via the shared
// helper plus explicit subregions for the custom-painted tree cells and the
// editor rows a port must reproduce.
QList<checks::visual::Region> browserRegions(VoicegroupBrowser &browser)
{
    auto regions = checks::visual::widgetRegions(browser);

    if (QComboBox *selector = browser.findChild<QComboBox *>(QStringLiteral("vgArgCombo")))
        addWidgetRegion(regions, browser, selector, QStringLiteral("selector"));

    auto *tree = browser.findChild<QTreeWidget *>(QString(), Qt::FindDirectChildrenOnly);
    if (tree) {
        addWidgetRegion(regions, browser, tree, QStringLiteral("tree"));
        addWidgetRegion(regions, browser, tree->header(), QStringLiteral("tree.header"));
        for (int slot = 0; slot < tree->topLevelItemCount(); ++slot) {
            QTreeWidgetItem *const item = tree->topLevelItem(slot);
            if (!item->isHidden())
                addTreeRowRegions(regions, browser, *tree, item,
                                  QStringLiteral("tree.row.%1").arg(slot, 3, 10, QLatin1Char('0')));
        }
    }

    addWidgetRegion(regions, browser,
                    browser.findChild<QLabel *>(QStringLiteral("voicegroupEditorNotice")),
                    QStringLiteral("editor.notice"));
    addWidgetRegion(regions, browser, editorTypeCombo(browser), QStringLiteral("editor.type"));
    if (SamplePickerButton *picker = browser.findChild<SamplePickerButton *>()) {
        addWidgetRegion(regions, browser, rowOf(picker), QStringLiteral("editor.sample"));
        addWidgetRegion(regions, browser, picker, QStringLiteral("editor.sample.button"));
    }
    addWidgetRegion(regions, browser,
                    browser.findChild<QToolButton *>(QStringLiteral("vgNewSampleButton")),
                    QStringLiteral("editor.sample.new"));
    addWidgetRegion(regions, browser,
                    browser.findChild<QToolButton *>(QStringLiteral("vgEditSampleButton")),
                    QStringLiteral("editor.sample.edit"));

    struct AdsrField {
        const char *name;
        const char *tooltip;
    };
    const AdsrField adsrFields[] = {
        {"attack", "Attack"},
        {"decay", "Decay"},
        {"sustain", "Sustain"},
        {"release", "Release"},
    };
    for (const AdsrField &field : adsrFields) {
        addWidgetRegion(regions, browser, adsrSpin(browser, QString::fromLatin1(field.tooltip)),
                        QStringLiteral("editor.adsr.%1").arg(QLatin1String(field.name)));
    }
    if (DragSpinBox *attack = adsrSpin(browser, QStringLiteral("Attack")))
        addWidgetRegion(regions, browser, rowOf(attack), QStringLiteral("editor.adsr"));

    // CGB-only rows (sweep, duty, period) and the synth rows surface through
    // their field widgets' tooltips; the row parent is the semantic bound.
    const QHash<QString, QString> rowTooltips = {
        {QStringLiteral("editor.sweep"), QStringLiteral("Speed: 128 Hz")},
        {QStringLiteral("editor.synth.duty"), QStringLiteral("Base duty")},
        {QStringLiteral("editor.synth.step"), QStringLiteral("Duty LFO step")},
        {QStringLiteral("editor.synth.depth"), QStringLiteral("Modulation")},
        {QStringLiteral("editor.synth.phase"), QStringLiteral("Duty LFO phase")},
    };
    for (QSpinBox *spin : browser.findChildren<QSpinBox *>()) {
        for (auto it = rowTooltips.constBegin(); it != rowTooltips.constEnd(); ++it) {
            if (spin->toolTip().startsWith(it.value()))
                addWidgetRegion(regions, browser, rowOf(spin), it.key());
        }
    }
    return regions;
}

// Semantic regions for the open picker popup: the named children plus each
// section header, every visible row, and the loop-badge cell.
QList<checks::visual::Region> popupRegions(QWidget &popup)
{
    auto regions = checks::visual::widgetRegions(popup);
    auto *tree = popup.findChild<QTreeWidget *>(QStringLiteral("vgSamplePickerList"));
    if (!tree)
        return regions;

    int section = 0;
    for (QTreeWidgetItemIterator it(tree); *it; ++it) {
        QTreeWidgetItem *const item = *it;
        if (item->isHidden())
            continue;
        const QString symbol = item->data(0, Qt::UserRole).toString();
        if (symbol.isEmpty()) {
            addTreeRowRegions(regions, popup, *tree, item,
                              QStringLiteral("picker.section.%1").arg(section++));
            continue;
        }
        const QString name = QStringLiteral("picker.row.%1").arg(symbol);
        addTreeRowRegions(regions, popup, *tree, item, name);
        const QRect badge = treeCellRect(popup, *tree, item, 1);
        if (badge.isValid() && !item->text(1).isEmpty())
            regions.append({name + QStringLiteral(".loop-badge"), badge});
    }
    return regions;
}

} // namespace

namespace checks {

class VisualBrowsersTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VisualBrowsersTest)

  public:
    explicit VisualBrowsersTest(QString projectRoot) : m_projectRoot(std::move(projectRoot)) {}

  private slots:
    void initTestCase();
    void cleanupTestCase();

    void browserBaseline_data();
    void browserBaseline();
    void editorVariants_data();
    void editorVariants();
    void samplePickerPopup_data();
    void samplePickerPopup();

  private:
    bool populateBrowser(QString &error);
    bool applyTheme(const QString &id);
    bool grabBrowser(const QString &id);
    QWidget *pickerPopup() const;

    QString m_projectRoot;
    DecompProject m_project;
    std::optional<LoadedBankView> m_bank;
    std::unique_ptr<SongViewRig> m_rig;
    SampleSetLease m_sampleSet;
    std::unique_ptr<VoicegroupBrowser> m_browser;
};

void VisualBrowsersTest::initTestCase()
{
    QString error;
    QVERIFY2(m_project.open(m_projectRoot, &error), qPrintable(error));

    const auto songName = SongName::create(QString::fromLatin1(kSongLabel));
    QVERIFY2(songName,
             qPrintable(
                 QStringLiteral("invalid fixture song label '%1'").arg(QLatin1String(kSongLabel))));
    const auto song = m_project.playableSong(*songName);
    QVERIFY2(
        song,
        qPrintable(
            QStringLiteral("fixture has no playable song '%1'").arg(QLatin1String(kSongLabel))));
    m_bank = m_project.loadBank(*song, &error);
    QVERIFY2(m_bank, qPrintable(error));

    auto loaded = LoadedSong::load(m_projectRoot, QString::fromLatin1(kSongLabel), error);
    QVERIFY2(loaded, qPrintable(error));
    m_rig = SongViewRig::create(std::move(loaded), 48000.0, error);
    QVERIFY2(m_rig, qPrintable(error));

    QVERIFY2(populateBrowser(error), qPrintable(error));
}

void VisualBrowsersTest::cleanupTestCase()
{
    if (m_browser) {
        m_browser->hide();
        m_browser.reset();
    }
    m_rig.reset();
    m_sampleSet.reset();
    m_bank.reset();
    m_project.close();
    themes::apply(*qApp, themes::vanilla());
}

bool VisualBrowsersTest::populateBrowser(QString &error)
{
    const VgCatalogScan catalog = VoicegroupSource::catalogScan(m_projectRoot);
    const VgDirectSoundScan directSound = VoicegroupSource::directSoundCatalog(m_projectRoot);
    const QStringList progWave = VoicegroupSource::progWaveSymbols(m_projectRoot);

    QVector<QByteArray> sampleSymbols, waveSymbols, keysplitSymbols, keysplitTables;
    QVector<const char *> samplePtrs, wavePtrs, keysplitPtrs, tablePtrs;
    for (const QString &symbol : directSound.directSound)
        sampleSymbols.append(symbol.toUtf8());
    for (const QString &symbol : progWave)
        waveSymbols.append(symbol.toUtf8());
    for (const auto &pair : catalog.keysplits) {
        keysplitSymbols.append(pair.first.toUtf8());
        keysplitTables.append(pair.second.toUtf8());
    }
    for (const QByteArray &symbol : sampleSymbols)
        samplePtrs.append(symbol.constData());
    for (const QByteArray &symbol : waveSymbols)
        wavePtrs.append(symbol.constData());
    for (int i = 0; i < keysplitSymbols.size(); ++i) {
        keysplitPtrs.append(keysplitSymbols.at(i).constData());
        tablePtrs.append(keysplitTables.at(i).constData());
    }
    LoadedSampleSet *const set = m_project.loadSampleSet(
        samplePtrs.constData(), samplePtrs.size(), wavePtrs.constData(), wavePtrs.size(),
        keysplitPtrs.constData(), tablePtrs.constData(), keysplitPtrs.size());
    if (!set) {
        error = QStringLiteral("fixture sample set did not load");
        return false;
    }
    m_sampleSet = SampleSetLease(set, &voicegroup_free_samples);

    m_browser = std::make_unique<VoicegroupBrowser>();
    m_browser->setVoicegroupChoices(catalog.groupArgs);
    // The same lookup WorkspaceUi::samplePickInfoFor performs against the
    // loaded sample set: known/looped/rate/seconds from the committed WaveData.
    const QStringList directSoundSymbols = directSound.directSound;
    m_browser->setSampleInfoProvider([this, directSoundSymbols](const QString &symbol) {
        SamplePickInfo info;
        const int index = directSoundSymbols.indexOf(symbol);
        const WaveData *wave = m_sampleSet && index >= 0 && index < m_sampleSet->count
                                   ? m_sampleSet->waves[index]
                                   : nullptr;
        if (!wave || !wave->data || wave->size == 0)
            return info;
        info.known = true;
        info.looped = (wave->status & 0x4000) != 0;
        info.rateHz = int(wave->freq / 1024);
        info.seconds = info.rateHz > 0 ? double(wave->size) / info.rateHz : 0.0;
        return info;
    });
    m_browser->setSource(&*m_bank, directSound.directSound, progWave, catalog.keysplits,
                         catalog.drumkits, catalog.typicalAdsr, directSound.synths);
    m_browser->setCurrentVoicegroupArg(QStringLiteral("_fixture_rich"));
    m_browser->setUsedVoices(m_rig->view().usedVoices());
    m_browser->selectSlot(kDirectSoundSlot);
    m_browser->setFixedSize(kBrowserSize);
    m_browser->show();
    QApplication::processEvents();
    return true;
}

bool VisualBrowsersTest::applyTheme(const QString &id)
{
    for (const ThemeVariant &variant : kThemeVariants) {
        if (id == QLatin1String(variant.id)) {
            themes::apply(*qApp, variant.theme());
            QApplication::processEvents();
            return true;
        }
    }
    return false;
}

bool VisualBrowsersTest::grabBrowser(const QString &id)
{
    // The canonical fixture size must survive the window system: a native
    // first-show auto-shrink would silently record a different surface.
    if (m_browser->size() != kBrowserSize) {
        qWarning() << "browser size" << m_browser->size() << "!= canonical" << kBrowserSize;
        return false;
    }
    if (QWidget *focused = QApplication::focusWidget())
        focused->clearFocus();
    QApplication::processEvents();
    QString error;
    const bool ok = visual::compareWidget(id, *m_browser, browserRegions(*m_browser), &error);
    if (!ok)
        qWarning().noquote() << error;
    return ok;
}

QWidget *VisualBrowsersTest::pickerPopup() const
{
    return m_browser ? m_browser->findChild<QWidget *>(QStringLiteral("vgSamplePickerPopup"))
                     : nullptr;
}

void VisualBrowsersTest::browserBaseline_data()
{
    QTest::addColumn<QString>("theme");
    for (const ThemeVariant &variant : kThemeVariants)
        QTest::newRow(variant.id) << QString::fromLatin1(variant.id);
}

// The full dock surface: selector, tree header, every visible row with its
// type icon and ADSR cell, selection, used-voice tints, and the DirectSound
// editor (type combo, sample picker button, new/edit buttons, ADSR spins).
void VisualBrowsersTest::browserBaseline()
{
    QFETCH(QString, theme);
    QVERIFY2(applyTheme(theme), qPrintable(QStringLiteral("unknown theme '%1'").arg(theme)));
    m_browser->selectSlot(kDirectSoundSlot);
    m_browser->revealSlot(0);
    QApplication::processEvents();
    QVERIFY(grabBrowser(QStringLiteral("voicegroupbrowser/%1").arg(theme)));
}

void VisualBrowsersTest::editorVariants_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<int>("slot");
    QTest::addColumn<QString>("variant");
    for (const ThemeVariant &variant : kThemeVariants) {
        const QString id = QString::fromLatin1(variant.id);
        QTest::newRow(qPrintable(id + "-square1"))
            << id << kSquare1Slot << QStringLiteral("editor-square1");
        QTest::newRow(qPrintable(id + "-readonly"))
            << id << kCrySlot << QStringLiteral("editor-readonly");
    }
}

// Editor form states: the Square 1 voice shows the sweep/duty rows with the
// masked CGB ADSR fields; the cry voice shows the read-only notice with the
// editor disabled.
void VisualBrowsersTest::editorVariants()
{
    QFETCH(QString, theme);
    QFETCH(int, slot);
    QFETCH(QString, variant);
    QVERIFY2(applyTheme(theme), qPrintable(QStringLiteral("unknown theme '%1'").arg(theme)));
    m_browser->selectSlot(slot);
    QApplication::processEvents();
    QVERIFY(grabBrowser(QStringLiteral("voicegroupbrowser/%1/%2").arg(variant, theme)));
}

void VisualBrowsersTest::samplePickerPopup_data()
{
    QTest::addColumn<QString>("theme");
    for (const ThemeVariant &variant : kThemeVariants)
        QTest::newRow(variant.id) << QString::fromLatin1(variant.id);
}

// The real opened popup: search field, section headers, keysplit/sample/
// phoneme rows, and the loop badge — grabbed from the shown popup widget.
void VisualBrowsersTest::samplePickerPopup()
{
    QFETCH(QString, theme);
    QVERIFY2(applyTheme(theme), qPrintable(QStringLiteral("unknown theme '%1'").arg(theme)));
    m_browser->selectSlot(kDirectSoundSlot);
    QApplication::processEvents();

    auto *picker = m_browser->findChild<SamplePickerButton *>();
    QVERIFY(picker);
    picker->openPopup();
    QWidget *popup = pickerPopup();
    QVERIFY(popup);
    QTRY_VERIFY_WITH_TIMEOUT(popup->isVisible(), 5000);
    // Production popup geometry is explicit tested state: width follows the
    // picker button (min 340), height is the fixed 420 cap; only its screen
    // position is clamped, never its size.
    const QSize expectedPopupSize{qMax(picker->width(), 340), 420};
    QVERIFY2(popup->size() == expectedPopupSize,
             qPrintable(QStringLiteral("popup size %1x%2 != expected %3x%4")
                            .arg(popup->width())
                            .arg(popup->height())
                            .arg(expectedPopupSize.width())
                            .arg(expectedPopupSize.height())));
    QApplication::processEvents();
    // The search field takes focus on open; a blinking caret is transient
    // state the baseline must not depend on.
    if (QWidget *focused = QApplication::focusWidget())
        focused->clearFocus();
    QApplication::processEvents();

    QString error;
    const bool ok = visual::compareWidget(QStringLiteral("samplepicker/%1").arg(theme), *popup,
                                          popupRegions(*popup), &error);
    if (!ok)
        qWarning().noquote() << error;

    popup->hide();
    QApplication::processEvents();
    QVERIFY2(!picker->popupVisible(), "sample picker popup did not close");
    QVERIFY(ok);
}

} // namespace checks

int runVisualBrowsersCheck(QApplication &application, const QStringList &qtArguments)
{
    // The registry stages the decomp fixture into a scratch directory and
    // exports its root; without it the checked-in copy is used read-only.
    QString projectRoot = qEnvironmentVariable("PORYDAW_VISUAL_PROJECT_ROOT");
    if (projectRoot.isEmpty()) {
        const QDir sourceRoot(QStringLiteral(PORYDAW_CHECK_SOURCE_DIR));
        projectRoot = sourceRoot.filePath(QStringLiteral("src/checks/fixtures/decompproject"));
    }
    if (!QFileInfo(projectRoot).isDir()) {
        std::fprintf(stderr, "visual-browsers: project fixture root '%s' is not a directory\n",
                     qPrintable(projectRoot));
        return 2;
    }

    checks::visual::prepare(application);
    checks::VisualBrowsersTest test(projectRoot);
    QStringList exec{QStringLiteral("visual-browsers")};
    exec.append(qtArguments);
    return QTest::qExec(&test, exec);
}

#include "browsers.moc"
