#include "songtabs_smoke.h"

#include <QAbstractItemModel>
#include <QDeadlineTimer>
#include <QFont>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QMetaObject>
#include <QPersistentModelIndex>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>
#include <QSignalSpy>
#include <QSize>
#include <QString>
#include <QtTest/QTest>
#include <chrono>
#include <cstdio>
#include <cstdlib>

namespace {
using namespace std::chrono_literals;

[[noreturn]] void fail(const char *reason)
{
    std::fprintf(stderr, "SWIFT_GRID_SMOKE FAIL: %s\n", reason);
    std::fflush(stderr);
    std::exit(EXIT_FAILURE);
}

void require(bool condition, const char *reason)
{
    if (!condition)
        fail(reason);
}

void pass(const char *scenario)
{
    std::printf("SWIFT_GRID_SMOKE %s PASS\n", scenario);
    std::fflush(stdout);
}

template <typename Predicate>
void awaitState(Predicate predicate, const char *reason)
{
    QDeadlineTimer deadline(3s);
    while (!predicate()) {
        if (deadline.hasExpired())
            fail(reason);
        QTest::qWait(10ms);
    }
}

QQuickItem *namedItem(QQuickItem *parent, const QString &name)
{
    if (!parent)
        return nullptr;
    if (parent->objectName() == name)
        return parent;
    for (QQuickItem *child : parent->childItems()) {
        if (auto *found = namedItem(child, name))
            return found;
    }
    return nullptr;
}

QPoint center(QQuickItem *item)
{
    require(item && item->isVisible() && item->isEnabled(),
            "native tab input target is unavailable");
    return item->mapToScene(item->boundingRect().center()).toPoint();
}

void click(QQuickWindow *window, QQuickItem *item)
{
    const QPoint target = center(item);
    QTest::mouseMove(window, target);
    QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, target);
    QTest::qWait(30ms);
}

QJsonArray notes(QObject *grid)
{
    const QJsonDocument document =
        QJsonDocument::fromJson(grid->property("noteSummary").toString().toUtf8());
    require(document.isArray(), "tab grid noteSummary is not a JSON array");
    return document.array();
}

int selectedNoteCount(QObject *grid)
{
    int count = 0;
    for (const QJsonValue &value : notes(grid))
        count += value.toObject().value("selected").toBool() ? 1 : 0;
    return count;
}

int colorCount(const QImage &image, const QRectF &logicalRegion, qreal dpr, QRgb color)
{
    const QRect pixels = QRectF(logicalRegion.topLeft() * dpr, logicalRegion.size() * dpr)
                             .toAlignedRect()
                             .intersected(image.rect());
    int count = 0;
    for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
        for (int x = pixels.left(); x <= pixels.right(); ++x)
            count += image.pixel(x, y) == color ? 1 : 0;
    }
    return count;
}

int changedPixels(const QImage &before, const QImage &after, const QRectF &logicalRegion, qreal dpr)
{
    const QRect pixels = QRectF(logicalRegion.topLeft() * dpr, logicalRegion.size() * dpr)
                             .toAlignedRect()
                             .intersected(before.rect())
                             .intersected(after.rect());
    int changed = 0;
    for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
        for (int x = pixels.left(); x <= pixels.right(); ++x)
            changed += before.pixel(x, y) != after.pixel(x, y) ? 1 : 0;
    }
    return changed;
}

struct TabsScene {
    QQuickWindow *window = nullptr;
    QObject *controller = nullptr;
    QAbstractItemModel *tabs = nullptr;

    int selectedId() const { return controller->property("selectedId").toInt(); }
    int tabCount() const { return controller->property("tabCount").toInt(); }
    int pendingCloseId() const { return controller->property("pendingCloseId").toInt(); }

    QQuickItem *rootItem(const QString &name) const
    {
        return namedItem(window->contentItem(), name);
    }

    QQuickItem *page(int tabId) const { return rootItem(QStringLiteral("songTab_%1").arg(tabId)); }

    QQuickItem *pageItem(int tabId, const QString &name) const
    {
        return namedItem(page(tabId), name);
    }

    QObject *grid(int tabId) const
    {
        QQuickItem *tabPage = page(tabId);
        return tabPage ? tabPage->property("gridModel").value<QObject *>() : nullptr;
    }

