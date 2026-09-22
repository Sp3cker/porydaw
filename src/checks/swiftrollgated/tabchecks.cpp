#include "tst_swiftrollgated.h"

#include "tabfixture.h"

#include <QAbstractItemModel>
#include <QColor>
#include <QCoreApplication>
#include <QFont>
#include <QImage>
#include <QMetaObject>
#include <QPersistentModelIndex>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QSignalSpy>
#include <QString>
#include <QVariant>
#include <QtTest/QTest>

#include <algorithm>
#include <cmath>
#include <optional>

using tabcheck::captionOf;
using tabcheck::changedPixels;
using tabcheck::kCloseExtent;
using tabcheck::kFourthSong;
using tabcheck::kInputSettleMs;
using tabcheck::kOpenTimeoutMs;
using tabcheck::kSecondSong;
using tabcheck::kSettleTimeoutMs;
using tabcheck::kThirdSong;
using tabcheck::matchingColorCount;
using tabcheck::pixelsDifferingFrom;
using tabcheck::sceneRectOf;
using tabcheck::songBytes;
using tabcheck::songPath;
using tabcheck::TabMetrics;
using tabcheck::tabMetricsFor;
using tabcheck::TabNote;
using tabcheck::TabScene;

void SwiftRollGatedTest::songTabsGeometryAndSelection()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("song tab geometry and selection belong to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();
    QVERIFY(firstId >= 0);
    int secondId = -1;
    int thirdId = -1;
    QVERIFY2(scene.openSong(kSecondSong, &secondId, &error), qPrintable(error));
    QVERIFY2(scene.openSong(kThirdSong, &thirdId, &error), qPrintable(error));
    QCOMPARE(scene.tabCount(), 3);
    QCOMPARE(scene.idAt(0), firstId);
    QCOMPARE(scene.idAt(1), secondId);
    QCOMPARE(scene.idAt(2), thirdId);

    // Selecting reveals its tab, so the measured tab is inside the strip, and
    // three tabs fit, so no selection can scroll the measured geometry.
    QVERIFY2(scene.select(firstId, &error), qPrintable(error));
    QVERIFY2(scene.tabButtonVisible(thirdId),
             "the three tabs do not fit the window, so the strip geometry is scrolled");

    QQuickItem *const strip = scene.strip();
    QQuickItem *const pages = scene.pages();
    QQuickItem *const button = scene.selectButton(firstId);
    QQuickItem *const close = scene.closeButton(firstId);
    QVERIFY(strip != nullptr);
    QVERIFY(pages != nullptr);
    QVERIFY(button != nullptr);
    QVERIFY(close != nullptr);
    QVERIFY(strip->isVisible());
    QVERIFY(pages->isVisible());

    const QFont tabFont = button->property("font").value<QFont>();
    const TabMetrics *const metrics = tabMetricsFor(tabFont.pixelSize());
    QVERIFY2(metrics != nullptr,
             qPrintable(QStringLiteral("the tab label font resolved to %1px, which is not a "
                                       "captured production font scale")
                            .arg(tabFont.pixelSize())));

    const QRectF rootRect = sceneRectOf(scene.m_root);
    const QRectF stripRect = sceneRectOf(strip);
    const QRectF pagesRect = sceneRectOf(pages);
    const QRectF buttonRect = sceneRectOf(button);
    const QRectF closeRect = sceneRectOf(close);

    // The strip is the whole top band of the mounted surface, and the page stack
    // begins exactly at its bottom edge.
    QCOMPARE(qRound(stripRect.left()), qRound(rootRect.left()));
    QCOMPARE(qRound(stripRect.width()), qRound(rootRect.width()));
    QCOMPARE(qRound(stripRect.top()), qRound(rootRect.top()));
    QCOMPARE(qRound(stripRect.height()), metrics->stripHeight);
    QCOMPARE(qRound(pagesRect.top()), qRound(stripRect.bottom()));
    QCOMPARE(qRound(pagesRect.width()), qRound(rootRect.width()));

    // The tab body and the inset close control are the production boxes.
    QCOMPARE(qRound(buttonRect.height()), metrics->tabHeight);
    QCOMPARE(qRound(closeRect.width()), kCloseExtent);
    QCOMPARE(qRound(closeRect.height()), kCloseExtent);
    QCOMPARE(qRound(closeRect.left() - buttonRect.left()), qRound(buttonRect.width()) - 21);
    QCOMPARE(qRound(closeRect.top() - buttonRect.top()), 4);

    // The caption is the production typography and never reaches the close
    // control or the tab edge.
    QCOMPARE(tabFont.pixelSize(), metrics->labelFontPx);
    QVERIFY(tabFont.weight() == QFont::DemiBold);
    QQuickItem *const caption = captionOf(button);
    QVERIFY2(caption != nullptr, "the tab button presents no caption");
    const qreal captionWidth = caption->property("contentWidth").toDouble();
    const qreal captionLeft =
        caption->mapToScene(QPointF((caption->width() - captionWidth) / 2.0, 0.0)).x();
    QVERIFY(captionWidth > 0.0);
    QVERIFY2(captionLeft >= buttonRect.left(), "the tab caption starts outside its tab body");
    QVERIFY2(captionLeft + captionWidth <= closeRect.left(),
             "the tab caption overlaps the close control");

    // Strip controls never take focus from the grid.
    for (QQuickItem *const control : {button, close, scene.scrollLeft(), scene.scrollRight()}) {
        QVERIFY(control != nullptr);
        QCOMPARE(control->property("focusPolicy").toInt(), int(Qt::NoFocus));
    }

    // The selection mark follows selectedId: the selected tab's body changes, an
    // untouched neighbour's does not.
    QVERIFY2(scene.awaitFrame(&error), qPrintable(error));
    const QImage selectedFrame = scene.m_view->grabWindow();
    QVERIFY(!selectedFrame.isNull());
    QVERIFY2(scene.select(secondId, &error), qPrintable(error));
    QVERIFY2(scene.awaitFrame(&error), qPrintable(error));
    const QImage otherFrame = scene.m_view->grabWindow();
    QVERIFY(!otherFrame.isNull());
    QCOMPARE(otherFrame.size(), selectedFrame.size());
    QCOMPARE(otherFrame.devicePixelRatio(), selectedFrame.devicePixelRatio());

    const qreal dpr = selectedFrame.devicePixelRatio();
    const QRectF firstBody = sceneRectOf(button);
    const QRectF secondBody = sceneRectOf(scene.selectButton(secondId));
    // The tab is taller than the strip: its bottom margin is clipped by the
    // viewport, so the button's scene rect reaches into the page stack. The
    // untouched neighbour is measured only over the strip's visible band —
    // below it the page stack repaints on every selection.
    const QRectF thirdBody =
        sceneRectOf(scene.selectButton(thirdId)).intersected(sceneRectOf(strip));
    QVERIFY2(changedPixels(selectedFrame, otherFrame, firstBody) > qMax(16, int(dpr * dpr * 16)),
             "the deselected tab body did not repaint");
    QVERIFY2(changedPixels(selectedFrame, otherFrame, secondBody) > qMax(16, int(dpr * dpr * 16)),
             "the selected state does not cover the complete tab body");
    const QRectF closeSurrounding(secondBody.right() - 24, secondBody.top(), 24,
                                  secondBody.height());
    QVERIFY2(changedPixels(selectedFrame, otherFrame, closeSurrounding) >
                 qMax(4, int(dpr * dpr * 4)),
             "the selected state stops before the inset close control");
    QCOMPARE(changedPixels(selectedFrame, otherFrame, thirdBody), 0);

    // The grid renders inside the clipped page stack: the selected page's note
    // faces are painted below the strip.
    const auto rendered = scene.firstVisibleNote(secondId);
    QVERIFY2(rendered.has_value(), "the selected tab has no fully visible note");
    QQuickItem *const note = scene.noteItem(secondId, rendered->id);
    QVERIFY(note != nullptr);
    QVERIFY(note->isVisible());
    QVERIFY2(pagesRect.contains(sceneRectOf(note)),
             "the selected page lays a note outside the page stack");
    const QColor noteFace(note->property("fillColor").toString());
    QVERIFY(noteFace.isValid());
    QVERIFY2(matchingColorCount(otherFrame, pagesRect, noteFace) > 0,
             "the selected page's note face is not rendered inside the page stack");
}

