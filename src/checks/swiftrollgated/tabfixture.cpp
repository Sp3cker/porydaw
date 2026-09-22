#include "tabfixture.h"

#include "tst_swiftrollgated.h"

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QPoint>
#include <QPointer>
#include <QQuickItem>
#include <QQuickView>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QVariant>
#include <QWheelEvent>
#include <QtTest/QTest>

#include <algorithm>
#include <array>
#include <cmath>

namespace tabcheck {
namespace {

using gridcheck::visualDescendant;

constexpr std::array<TabMetrics, 3> kTabMetrics = {{{14, 22, 28}, {15, 23, 28}, {18, 27, 28}}};

std::optional<QList<TabNote>> tabNotes(QObject *grid)
{
    const QJsonDocument document =
        QJsonDocument::fromJson(grid->property("noteSummary").toString().toUtf8());
    if (!document.isArray())
        return std::nullopt;
    QList<TabNote> result;
    result.reserve(document.array().size());
    for (const QJsonValue value : document.array()) {
        if (!value.isObject())
            return std::nullopt;
        const QJsonObject object = value.toObject();
        result.append({quint64(object.value(QStringLiteral("id")).toDouble()),
                       object.value(QStringLiteral("tick")).toInt(),
                       object.value(QStringLiteral("duration")).toInt(),
                       object.value(QStringLiteral("pitch")).toInt(),
                       object.value(QStringLiteral("track")).toInt(),
                       object.value(QStringLiteral("velocity")).toInt(),
                       object.value(QStringLiteral("selected")).toBool()});
    }
    return result;
}

QRect deviceRegion(const QImage &image, const QRectF &logicalRegion)
{
    const qreal dpr = image.devicePixelRatio();
    return QRectF(logicalRegion.topLeft() * dpr, logicalRegion.size() * dpr)
        .toAlignedRect()
        .intersected(image.rect());
}

} // namespace

const TabMetrics *tabMetricsFor(int labelFontPx)
{
    for (const TabMetrics &metrics : kTabMetrics) {
        if (metrics.labelFontPx == labelFontPx)
            return &metrics;
    }
    return nullptr;
}

QRectF sceneRectOf(QQuickItem *item)
{
    return item ? QRectF(item->mapToScene(QPointF{}), item->size()) : QRectF{};
}

int changedPixels(const QImage &before, const QImage &after, const QRectF &logicalRegion)
{
    const QRect pixels = deviceRegion(before, logicalRegion).intersected(after.rect());
    int changed = 0;
    for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
        for (int x = pixels.left(); x <= pixels.right(); ++x)
            changed += before.pixel(x, y) != after.pixel(x, y) ? 1 : 0;
    }
    return changed;
}

int matchingColorCount(const QImage &image, const QRectF &logicalRegion, const QColor &expected)
{
    const QRect pixels = deviceRegion(image, logicalRegion);
    int count = 0;
    for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
        for (int x = pixels.left(); x <= pixels.right(); ++x)
            count += gridcheck::colorsNear(image.pixelColor(x, y), expected) ? 1 : 0;
    }
    return count;
}

int pixelsDifferingFrom(const QImage &image, const QRectF &logicalRegion, const QColor &expected)
{
    const QRect pixels = deviceRegion(image, logicalRegion);
    int differing = 0;
    for (int y = pixels.top(); y <= pixels.bottom(); ++y) {
        for (int x = pixels.left(); x <= pixels.right(); ++x)
            differing += gridcheck::colorsNear(image.pixelColor(x, y), expected) ? 0 : 1;
    }
    return differing;
}

QQuickItem *captionOf(QQuickItem *button)
{
    if (!button)
        return nullptr;
    const QString text = button->property("text").toString();
    for (QQuickItem *const candidate : button->findChildren<QQuickItem *>()) {
        if (candidate->property("text").toString() == text &&
            candidate->property("contentWidth").isValid())
            return candidate;
    }
    return nullptr;
}

QString songPath(const QString &projectRoot, const QString &label)
{
    return projectRoot + QStringLiteral("/sound/songs/midi/%1.mid").arg(label);
}

QByteArray songBytes(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray{};
}

