#include "checks/eventviews/eventview_fixture.h"
#include "checks/eventviews/tst_eventviews.h"

#include <QAbstractItemDelegate>
#include <QAction>
#include <QComboBox>
#include <QFontInfo>
#include <QMenu>
#include <QStyleOptionViewItem>
#include <QTableView>
#include <QWidget>
#include <QtTest>
#include <memory>

#include "ui/songview.h"
#include "ui/typography.h"

using checks::eventviews::EventWidgets;
using checks::eventviews::FixtureShape;

void EventViewsChromeTest::visibilityAndTrackSelection()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    QVERIFY(!opened.fixture->view().eventListVisible());

    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);
    QVERIFY(opened.fixture->view().eventListVisible());

    opened.fixture->view().selectTrack(1);
    QTRY_COMPARE(widgets.chunkCombo->currentData().toInt(),
                 checks::eventviews::chunkForTrack(opened.fixture->document(), 1));
}

void EventViewsChromeTest::rowMirrorPlusEot_data()
{
    QTest::addColumn<int>("shape");
    QTest::newRow("empty chunk") << int(FixtureShape::Empty);
    QTest::newRow("single event at EOT") << int(FixtureShape::EotCoincident);
    QTest::newRow("multi-event chunk") << int(FixtureShape::Basic);
}

void EventViewsChromeTest::rowMirrorPlusEot()
{
    QFETCH(int, shape);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape(shape));
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    const int chunk = widgets.chunkCombo->currentData().toInt();
    QVERIFY(chunk >= 0);
    const SmfTrack &track = opened.fixture->document().smf().tracks[chunk];
    const int projectedTempoRows =
        chunk == 0 ? int(opened.fixture->document().tempoPoints().size()) : 0;
    QCOMPARE(widgets.model->rowCount(), int(track.events.size()) + projectedTempoRows + 1);
    QCOMPARE(
        widgets.model->data(widgets.model->index(widgets.model->rowCount() - 1, 0), Qt::EditRole)
            .toULongLong(),
        track.endTick);
}

void EventViewsChromeTest::monoTypography()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    const QFont expected = typography::tableMono(widgets.table->font());
    const QFontInfo expectedInfo(expected);
    const int rows[] = {0, widgets.model->rowCount() - 1};
    const int columns[] = {0, 2, 3, 4};
    for (const int row : rows) {
        for (const int column : columns) {
            const QModelIndex index = widgets.model->index(row, column);
            const QFont cell = widgets.model->data(index, Qt::FontRole).value<QFont>();
            QCOMPARE(QFontInfo(cell).family(), expectedInfo.family());
            QCOMPARE(cell.letterSpacingType(), QFont::AbsoluteSpacing);
            QCOMPARE(cell.letterSpacing(), -0.5);

            QStyleOptionViewItem option;
            option.initFrom(widgets.table);
            const std::unique_ptr<QWidget> editor(
                widgets.table->itemDelegate()->createEditor(widgets.table, option, index));
            QVERIFY(editor);
            QCOMPARE(QFontInfo(editor->font()).family(), expectedInfo.family());
            QCOMPARE(editor->font().letterSpacingType(), QFont::AbsoluteSpacing);
            QCOMPARE(editor->font().letterSpacing(), -0.5);
        }
    }
}

void EventViewsChromeTest::filterMatrix_data()
{
    QTest::addColumn<QStringList>("categories");
    QTest::addColumn<int>("expectedEvents");
    // The Basic fixture deliberately authors three meta rows, four note rows,
    // and four other channel rows. These are a fixed fixture ledger, not the
    // EventTableModel filtering predicate under test.
    QTest::newRow("meta") << QStringList{QStringLiteral("Meta")} << 3;
    QTest::newRow("meta and notes")
        << QStringList{QStringLiteral("Meta"), QStringLiteral("Notes")} << 7;
    QTest::newRow("none") << QStringList{} << 0;
    QTest::newRow("all") << QStringList{QStringLiteral("Notes"),
                                        QStringLiteral("Control changes"),
                                        QStringLiteral("Program changes"),
                                        QStringLiteral("Pitch bends"),
                                        QStringLiteral("Aftertouch"),
                                        QStringLiteral("SysEx"),
                                        QStringLiteral("Meta")}
                         << 11;
}

void EventViewsChromeTest::filterMatrix()
{
    QFETCH(QStringList, categories);
    QFETCH(int, expectedEvents);
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    for (QAction *action : widgets.filterMenu->actions()) {
        const bool wanted = categories.contains(action->text());
        if (action->isChecked() != wanted)
            action->trigger();
    }
    QCOMPARE(widgets.model->rowCount(), expectedEvents + 1);
}

void EventViewsChromeTest::viewStateRoundTrip()
{
    const auto opened = checks::eventviews::openRigFixture(FixtureShape::Basic);
    QVERIFY2(opened, qPrintable(opened.error));
    const EventWidgets widgets = opened.fixture->openEventList();
    QVERIFY(widgets);

    SongView::ViewState state = opened.fixture->view().viewState();
    QVERIFY(state.eventList);
    state.eventList = false;
    opened.fixture->view().applyViewState(state);
    QVERIFY(!opened.fixture->view().eventListVisible());

    state = opened.fixture->view().viewState();
    QVERIFY(!state.eventList);
    state.eventList = true;
    opened.fixture->view().applyViewState(state);
    QVERIFY(opened.fixture->view().eventListVisible());
}

int runEventViewsChromeCheck(const QStringList &qtArguments)
{
    EventViewsChromeTest test;
    QStringList arguments{QStringLiteral("eventviews-chrome")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}