void SwiftRollGatedTest::songTabsScrollControlsAndGridInput()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("song tab scroll controls belong to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();

    // Four song tabs must overflow the strip for its native scroll controls to
    // appear; the scenario keeps the widest window that still overflows.
    int lastId = firstId;
    QVERIFY2(scene.openSong(kSecondSong, &lastId, &error), qPrintable(error));
    QVERIFY2(scene.openSong(kThirdSong, &lastId, &error), qPrintable(error));
    QVERIFY2(scene.openSong(kFourthSong, &lastId, &error), qPrintable(error));
    QCOMPARE(scene.tabCount(), 4);
    QVERIFY2(scene.narrowUntilStripOverflows(&error), qPrintable(error));

    QQuickItem *const scrollLeft = scene.scrollLeft();
    QQuickItem *const scrollRight = scene.scrollRight();
    QVERIFY(scrollLeft != nullptr);
    QVERIFY(scrollRight != nullptr);
    QVERIFY(scrollLeft->isVisible() && scrollRight->isVisible());

    // The selected tab is revealed at the end of the row, so the first tab is
    // clipped and the strip can only scroll towards it.
    QTRY_VERIFY_WITH_TIMEOUT(scene.tabButtonVisible(lastId), kSettleTimeoutMs);
    QVERIFY2(!scene.tabButtonVisible(firstId), "the overflowing strip did not clip its first tab");
    QVERIFY(scrollLeft->isEnabled());

    QVERIFY2(scene.revealTab(firstId, &error), qPrintable(error));
    QVERIFY2(!scrollLeft->isEnabled(), "the left scroll control stays enabled at the row start");
    QVERIFY2(!scene.tabButtonVisible(lastId),
             "scrolling to the row start did not clip the last tab");
    QVERIFY2(scene.select(firstId, &error), qPrintable(error));

    // The strip takes no input after a scroll-control click: pointer and keyboard
    // input still reach the active page's grid.
    const auto target = scene.firstClickableNote(firstId);
    QVERIFY2(target.has_value(), "the active tab has no note a click can reach");
    QTest::mouseClick(scene.m_view, Qt::LeftButton, Qt::NoModifier,
                      scene.noteCenter(firstId, target->id));
    QTRY_COMPARE_WITH_TIMEOUT(scene.selectedNoteCount(firstId), 1, kSettleTimeoutMs);
    QTest::keyClick(scene.m_view, Qt::Key_Escape);
    QTRY_COMPARE_WITH_TIMEOUT(scene.selectedNoteCount(firstId), 0, kSettleTimeoutMs);
    TabNote drawn;
    QVERIFY2(scene.drawNote(firstId, &drawn, &error), qPrintable(error));

    // The right control reaches the clipped end of the row the same way.
    QVERIFY2(scene.revealTab(lastId, &error), qPrintable(error));
    QVERIFY2(!scrollRight->isEnabled(), "the right scroll control stays enabled at the row end");
    QVERIFY2(scene.select(lastId, &error), qPrintable(error));
    QCOMPARE(scene.selectedId(), lastId);
    QVERIFY(scene.page(lastId)->isVisible());
}