bool TabScene::open(const QString &projectRoot, const QString &songLabel, QString *error)
{
    if (!m_window.isReady()) {
        *error = QStringLiteral("the window has no session");
        return false;
    }
    m_window.show();
    m_window.openStartup(projectRoot, songLabel);
    m_session = m_window.sessionObject();
    if (!QTest::qWaitFor(
            [this] {
                return m_session->property("projectOpen").toBool() &&
                       m_session->property("songOpen").toBool();
            },
            kOpenTimeoutMs)) {
        *error = QStringLiteral("the window did not open the staged project and song");
        return false;
    }
    if (!QTest::qWaitFor(
            [this] {
                return m_window.gridView() && m_window.gridView()->isExposed() &&
                       m_window.gridView()->rootObject() && m_window.gridView()->width() > 0 &&
                       m_window.gridView()->height() > 0;
            },
            kSettleTimeoutMs)) {
        *error = QStringLiteral("the production QQuickView did not expose its root");
        return false;
    }
    m_view = m_window.gridView();
    m_content = m_view->contentItem();
    m_root = qobject_cast<QQuickItem *>(m_view->rootObject());
    m_controller = m_session->property("songTabs").value<QObject *>();
    m_tabs =
        m_controller
            ? qobject_cast<QAbstractItemModel *>(m_controller->property("tabs").value<QObject *>())
            : nullptr;
    if (!m_root || !m_controller || !m_tabs) {
        *error = QStringLiteral("the mounted surface does not expose the song tab strip");
        return false;
    }
    const int firstId = selectedId();
    if (!QTest::qWaitFor([this, firstId] { return pageReady(firstId); }, kOpenTimeoutMs)) {
        *error = QStringLiteral("the first song tab did not publish its rendered grid");
        return false;
    }
    return true;
}

QQuickItem *TabScene::item(const QString &name) const
{
    return visualDescendant(m_content, name);
}

QQuickItem *TabScene::strip() const
{
    return item(QStringLiteral("songTabStrip"));
}

QQuickItem *TabScene::pages() const
{
    return item(QStringLiteral("songTabPages"));
}

QQuickItem *TabScene::page(int tabId) const
{
    return item(QStringLiteral("songTab_%1").arg(tabId));
}

QQuickItem *TabScene::pageItem(int tabId, const QString &name) const
{
    return visualDescendant(page(tabId), name);
}

QQuickItem *TabScene::selectButton(int tabId) const
{
    return item(QStringLiteral("songTabSelect_%1").arg(tabId));
}

QQuickItem *TabScene::closeButton(int tabId) const
{
    return item(QStringLiteral("songTabClose_%1").arg(tabId));
}

QQuickItem *TabScene::scrollLeft() const
{
    return item(QStringLiteral("songTabScrollLeft"));
}

QQuickItem *TabScene::scrollRight() const
{
    return item(QStringLiteral("songTabScrollRight"));
}

QQuickItem *TabScene::pageSurface(int tabId) const
{
    return pageItem(tabId, QStringLiteral("swiftRollOverlay"));
}

QQuickItem *TabScene::noteItem(int tabId, quint64 noteId) const
{
    return visualDescendant(pageItem(tabId, QStringLiteral("timelineQuickPianoNoteFills")),
                            QStringLiteral("gridNote_%1").arg(noteId));
}

int TabScene::tabCount() const
{
    return m_controller->property("tabCount").toInt();
}

int TabScene::selectedId() const
{
    return m_controller->property("selectedId").toInt();
}

int TabScene::selectedIndex() const
{
    return m_controller->property("selectedIndex").toInt();
}

int TabScene::pendingCloseId() const
{
    return m_controller->property("pendingCloseId").toInt();
}

QObject *TabScene::sessionAt(int row) const
{
    if (row < 0 || row >= m_tabs->rowCount())
        return nullptr;
    return m_tabs->data(m_tabs->index(row, 0), Qt::DisplayRole).value<QObject *>();
}

int TabScene::idAt(int row) const
{
    QObject *const tab = sessionAt(row);
    return tab ? tab->property("tabId").toInt() : -1;
}

int TabScene::rowForId(int tabId) const
{
    for (int row = 0; row < m_tabs->rowCount(); ++row) {
        if (idAt(row) == tabId)
            return row;
    }
    return -1;
}