    QQuickItem *selectButton(int tabId) const
    {
        return rootItem(QStringLiteral("songTabSelect_%1").arg(tabId));
    }

    QQuickItem *closeButton(int tabId) const
    {
        return rootItem(QStringLiteral("songTabClose_%1").arg(tabId));
    }

    int idAt(int row) const
    {
        QObject *session = tabs->data(tabs->index(row, 0), Qt::DisplayRole).value<QObject *>();
        return session ? session->property("tabId").toInt() : -1;
    }

    int rowForId(int tabId) const
    {
        for (int row = 0; row < tabs->rowCount(); ++row) {
            if (idAt(row) == tabId)
                return row;
        }
        return -1;
    }

    int openFixture() const
    {
        const int oldCount = tabCount();
        const int oldSelected = selectedId();
        require(QMetaObject::invokeMethod(controller, "openTab"),
                "controller fixture setup cannot open a tab");
        awaitState([&] { return tabCount() == oldCount + 1 && selectedId() != oldSelected; },
                   "fixture setup did not create and select a tab");
        const int addedId = selectedId();
        awaitState([&] { return page(addedId) && grid(addedId); },
                   "fixture setup did not create a persistent grid page");
        QSignalSpy frameSwapped(window, &QQuickWindow::frameSwapped);
        window->update();
        awaitState([&] { return frameSwapped.count() > 0; },
                   "fixture setup did not reach a rendered native Quick frame");
        return addedId;
    }

    void select(int tabId) const
    {
        QQuickItem *targetButton = selectButton(tabId);
        click(window, targetButton);
        const bool selected = QTest::qWaitFor(
            [&] {
                QQuickItem *tabPage = page(tabId);
                return selectedId() == tabId && tabPage && tabPage->isVisible();
            },
            3s);
        if (!selected) {
            QQuickItem *tabPage = page(tabId);
            auto *currentPage =
                qobject_cast<QQuickItem *>(window->property("currentPage").value<QObject *>());
            const QRectF buttonRect(targetButton->mapToScene(QPointF{}), targetButton->size());
            std::fprintf(
                stderr,
                "Tab selection diagnostic: targetId=%d row=%d selectedId=%d selectedIndex=%d "
                "pendingCloseId=%d windowActive=%d buttonVisible=%d buttonEnabled=%d "
                "buttonRect=(%g,%g %gx%g) pageExists=%d pageVisible=%d currentPage='%s'\n",
                tabId, rowForId(tabId), selectedId(), controller->property("selectedIndex").toInt(),
                pendingCloseId(), window->isActive(), targetButton->isVisible(),
                targetButton->isEnabled(), buttonRect.x(), buttonRect.y(), buttonRect.width(),
                buttonRect.height(), tabPage != nullptr, tabPage && tabPage->isVisible(),
                qPrintable(currentPage ? currentPage->objectName() : QStringLiteral("<null>")));
            std::fflush(stderr);
        }
        require(selected, "tab click did not select its persistent page");
    }

    void close(int tabId) const { click(window, closeButton(tabId)); }
};

void editFirstNote(const TabsScene &scene, int tabId)
{
    QObject *grid = scene.grid(tabId);
    QQuickItem *viewport = scene.pageItem(tabId, QStringLiteral("pianoGridViewport"));
    QQuickItem *note = scene.pageItem(tabId, QStringLiteral("gridNote_1"));
    require(grid && viewport && note, "selected tab is missing its first grid note or viewport");

    const QRectF viewportRect = viewport->mapRectToScene(viewport->boundingRect());
    const QPointF noteCenter = note->mapToScene(note->boundingRect().center());
    const double currentX = viewport->property("contentX").toDouble();
    const double currentY = viewport->property("contentY").toDouble();
    const double maxX =
        qMax(0.0, viewport->property("contentWidth").toDouble() - viewport->width());
    const double maxY =
        qMax(0.0, viewport->property("contentHeight").toDouble() - viewport->height());
    require(
        viewport->setProperty(
            "contentX", qBound(0.0, currentX + noteCenter.x() - viewportRect.center().x(), maxX)) &&
            viewport->setProperty(
                "contentY",
                qBound(0.0, currentY + noteCenter.y() - viewportRect.center().y(), maxY)),
        "cannot reveal the edit target in its selected page viewport");
    QTest::qWait(30ms);

    const QString before = grid->property("noteSummary").toString();
    const QPoint start = center(note);
    require(viewportRect.contains(start), "grid edit target remains clipped after reveal");
    const int dragDistance = qMax(8, qRound(grid->property("beatWidth").toDouble() / 2));
    const QPoint end = start + QPoint(dragDistance, 0);
    require(viewportRect.contains(end), "grid edit drag would leave the selected page viewport");
    QTest::mouseMove(scene.window, start);
    QTest::mousePress(scene.window, Qt::LeftButton, Qt::NoModifier, start);
    QTest::mouseMove(scene.window, end);
    QTest::qWait(30ms);
    QTest::mouseRelease(scene.window, Qt::LeftButton, Qt::NoModifier, end);
    awaitState(
        [&] {
            return grid->property("canUndo").toBool() &&
                   grid->property("noteSummary").toString() != before;
        },
        "real grid drag did not dirty the selected tab");
}

