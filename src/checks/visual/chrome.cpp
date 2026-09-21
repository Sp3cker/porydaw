// Visual baselines for the persistent shell chrome: the TransportBar, the
// Songs dock panel, the MainWindow shell (tab bar, dock title bars, status
// bar polyphony meter), and the Polyphony dock panel at both responsive
// layouts. Every scenario shows the real production widget in the canonical
// check environment and compares the actual render against frozen geometry +
// PNG baselines recorded from the unmodified UI
// (PORYDAW_RECORD_VISUAL_BASELINES=1). Nothing here derives expected geometry
// or colors from live layout/theme functions, fakes a replacement widget, or
// starts audio playback.

#include "checks/visual/visualbaseline.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCoreApplication>
#include <QDockWidget>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMainWindow>
#include <QMenuBar>
#include <QPushButton>
#include <QQuickWindow>
#include <QScrollArea>
#include <QSettings>
#include <QStatusBar>
#include <QTabBar>
#include <QTabWidget>
#include <QTableWidget>
#include <QTemporaryDir>
#include <QTimer>
#include <QToolBar>
#include <QtTest>

#include <memory>
#include <optional>

#include "audio/audioengine.h"
#include "checks/support/loadedshell.h"
#include "checks/support/quickframebuffer.h"
#include "checks/visual/transportregions.h"
#include "checks/visual/visualfixture.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "mainwindow.h"
#include "project/decompproject.h"
#include "ui/fastlabel.h"
#include "ui/polyphonypanel.h"
#include "ui/songlistpanel.h"
#include "ui/songtab.h"
#include "ui/songtabquickhost.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/theme/themeresolver.h"
#include "ui/theme/themeruntime.h"
#include "ui/transportbar.h"

// The scenarios consume the shared visual helpers unqualified: one definition
// per rule lives in checks/visual (regions, focus parking, compare path, the
// canonical transport strip) so every suite pins the same bounds for the same
// surface.
using checks::visual::appendRequiredRegion;
using checks::visual::childRegion;
using checks::visual::clippedItemRect;
using checks::visual::compare;
using checks::visual::compareComboPopup;
using checks::visual::compareMenuPopup;
using checks::visual::compareShown;
using checks::visual::mergeRegions;
using checks::visual::nameChild;
using checks::visual::parkFocus;
using checks::visual::Region;
using checks::visual::scopeIndicatorNames;
using checks::visual::showSettled;
using checks::visual::transportRegions;
using checks::visual::widgetRegions;