QObject *TabScene::pageSession(int tabId) const
{
    QQuickItem *const tabPage = page(tabId);
    return tabPage ? tabPage->property("session").value<QObject *>() : nullptr;
}

QObject *TabScene::grid(int tabId) const
{
    QObject *const tab = pageSession(tabId);
    return tab ? tab->property("grid").value<QObject *>() : nullptr;
}

QObject *TabScene::gridAt(int row) const
{
    QObject *const tab = sessionAt(row);
    return tab ? tab->property("grid").value<QObject *>() : nullptr;
}

bool TabScene::pageReady(int tabId) const
{
    QObject *const tabGrid = grid(tabId);
    return page(tabId) && tabGrid && tabGrid->property("renderedNoteCount").toInt() > 0;
}

bool TabScene::openSong(const QString &label, int *tabId, QString *error)
{
    const int before = tabCount();
    if (!QMetaObject::invokeMethod(m_session, "openSong", Q_ARG(QString, label))) {
        *error = QStringLiteral("the session does not accept openSong(%1)").arg(label);
        return false;
    }
    if (!QTest::qWaitFor([this, before] { return tabCount() == before + 1; }, kOpenTimeoutMs)) {
        *error =
            QStringLiteral("opening %1 did not append a tab (%2 rows)").arg(label).arg(tabCount());
        return false;
    }
    if (tabId)
        *tabId = selectedId();
    if (!QTest::qWaitFor([this] { return pageReady(selectedId()); }, kOpenTimeoutMs)) {
        *error =
            QStringLiteral("the tab opened for %1 did not publish its rendered grid").arg(label);
        return false;
    }
    return true;
}

bool TabScene::narrowUntilStripOverflows(QString *error)
{
    QQuickItem *const left = scrollLeft();
    if (!left) {
        *error = QStringLiteral("the mounted strip has no scroll controls");
        return false;
    }
    const int height = m_window.height();
    for (int width = m_window.width(); width > kMinWindowWidth; width -= 40) {
        m_window.resize(width, height);
        if (QTest::qWaitFor([left] { return left->isVisible(); }, 500))
            return true;
    }
    *error = QStringLiteral("the song tabs do not overflow the strip at any window width");
    return false;
}

bool TabScene::clickItem(QQuickItem *target, QString *error)
{
    if (!m_view || !target || !target->isVisible() || !target->isEnabled()) {
        *error = QStringLiteral("the requested tab control is unavailable for pointer input");
        return false;
    }
    const QPoint point = target->mapToScene(target->boundingRect().center()).toPoint();
    QTest::mouseMove(m_view, point);
    QTest::mouseClick(m_view, Qt::LeftButton, Qt::NoModifier, point);
    QTest::qWait(kInputSettleMs);
    return true;
}

bool TabScene::tabButtonVisible(int tabId) const
{
    QQuickItem *const button = selectButton(tabId);
    QQuickItem *const stripItem = strip();
    if (!button || !stripItem || !button->isVisible())
        return false;
    QRectF visible = sceneRectOf(stripItem);
    if (QQuickItem *const left = scrollLeft(); left && left->isVisible())
        visible.setRight(sceneRectOf(left).left());
    const QRectF rect = sceneRectOf(button);
    return rect.left() >= visible.left() - 0.5 && rect.right() <= visible.right() + 0.5;
}

bool TabScene::revealTab(int tabId, QString *error)
{
    QQuickItem *const button = selectButton(tabId);
    if (!button) {
        *error = QStringLiteral("tab %1 has no strip button").arg(tabId);
        return false;
    }
    const double stripCenter = sceneRectOf(strip()).center().x();
    for (int attempt = 0; attempt < 64 && !tabButtonVisible(tabId); ++attempt) {
        const bool pointsLeft = sceneRectOf(button).center().x() < stripCenter;
        QQuickItem *const control = pointsLeft ? scrollLeft() : scrollRight();
        const QString side = pointsLeft ? QStringLiteral("left") : QStringLiteral("right");
        if (!control || !control->isVisible()) {
            *error = QStringLiteral("the strip exposes no %1 scroll control").arg(side);
            return false;
        }
        if (!control->isEnabled()) {
            *error = QStringLiteral("the strip's %1 scroll control is disabled at the bound "
                                    "before tab %2 is revealed")
                         .arg(side)
                         .arg(tabId);
            return false;
        }
        if (!clickItem(control, error))
            return false;
    }
    if (!tabButtonVisible(tabId)) {
        *error = QStringLiteral("the strip's scroll controls did not reveal tab %1").arg(tabId);
        return false;
    }
    return true;
}