void dragTab(const TabsScene &scene, int tabId, int destinationId)
{
    QQuickItem *source = scene.selectButton(tabId);
    QQuickItem *destination = scene.selectButton(destinationId);
    const QPoint start = center(source);
    const QPoint end = center(destination);
    QTest::mouseMove(scene.window, start);
    QTest::mousePress(scene.window, Qt::LeftButton, Qt::NoModifier, start);
    QTest::mouseMove(scene.window, end);
    QTest::qWait(30ms);
    QTest::mouseRelease(scene.window, Qt::LeftButton, Qt::NoModifier, end);
}

void verifySelectionRendering(const TabsScene &scene, int firstId, int secondId)
{
    const int baseFontPx = qRound(scene.window->property("baseFontPx").toDouble());
    struct NativeMetrics {
        int stripHeight;
        int labelFontPx;
    };
    NativeMetrics metrics{};
    switch (baseFontPx) {
    case 12:
        metrics = {22, 14};
        break;
    case 13:
        metrics = {23, 15};
        break;
    case 16:
        metrics = {27, 18};
        break;
    default:
        fail("tab geometry smoke supports only captured production font sizes 12, 13, and 16");
    }

    scene.select(firstId);
    QQuickItem *firstButton = scene.selectButton(firstId);
    QQuickItem *closeButton = scene.closeButton(firstId);
    QQuickItem *strip = scene.rootItem(QStringLiteral("songTabStrip"));
    QQuickItem *pages = scene.rootItem(QStringLiteral("songTabPages"));
    require(firstButton && closeButton && strip && pages, "tab visual geometry is incomplete");
    const QRectF buttonRect(firstButton->mapToScene(QPointF{}), firstButton->size());
    const QRectF closeRect(closeButton->mapToScene(QPointF{}), closeButton->size());
    const QRectF stripRect(strip->mapToScene(QPointF{}), strip->size());
    const QRectF pagesRect(pages->mapToScene(QPointF{}), pages->size());
    require(qRound(stripRect.height()) == metrics.stripHeight,
            "tab strip height diverged from production QTabBar geometry");
    require(qRound(buttonRect.height()) == 28,
            "tab body height diverged from production QTabBar geometry");
    require(qRound(closeRect.width()) == 20 && qRound(closeRect.height()) == 20 &&
                qRound(closeRect.left() - buttonRect.left()) == qRound(buttonRect.width()) - 21 &&
                qRound(closeRect.top() - buttonRect.top()) == 4,
            "close control is not inset at the production tab-button bounds");
    require(qAbs(pagesRect.top() - (stripRect.top() + stripRect.height())) < 0.01,
            "tab page stack does not begin at the production tab-bar boundary");
    const QFont tabFont = firstButton->property("font").value<QFont>();
    require(tabFont.pixelSize() == metrics.labelFontPx && tabFont.weight() == QFont::DemiBold,
            "tab label typography diverged from the production stylesheet");
    QQuickItem *caption = nullptr;
    const QString captionText = firstButton->property("text").toString();
    for (QQuickItem *candidate : firstButton->findChildren<QQuickItem *>()) {
        if (candidate->property("text").toString() == captionText &&
            candidate->property("contentWidth").isValid()) {
            caption = candidate;
            break;
        }
    }
    require(caption, "tab caption is missing");
    const qreal captionWidth = caption->property("contentWidth").toDouble();
    const qreal captionLeft =
        caption->mapToScene(QPointF((caption->width() - captionWidth) / 2, 0)).x();
    require(captionWidth > 0 && captionLeft >= buttonRect.left() &&
                captionLeft + captionWidth <= closeRect.left(),
            "tab caption overlaps the tab edge or close control");

    QTest::qWait(30ms);
    const QImage selected = scene.window->grabWindow();
    scene.select(secondId);
    QTest::qWait(30ms);
    const QImage unselected = scene.window->grabWindow();
    require(!selected.isNull() && !unselected.isNull(), "tab strip framebuffer is empty");
    const qreal dpr = selected.devicePixelRatio();
    require(changedPixels(selected, unselected, buttonRect, dpr) > qMax(16, int(dpr * dpr * 16)),
            "selected state does not cover the complete tab body");
    const QRectF closeSurroundingBody(buttonRect.right() - 24, buttonRect.top(), 24,
                                      buttonRect.height());
    require(changedPixels(selected, unselected, closeSurroundingBody, dpr) >
                qMax(4, int(dpr * dpr * 4)),
            "selected state stops before the inset close control");

    const QRect closePixels =
        QRectF(closeRect.topLeft() * dpr, closeRect.size() * dpr).toAlignedRect();
    const QPoint samplePoint{closePixels.left() + qRound(2 * dpr),
                             closePixels.top() + qRound(2 * dpr)};
    require(selected.rect().contains(closePixels) && selected.rect().contains(samplePoint),
            "close control framebuffer bounds are invalid");
    const QRgb closeBackground = selected.pixel(samplePoint);
    int glyphPixels = 0;
    const int inset = qMax(1, qRound(4 * dpr));
    for (int y = closePixels.top() + inset; y < closePixels.bottom() - inset; ++y) {
        for (int x = closePixels.left() + inset; x < closePixels.right() - inset; ++x) {
            const QRgb pixel = selected.pixel(x, y);
            if (qAbs(qRed(pixel) - qRed(closeBackground)) +
                    qAbs(qGreen(pixel) - qGreen(closeBackground)) +
                    qAbs(qBlue(pixel) - qBlue(closeBackground)) >
                24)
                ++glyphPixels;
        }
    }
    require(glyphPixels > qMax(4, qRound(dpr * dpr * 4)),
            "close SVG did not render a visible glyph inside its control");

    const QRgb noteFill = qRgb(192, 98, 94);
    require(colorCount(selected, pagesRect, dpr, noteFill) > 0 &&
                colorCount(selected, stripRect, dpr, noteFill) == 0,
            "tab-hosted grid did not render inside the clipped page stack");
    pass("song-tabs-production-geometry-and-selection");
}

