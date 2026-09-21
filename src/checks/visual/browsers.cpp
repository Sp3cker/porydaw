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
#include "checks/visual/visualfixture.h"

#include "checks/support/songfixture.h"

#include "project/decompproject.h"
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
#include <QLineEdit>
#include <QModelIndex>
#include <QSet>
#include <QSpinBox>
#include <QTreeWidget>
#include <QTreeWidgetItemIterator>
#include <QtTest>

#include <cstdio>
#include <memory>
#include <optional>

namespace {

// The shared region helpers (checks/visual/visualfixture.h): scenario code
// spells them unqualified, one name per rule.
using checks::visual::appendNamedRegion;
using checks::visual::appendRequiredRegion;
using checks::visual::childRegion;
using checks::visual::compareComboPopup;
using checks::visual::compareShown;
using checks::visual::Region;

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

// The two committed themes the baselines cover, in data-row order; the id is
// both the QTest row name and the theme segment of every baseline id, and
// applyTheme() maps it to the theme itself.
constexpr const char *kThemeIds[] = {"vanilla", "darkneutralhigh"};

// A tree cell's rect in captured-root coordinates (visualRect is viewport
// coordinates; the grabbed image is the browser/popup widget's).
//
// Deliberately stricter than checks::visual::clippedItemRect: a partially
// scrolled row is not a stable bound for a baseline, so this drops cells the
// viewport only partly paints instead of freezing the clipped sliver.
QRect fullyVisibleTreeCellRect(const QWidget &root, QTreeWidget &tree, QTreeWidgetItem *item,
                               int column)
{
    const QModelIndex index = tree.indexFromItem(item, column);
    if (!index.isValid())
        return QRect();
    const QRect rect = tree.visualRect(index);
    if (!rect.isValid())
        return QRect();
    const QRect inTree{tree.viewport()->mapTo(&tree, rect.topLeft()), rect.size()};
    if (!tree.rect().contains(inTree))
        return QRect();
    return {tree.viewport()->mapTo(&root, rect.topLeft()), rect.size()};
}

void addTreeRowRegions(QList<Region> &regions, const QWidget &root, QTreeWidget &tree,
                       QTreeWidgetItem *item, const QString &name)
{
    const QRect row = fullyVisibleTreeCellRect(root, tree, item, 0);
    if (!row.isValid())
        return;
    regions.append({name, row.united(fullyVisibleTreeCellRect(root, tree, item, 1))
                              .united(fullyVisibleTreeCellRect(root, tree, item, 2))});
    const QRect icon = fullyVisibleTreeCellRect(root, tree, item, 1);
    if (icon.isValid())
        regions.append({name + QStringLiteral(".type-icon"), icon});
    const QRect adsr = fullyVisibleTreeCellRect(root, tree, item, 2);
    if (adsr.isValid())
        regions.append({name + QStringLiteral(".adsr"), adsr});
}

// Pins a child under a caller-chosen semantic name. childRegion() supplies the
// shared rule — the visibleRegion clipped through ancestor viewports and
// root.rect() — and a child that paints nothing (whole editor rows hidden for
// the selected voice family) contributes no region instead of a degenerate
// one.
void appendPaintedRegion(QList<Region> &regions, const QString &name, QWidget &root,
                         const QWidget *child)
{
    if (!child)
        return;
    const Region region = childRegion(name, root, *child);
    if (!region.bounds.isEmpty())
        regions.append(region);
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

// The editor's type combo is the only combo carrying the Square 1 macro: zero
// matches (the editor never rendered) and several (an ambiguous editor) both
// return null, so appendBrowserRegions() fails the test rather than silently
// pinning whichever combo the scan reached first.
QComboBox *editorTypeCombo(VoicegroupBrowser &browser)
{
    QComboBox *match = nullptr;
    for (QComboBox *combo : browser.findChildren<QComboBox *>()) {
        if (combo->findData(int(VgMacro::Square1)) < 0)
            continue;
        if (match)
            return nullptr;
        match = combo;
    }
    return match;
}

// Appends the browser's semantic regions on top of the automatic ones the
// shared compare path adds: stable names for the widgets a QML port must
// reproduce, plus explicit subregions for the custom-painted tree cells and
// the editor rows. A widget that paints nothing (the editor rows another voice
// family hides) contributes no region; chrome that must exist fails the test
// here rather than silently shrinking the frozen surface.
void appendBrowserRegions(QList<Region> &regions, VoicegroupBrowser &browser)
{
    QVERIFY2(appendNamedRegion(regions, QStringLiteral("selector"), browser,
                               QStringLiteral("vgArgCombo")),
             "voicegroup selector combo not found");

    auto *tree = browser.findChild<QTreeWidget *>(QString(), Qt::FindDirectChildrenOnly);
    QVERIFY2(tree, "voicegroup tree not found");
    QVERIFY2(appendRequiredRegion(regions, QStringLiteral("tree"), browser, tree),
             "voicegroup tree painted nothing");
    QVERIFY2(appendRequiredRegion(regions, QStringLiteral("tree.header"), browser, tree->header()),
             "voicegroup tree header painted nothing");
    for (int slot = 0; slot < tree->topLevelItemCount(); ++slot) {
        QTreeWidgetItem *const item = tree->topLevelItem(slot);
        if (!item->isHidden())
            addTreeRowRegions(regions, browser, *tree, item,
                              QStringLiteral("tree.row.%1").arg(slot, 3, 10, QLatin1Char('0')));
    }

    QVERIFY2(appendNamedRegion(regions, QStringLiteral("editor.notice"), browser,
                               QStringLiteral("voicegroupEditorNotice")),
             "voicegroup editor notice not found");

    QComboBox *const typeCombo = editorTypeCombo(browser);
    QVERIFY2(typeCombo, "voicegroup editor needs exactly one Square 1 type combo");
    appendPaintedRegion(regions, QStringLiteral("editor.type"), browser, typeCombo);

    auto *picker = browser.findChild<SamplePickerButton *>();
    QVERIFY2(picker, "voicegroup sample picker not found");
    appendPaintedRegion(regions, QStringLiteral("editor.sample"), browser, rowOf(picker));
    QVERIFY2(appendNamedRegion(regions, QStringLiteral("editor.sample.button"), browser,
                               QStringLiteral("vgSamplePickerButton")),
             "voicegroup sample picker button not found");
    QVERIFY2(appendNamedRegion(regions, QStringLiteral("editor.sample.new"), browser,
                               QStringLiteral("vgNewSampleButton")),
             "voicegroup new-sample button not found");
    QVERIFY2(appendNamedRegion(regions, QStringLiteral("editor.sample.edit"), browser,
                               QStringLiteral("vgEditSampleButton")),
             "voicegroup edit-sample button not found");

    struct AdsrField {
        const char *name;
        const char *tooltip;
    };
    constexpr AdsrField kAdsrFields[] = {
        {"attack", "Attack"},
        {"decay", "Decay"},
        {"sustain", "Sustain"},
        {"release", "Release"},
    };
    for (const AdsrField &field : kAdsrFields) {
        const QString tooltip = QString::fromLatin1(field.tooltip);
        DragSpinBox *const spin = adsrSpin(browser, tooltip);
        QVERIFY2(spin, qPrintable(QStringLiteral("ADSR spin '%1' not found").arg(tooltip)));
        const QString name = QStringLiteral("editor.adsr.%1").arg(QLatin1String(field.name));
        appendPaintedRegion(regions, name, browser, spin);
    }
    appendPaintedRegion(regions, QStringLiteral("editor.adsr"), browser,
                        rowOf(adsrSpin(browser, QStringLiteral("Attack"))));

    // The CGB-only rows (sweep) and the synth rows surface through their field
    // widgets' tooltips; the row parent is the semantic bound. The production
    // tooltips are static strings, so each entry matches exactly: a reworded
    // tooltip must fail here rather than silently pin a different row.
    struct TooltipRow {
        const char *tooltip;
        const char *name;
    };
    constexpr TooltipRow kTooltipRows[] = {
        {"Speed: 128 Hz clocks between pitch steps (1 = fastest, 7 = slowest, Off = no sweep).",
         "editor.sweep"},
        {"Base duty cycle: the pulse width the wave centers on (128 = 50% square).",
         "editor.synth.duty"},
        {"Duty LFO step per frame: how fast the pulse width wobbles (0 = static).",
         "editor.synth.step"},
        {"Modulation amount: how far the pulse width swings around the base duty.",
         "editor.synth.depth"},
        {"Duty LFO phase offset.", "editor.synth.phase"},
    };
    for (const TooltipRow &row : kTooltipRows) {
        QSpinBox *match = nullptr;
        for (QSpinBox *spin : browser.findChildren<QSpinBox *>()) {
            if (spin->toolTip() == QLatin1String(row.tooltip)) {
                match = spin;
                break; // first match wins; the production tooltips are unique
            }
        }
        const QString name = QString::fromLatin1(row.name);
        QVERIFY2(match,
                 qPrintable(QStringLiteral("editor row '%1' not found by tooltip").arg(name)));
        appendPaintedRegion(regions, name, browser, rowOf(match));
    }
}

// Appends the open picker popup's semantic regions on top of the automatic
// ones the shared compare path adds: each section header, every visible row,
// and the loop-badge cell.
void appendPopupRegions(QList<Region> &regions, QWidget &popup)
{
    auto *tree = popup.findChild<QTreeWidget *>(QStringLiteral("vgSamplePickerList"));
    QVERIFY2(tree, "sample picker list not found");

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
        const QRect badge = fullyVisibleTreeCellRect(popup, *tree, item, 1);
        if (badge.isValid() && !item->text(1).isEmpty())
            regions.append({name + QStringLiteral(".loop-badge"), badge});
    }
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
    void selectorPopup_data();
    void selectorPopup();
    void typePopup_data();
    void typePopup();
    void loadingState_data();
    void loadingState();
    void scrolledTree_data();
    void scrolledTree();
    void emptySong_data();
    void emptySong();
    void samplePickerPopup_data();
    void samplePickerPopup();
    void pickerPopupFiltered_data();
    void pickerPopupFiltered();

  private:
    bool populateBrowser(QString &error);
    void applyTheme(const QString &id);
    void grabBrowser(const QString &id);
    QWidget *pickerPopup() const;
    // Rebinds the browser to `view` with the fixture's full catalog state;
    // the synth variant passes its pendingSynths overlay.
    void bindView(const LoadedBankView *view,
                  const QHash<QString, VgSynthDesc> &pendingSynths = {});

    QString m_projectRoot;
    DecompProject m_project;
    VgCatalogScan m_catalog;
    VgDirectSoundScan m_directSound;
    QStringList m_progWave;
    std::optional<LoadedBankView> m_bank;
    // A slot-kind overlay of m_bank for the Broken-variant grab; a member so
    // the borrowed view stays alive through the compare.
    std::optional<LoadedBankView> m_derivedBank;
    std::unique_ptr<SongViewRig> m_rig;
    std::unique_ptr<FixtureSampleSet> m_sampleSet;
    std::unique_ptr<VoicegroupBrowser> m_browser;
};

void VisualBrowsersTest::initTestCase()
{
    // No QSettings isolation here, unlike the chrome/dialogs suites: nothing
    // this scenario builds reads or writes settings. DecompProject, the
    // VoicegroupBrowser, SamplePickerButton, and the theme applier all keep
    // their state in the fixture project or in memory; each scenario applies
    // its own theme, so no persisted preference can leak into a capture.
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
    m_catalog = VoicegroupSource::catalogScan(m_projectRoot);
    m_directSound = VoicegroupSource::directSoundCatalog(m_projectRoot);
    m_progWave = VoicegroupSource::progWaveSymbols(m_projectRoot);

    m_sampleSet = FixtureSampleSet::load(m_project, m_catalog, m_directSound, m_progWave, error);
    if (!m_sampleSet)
        return false;

    m_browser = std::make_unique<VoicegroupBrowser>();
    m_browser->setVoicegroupChoices(m_catalog.groupArgs);
    m_browser->setSampleInfoProvider(m_sampleSet->pickInfoProvider());
    bindView(&*m_bank);
    m_browser->setCurrentVoicegroupArg(QStringLiteral("_fixture_rich"));
    m_browser->setUsedVoices(m_rig->view().usedVoices());
    m_browser->selectSlot(kDirectSoundSlot);
    m_browser->setFixedSize(kBrowserSize);
    m_browser->show();
    QApplication::processEvents();
    return true;
}

void VisualBrowsersTest::bindView(const LoadedBankView *view,
                                  const QHash<QString, VgSynthDesc> &pendingSynths)
{
    m_browser->setSource(view, m_directSound.directSound, m_progWave, m_catalog.keysplits,
                         m_catalog.drumkits, m_catalog.typicalAdsr, m_directSound.synths,
                         pendingSynths);
}

// id -> theme, the only two the baselines cover; the data rows cannot carry
// anything else, so an unknown id is a test bug and fails the scenario.
void VisualBrowsersTest::applyTheme(const QString &id)
{
    if (id == QLatin1String("vanilla")) {
        themes::apply(*qApp, themes::vanilla());
    } else if (id == QLatin1String("darkneutralhigh")) {
        themes::apply(*qApp, themes::darkNeutralHigh());
    } else {
        QFAIL(qPrintable(QStringLiteral("unknown theme '%1'").arg(id)));
    }
    QApplication::processEvents();
}

void VisualBrowsersTest::grabBrowser(const QString &id)
{
    // The canonical fixture size must survive the window system: a native
    // first-show auto-shrink would silently record a different surface.
    QVERIFY2(m_browser->size() == kBrowserSize,
             qPrintable(QStringLiteral("browser size %1x%2 != canonical %3x%4")
                            .arg(m_browser->width())
                            .arg(m_browser->height())
                            .arg(kBrowserSize.width())
                            .arg(kBrowserSize.height())));
    // A focus ring is transient state the baseline must not depend on, and
    // parking focus (checks::visual::parkFocus) would ink one on the editor's
    // New… button: drop focus entirely, like the popup's search field.
    if (QWidget *focused = QApplication::focusWidget())
        focused->clearFocus();
    QApplication::processEvents();

    QList<Region> regions;
    appendBrowserRegions(regions, *m_browser);
    compareShown(id, *m_browser, regions);
}

QWidget *VisualBrowsersTest::pickerPopup() const
{
    return m_browser ? m_browser->findChild<QWidget *>(QStringLiteral("vgSamplePickerPopup"))
                     : nullptr;
}

void VisualBrowsersTest::browserBaseline_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The full dock surface: selector, tree header, every visible row with its
// type icon and ADSR cell, selection, used-voice tints, and the DirectSound
// editor (type combo, sample picker button, new/edit buttons, ADSR spins).
void VisualBrowsersTest::browserBaseline()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    m_browser->selectSlot(kDirectSoundSlot);
    m_browser->revealSlot(0);
    QApplication::processEvents();
    grabBrowser(QStringLiteral("voicegroupbrowser/%1").arg(theme));
}