namespace {

constexpr uint32_t kPolyDivision = 24;
constexpr double kPolySampleRate = 48000.0;

// ---- Fail-loud discovery ---------------------------------------------------

// Display text is the only handle on several production labels: the polyphony
// panel ships its headings unnamed, and so does the status meter's caption
// without an object name. A missing or duplicated label would silently drop
// regions from the frozen baseline, so these lookups report the drift instead.
bool uniqueLabel(QWidget &root, const QString &text, QLabel **out, QString *error)
{
    QList<QLabel *> matches;
    for (QLabel *label : root.findChildren<QLabel *>())
        if (label->text() == text)
            matches.append(label);
    if (matches.size() != 1) {
        *error = matches.isEmpty()
                     ? QStringLiteral("no label reads \"%1\"").arg(text)
                     : QStringLiteral("%1 labels read \"%2\"; the label must be unique")
                           .arg(matches.size())
                           .arg(text);
        return false;
    }
    *out = matches.first();
    return true;
}

// Names an unnamed production label through its display text; false with
// `error` when that text is absent or ambiguous.
bool nameLabelByText(QWidget &root, const QString &text, const QString &name, QString *error)
{
    QLabel *label = nullptr;
    if (!uniqueLabel(root, text, &label, error))
        return false;
    nameChild(label, name);
    return true;
}

// ---- SongListPanel ---------------------------------------------------------

QVector<SongInfo> visualSongs()
{
    const auto song = [](int id, const char *label, bool registered = true,
                         const QStringList &gaps = {}) {
        SongInfo info;
        info.id = id;
        info.label = QString::fromLatin1(label);
        info.constant = info.label.toUpper();
        info.player = QStringLiteral("MUSIC_PLAYER_BGM");
        info.hasMid = true;
        info.hasCfg = true;
        info.registered = registered;
        info.registrationGaps = gaps;
        return info;
    };
    return {
        song(0, "mus_route101"),
        song(1, "mus_petalburg"),
        song(2, "mus_gym"),
        song(3, "mus_surf"),
        song(4, "mus_victory_wild"),
        song(5, "se_fanfare_1trk"),
        song(6, "se_pc_login"),
        song(7, "se_use_item"),
        song(8, "mus_stray_unregistered", false),
        song(9, "mus_partial_entry", true, {QStringLiteral("song_table.inc")}),
        // A lone prefix lands in the Other bucket, so the category popup and
        // filter scenarios freeze that entry too.
        song(10, "fanfare_jingle"),
    };
}

// The panel's semantic regions: the list and its count label ship unnamed, so
// the scenario names them here and every listed child is required — a renamed
// or removed production widget fails the scenario instead of quietly shrinking
// the frozen baseline.
bool appendSongListRegions(QList<Region> &regions, SongListPanel &panel, QString *error)
{
    auto *const list = panel.findChild<QListWidget *>();
    auto *const count = panel.findChild<QLabel *>();
    if (!list || !count) {
        *error =
            QStringLiteral("the song list panel no longer holds its song list and count label");
        return false;
    }
    nameChild(list, QStringLiteral("songList"));
    nameChild(count, QStringLiteral("songListCount"));
    scopeIndicatorNames(panel);
    const struct {
        const char *name;
        const char *objectName;
        QWidget *child;
    } required[] = {
        {"songs.search", "songListSearch",
         panel.findChild<QWidget *>(QStringLiteral("songListSearch"))},
        {"songs.category", "songListCategory",
         panel.findChild<QWidget *>(QStringLiteral("songListCategory"))},
        {"songs.sort", "songListSort", panel.findChild<QWidget *>(QStringLiteral("songListSort"))},
        {"songs.list", "songList", list},
        {"songs.count", "songListCount", count},
    };
    for (const auto &entry : required) {
        if (appendRequiredRegion(regions, QString::fromLatin1(entry.name), panel, entry.child))
            continue;
        *error = QStringLiteral("region \"%1\" needs a rendered widget named \"%2\"")
                     .arg(QString::fromLatin1(entry.name), QString::fromLatin1(entry.objectName));
        return false;
    }
    const auto itemRegion = [&](const QString &name, QListWidgetItem *item) {
        if (!item)
            return;
        const QRect rect = clippedItemRect(*list, list->visualItemRect(item));
        if (rect.isValid() && !rect.isEmpty())
            regions.append({name, rect.translated(list->viewport()->mapTo(&panel, QPoint(0, 0)))});
    };
    const auto itemForSong = [&](int songId) -> QListWidgetItem * {
        for (int row = 0; row < list->count(); ++row)
            if (list->item(row)->data(Qt::UserRole).toInt() == songId)
                return list->item(row);
        return nullptr;
    };
    // Every visible row is pinned by position so filtered and sorted states
    // freeze their exact membership and order; the warning rows are also
    // pinned by song id so they stay semantic when a filter reorders them.
    for (int row = 0; row < list->count(); ++row)
        itemRegion(QStringLiteral("songs.row.%1").arg(row), list->item(row));
    itemRegion(QStringLiteral("songs.row.first"), list->item(0));
    itemRegion(QStringLiteral("songs.row.second"), list->item(1));
    itemRegion(QStringLiteral("songs.row.unregistered"), itemForSong(8));
    itemRegion(QStringLiteral("songs.row.partial"), itemForSong(9));
    return true;
}

// ---- PolyphonyPanel --------------------------------------------------------

SmfEvent polyEvent(uint64_t tick, uint8_t status, uint8_t data0, uint8_t data1)
{
    SmfEvent result;
    result.tick = tick;
    result.status = status;
    result.data0 = data0;
    result.data1 = data1;
    return result;
}

SmfEvent polyMeta(uint64_t tick, uint8_t type, const QByteArray &blob)
{
    SmfEvent result;
    result.tick = tick;
    result.status = 0xFF;
    result.metaType = type;
    result.blob = blob;
    return result;
}

std::unique_ptr<MidiTimeline> polyTimeline()
{
    SmfFile smf;
    smf.format = 1;
    smf.division = kPolyDivision;
    smf.tracks.resize(2);
    smf.tracks[0].events = {polyMeta(0, 0x51, QByteArray("\x07\xA1\x20", 3)),
                            polyMeta(0, 0x58, QByteArray("\x04\x02\x18\x08", 4))};
    smf.tracks[0].endTick = 384;
    smf.tracks[1].events = {polyEvent(0, 0xC0, 0, 0), polyEvent(0, 0x90, 60, 100),
                            polyEvent(24, 0x80, 60, 0)};
    smf.tracks[1].endTick = 384;
    return MidiTimeline::build(smf, kPolySampleRate);
}

AudioEngine::PolySnapshot polySnapshot()
{
    AudioEngine::PolySnapshot snapshot;
    snapshot.maxPcmChannels = 5;
    uint32_t total = 0;
    for (const M4APolyEvent &event :
         {M4APolyEvent{M4A_POLY_STOLEN, 2, 60, 4, 5, 96},
          M4APolyEvent{M4A_POLY_TAIL_CUT, 2, 72, 0, 5, 216},
          M4APolyEvent{M4A_POLY_DROPPED, 1, 67, 1, 0, M4A_POLY_TICK_NONE}})
        snapshot.events[total++ % M4A_POLY_EVENT_CAPACITY] = event;
    snapshot.eventTotal = total;
    snapshot.steal[2] = 1;
    snapshot.tailCut[2] = 1;
    snapshot.drop[1] = 1;
    snapshot.invert = true;
    snapshot.pcm[0] = {true, false, 2, 60};
    snapshot.pcm[MAX_PCM_CHANNELS] = {true, false, 4, 72};
    return snapshot;
}

// PolyphonyPanel ships no object names; name the semantic children in the
// test so widgetRegions() covers them, then add row-level subregions. The
// headings are found by display text alone, so an absent or duplicated heading
// fails the scenario instead of silently losing its region.
bool appendPolyphonyRegions(QList<Region> &regions, PolyphonyPanel &panel, QString *error)
{
    auto *const invert = panel.findChild<QCheckBox *>();
    auto *const table = panel.findChild<QTableWidget *>();
    auto *const log = panel.findChild<QListWidget *>();
    auto *const reset = panel.findChild<QPushButton *>();
    auto *const scroll = panel.findChild<QScrollArea *>();
    if (!invert || !table || !log || !reset || !scroll) {
        *error = QStringLiteral("the polyphony panel no longer holds its invert toggle, "
                                "overflow table, event log, reset button, and scroll area");
        return false;
    }
    nameChild(invert, QStringLiteral("poly.invert"));
    nameChild(table, QStringLiteral("poly.overflow-table"));
    nameChild(log, QStringLiteral("poly.event-log"));
    nameChild(reset, QStringLiteral("poly.reset"));
    nameChild(scroll, QStringLiteral("poly.scroll"));
    scopeIndicatorNames(panel);
    const struct {
        const char *text;
        const char *name;
    } headings[] = {
        {"Channel usage", "poly.usage-heading"},
        {"Overflow by track", "poly.overflow-heading"},
        {"Recent events", "poly.log-heading"},
        {"No overflow recorded", "poly.overflow-empty"},
    };
    for (const auto &heading : headings) {
        if (!nameLabelByText(panel, QString::fromLatin1(heading.text),
                             QString::fromLatin1(heading.name), error))
            return false;
    }
    if (QWidget *overflowBox = table->parentWidget())
        regions.append(childRegion(QStringLiteral("poly.overflow-section"), panel, *overflowBox));
    for (int row = 0; row < table->rowCount(); ++row) {
        QTableWidgetItem *item = table->item(row, 0);
        if (!item)
            continue;
        const QRect rect = clippedItemRect(*table, table->visualItemRect(item));
        if (rect.isValid() && !rect.isEmpty()) {
            regions.append({QStringLiteral("poly.overflow-row.%1").arg(row),
                            rect.translated(table->viewport()->mapTo(&panel, QPoint(0, 0)))});
        }
    }
    for (int row = 0; row < log->count() && row < 3; ++row) {
        QListWidgetItem *item = log->item(row);
        const QRect rect = clippedItemRect(*log, log->visualItemRect(item));
        if (rect.isValid() && !rect.isEmpty()) {
            regions.append({QStringLiteral("poly.log-row.%1").arg(row),
                            rect.translated(log->viewport()->mapTo(&panel, QPoint(0, 0)))});
        }
    }
    return true;
}

// ---- Shell -----------------------------------------------------------------

// The status polyphony meter is an unnamed permanent status-bar widget;
// identify it through its "PCM" caption label, which must exist exactly once.
QWidget *polyMeter(QMainWindow &window, QString *error)
{
    QStatusBar *statusBar = window.statusBar();
    if (!statusBar) {
        *error = QStringLiteral("the shell has no status bar");
        return nullptr;
    }
    QLabel *caption = nullptr;
    if (!uniqueLabel(*statusBar, QStringLiteral("PCM"), &caption, error)) {
        *error = QStringLiteral("the status bar has no polyphony meter: %1").arg(*error);
        return nullptr;
    }
    return caption->parentWidget();
}

// Names the shell's unnamed structural chrome in the test so widgetRegions()
// freezes it; false with `error` when the text-identified polyphony meter is
// missing.
bool nameShellChildren(QMainWindow &window, QString *error)
{
    if (QMenuBar *bar = window.menuBar())
        nameChild(bar, QStringLiteral("shell.menu-bar"));
    if (QStatusBar *bar = window.statusBar())
        nameChild(bar, QStringLiteral("shell.status-bar"));
    if (QTabWidget *tabs = window.findChild<QTabWidget *>()) {
        nameChild(tabs, QStringLiteral("shell.tabs"));
        nameChild(tabs->tabBar(), QStringLiteral("shell.tab-bar"));
    }
    if (QToolBar *transport = window.findChild<QToolBar *>(QStringLiteral("transportToolbar")))
        nameChild(transport, QStringLiteral("shell.transport"));
    for (QDockWidget *dock : window.findChildren<QDockWidget *>()) {
        const QString dockName = dock->objectName();
        if (QWidget *title = dock->titleBarWidget())
            nameChild(title, dockName + QStringLiteral(".title"));
    }
    QWidget *meter = polyMeter(window, error);
    if (!meter)
        return false;
    nameChild(meter, QStringLiteral("shell.poly-meter"));
    scopeIndicatorNames(window);
    return true;
}

// The shell's explicit subregions: tab-strip rects (the tab bar reports them
// beyond the automatic child regions) and the meter's values and captions.
// Captions are text-identified, so each must exist exactly once.
bool appendShellRegions(QList<Region> &regions, QMainWindow &window, QString *error)
{
    if (QTabWidget *tabs = window.findChild<QTabWidget *>()) {
        QTabBar *bar = tabs->tabBar();
        for (int index = 0; index < bar->count(); ++index) {
            const QRect rect = bar->tabRect(index);
            if (rect.isValid() && !rect.isEmpty()) {
                regions.append({QStringLiteral("shell.tab.%1").arg(index),
                                rect.translated(bar->mapTo(&window, QPoint(0, 0)))});
            }
        }
    }
    QWidget *meter = polyMeter(window, error);
    if (!meter)
        return false;
    int valueIndex = 0;
    for (FastLabel *label : meter->findChildren<FastLabel *>()) {
        if (label->isVisible()) {
            regions.append(childRegion(
                QStringLiteral("shell.poly-meter.value.%1").arg(valueIndex++), window, *label));
        }
    }
    const struct {
        const char *text;
        const char *name;
    } captions[] = {
        {"PCM", "shell.poly-meter.pcm-caption"},
        {"CGB", "shell.poly-meter.cgb-caption"},
        {"notes lost", "shell.poly-meter.lost-caption"},
    };
    for (const auto &caption : captions) {
        QLabel *label = nullptr;
        if (!uniqueLabel(*meter, QString::fromLatin1(caption.text), &label, error))
            return false;
        if (label->isVisible())
            regions.append(childRegion(QString::fromLatin1(caption.name), window, *label));
    }
    return true;
}

// ---- Theme variants --------------------------------------------------------

// Two frozen profiles only: the data column names the baseline id suffix, and
// this one branch per profile selects the resolved theme. An unknown id stays
// missing so the scenario fails instead of quietly re-testing vanilla.
std::optional<themes::Theme> themeFor(const QString &themeId)
{
    if (themeId == QLatin1String("vanilla"))
        return themes::vanilla();
    if (themeId == QLatin1String("darkneutralhigh"))
        return themes::darkNeutralHigh();
    return std::nullopt;
}

void addThemeRows()
{
    QTest::addColumn<QString>("theme");
    QTest::newRow("vanilla") << QStringLiteral("vanilla");
    QTest::newRow("darkneutralhigh") << QStringLiteral("darkneutralhigh");
}

} // namespace

class VisualChromeTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(VisualChromeTest)

  public:
    VisualChromeTest() = default;

  private slots:
    void initTestCase();
    void cleanup();

    void comparatorSelfTest();
    void transportBar_data();
    void transportBar();
    void songList_data();
    void songList();
    void songListFiltered_data();
    void songListFiltered();
    void songListCategory_data();
    void songListCategory();
    void songListSorted_data();
    void songListSorted();
    void songListEmpty_data();
    void songListEmpty();
    void songListCategoryPopup_data();
    void songListCategoryPopup();
    void songListSortPopup_data();
    void songListSortPopup();
    void songListMenu_data();
    void songListMenu();
    void shellVanilla();
    void shellLoaded();
    void polyphonyPanel_data();
    void polyphonyPanel();

  private:
    QApplication *app() const;
    QTemporaryDir m_settingsDirectory;
};

QApplication *VisualChromeTest::app() const
{
    return qobject_cast<QApplication *>(QCoreApplication::instance());
}

void VisualChromeTest::initTestCase()
{
    QVERIFY2(m_settingsDirectory.isValid(), "could not create isolated QSettings directory");
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_settingsDirectory.path());
    QSettings::setPath(QSettings::NativeFormat, QSettings::UserScope, m_settingsDirectory.path());
}

