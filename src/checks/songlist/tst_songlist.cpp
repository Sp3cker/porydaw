// Behavioral contract for SongListPanel, the Songs dock list being ported to
// QML: category buckets, search and fuzzy filtering, sort order, warning-row
// presentation, selection tracking, keyboard routing, and the context menu's
// signal contract. The visual-* suites freeze the pixels; this suite freezes
// the semantics a port must reproduce. No project fixture: the panel takes a
// plain SongInfo vector.

#include <QApplication>
#include <QComboBox>
#include <QKeyEvent>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QSignalSpy>
#include <QTimer>
#include <QtTest>

#include "project/decompproject.h"
#include "ui/songlistpanel.h"

namespace {

// Mirrors the visual suite's fixture so both pin the same surface: seven mus_
// songs (two with registration warnings), three se_ songs, and one lone
// prefix that lands in Other.
QVector<SongInfo> checkSongs()
{
    const auto song = [](int id, const char *label, bool registered = true,
                         const QStringList &gaps = {}, bool hasMid = true) {
        SongInfo info;
        info.id = id;
        info.label = QString::fromLatin1(label);
        info.constant = info.label.toUpper();
        info.player = QStringLiteral("MUSIC_PLAYER_BGM");
        info.hasMid = hasMid;
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
        song(10, "fanfare_jingle"),
        // A .mid-less table entry is not playable and never lists.
        song(11, "mus_no_midi", true, {}, false),
    };
}

QListWidget *list(SongListPanel &panel)
{
    return panel.findChild<QListWidget *>();
}

QLineEdit *search(SongListPanel &panel)
{
    return panel.findChild<QLineEdit *>(QStringLiteral("songListSearch"));
}

QComboBox *category(SongListPanel &panel)
{
    return panel.findChild<QComboBox *>(QStringLiteral("songListCategory"));
}

QComboBox *sort(SongListPanel &panel)
{
    return panel.findChild<QComboBox *>(QStringLiteral("songListSort"));
}

QLabel *count(SongListPanel &panel)
{
    return panel.findChild<QLabel *>();
}

QStringList rowLabels(QListWidget &list)
{
    QStringList labels;
    for (int row = 0; row < list.count(); ++row)
        labels.append(list.item(row)->text());
    return labels;
}

QList<int> rowIds(QListWidget &list)
{
    QList<int> ids;
    for (int row = 0; row < list.count(); ++row)
        ids.append(list.item(row)->data(Qt::UserRole).toInt());
    return ids;
}

QListWidgetItem *rowForSong(QListWidget &list, int songId)
{
    for (int row = 0; row < list.count(); ++row)
        if (list.item(row)->data(Qt::UserRole).toInt() == songId)
            return list.item(row);
    return nullptr;
}

// Fires the panel's real context-menu slot for `songId`, then runs `inspect`
// inside the menu's modal loop. The menu is a stack-local QMenu::exec(); a
// zero-delay single-shot is delivered during exec()'s initial show, before
// the native tracking loop starts, so it is the only timer that fires inside.
// `inspect` must trigger an action or close the popup for exec() to return.
void inspectRowMenu(SongListPanel &panel, QListWidget &list, int songId,
                    const std::function<void(QWidget *)> &inspect)
{
    QListWidgetItem *item = rowForSong(list, songId);
    QVERIFY(item);
    QTimer::singleShot(0, &panel, [inspect] {
        QWidget *popup = QApplication::activePopupWidget();
        inspect(popup);
        // QAction::trigger() emits the signal but does not dismiss exec()'s
        // modal loop; close the popup explicitly so the slot returns.
        if (popup)
            popup->close();
    });
    emit list.customContextMenuRequested(list.visualItemRect(item).center());
    QApplication::processEvents();
}

class SongListCheck final : public QObject
{
    Q_OBJECT