void verifyScrollControls(TabsScene &scene, int targetId)
{
    const QSize oldSize = scene.window->size();
    const int narrowWidth = qMax(320, qRound(scene.window->property("baseFontPx").toDouble() * 24));
    scene.window->resize(narrowWidth, oldSize.height());
    QTest::qWait(50ms);

    int lastId = scene.selectedId();
    while (scene.tabCount() < 9)
        lastId = scene.openFixture();
    QTest::qWait(50ms);

    QQuickItem *strip = scene.rootItem(QStringLiteral("songTabStrip"));
    QQuickItem *scrollLeft = scene.rootItem(QStringLiteral("songTabScrollLeft"));
    QQuickItem *scrollRight = scene.rootItem(QStringLiteral("songTabScrollRight"));
    require(strip && scrollLeft && scrollRight && scrollLeft->isVisible() &&
                scrollRight->isVisible(),
            "narrow tab strip did not expose native scroll controls");

    // Horizontal reveal only: the corrected production geometry pins the tab
    // body at 28px against a shorter strip box (see verifySelectionRendering),
    // so full-rect containment is impossible by design. The strip never
    // clips vertically; "revealed" means inside the strip area left of the
    // scroll controls.
    const auto buttonHorizontallyVisible = [&](int tabId) {
        QQuickItem *button = scene.selectButton(tabId);
        if (!button)
            return false;
        const QRectF stripRect(strip->mapToScene(QPointF{}), strip->size());
        const QRectF leftControlRect(scrollLeft->mapToScene(QPointF{}), scrollLeft->size());
        const QRectF buttonRect(button->mapToScene(QPointF{}), button->size());
        return buttonRect.left() >= stripRect.left() &&
               buttonRect.right() <= leftControlRect.left();
    };
    const auto revealWith = [&](int tabId, QQuickItem *control, const char *failure) {
        for (int clickCount = 0; clickCount < 64 && !buttonHorizontallyVisible(tabId);
             ++clickCount) {
            require(control->isEnabled(), failure);
            click(scene.window, control);
            QTest::qWait(10ms);
        }
        require(buttonHorizontallyVisible(tabId), failure);
    };

    require(!buttonHorizontallyVisible(targetId) && scene.selectedId() != targetId,
            "scroll scenario did not establish a genuinely clipped inactive left tab");
    revealWith(targetId, scrollLeft, "left scroll control did not reveal the clipped tab");
    scene.select(targetId);

    awaitState([&] { return !buttonHorizontallyVisible(lastId); },
               "selecting the left tab did not establish a clipped right tab");
    revealWith(lastId, scrollRight, "right scroll control did not reveal the clipped tab");
    scene.select(lastId);

    editFirstNote(scene, lastId);
    QTest::keyClick(scene.window, Qt::Key_Escape);
    awaitState([&] { return selectedNoteCount(scene.grid(lastId)) == 0; },
               "active scroll-selected grid did not receive keyboard input");
    scene.window->resize(oldSize);
    pass("song-tabs-scroll-controls-and-grid-input");
}

} // namespace