void VisualChromeTest::cleanup()
{
    // Every scenario returns the app to the committed vanilla baseline so
    // theme state never leaks between tests.
    if (app())
        themes::apply(*app(), themes::vanilla());
}

void VisualChromeTest::comparatorSelfTest()
{
    QString error;
    QVERIFY2(checks::visual::selfTest(&error), qPrintable(error));
}

void VisualChromeTest::transportBar_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<int>("playback");
    // Both rows are the scenarios this suite already froze: the playing state
    // belongs to the dark row, and now rides the data table beside the theme.
    QTest::newRow("vanilla") << QStringLiteral("vanilla")
                             << int(TransportBar::PlaybackState::Stopped);
    QTest::newRow("darkneutralhigh")
        << QStringLiteral("darkneutralhigh") << int(TransportBar::PlaybackState::Playing);
}

void VisualChromeTest::transportBar()
{
    QFETCH(QString, theme);
    QFETCH(int, playback);
    const auto selected = themeFor(theme);
    QVERIFY2(selected.has_value(),
             qPrintable(QStringLiteral("unknown theme id \"%1\"").arg(theme)));
    themes::apply(*app(), *selected);
    TransportBar bar;
    bar.setSessionAvailable(true);
    bar.setPlaybackState(static_cast<TransportBar::PlaybackState>(playback));
    bar.setFollowPlayhead(true);
    bar.setTimeText(QStringLiteral("1:23.4 / 4:56.7"));
    bar.setMasterVolume(96, true);
    bar.setOutputVolume(80);
    bar.setScaleState(0, porydaw_scale::ScaleId::major, true, false);
    bar.resize(1100, qMax(24, bar.sizeHint().height()));
    showSettled(bar);
    compareShown(QStringLiteral("transportbar/%1").arg(theme), bar, transportRegions(bar));
}