bool TabScene::select(int tabId, QString *error)
{
    if (!revealTab(tabId, error))
        return false;
    if (!clickItem(selectButton(tabId), error))
        return false;
    if (!QTest::qWaitFor(
            [this, tabId] {
                QQuickItem *const tabPage = page(tabId);
                return selectedId() == tabId && tabPage && tabPage->isVisible();
            },
            kSettleTimeoutMs)) {
        *error = QStringLiteral("clicking tab %1 did not select its page (selected %2)")
                     .arg(tabId)
                     .arg(selectedId());
        return false;
    }
    return true;
}

bool TabScene::clickClose(int tabId, QString *error)
{
    if (!revealTab(tabId, error))
        return false;
    return clickItem(closeButton(tabId), error);
}

bool TabScene::clickDialogButton(const QString &name, QString *error)
{
    QQuickItem *button = nullptr;
    if (!QTest::qWaitFor(
            [this, &name, &button] {
                button = item(name);
                return button && button->isVisible();
            },
            kSettleTimeoutMs)) {
        *error = QStringLiteral("the close gate's %1 control is not presented").arg(name);
        return false;
    }
    return clickItem(button, error);
}

bool TabScene::awaitFrame(QString *error)
{
    QSignalSpy frameSwapped(m_view, &QQuickWindow::frameSwapped);
    if (!frameSwapped.isValid()) {
        *error = QStringLiteral("the QQuickView does not report swapped frames");
        return false;
    }
    m_view->update();
    if (!QTest::qWaitFor([&frameSwapped] { return frameSwapped.count() > 0; }, kSettleTimeoutMs)) {
        *error = QStringLiteral("the QQuickView did not render a frame");
        return false;
    }
    return true;
}

QList<TabNote> TabScene::notes(int tabId) const
{
    QObject *const tabGrid = grid(tabId);
    return tabGrid ? tabNotes(tabGrid).value_or(QList<TabNote>{}) : QList<TabNote>{};
}

int TabScene::selectedNoteCount(int tabId) const
{
    int count = 0;
    for (const TabNote &note : notes(tabId))
        count += note.selected ? 1 : 0;
    return count;
}

QPoint TabScene::noteCenter(int tabId, quint64 noteId) const
{
    QQuickItem *const note = noteItem(tabId, noteId);
    return note ? note->mapToScene(note->boundingRect().center()).toPoint() : QPoint{};
}

std::optional<TabNote> TabScene::firstVisibleNote(int tabId) const
{
    QQuickItem *const input = pageItem(tabId, QStringLiteral("swiftRollInput"));
    if (!input)
        return std::nullopt;
    const QRectF inputRect = sceneRectOf(input).adjusted(1.0, 1.0, -1.0, -1.0);
    for (const TabNote &note : notes(tabId)) {
        QQuickItem *const item = noteItem(tabId, note.id);
        if (!item || !item->isVisible())
            continue;
        if (inputRect.contains(sceneRectOf(item).adjusted(-3.0, -3.0, 3.0, 3.0)))
            return note;
    }
    return std::nullopt;
}

std::optional<TabNote> TabScene::firstClickableNote(int tabId) const
{
    QQuickItem *const input = pageItem(tabId, QStringLiteral("swiftRollInput"));
    if (!input)
        return std::nullopt;
    const QRectF inputRect = sceneRectOf(input).adjusted(1.0, 1.0, -1.0, -1.0);
    for (const TabNote &note : notes(tabId)) {
        QQuickItem *const item = noteItem(tabId, note.id);
        if (!item || !item->isVisible())
            continue;
        if (inputRect.contains(sceneRectOf(item).center()))
            return note;
    }
    return std::nullopt;
}