  private slots:
    void categoriesBuiltFromPrefixes();
    void searchNarrowsList();
    void searchMatchesConstantAndFuzzy();
    void categoryFilterNarrows();
    void sortOrdersAlphabetically();
    void warningRowsMarked();
    void selectionTracksCurrentSong();
    void searchClearsSelectionUntilEmptied();
    void enterActivatesFirstMatch();
    void arrowKeysSteerListFromSearch();
    void spaceStaysWindowShortcut();
    void contextMenuEmitsSignals();
    void contextMenuSkipsEmptyArea();
    void restoreFiltersAppliesAfterSetSongs();
    void setSongsPreservesActiveFilters();
};

void SongListCheck::categoriesBuiltFromPrefixes()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QComboBox *box = category(panel);
    QVERIFY(box);
    // Biggest prefix first, Other last; the captions carry their counts.
    QStringList texts, data;
    for (int i = 0; i < box->count(); ++i) {
        texts.append(box->itemText(i));
        data.append(box->itemData(i).toString());
    }
    QCOMPARE(data, QStringList({QString(), QStringLiteral("mus_"), QStringLiteral("se_"),
                                QStringLiteral("<other>")}));
    QCOMPARE(texts.at(0), QStringLiteral("All (11)"));
    QVERIFY(texts.at(1).contains(QStringLiteral("mus_")) && texts.at(1).contains('7'));
    QVERIFY(texts.at(2).contains(QStringLiteral("se_")) && texts.at(2).contains('3'));
    QCOMPARE(texts.at(3), QStringLiteral("Other (1)"));
}

void SongListCheck::searchNarrowsList()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs && count(panel));
    QCOMPARE(songs->count(), 11);
    QCOMPARE(count(panel)->text(), QStringLiteral("11 songs"));

    search(panel)->setText(QStringLiteral("gym"));
    QCOMPARE(rowIds(*songs), QList<int>({2}));
    QCOMPARE(count(panel)->text(), QStringLiteral("1 of 11 songs"));

    search(panel)->clear();
    QCOMPARE(songs->count(), 11);
    QCOMPARE(count(panel)->text(), QStringLiteral("11 songs"));
}

void SongListCheck::searchMatchesConstantAndFuzzy()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);

    // The constant is part of the haystack, case-insensitively.
    search(panel)->setText(QStringLiteral("MUS_GYM"));
    QCOMPARE(rowIds(*songs), QList<int>({2}));

    // Multi-word queries need every word in label+constant.
    search(panel)->setText(QStringLiteral("se pc"));
    QCOMPARE(rowIds(*songs), QList<int>({6}));

    // Single-word fallback: a subsequence of the label matches ("msgm" ⊂
    // "mus_gym"), so typing without underscores still finds songs.
    search(panel)->setText(QStringLiteral("msgm"));
    QCOMPARE(rowIds(*songs), QList<int>({2}));

    // A two-word query never takes the fuzzy path: each word must match
    // literally, so "ms gm" finds nothing even though "msgm" would.
    search(panel)->setText(QStringLiteral("ms gm"));
    QVERIFY(rowIds(*songs).isEmpty());
    search(panel)->setText(QStringLiteral("zz zz"));
    QVERIFY(rowIds(*songs).isEmpty());
}

void SongListCheck::categoryFilterNarrows()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QComboBox *box = category(panel);
    QVERIFY(songs && box);

    box->setCurrentIndex(box->findData(QStringLiteral("se_")));
    QCOMPARE(rowIds(*songs), QList<int>({5, 6, 7}));
    QCOMPARE(count(panel)->text(), QStringLiteral("3 of 11 songs"));

    // Other pools the singleton prefixes — here only fanfare_jingle.
    box->setCurrentIndex(box->findData(QStringLiteral("<other>")));
    QCOMPARE(rowIds(*songs), QList<int>({10}));

    box->setCurrentIndex(0);
    QCOMPARE(songs->count(), 11);
}

void SongListCheck::sortOrdersAlphabetically()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs && sort(panel));

    QCOMPARE(rowIds(*songs).first(), 0); // ID order by default
    sort(panel)->setCurrentIndex(1);
    const QStringList labels = rowLabels(*songs);
    QCOMPARE(labels.first(), QStringLiteral("fanfare_jingle"));
    QCOMPARE(labels.at(1), QStringLiteral("mus_gym"));
    QCOMPARE(labels.last(), QStringLiteral("se_use_item"));
    // Case-insensitive label order, id as the tiebreak; the warning suffixes
    // ride along on their rows.
    QVERIFY(labels.at(5).startsWith(QStringLiteral("mus_stray_unregistered")));
}