void VisualChromeTest::songList_data()
{
    addThemeRows();
}

void VisualChromeTest::songList()
{
    QFETCH(QString, theme);
    const auto selected = themeFor(theme);
    QVERIFY2(selected.has_value(),
             qPrintable(QStringLiteral("unknown theme id \"%1\"").arg(theme)));
    themes::apply(*app(), *selected);
    SongListPanel panel;
    panel.setSongs(visualSongs());
    panel.setCurrentSong(1);
    panel.resize(280, 480);
    showSettled(panel);
    QList<Region> regions;
    QString error;
    QVERIFY2(appendSongListRegions(regions, panel, &error), qPrintable(error));
    compareShown(QStringLiteral("songlist/%1").arg(theme), panel, regions);
}

// Every filtered-state scenario shares the same staged panel: the ten-song
// fixture, the loaded song selected, and the frozen dock size. The caller
// mutates one control, then the standard region set freezes the result.
static void stageSongList(SongListPanel &panel, const QString &theme)
{
    const auto selected = themeFor(theme);
    QVERIFY2(selected.has_value(),
             qPrintable(QStringLiteral("unknown theme id \"%1\"").arg(theme)));
    themes::apply(*qApp, *selected);
    panel.setSongs(visualSongs());
    panel.setCurrentSong(1);
    panel.resize(280, 480);
    showSettled(panel);
}