void VisualBrowsersTest::editorVariants_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<int>("slot");
    QTest::addColumn<QString>("variant");
    QTest::addColumn<QString>("kind");
    // fixture_rich slot map (sound/voicegroups/fixture_rich.inc): every
    // editor family gets a frozen form — the CGB sweep/duty rows, the
    // picker's wave mode, the keysplit/drumkit symbol combos, the noise
    // period row, the blank-slot materialization draft, the read-only cry
    // notice, the unparseable-line notice, and the Golden Sun synth rows.
    const struct {
        int slot;
        const char *variant;
        const char *kind;
    } variants[] = {
        {kSquare1Slot, "editor-square1", "normal"},
        {5, "editor-square2", "normal"},
        {6, "editor-wave", "normal"},
        {7, "editor-noise", "normal"},
        {8, "editor-keysplit", "normal"},
        {10, "editor-drumkit", "normal"},
        {13, "editor-blank", "normal"},
        {kCrySlot, "editor-readonly", "normal"},
        {1, "editor-broken", "broken"},
        {kDirectSoundSlot, "editor-synth", "synth"},
    };
    for (const char *themeId : kThemeIds) {
        const QString theme = QString::fromLatin1(themeId);
        for (const auto &v : variants)
            QTest::newRow(qPrintable(theme + "-" + QLatin1String(v.variant)))
                << theme << v.slot << QString::fromLatin1(v.variant) << QString::fromLatin1(v.kind);
    }
}