void SwiftRollGatedTest::songTabsOpenCreatesIndependentWorkspace()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("song tab opening belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();
    QObject *const firstGrid = scene.grid(firstId);
    QVERIFY(firstGrid != nullptr);
    const QString firstSummary = firstGrid->property("noteSummary").toString();
    QVERIFY(!firstSummary.isEmpty());

    int secondId = -1;
    QVERIFY2(scene.openSong(kSecondSong, &secondId, &error), qPrintable(error));
    QCOMPARE(scene.tabCount(), 2);
    QCOMPARE(scene.selectedId(), secondId);
    QCOMPARE(scene.idAt(0), firstId);
    QCOMPARE(scene.idAt(1), secondId);

    // The appended tab owns its own page, grid and document.
    QObject *const secondGrid = scene.grid(secondId);
    QVERIFY(secondGrid != nullptr);
    QVERIFY2(secondGrid != firstGrid, "the appended tab reused the open tab's grid");
    QVERIFY2(secondGrid->property("noteSummary").toString() != firstSummary,
             "the appended tab presents the open tab's document");
    QQuickItem *const firstPage = scene.page(firstId);
    QQuickItem *const secondPage = scene.page(secondId);
    QVERIFY(firstPage != nullptr);
    QVERIFY(secondPage != nullptr);
    QVERIFY(secondPage->isVisible() && secondPage->isEnabled());
    QVERIFY2(!firstPage->isVisible(), "the outgoing tab's page stayed presented");
    QCOMPARE(scene.pageSession(firstId), scene.sessionAt(0));
    QCOMPARE(scene.pageSession(secondId), scene.sessionAt(1));
    QQuickItem *const secondSurface = scene.pageSurface(secondId);
    QVERIFY(secondSurface != nullptr);
    QCOMPARE(secondSurface->property("gridModel").value<QObject *>(), secondGrid);

    // The open tab keeps its page, grid and document untouched, and the mounted
    // surface publishes the selected page's grid.
    QCOMPARE(scene.grid(firstId), firstGrid);
    QCOMPARE(firstGrid->property("noteSummary").toString(), firstSummary);
    QCOMPARE(scene.gridAt(0), firstGrid);
    QCOMPARE(scene.m_root->property("gridModel").value<QObject *>(), secondGrid);
}