void SongListCheck::warningRowsMarked()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);
    const QColor warning(0xc0, 0x80, 0x30);

    QListWidgetItem *unregistered = rowForSong(*songs, 8);
    QListWidgetItem *partial = rowForSong(*songs, 9);
    QListWidgetItem *normal = rowForSong(*songs, 0);
    QVERIFY(unregistered && partial && normal);

    QVERIFY(unregistered->text().contains(QStringLiteral("not registered")));
    QCOMPARE(unregistered->foreground().color(), warning);
    QVERIFY(!unregistered->toolTip().isEmpty());

    QVERIFY(partial->text().contains(QStringLiteral("not fully registered")));
    QCOMPARE(partial->foreground().color(), warning);
    QVERIFY(partial->toolTip().contains(QStringLiteral("song_table.inc")));

    QCOMPARE(normal->text(), QStringLiteral("mus_route101")); // no warning suffix
    QVERIFY(normal->foreground().color() != warning);
}

void SongListCheck::selectionTracksCurrentSong()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);

    panel.setCurrentSong(4);
    QVERIFY(songs->currentItem());
    QCOMPARE(songs->currentItem()->data(Qt::UserRole).toInt(), 4);

    // An id outside the list clears the selection rather than guessing.
    panel.setCurrentSong(999);
    QVERIFY(!songs->currentItem());
}

void SongListCheck::searchClearsSelectionUntilEmptied()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);
    panel.setCurrentSong(1);
    QVERIFY(songs->currentItem());

    // Mid-search the selection stays clear so Enter takes the first match.
    search(panel)->setText(QStringLiteral("gym"));
    QVERIFY(!songs->currentItem());

    search(panel)->clear();
    QVERIFY(songs->currentItem());
    QCOMPARE(songs->currentItem()->data(Qt::UserRole).toInt(), 1);
}

void SongListCheck::enterActivatesFirstMatch()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);
    QSignalSpy activated(&panel, &SongListPanel::songActivated);

    search(panel)->setText(QStringLiteral("se_"));
    QTest::keyClick(search(panel), Qt::Key_Return);
    QCOMPARE(activated.count(), 1);
    QCOMPARE(activated.takeFirst().at(0).toInt(), 5); // first match in ID order

    // With a current row, Enter activates that row instead.
    songs->setCurrentItem(rowForSong(*songs, 7));
    QTest::keyClick(search(panel), Qt::Key_Return);
    QCOMPARE(activated.count(), 1);
    QCOMPARE(activated.takeFirst().at(0).toInt(), 7);
}

void SongListCheck::arrowKeysSteerListFromSearch()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);
    panel.show();
    QApplication::processEvents();
    search(panel)->setFocus();
    QVERIFY(search(panel)->hasFocus());

    // Up/Down in the search box move the list's current row, so
    // type-arrow-Enter works without leaving the field.
    QTest::keyClick(search(panel), Qt::Key_Down);
    QCOMPARE(songs->currentRow(), 0);
    QTest::keyClick(search(panel), Qt::Key_Down);
    QCOMPARE(songs->currentRow(), 1);
    QTest::keyClick(search(panel), Qt::Key_Up);
    QCOMPARE(songs->currentRow(), 0);
}

void SongListCheck::spaceStaysWindowShortcut()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    // Bare Space is ignored at ShortcutOverride so the window-level
    // play/pause binding fires instead of inserting a space.
    QKeyEvent space(QEvent::ShortcutOverride, Qt::Key_Space, Qt::NoModifier);
    QCoreApplication::sendEvent(search(panel), &space);
    QVERIFY(!space.isAccepted());
}