static void compareSongList(const QString &id, SongListPanel &panel)
{
    QList<Region> regions;
    QString error;
    QVERIFY2(appendSongListRegions(regions, panel, &error), qPrintable(error));
    // The search field's clear button is a platform ✕ glyph whose subpixel
    // placement jitters between grabs; it carries no app-specific state, so
    // both regions covering the field stop short of its right-docked square.
    // songs.search is already in the list from appendSongListRegions — replace
    // it in place; songListSearch comes from widgetRegions and overrides here.
    if (auto *search = panel.findChild<QLineEdit *>(QStringLiteral("songListSearch"))) {
        const QRect rect(search->mapTo(&panel, QPoint(0, 0)), search->size());
        const QRect trimmed = rect.adjusted(0, 0, -search->height(), 0);
        for (Region &region : regions)
            if (region.name == QLatin1String("songs.search"))
                region.bounds = trimmed;
        regions.append({QStringLiteral("songListSearch"), trimmed});
    }
    compareShown(id, panel, regions);
}

void VisualChromeTest::songListFiltered_data()
{
    addThemeRows();
}

void VisualChromeTest::songListFiltered()
{
    QFETCH(QString, theme);
    SongListPanel panel;
    stageSongList(panel, theme);
    // A live query: the search text, the narrowed list, and the "N of M"
    // count are all part of the frozen state. Mid-search the loaded song's
    // selection stays clear so Enter takes the first match.
    panel.findChild<QLineEdit *>(QStringLiteral("songListSearch"))->setText(QStringLiteral("gym"));
    QApplication::processEvents();
    parkFocus(panel);
    compareSongList(QStringLiteral("songlist/filtered-%1").arg(theme), panel);
}

void VisualChromeTest::songListCategory_data()
{
    addThemeRows();
}

void VisualChromeTest::songListCategory()
{
    QFETCH(QString, theme);
    SongListPanel panel;
    stageSongList(panel, theme);
    // The category combo's data is the prefix; "se_" narrows to the three
    // sound-effect songs and rewrites the All/count captions.
    auto *category = panel.findChild<QComboBox *>(QStringLiteral("songListCategory"));
    QVERIFY(category);
    category->setCurrentIndex(category->findData(QStringLiteral("se_")));
    QApplication::processEvents();
    parkFocus(panel);
    compareSongList(QStringLiteral("songlist/category-%1").arg(theme), panel);
}

void VisualChromeTest::songListSorted_data()
{
    addThemeRows();
}

void VisualChromeTest::songListSorted()
{
    QFETCH(QString, theme);
    SongListPanel panel;
    stageSongList(panel, theme);
    // A–Z order: the row regions pin the reordered membership, including the
    // warning rows' new positions.
    auto *sort = panel.findChild<QComboBox *>(QStringLiteral("songListSort"));
    QVERIFY(sort);
    sort->setCurrentIndex(1);
    QApplication::processEvents();
    parkFocus(panel);
    compareSongList(QStringLiteral("songlist/sorted-%1").arg(theme), panel);
}

void VisualChromeTest::songListEmpty_data()
{
    addThemeRows();
}

void VisualChromeTest::songListEmpty()
{
    QFETCH(QString, theme);
    SongListPanel panel;
    stageSongList(panel, theme);
    // A query with no matches: empty list, "0 of 10 songs" caption.
    panel.findChild<QLineEdit *>(QStringLiteral("songListSearch"))
        ->setText(QStringLiteral("no-such-song"));
    QApplication::processEvents();
    parkFocus(panel);
    compareSongList(QStringLiteral("songlist/empty-%1").arg(theme), panel);
}