void SwiftRollGatedTest::songTabsSwitchPreservesPageState()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("song tab switching belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();
    int secondId = -1;
    QVERIFY2(scene.openSong(kSecondSong, &secondId, &error), qPrintable(error));
    QVERIFY2(scene.select(firstId, &error), qPrintable(error));

    // A real edit plus a scrolled camera are this tab's own state.
    TabNote drawn;
    QVERIFY2(scene.drawNote(firstId, &drawn, &error), qPrintable(error));
    QObject *const firstGrid = scene.grid(firstId);
    QVERIFY(firstGrid != nullptr);
    const QString editedSummary = firstGrid->property("noteSummary").toString();
    QVERIFY(scene.canUndo());
    QQuickItem *const gutter = scene.pageItem(firstId, QStringLiteral("timelineQuickRollGutter"));
    QVERIFY(gutter != nullptr);
    const double initialScrollY = firstGrid->property("cameraScrollY").toDouble();
    const double maximumScrollY = firstGrid->property("cameraMaxVScroll").toDouble();
    QVERIFY(maximumScrollY > 1.0);
    // A wheel over the keyboard gutter scrolls the roll vertically; a wheel over
    // the plot zooms instead, so the gutter is the scroll target.
    scene.wheelVertical(*gutter, initialScrollY < maximumScrollY - 1.0 ? -120 : 120);
    QTRY_VERIFY_WITH_TIMEOUT(
        std::abs(firstGrid->property("cameraScrollY").toDouble() - initialScrollY) > 0.5,
        kSettleTimeoutMs);
    const QPointer<QQuickItem> firstPage = scene.page(firstId);
    const QPointer<QObject> firstGridGuard = firstGrid;
    const double cameraX = firstGrid->property("cameraScrollX").toDouble();
    const double cameraY = firstGrid->property("cameraScrollY").toDouble();
    const QString siblingSummary = scene.grid(secondId)->property("noteSummary").toString();

    QVERIFY2(scene.select(secondId, &error), qPrintable(error));
    QCOMPARE(scene.grid(secondId)->property("noteSummary").toString(), siblingSummary);
    QVERIFY2(!scene.canUndo(), "the sibling tab inherited the edited tab's history");
    QVERIFY(firstPage != nullptr);
    QVERIFY2(!firstPage->isVisible(), "the hidden tab's page stayed presented");

    QVERIFY2(scene.select(firstId, &error), qPrintable(error));
    QVERIFY2(scene.page(firstId) == firstPage, "switching away and back replaced the tab's page");
    QVERIFY2(scene.grid(firstId) == firstGridGuard,
             "switching away and back replaced the tab's grid");
    QCOMPARE(firstGrid->property("noteSummary").toString(), editedSummary);
    QVERIFY2(scene.canUndo(), "switching away and back dropped the tab's history");
    QVERIFY(qFuzzyCompare(firstGrid->property("cameraScrollX").toDouble() + 1.0, cameraX + 1.0));
    QVERIFY(qFuzzyCompare(firstGrid->property("cameraScrollY").toDouble() + 1.0, cameraY + 1.0));
}