// Editor form states: each voice family shows its own rows — Square 1 the
// sweep/duty fields with masked CGB ADSR, wave the picker in wave mode,
// keysplit/drumkit their symbol combos, noise the period field, a blank slot
// the materialization draft, the cry voice the read-only notice, a broken
// line the kept-as-is notice, and a synth voice the Golden Sun parameters.
void VisualBrowsersTest::editorVariants()
{
    QFETCH(QString, theme);
    QFETCH(int, slot);
    QFETCH(QString, variant);
    QFETCH(QString, kind);
    applyTheme(theme);

    if (kind == QLatin1String("broken")) {
        // A line the loader consumed but couldn't parse: the row renders the
        // bank's tone while the editor shows the kept-as-is notice. The view
        // overlay drops the parsed voice so the slot is read-only.
        m_derivedBank = *m_bank;
        m_derivedBank->slotViews[slot].kind = VgLineKind::Broken;
        m_derivedBank->slotViews[slot].voice.reset();
        bindView(&*m_derivedBank);
    } else if (kind == QLatin1String("synth")) {
        // A minted-but-unsaved synth definition: the voice's sample symbol
        // resolves through pendingSynths, so the editor shows the Golden Sun
        // rows without any fixture-file synth data.
        const QString symbol = m_bank->slotViews[slot].voice->symbol;
        VgSynthDesc desc; // pulse defaults: 50% duty, no LFO
        bindView(&*m_bank, {{symbol, desc}});
    }

    m_browser->selectSlot(slot);
    QApplication::processEvents();
    grabBrowser(QStringLiteral("voicegroupbrowser/%1/%2").arg(variant, theme));

    if (kind == QLatin1String("synth")) {
        // The synth voice's Type dropdown carries the extra "Synth (Golden
        // Sun)" entry — freeze the open popup while the overlay is bound.
        QComboBox *const typeCombo = editorTypeCombo(*m_browser);
        QVERIFY(typeCombo);
        compareComboPopup(*typeCombo,
                          QStringLiteral("voicegroupbrowser/type-popup-synth/%1").arg(theme));
    }
    if (kind != QLatin1String("normal")) {
        bindView(&*m_bank);
        m_derivedBank.reset();
        m_browser->selectSlot(kDirectSoundSlot);
        QApplication::processEvents();
    }
}