void VisualChromeTest::songListCategoryPopup_data()
{
    addThemeRows();
}

void VisualChromeTest::songListCategoryPopup()
{
    QFETCH(QString, theme);
    SongListPanel panel;
    stageSongList(panel, theme);
    // The open dropdown freezes the category list: All, the counted prefixes
    // with their friendly names, and Other.
    auto *category = panel.findChild<QComboBox *>(QStringLiteral("songListCategory"));
    QVERIFY(category);
    compareComboPopup(*category, QStringLiteral("songlist/category-popup-%1").arg(theme));
}

void VisualChromeTest::songListSortPopup_data()
{
    addThemeRows();
}

void VisualChromeTest::songListSortPopup()
{
    QFETCH(QString, theme);
    SongListPanel panel;
    stageSongList(panel, theme);
    auto *sort = panel.findChild<QComboBox *>(QStringLiteral("songListSort"));
    QVERIFY(sort);
    compareComboPopup(*sort, QStringLiteral("songlist/sort-popup-%1").arg(theme));
}

void VisualChromeTest::songListMenu_data()
{
    QTest::addColumn<QString>("theme");
    QTest::addColumn<int>("songId");
    // The registered row's Register action is disabled; the unregistered
    // row's is enabled. Both menus freeze their full item set.
    QTest::newRow("vanilla-registered") << QStringLiteral("vanilla") << 0;
    QTest::newRow("vanilla-unregistered") << QStringLiteral("vanilla") << 8;
    QTest::newRow("dark-registered") << QStringLiteral("darkneutralhigh") << 0;
    QTest::newRow("dark-unregistered") << QStringLiteral("darkneutralhigh") << 8;
}

void VisualChromeTest::songListMenu()
{
    QFETCH(QString, theme);
    QFETCH(int, songId);
    SongListPanel panel;
    stageSongList(panel, theme);
    auto *list = panel.findChild<QListWidget *>();
    QVERIFY(list);
    QListWidgetItem *item = nullptr;
    for (int row = 0; row < list->count(); ++row)
        if (list->item(row)->data(Qt::UserRole).toInt() == songId)
            item = list->item(row);
    QVERIFY(item);
    // The production menu runs exec() inside the slot; a zero-delay timer
    // fires inside that modal loop, grabs the active popup, and closes it.
    const QString id =
        QStringLiteral("songlist/menu-%1-%2")
            .arg(songId == 8 ? QStringLiteral("unregistered") : QStringLiteral("registered"))
            .arg(theme);
    QTimer::singleShot(0, &panel, [id] { compareMenuPopup(id); });
    emit list->customContextMenuRequested(list->visualItemRect(item).center());
    QApplication::processEvents();
}

void VisualChromeTest::shellVanilla()
{
    themes::apply(*app(), themes::vanilla());
    // The real shell: MainWindow owns WorkspaceUi, the docks, the tab strip,
    // and the status-bar polyphony meter. The null audio backend keeps this
    // deterministic; with no song loaded the meter stays hidden, which is
    // itself part of the frozen baseline.
    auto window = std::make_unique<MainWindow>();
    window->resize(1104, 684);
    QString error;
    QVERIFY2(nameShellChildren(*window, &error), qPrintable(error));
    showSettled(*window);
    QList<Region> regions;
    QVERIFY2(appendShellRegions(regions, *window, &error), qPrintable(error));
    compareShown(QStringLiteral("shell/empty-vanilla"), *window, regions);
    window->close();
    QApplication::processEvents();
}