void SwiftRollGatedTest::songTabsPointerReorderPreservesIdentities()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("pointer tab reordering belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();
    int secondId = -1;
    QVERIFY2(scene.openSong(kSecondSong, &secondId, &error), qPrintable(error));
    QVERIFY2(scene.select(firstId, &error), qPrintable(error));

    TabNote drawn;
    QVERIFY2(scene.drawNote(firstId, &drawn, &error), qPrintable(error));
    QObject *const firstGrid = scene.grid(firstId);
    QObject *const secondGrid = scene.grid(secondId);
    QVERIFY(firstGrid != nullptr);
    QVERIFY(secondGrid != nullptr);
    const QString editedSummary = firstGrid->property("noteSummary").toString();
    QQuickItem *const gutter = scene.pageItem(firstId, QStringLiteral("timelineQuickRollGutter"));
    QVERIFY(gutter != nullptr);
    const double initialScrollY = firstGrid->property("cameraScrollY").toDouble();
    const double maximumScrollY = firstGrid->property("cameraMaxVScroll").toDouble();
    QVERIFY(maximumScrollY > 1.0);
    scene.wheelVertical(*gutter, initialScrollY < maximumScrollY - 1.0 ? -120 : 120);
    QTRY_VERIFY_WITH_TIMEOUT(
        std::abs(firstGrid->property("cameraScrollY").toDouble() - initialScrollY) > 0.5,
        kSettleTimeoutMs);
    const double cameraX = firstGrid->property("cameraScrollX").toDouble();
    const double cameraY = firstGrid->property("cameraScrollY").toDouble();

    const int secondRow = scene.rowForId(secondId);
    QVERIFY(secondRow >= 0);
    QPersistentModelIndex persistentSecond(scene.m_tabs->index(secondRow, 0));
    QSignalSpy rowsMoved(scene.m_tabs, &QAbstractItemModel::rowsMoved);
    QSignalSpy rowsRemoved(scene.m_tabs, &QAbstractItemModel::rowsRemoved);
    QSignalSpy rowsInserted(scene.m_tabs, &QAbstractItemModel::rowsInserted);
    QVERIFY(rowsMoved.isValid());
    QVERIFY(rowsRemoved.isValid());
    QVERIFY(rowsInserted.isValid());

    // A real pointer drag from the first tab to the second tab's position.
    QQuickItem *const source = scene.selectButton(firstId);
    QQuickItem *const destination = scene.selectButton(secondId);
    QVERIFY(source != nullptr);
    QVERIFY(destination != nullptr);
    const QPoint start = source->mapToScene(source->boundingRect().center()).toPoint();
    const QPoint finish = destination->mapToScene(destination->boundingRect().center()).toPoint();
    QTest::mouseMove(scene.m_view, start);
    QTest::mousePress(scene.m_view, Qt::LeftButton, Qt::NoModifier, start);
    for (int step = 1; step <= 4; ++step) {
        QTest::mouseMove(scene.m_view, start + (finish - start) * step / 4);
        QTest::qWait(kInputSettleMs);
    }
    QTest::mouseRelease(scene.m_view, Qt::LeftButton, Qt::NoModifier, finish);

    QTRY_VERIFY_WITH_TIMEOUT(rowsMoved.count() == 1, kSettleTimeoutMs);
    QVERIFY2(scene.rowForId(firstId) == 1,
             "the pointer drag did not move the dragged tab to the dropped index");
    QCOMPARE(scene.rowForId(secondId), 0);
    QCOMPARE(rowsRemoved.count(), 0);
    QCOMPARE(rowsInserted.count(), 0);
    QVERIFY2(persistentSecond.isValid() && persistentSecond.row() == 0,
             "the reorder was not a genuine row move of the untouched session");
    QCOMPARE(scene.selectedId(), firstId);

    // The strip's page pairing survives: each row's `songTab_<id>` page presents
    // that row's session, and every grid is still the object it was. A model move
    // rebuilds the pages it moves, so the pairing is awaited rather than read at
    // one instant.
    const auto paired = [&scene] {
        for (int row = 0; row < scene.tabCount(); ++row) {
            const int tabId = scene.idAt(row);
            if (tabId < 0)
                return false;
            QObject *const session = scene.sessionAt(row);
            QQuickItem *const surface = scene.pageSurface(tabId);
            if (!surface || scene.pageSession(tabId) != session)
                return false;
            if (surface->property("gridModel").value<QObject *>() !=
                session->property("grid").value<QObject *>())
                return false;
        }
        return true;
    };
    QVERIFY2(QTest::qWaitFor(paired, kSettleTimeoutMs),
             "the pointer reorder broke the strip's page pairing");
    QCOMPARE(scene.grid(firstId), firstGrid);
    QCOMPARE(scene.grid(secondId), secondGrid);
    QCOMPARE(firstGrid->property("noteSummary").toString(), editedSummary);
    QVERIFY(scene.canUndo());
    QVERIFY(qFuzzyCompare(firstGrid->property("cameraScrollX").toDouble() + 1.0, cameraX + 1.0));
    QVERIFY(qFuzzyCompare(firstGrid->property("cameraScrollY").toDouble() + 1.0, cameraY + 1.0));
}

void SwiftRollGatedTest::songTabsBackgroundClosePreservesActive()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("background tab closing belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();
    int secondId = -1;
    int thirdId = -1;
    QVERIFY2(scene.openSong(kSecondSong, &secondId, &error), qPrintable(error));
    QVERIFY2(scene.openSong(kThirdSong, &thirdId, &error), qPrintable(error));
    QVERIFY2(scene.select(secondId, &error), qPrintable(error));

    QObject *const activeGrid = scene.grid(secondId);
    QVERIFY(activeGrid != nullptr);
    const QString activeSummary = activeGrid->property("noteSummary").toString();
    const QPointer<QQuickItem> activePage = scene.page(secondId);
    const int activeRow = scene.rowForId(secondId);
    QVERIFY(activeRow >= 0);

    QVERIFY2(scene.clickClose(thirdId, &error), qPrintable(error));
    QTRY_VERIFY_WITH_TIMEOUT(scene.tabCount() == 2, kSettleTimeoutMs);
    QCOMPARE(scene.pendingCloseId(), -1);
    QCOMPARE(scene.rowForId(thirdId), -1);
    QTRY_VERIFY_WITH_TIMEOUT(scene.page(thirdId) == nullptr, kSettleTimeoutMs);
    QCOMPARE(scene.selectedId(), secondId);
    QCOMPARE(scene.selectedIndex(), activeRow);
    QVERIFY2(scene.page(secondId) == activePage, "the background close replaced the active page");
    QCOMPARE(scene.grid(secondId), activeGrid);
    QCOMPARE(activeGrid->property("noteSummary").toString(), activeSummary);
    QVERIFY(scene.page(secondId)->isVisible());
    QVERIFY2(scene.page(firstId) != nullptr, "the background close dropped the first tab");
}