void SongListCheck::contextMenuEmitsSignals()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);
    // The menu's exec() only enters its modal loop once the panel is shown;
    // a hidden panel's itemAt() misses and no popup ever opens.
    panel.resize(280, 480);
    panel.show();
    panel.activateWindow();
    QVERIFY(QTest::qWaitForWindowExposed(&panel));
    QApplication::processEvents();
    QSignalSpy activated(&panel, &SongListPanel::songActivated);
    QSignalSpy newTab(&panel, &SongListPanel::songOpenInNewTabRequested);
    QSignalSpy reg(&panel, &SongListPanel::songRegisterRequested);
    QSignalSpy del(&panel, &SongListPanel::songDeleteRequested);

    // Unregistered row: Register Song is enabled; Open fires songActivated.
    inspectRowMenu(panel, *songs, 8, [&](QWidget *menu) {
        QVERIFY(menu);
        const auto texts = menu->actions();
        QCOMPARE(texts.size(), 5); // Open, Open in New Tab, sep, Register, Delete
        QAction *open = texts.at(0);
        QAction *regAction = texts.at(3);
        QCOMPARE(open->text(), QStringLiteral("Open"));
        QCOMPARE(regAction->text(), QStringLiteral("Register Song"));
        QVERIFY(regAction->isEnabled());
        open->trigger();
    });
    QCOMPARE(activated.count(), 1);
    QCOMPARE(activated.takeFirst().at(0).toInt(), 8);

    // Registered row: Register Song is disabled; Delete emits its request.
    inspectRowMenu(panel, *songs, 0, [&](QWidget *menu) {
        QVERIFY(menu);
        QAction *regAction = menu->actions().at(3);
        QVERIFY(!regAction->isEnabled());
        QAction *delAction = menu->actions().at(4);
        QVERIFY(delAction->text().startsWith(QStringLiteral("Delete Song")));
        delAction->trigger();
    });
    QCOMPARE(del.count(), 1);
    QCOMPARE(del.takeFirst().at(0).toInt(), 0);

    // The remaining actions emit their own signals with the row's song id.
    inspectRowMenu(panel, *songs, 9, [&](QWidget *menu) {
        QVERIFY(menu);
        QVERIFY(menu->actions().at(3)->isEnabled()); // partial registration
        menu->actions().at(1)->trigger();            // Open in New Tab
    });
    QCOMPARE(newTab.count(), 1);
    QCOMPARE(newTab.takeFirst().at(0).toInt(), 9);

    inspectRowMenu(panel, *songs, 8, [&](QWidget *menu) {
        QVERIFY(menu);
        menu->actions().at(3)->trigger(); // Register Song
    });
    QCOMPARE(reg.count(), 1);
    QCOMPARE(reg.takeFirst().at(0).toInt(), 8);
}

void SongListCheck::contextMenuSkipsEmptyArea()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    QListWidget *songs = list(panel);
    QVERIFY(songs);
    panel.resize(280, 480);
    panel.show();
    QApplication::processEvents();
    // Below the last row there is no item: the slot returns before a menu
    // exists, so no popup ever activates.
    emit songs->customContextMenuRequested(
        QPoint(songs->viewport()->width() / 2, songs->viewport()->height() - 2));
    QApplication::processEvents();
    QVERIFY(!QApplication::activePopupWidget());
}

void SongListCheck::restoreFiltersAppliesAfterSetSongs()
{
    SongListPanel panel;
    // Before any songs arrive the restored category is pending: it reports
    // through categoryPrefix() and applies once setSongs rebuilds.
    panel.restoreFilters(QString(), 1, QStringLiteral("se_"));
    QCOMPARE(panel.categoryPrefix(), QStringLiteral("se_"));
    QCOMPARE(panel.sortIndex(), 1);

    panel.setSongs(checkSongs());
    QCOMPARE(panel.categoryPrefix(), QStringLiteral("se_"));
    QCOMPARE(rowIds(*list(panel)), QList<int>({5, 6, 7}));
    // A–Z order inside the category.
    QCOMPARE(rowLabels(*list(panel)).first(), QStringLiteral("se_fanfare_1trk"));

    // A category that no longer exists falls back to All.
    SongListPanel other;
    other.restoreFilters(QString(), 0, QStringLiteral("ph_"));
    other.setSongs(checkSongs());
    QCOMPARE(other.categoryPrefix(), QString());
    QCOMPARE(list(other)->count(), 11);
}

void SongListCheck::setSongsPreservesActiveFilters()
{
    SongListPanel panel;
    panel.setSongs(checkSongs());
    search(panel)->setText(QStringLiteral("se_"));
    QCOMPARE(list(panel)->count(), 3);

    // A refresh of the song vector keeps the user's query and category.
    panel.setSongs(checkSongs());
    QCOMPARE(search(panel)->text(), QStringLiteral("se_"));
    QCOMPARE(rowIds(*list(panel)), QList<int>({5, 6, 7}));
}

} // namespace

int runSongListCheck(const QStringList &qtArguments)
{
    SongListCheck test;
    QStringList arguments{QStringLiteral("songlistcheck")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_songlist.moc"