void VisualBrowsersTest::selectorPopup_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The voicegroup selector's open dropdown: every -G arg the project offers,
// in catalog order, with the current arg highlighted.
void VisualBrowsersTest::selectorPopup()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    auto *selector = m_browser->findChild<QComboBox *>(QStringLiteral("vgArgCombo"));
    QVERIFY(selector);
    compareComboPopup(*selector, QStringLiteral("voicegroupbrowser/selector-popup/%1").arg(theme));
}

void VisualBrowsersTest::typePopup_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The editor's Type dropdown on a plain sample voice: each selectable family
// once, no _alt duplicates, no Synth entry while the project has none.
void VisualBrowsersTest::typePopup()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    // Rebind so a prior variant's overlay (synth pending defs, derived bank)
    // can't leak into the combo model — the popup must show the plain list.
    bindView(&*m_bank);
    m_browser->selectSlot(kDirectSoundSlot);
    QApplication::processEvents();
    QComboBox *const typeCombo = editorTypeCombo(*m_browser);
    QVERIFY(typeCombo);
    compareComboPopup(*typeCombo, QStringLiteral("voicegroupbrowser/type-popup/%1").arg(theme));
}

void VisualBrowsersTest::loadingState_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The async-load overlay: all 128 rows read "NNN Loading...", the selector
// shows its loading text, and the editor is disabled in place — geometry
// identical to the bound state.
void VisualBrowsersTest::loadingState()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    m_browser->setLoading(true);
    QApplication::processEvents();
    grabBrowser(QStringLiteral("voicegroupbrowser/loading/%1").arg(theme));
    m_browser->setLoading(false);
    m_browser->selectSlot(kDirectSoundSlot);
    QApplication::processEvents();
}