void SwiftRollGatedTest::songTabsFinalCloseEmptyAndReopen()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("closing the final tab belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int onlyId = scene.selectedId();
    QCOMPARE(scene.tabCount(), 1);
    const QPointer<QQuickView> view = scene.m_view;
    const QPointer<QQuickItem> rootObject = scene.m_root;
    QQuickItem *const strip = scene.strip();
    QVERIFY(strip != nullptr);

    const auto rendered = scene.firstVisibleNote(onlyId);
    QVERIFY2(rendered.has_value(), "the staged song has no fully visible note");
    QQuickItem *const note = scene.noteItem(onlyId, rendered->id);
    QVERIFY(note != nullptr);
    const QColor noteFace(note->property("fillColor").toString());
    QVERIFY(noteFace.isValid());

    QVERIFY2(scene.clickClose(onlyId, &error), qPrintable(error));
    QTRY_VERIFY_WITH_TIMEOUT(scene.tabCount() == 0, kSettleTimeoutMs);
    QCOMPARE(scene.pendingCloseId(), -1);
    QCOMPARE(scene.selectedId(), -1);
    QCOMPARE(scene.selectedIndex(), -1);
    QVERIFY2(!scene.m_session->property("songOpen").toBool(),
             "the empty strip still reports an open song");
    QTRY_VERIFY_WITH_TIMEOUT(scene.page(onlyId) == nullptr, kSettleTimeoutMs);
    QVERIFY2(!scene.m_root->property("gridModel").value<QObject *>(),
             "the empty strip still publishes a grid");

    // The view survives the empty strip: the blank page is the same mounted
    // scene, and the strip stays presented with no tabs.
    QCOMPARE(scene.m_window.gridView(), view.data());
    QVERIFY(scene.m_root == rootObject);
    QVERIFY(scene.m_view->isExposed());
    QVERIFY2(strip->isVisible(), "the empty strip is not presented");
    QQuickItem *const pages = scene.pages();
    QVERIFY(pages != nullptr);
    QVERIFY(pages->isVisible());
    QVERIFY2(scene.awaitFrame(&error), qPrintable(error));
    const QImage emptyFrame = scene.m_view->grabWindow();
    QVERIFY(!emptyFrame.isNull());
    const QRectF pagesRect = sceneRectOf(pages);
    QVERIFY2(pixelsDifferingFrom(emptyFrame, pagesRect, scene.m_view->color()) == 0,
             "the empty workspace paints something over the blank page");
    QVERIFY2(matchingColorCount(emptyFrame, pagesRect, noteFace) == 0,
             "the closed tab's note rendering leaked into the empty workspace");

    // A later open works from the empty strip and renders inside the same view.
    int reopenedId = -1;
    QVERIFY2(scene.openSong(kThirdSong, &reopenedId, &error), qPrintable(error));
    QCOMPARE(scene.tabCount(), 1);
    QVERIFY(reopenedId >= 0 && reopenedId != onlyId);
    QVERIFY(scene.page(reopenedId) != nullptr);
    QVERIFY(scene.page(reopenedId)->isVisible());
    QVERIFY2(scene.selectButton(reopenedId) != nullptr, "the reopened song has no strip tab");
    QCOMPARE(scene.m_window.gridView(), view.data());
    QVERIFY2(scene.awaitFrame(&error), qPrintable(error));
    const QImage reopenedFrame = scene.m_view->grabWindow();
    QVERIFY(!reopenedFrame.isNull());
    const auto reopenedNote = scene.firstVisibleNote(reopenedId);
    QVERIFY2(reopenedNote.has_value(), "the reopened tab has no fully visible note");
    QQuickItem *const reopenedItem = scene.noteItem(reopenedId, reopenedNote->id);
    QVERIFY(reopenedItem != nullptr);
    const QColor reopenedFace(reopenedItem->property("fillColor").toString());
    QVERIFY(reopenedFace.isValid());
    QVERIFY2(matchingColorCount(reopenedFrame, sceneRectOf(scene.pages()), reopenedFace) > 0,
             "the reopened tab's note face is not rendered inside the page stack");
}