void verifySongTabs(QQuickWindow *window)
{
    require(window, "song tab smoke received no window");
    auto *controller = window->property("songTabs").value<QObject *>();
    require(controller, "main window does not expose songTabs");
    auto *tabs =
        qobject_cast<QAbstractItemModel *>(controller->property("tabs").value<QObject *>());
    require(tabs, "songTabs does not expose its native list model");
    TabsScene scene{window, controller, tabs};
    require(scene.tabCount() == 3 && scene.selectedId() >= 0,
            "tab smoke did not start from the three seeded fixtures");

    const int firstId = scene.selectedId();
    require(scene.idAt(0) == firstId,
            "tab smoke did not start with the first seeded fixture selected");
    const int secondBootstrapId = scene.idAt(1);
    const int thirdBootstrapId = scene.idAt(2);
    scene.close(secondBootstrapId);
    awaitState([&] { return scene.tabCount() == 2 && !scene.page(secondBootstrapId); },
               "clean fixture close did not remove the second seeded page");
    scene.close(thirdBootstrapId);
    awaitState([&] { return scene.tabCount() == 1 && !scene.page(thirdBootstrapId); },
               "clean fixture close did not remove the third seeded page");
    require(scene.selectedId() == firstId,
            "clean fixture isolation changed the selected first page");

    QPointer<QQuickItem> firstPage = scene.page(firstId);
    QPointer<QObject> firstGrid = scene.grid(firstId);
    require(firstPage && firstGrid, "initial tab page is unavailable");
    const int secondId = scene.openFixture();
    QPointer<QQuickItem> secondPage = scene.page(secondId);
    QPointer<QObject> secondGrid = scene.grid(secondId);
    require(secondPage && secondGrid && secondGrid != firstGrid,
            "fixture setup reused the existing tab page or grid");
    const QString secondState = secondGrid->property("noteSummary").toString();
    pass("song-tabs-fixture-open-creates-independent-grid");

    scene.select(firstId);
    auto *firstViewport = scene.pageItem(firstId, QStringLiteral("pianoGridViewport"));
    require(firstViewport, "selected page is missing its scoped grid viewport");
    editFirstNote(scene, firstId);
    const QString editedState = firstGrid->property("noteSummary").toString();
    const double maxX =
        qMax(0.0, firstViewport->property("contentWidth").toDouble() - firstViewport->width());
    require(maxX > 0, "selected page has no horizontal camera range");
    require(firstViewport->setProperty("contentX",
                                       qMin(maxX, firstGrid->property("beatWidth").toDouble() * 2)),
            "cannot stage a retained tab camera offset");
    QTest::qWait(30ms);
    const double cameraX = firstViewport->property("contentX").toDouble();
    const double cameraY = firstViewport->property("contentY").toDouble();
    require(cameraX > 0, "tab camera setup did not produce a nonzero offset");
    scene.select(secondId);
    require(secondGrid->property("noteSummary").toString() == secondState,
            "editing one tab changed its sibling musical state");
    scene.select(firstId);
    require(scene.page(firstId) == firstPage && scene.grid(firstId) == firstGrid &&
                firstGrid->property("noteSummary").toString() == editedState &&
                firstGrid->property("canUndo").toBool() &&
                qFuzzyCompare(firstViewport->property("contentX").toDouble() + 1, cameraX + 1) &&
                qFuzzyCompare(firstViewport->property("contentY").toDouble() + 1, cameraY + 1),
            "tab switching replaced or reset the page, grid, selection/undo, or camera");
    pass("song-tabs-switch-preserves-independent-page-state");

    verifySelectionRendering(scene, firstId, secondId);
    const int selectedBeforeMove = scene.selectedId();
    const int secondRow = scene.rowForId(secondId);
    require(secondRow >= 0, "selected session is missing from the native tab model");
    QPersistentModelIndex persistentSecond(scene.tabs->index(secondRow, 0));
    QSignalSpy rowsMoved(scene.tabs, &QAbstractItemModel::rowsMoved);
    dragTab(scene, firstId, secondId);
    awaitState([&] { return rowsMoved.count() == 1 && scene.rowForId(firstId) == 1; },
               "pointer tab reorder did not emit one real rowsMoved notification");
    require(persistentSecond.isValid() && persistentSecond.row() == 0 &&
                scene.selectedId() == selectedBeforeMove && scene.page(secondId) == secondPage &&
                scene.grid(secondId) == secondGrid,
            "tab reorder invalidated identity, selection, page, model, or persistent index");
    require(qFuzzyCompare(firstViewport->property("contentX").toDouble() + 1, cameraX + 1) &&
                qFuzzyCompare(firstViewport->property("contentY").toDouble() + 1, cameraY + 1),
            "tab reorder reset the retained page camera");
    pass("song-tabs-pointer-reorder-preserves-identities");

    const int backgroundId = scene.openFixture();
    scene.select(secondId);
    scene.close(backgroundId);
    awaitState([&] { return scene.tabCount() == 2 && !scene.page(backgroundId); },
               "background close did not remove the clean tab");
    require(scene.selectedId() == secondId && scene.page(secondId) == secondPage,
            "background close changed the active tab identity");
    pass("song-tabs-background-close-preserves-active-page");

    scene.select(firstId);
    scene.close(firstId);
    awaitState([&] { return scene.pendingCloseId() == firstId; },
               "dirty close did not open the discard prompt");
    click(window, scene.rootItem(QStringLiteral("songTabCancel")));
    awaitState([&] { return scene.pendingCloseId() == -1; },
               "Cancel did not dismiss the dirty-close prompt");
    require(scene.page(firstId) == firstPage && scene.grid(firstId) == firstGrid,
            "Cancel destroyed the dirty tab");
    scene.close(firstId);
    awaitState([&] { return scene.pendingCloseId() == firstId; },
               "second dirty close did not reopen the discard prompt");
    click(window, scene.rootItem(QStringLiteral("songTabDiscard")));
    awaitState([&] { return scene.tabCount() == 1 && !scene.page(firstId); },
               "Discard did not close the dirty tab");
    require(scene.selectedId() == secondId, "discarding the selected tab chose the wrong survivor");
    pass("song-tabs-dirty-cancel-and-discard");

    scene.close(secondId);
    awaitState([&] { return scene.tabCount() == 0 && scene.selectedId() == -1; },
               "closing the final clean tab did not create an empty workspace");
    require(!window->property("gridModel").value<QObject *>(),
            "empty workspace retained a selected grid");
    QQuickItem *emptyPages = scene.rootItem(QStringLiteral("songTabPages"));
    require(emptyPages && emptyPages->isVisible(),
            "empty workspace did not retain its blank page surface");
    QTest::qWait(30ms);
    const QImage empty = window->grabWindow();
    const QRectF emptyPagesRect(emptyPages->mapToScene(QPointF{}), emptyPages->size());
    require(!empty.isNull() &&
                colorCount(empty, emptyPagesRect, empty.devicePixelRatio(), qRgb(192, 98, 94)) == 0,
            "hidden grid note rendering leaked into the empty workspace");
    const int reopenedId = scene.openFixture();
    require(scene.page(reopenedId) && scene.grid(reopenedId),
            "fixture setup from empty did not create a usable grid page");
    pass("song-tabs-final-close-empty-and-reopen");

    verifyScrollControls(scene, reopenedId);
}