void VisualBrowsersTest::scrolledTree_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The tree mid-scroll: a late slot selected and centered, so the baseline
// pins the scrollbar position, the visible window of rows, and the blank
// rows' presentation.
void VisualBrowsersTest::scrolledTree()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    m_browser->revealSlot(64);
    QApplication::processEvents();
    grabBrowser(QStringLiteral("voicegroupbrowser/scrolled/%1").arg(theme));
    m_browser->revealSlot(0);
    m_browser->selectSlot(kDirectSoundSlot);
    QApplication::processEvents();
}

void VisualBrowsersTest::emptySong_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// No bound bank: the selector placeholder, the cleared rows, and the empty
// editor state a song-less session shows.
void VisualBrowsersTest::emptySong()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    bindView(nullptr);
    QApplication::processEvents();
    grabBrowser(QStringLiteral("voicegroupbrowser/empty/%1").arg(theme));
    bindView(&*m_bank);
    m_browser->setCurrentVoicegroupArg(QStringLiteral("_fixture_rich"));
    m_browser->setUsedVoices(m_rig->view().usedVoices());
    m_browser->selectSlot(kDirectSoundSlot);
    QApplication::processEvents();
}

void VisualBrowsersTest::pickerPopupFiltered_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The picker popup mid-filter: only matching rows stay visible under their
// section headers, and the query text sits in the search field.
void VisualBrowsersTest::pickerPopupFiltered()
{
    QFETCH(QString, theme);
    applyTheme(theme);
    m_browser->selectSlot(kDirectSoundSlot);
    QApplication::processEvents();

    auto *picker = m_browser->findChild<SamplePickerButton *>();
    QVERIFY(picker);
    picker->openPopup();
    QWidget *popup = pickerPopup();
    QVERIFY(popup);
    QTRY_VERIFY_WITH_TIMEOUT(popup->isVisible(), 5000);
    auto *filter = popup->findChild<QLineEdit *>();
    QVERIFY(filter);
    filter->setText(QStringLiteral("pluck"));
    QApplication::processEvents();
    if (QWidget *focused = QApplication::focusWidget())
        focused->clearFocus();
    QApplication::processEvents();

    QList<Region> regions;
    appendPopupRegions(regions, *popup);
    // The line edit's clear button is a platform ✕ glyph whose subpixel
    // placement jitters between grabs; it carries no app-specific state, so
    // the search region stops short of its right-docked square.
    const QRect searchRect(filter->mapTo(popup, QPoint(0, 0)), filter->size());
    regions.append(
        {QStringLiteral("vgSamplePickerSearch"), searchRect.adjusted(0, 0, -filter->height(), 0)});
    compareShown(QStringLiteral("samplepicker/filtered-%1").arg(theme), *popup, regions);

    popup->hide();
    QApplication::processEvents();
    QVERIFY2(!picker->popupVisible(), "sample picker popup did not close");
}

void VisualBrowsersTest::samplePickerPopup_data()
{
    QTest::addColumn<QString>("theme");
    for (const char *themeId : kThemeIds)
        QTest::newRow(themeId) << QString::fromLatin1(themeId);
}

// The real opened popup: search field, section headers, keysplit/sample/
// phoneme rows, and the loop badge — grabbed from the shown popup widget.
void VisualBrowsersTest::samplePickerPopup()
{
    QFETCH(QString, theme);
    applyTheme(theme);
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

    QList<Region> regions;
    appendPopupRegions(regions, *popup);
    compareShown(QStringLiteral("samplepicker/%1").arg(theme), *popup, regions);

    popup->hide();
    QApplication::processEvents();
    QVERIFY2(!picker->popupVisible(), "sample picker popup did not close");
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