void SwiftRollGatedTest::songTabsReopenExistingFocusesTab()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("focusing an open song tab belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int firstId = scene.selectedId();
    int secondId = -1;
    QVERIFY2(scene.openSong(kSecondSong, &secondId, &error), qPrintable(error));
    QVERIFY2(scene.select(secondId, &error), qPrintable(error));

    const int firstRow = scene.rowForId(firstId);
    QVERIFY(firstRow >= 0);
    QObject *const firstGrid = scene.grid(firstId);
    QObject *const secondGrid = scene.grid(secondId);
    QVERIFY(firstGrid != nullptr);
    QVERIFY(secondGrid != nullptr);
    const QString firstSummary = firstGrid->property("noteSummary").toString();
    const QPointer<QQuickItem> firstPage = scene.page(firstId);
    QSignalSpy rowsMoved(scene.m_tabs, &QAbstractItemModel::rowsMoved);
    QSignalSpy rowsRemoved(scene.m_tabs, &QAbstractItemModel::rowsRemoved);
    QSignalSpy rowsInserted(scene.m_tabs, &QAbstractItemModel::rowsInserted);
    QVERIFY(rowsMoved.isValid());
    QVERIFY(rowsRemoved.isValid());
    QVERIFY(rowsInserted.isValid());

    // Re-opening an open label focuses its tab instead of adding a second one.
    QVERIFY(QMetaObject::invokeMethod(scene.m_session, "openSong", Q_ARG(QString, m_songLabel)));
    QTRY_COMPARE_WITH_TIMEOUT(scene.selectedId(), firstId, kOpenTimeoutMs);
    QCOMPARE(scene.tabCount(), 2);
    QCOMPARE(scene.rowForId(firstId), firstRow);
    QCOMPARE(scene.selectedIndex(), firstRow);
    QCOMPARE(rowsMoved.count(), 0);
    QCOMPARE(rowsRemoved.count(), 0);
    QCOMPARE(rowsInserted.count(), 0);

    // Focusing is not a reload: the tab keeps its page, grid and document, and the
    // sibling tab is untouched.
    QVERIFY2(scene.page(firstId) == firstPage, "focusing an open tab reloaded its page");
    QCOMPARE(scene.grid(firstId), firstGrid);
    QCOMPARE(firstGrid->property("noteSummary").toString(), firstSummary);
    QCOMPARE(scene.grid(secondId), secondGrid);
    // The selection signals are queued: the page's visible binding re-evaluates
    // on the next event-loop pass, after selectedId already reads the new tab.
    QTRY_VERIFY_WITH_TIMEOUT(scene.page(firstId)->isVisible() && scene.page(firstId)->isEnabled(),
                             kOpenTimeoutMs);
    QTRY_VERIFY_WITH_TIMEOUT(!scene.page(secondId)->isVisible(), kOpenTimeoutMs);
    QQuickItem *const button = scene.selectButton(firstId);
    QVERIFY(button != nullptr);
    QVERIFY2(button->property("checked").toBool(), "the focused tab is not the checked tab");
}