void VisualChromeTest::shellLoaded()
{
    themes::apply(*app(), themes::vanilla());
    QString error;
    checks::support::LoadedShell shell = checks::support::openLoadedShell(
        qEnvironmentVariable("PORYDAW_VISUAL_PROJECT_ROOT"), &error);
    QVERIFY2(shell.window, qPrintable(error));

    // The loaded shell is captured at the same frozen size as the empty one,
    // and only a settled show is compared: stage, name, show, compare.
    shell.window->resize(1104, 684);
    QVERIFY2(nameShellChildren(*shell.window, &error), qPrintable(error));
    showSettled(*shell.window);
    // The programmatic open leaves the browser unselected; the frozen baseline
    // is the state a real session shows, so pin the loaded song as the current
    // row through the production panel API. This must run after the window has
    // shown and laid out — before that, the list's scroll-to-selection no-ops.
    auto *songList = shell.window->findChild<SongListPanel *>();
    auto *workspace = shell.window->findChild<WorkspaceUi *>();
    QVERIFY2(songList && workspace, "the production shell lacks its panels");
    int loadedSongId = -1;
    for (const SongInfo &info : workspace->projectState().snapshot.songs())
        if (info.label == QLatin1String("mus_route101")) {
            loadedSongId = info.id;
            break;
        }
    QVERIFY2(loadedSongId >= 0, "the loaded song is absent from the project snapshot");
    songList->setCurrentSong(loadedSongId);
    QApplication::processEvents();

    QList<Region> regions;
    QVERIFY2(appendShellRegions(regions, *shell.window, &error), qPrintable(error));
    // The automatic named-descendant regions are read before the grab:
    // compositing pumps events while it waits for a Quick frame, and every
    // frozen bound must describe the grabbed image.
    QList<Region> frozen = mergeRegions(widgetRegions(*shell.window), regions);

    // QWidget::grab() omits the embedded native Quick window — composite the
    // actual QQuickWindow framebuffer at its mapped container bounds so the
    // baseline freezes the real mixed surface, not a blank center.
    auto *host = shell.tab->findChild<SongTabQuickHost *>();
    QVERIFY2(host && host->container(), "the loaded tab has no embedded Quick host");
    songview::TimelineQuickView *quick = shell.tab->view().quickView();
    QQuickWindow *quickWindow = quick ? quick->quickWindow() : nullptr;
    QVERIFY2(quickWindow, "the loaded tab exposes no Quick window");
    QRect containerBounds;
    const QImage composite = checks::support::compositeQuickWindowIntoGrab(
        *shell.window, *host->container(), *quickWindow, &containerBounds, &error);
    QVERIFY2(!composite.isNull(), qPrintable(error));
    frozen.append({QStringLiteral("shell.quick-surface"), containerBounds});

    QVERIFY2(compare(QStringLiteral("shell/loaded-vanilla"), composite, frozen, &error),
             qPrintable(error));

    shell.window->close();
    QApplication::processEvents();
}

void VisualChromeTest::polyphonyPanel_data()
{
    addThemeRows();
}

void VisualChromeTest::polyphonyPanel()
{
    QFETCH(QString, theme);
    const auto selected = themeFor(theme);
    QVERIFY2(selected.has_value(),
             qPrintable(QStringLiteral("unknown theme id \"%1\"").arg(theme)));
    themes::apply(*app(), *selected);
    const auto timeline = polyTimeline();
    QVERIFY(timeline);
    PolyphonyPanel panel;
    QStringList trackNames(16);
    trackNames[2] = QStringLiteral("Brass");
    panel.setTrackNames(trackNames);
    QStringList voiceNames(128);
    voiceNames[5] = QStringLiteral("voice_piano");
    panel.setVoiceNames(voiceNames);
    panel.setTimeline(timeline.get());
    panel.updateSnapshot(polySnapshot());

    panel.resize(380, 760);
    showSettled(panel);
    QTRY_VERIFY(!panel.wideLayoutActive());
    QString error;
    QList<Region> regions;
    QVERIFY2(appendPolyphonyRegions(regions, panel, &error), qPrintable(error));
    compareShown(QStringLiteral("polyphony/narrow-%1").arg(theme), panel, regions);

    panel.resize(900, 600);
    QApplication::processEvents();
    QTRY_VERIFY(panel.wideLayoutActive());
    parkFocus(panel);
    regions.clear();
    QVERIFY2(appendPolyphonyRegions(regions, panel, &error), qPrintable(error));
    compareShown(QStringLiteral("polyphony/wide-%1").arg(theme), panel, regions);
}

int runVisualChromeCheck(QApplication &application, const QStringList &qtArguments)
{
    checks::visual::prepare(application);
    VisualChromeTest test;
    QStringList arguments{QStringLiteral("visual-chrome")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "chrome.moc"