QPoint TabScene::pointFor(int tabId, int tick, int pitch) const
{
    QObject *const tabGrid = grid(tabId);
    QQuickItem *const surface = pageSurface(tabId);
    if (!tabGrid || !surface)
        return QPoint{};
    const double pixelsPerTick =
        tabGrid->property("beatWidth").toDouble() / tabGrid->property("ticksPerBeat").toInt();
    const double x = tick * pixelsPerTick - tabGrid->property("cameraScrollX").toDouble();
    const double y = (127.0 - pitch + 0.5) * tabGrid->property("rowHeight").toDouble() -
                     tabGrid->property("cameraScrollY").toDouble();
    return surface->mapToScene(QPointF(x, y)).toPoint();
}

bool TabScene::drawNote(int tabId, TabNote *drawn, QString *error)
{
    QObject *const tabGrid = grid(tabId);
    QQuickItem *const plot = pageItem(tabId, QStringLiteral("timelineQuickRollPlot"));
    if (!tabGrid || !plot) {
        *error = QStringLiteral("tab %1 has no mounted roll to edit").arg(tabId);
        return false;
    }
    const QList<TabNote> before = notes(tabId);
    const int snap = tabGrid->property("snapTicks").toInt();
    if (snap <= 0) {
        *error = QStringLiteral("tab %1 published no snap resolution").arg(tabId);
        return false;
    }
    const double pixelsPerTick =
        tabGrid->property("beatWidth").toDouble() / tabGrid->property("ticksPerBeat").toInt();
    const double rowHeight = tabGrid->property("rowHeight").toDouble();
    const double scrollX = tabGrid->property("cameraScrollX").toDouble();
    const double scrollY = tabGrid->property("cameraScrollY").toDouble();
    const int firstTick = int(std::ceil(((scrollX + 24.0) / pixelsPerTick) / snap)) * snap;
    const int lastTick =
        int(std::floor(((scrollX + plot->width() - 24.0) / pixelsPerTick) / snap)) * snap;
    const int firstRow = std::clamp(int(std::ceil(scrollY / rowHeight)) + 2, 0, 127);
    const int lastRow =
        std::clamp(int(std::floor((scrollY + plot->height()) / rowHeight)) - 2, 0, 127);
    int tick = -1;
    int pitch = -1;
    for (int row = firstRow; row <= lastRow && tick < 0; ++row) {
        const int candidatePitch = 127 - row;
        for (int candidate = (std::max)(0, firstTick); candidate + 2 * snap <= lastTick;
             candidate += snap) {
            const int end = candidate + 2 * snap;
            const bool occupied =
                std::any_of(before.cbegin(), before.cend(), [&](const TabNote &note) {
                    return note.pitch == candidatePitch && note.tick < end &&
                           note.tick + note.duration > candidate;
                });
            if (!occupied) {
                tick = candidate;
                pitch = candidatePitch;
                break;
            }
        }
    }
    if (tick < 0) {
        *error = QStringLiteral("tab %1 has no visible empty lane to draw in").arg(tabId);
        return false;
    }

    const int inset = (std::max)(1, snap / 4);
    const QPoint start = pointFor(tabId, tick + inset, pitch);
    const QPoint finish = pointFor(tabId, tick + 2 * snap - inset, pitch);
    QTest::mouseMove(m_view, start);
    QTest::mousePress(m_view, Qt::LeftButton, Qt::NoModifier, start);
    QTest::mouseMove(m_view, finish, 20);
    QTest::mouseRelease(m_view, Qt::LeftButton, Qt::NoModifier, finish);

    if (!QTest::qWaitFor(
            [&] {
                return tabGrid->property("canUndo").toBool() &&
                       notes(tabId).size() == before.size() + 1;
            },
            kSettleTimeoutMs)) {
        *error = QStringLiteral("a real pointer drag did not add one note to tab %1").arg(tabId);
        return false;
    }
    for (const TabNote &candidate : notes(tabId)) {
        const bool existed = std::any_of(before.cbegin(), before.cend(), [&](const TabNote &note) {
            return note.id == candidate.id;
        });
        if (!existed) {
            if (drawn)
                *drawn = candidate;
            return true;
        }
    }
    *error = QStringLiteral("the drawn note has no new document identity");
    return false;
}

void TabScene::wheelVertical(QQuickItem &target, int angle)
{
    const QPointF scenePoint = target.mapToScene(target.boundingRect().center());
    QWheelEvent event(scenePoint, m_view->mapToGlobal(scenePoint.toPoint()), QPoint(),
                      QPoint(0, angle), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(m_view, &event);
}

} // namespace tabcheck