void SwiftRollGatedTest::songTabsDirtyCancelDiscardSave()
{
    if (m_mode != QStringLiteral("swiftrollgated"))
        QSKIP("the dirty tab close gate belongs to the swiftrollgated surface");

    TabScene scene;
    QString error;
    QVERIFY2(scene.open(m_projectRoot, m_songLabel, &error), qPrintable(error));
    const int dirtyId = scene.selectedId();
    int otherId = -1;
    QVERIFY2(scene.openSong(kThirdSong, &otherId, &error), qPrintable(error));
    QVERIFY2(scene.select(dirtyId, &error), qPrintable(error));

    const QString dirtySongPath = songPath(m_projectRoot, m_songLabel);
    const QString otherSongPath = songPath(m_projectRoot, QString::fromLatin1(kThirdSong));
    const QByteArray dirtySongBefore = songBytes(dirtySongPath);
    const QByteArray otherSongBefore = songBytes(otherSongPath);
    QVERIFY(!dirtySongBefore.isEmpty());
    QVERIFY(!otherSongBefore.isEmpty());

    // A real edit through the session dirties the tab and marks its caption.
    TabNote drawn;
    QVERIFY2(scene.drawNote(dirtyId, &drawn, &error), qPrintable(error));
    QObject *const dirtySession = scene.sessionAt(scene.rowForId(dirtyId));
    QVERIFY(dirtySession != nullptr);
    QVERIFY2(dirtySession->property("dirty").toBool(), "a real edit did not dirty the tab");
    QQuickItem *const dirtyButton = scene.selectButton(dirtyId);
    QVERIFY(dirtyButton != nullptr);
    QVERIFY2(dirtyButton->property("text").toString().endsWith(QLatin1Char('*')),
             "a dirty tab's caption is not marked");
    QObject *const dirtyGrid = scene.grid(dirtyId);
    QVERIFY(dirtyGrid != nullptr);
    const QString dirtySummary = dirtyGrid->property("noteSummary").toString();

    // Cancel keeps the tab, its work and its page.
    QVERIFY2(scene.clickClose(dirtyId, &error), qPrintable(error));
    QTRY_COMPARE_WITH_TIMEOUT(scene.pendingCloseId(), dirtyId, kSettleTimeoutMs);
    QVERIFY2(!scene.strip()->isEnabled(), "the strip is not gated while the close dialog asks");
    const auto gateOffers = [&scene] {
        QQuickItem *const save = scene.item(QStringLiteral("songTabSave"));
        QQuickItem *const discard = scene.item(QStringLiteral("songTabDiscard"));
        QQuickItem *const cancel = scene.item(QStringLiteral("songTabCancel"));
        return save && discard && cancel && save->isVisible() && discard->isVisible() &&
               cancel->isVisible();
    };
    QTRY_VERIFY_WITH_TIMEOUT(gateOffers(), kSettleTimeoutMs);
    // The gate is modal: a background tab cannot be selected while it asks.
    QQuickItem *const otherButton = scene.selectButton(otherId);
    QVERIFY(otherButton != nullptr);
    QTest::mouseClick(scene.m_view, Qt::LeftButton, Qt::NoModifier,
                      otherButton->mapToScene(otherButton->boundingRect().center()).toPoint());
    QCoreApplication::processEvents();
    QCOMPARE(scene.selectedId(), dirtyId);
    QVERIFY2(scene.clickDialogButton(QStringLiteral("songTabCancel"), &error), qPrintable(error));
    QTRY_COMPARE_WITH_TIMEOUT(scene.pendingCloseId(), -1, kSettleTimeoutMs);
    QCOMPARE(scene.tabCount(), 2);
    QCOMPARE(scene.grid(dirtyId), dirtyGrid);
    QCOMPARE(dirtyGrid->property("noteSummary").toString(), dirtySummary);
    QVERIFY2(scene.sessionAt(scene.rowForId(dirtyId))->property("dirty").toBool(),
             "Cancel dropped the tab's unsaved work");

    // Discard drops the tab's work: nothing was written.
    QVERIFY2(scene.clickClose(dirtyId, &error), qPrintable(error));
    QTRY_COMPARE_WITH_TIMEOUT(scene.pendingCloseId(), dirtyId, kSettleTimeoutMs);
    QVERIFY2(scene.clickDialogButton(QStringLiteral("songTabDiscard"), &error), qPrintable(error));
    QTRY_COMPARE_WITH_TIMEOUT(scene.tabCount(), 1, kSettleTimeoutMs);
    QCOMPARE(scene.pendingCloseId(), -1);
    QTRY_VERIFY_WITH_TIMEOUT(scene.page(dirtyId) == nullptr, kSettleTimeoutMs);
    QCOMPARE(scene.selectedId(), otherId);
    QCOMPARE(songBytes(dirtySongPath), dirtySongBefore);

    // Save writes the song and then closes the tab: the drawn note is on disk.
    QVERIFY2(scene.select(otherId, &error), qPrintable(error));
    TabNote saved;
    QVERIFY2(scene.drawNote(otherId, &saved, &error), qPrintable(error));
    QVERIFY(scene.sessionAt(scene.rowForId(otherId))->property("dirty").toBool());
    QVERIFY2(scene.clickClose(otherId, &error), qPrintable(error));
    QTRY_COMPARE_WITH_TIMEOUT(scene.pendingCloseId(), otherId, kSettleTimeoutMs);
    QVERIFY2(scene.clickDialogButton(QStringLiteral("songTabSave"), &error), qPrintable(error));
    QTRY_VERIFY_WITH_TIMEOUT(scene.tabCount() == 0, kOpenTimeoutMs);
    QCOMPARE(scene.pendingCloseId(), -1);
    QVERIFY2(!scene.m_session->property("saveInProgress").toBool(),
             "the close gate closed the tab before the save finished");
    QCOMPARE(scene.m_session->property("lastSaveError").toString(), QString());
    QVERIFY2(songBytes(otherSongPath) != otherSongBefore,
             "Save closed the tab without writing the song");

    int reopenedId = -1;
    QVERIFY2(scene.openSong(kThirdSong, &reopenedId, &error), qPrintable(error));
    const QList<TabNote> reopened = scene.notes(reopenedId);
    const bool persisted =
        std::any_of(reopened.cbegin(), reopened.cend(), [&saved](const TabNote &note) {
            return note.tick == saved.tick && note.pitch == saved.pitch &&
                   note.duration == saved.duration;
        });
    QVERIFY2(persisted, "the saved song does not carry the note the user drew");
}
