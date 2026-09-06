#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QtTest>

#include "checks/drawerpresentation/fixtures.h"
#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"
#include <QApplication>
#include <QDialog>
#include <QImage>
#include <QListWidget>
#include <QMenu>
#include <algorithm>
#include <cmath>
#include <cstring>

using namespace checks::drawerpresentation;

namespace {

void createVoiceFixture(VoiceFixture &fixture)
{
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
}

void createVoiceFixture(VoiceTransactionFixture &fixture)
{
    QString error;
    if (!fixture.create(error))
        qFatal("%s", qPrintable(error));
}

void doubleClick(VoiceTransactionFixture &fixture, uint64_t tick)
{
    const QPointF point(fixture.xForTick(double(tick)), fixture.bandRect().height() / 2.0);
    sendMouse(fixture.input(), QEvent::MouseButtonDblClick, point, Qt::LeftButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, point, Qt::LeftButton);
    pump();
}

struct PickerAttempt {
    bool opened = false;
    bool listResolved = false;
};

struct MenuAttempt {
    bool opened = false;
    int actionCount = 0;
    bool actionFound = false;
    bool actionEnabled = false;
    bool actionResolved = false;
    bool pickerOpened = false;
    bool pickerListResolved = false;
};

void chooseVoice(int row, int &initialRow, bool detach, VoiceTransactionFixture &fixture,
                 PickerAttempt &attempt)
{
    QTimer::singleShot(0, [&fixture, &initialRow, detach, row, &attempt] {
        attempt.opened = QTest::qWaitFor(
            [] { return qobject_cast<QDialog *>(QApplication::activeModalWidget()) != nullptr; });
        if (!attempt.opened)
            return;
        auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
        auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
        attempt.listResolved = list != nullptr;
        if (!list)
            return;
        initialRow = list->currentRow();
        if (detach)
            fixture.view().setDocument(nullptr);
        if (row < 0)
            dialog->reject();
        else {
            list->setCurrentRow(row);
            dialog->accept();
        }
    });
}

QAction *findMenuAction(QMenu &menu, const QString &text)
{
    const auto found =
        std::find_if(menu.actions().cbegin(), menu.actions().cend(),
                     [&text](const QAction *candidate) { return candidate->text() == text; });
    return found == menu.actions().cend() ? nullptr : *found;
}

bool clickMenuAction(QMenu &menu, QAction &action)
{
    const QPoint point = menu.actionGeometry(&action).center();
    QTest::mousePress(&menu, Qt::LeftButton, Qt::NoModifier, point);
    QTest::mouseRelease(&menu, Qt::LeftButton, Qt::NoModifier, point);
    return true;
}

QMenu *openMenu()
{
    if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget()))
        return menu;
    for (QWidget *widget : QApplication::allWidgets()) {
        auto *menu = qobject_cast<QMenu *>(widget);
        if (menu && menu->isVisible())
            return menu;
    }
    return nullptr;
}

void closeBlockingWidgets()
{
    if (QWidget *modal = QApplication::activeModalWidget())
        modal->close();
    if (QWidget *popup = QApplication::activePopupWidget())
        popup->close();
    for (QWidget *widget : QApplication::allWidgets()) {
        auto *menu = qobject_cast<QMenu *>(widget);
        if (menu && menu->isVisible())
            menu->close();
    }
}

void openMenuAndChoose(VoiceTransactionFixture &fixture, uint64_t tick, const QString &action,
                       MenuAttempt &attempt, int pickerRow = -2)
{
    QTimer watchdog;
    watchdog.setSingleShot(true);
    QObject::connect(&watchdog, &QTimer::timeout, &watchdog, [] { closeBlockingWidgets(); });
    watchdog.start(1000);
    QTimer::singleShot(0, [action, pickerRow, &attempt] {
        QMenu *const menu = openMenu();
        attempt.opened = menu != nullptr;
        if (!menu)
            return;
        attempt.actionCount = menu->actions().size();
        QAction *const selected = findMenuAction(*menu, action);
        attempt.actionFound = selected != nullptr;
        attempt.actionEnabled = selected && selected->isEnabled();
        attempt.actionResolved = attempt.actionEnabled && clickMenuAction(*menu, *selected);
        if (!attempt.actionResolved || pickerRow < 0)
            return;
        // The menu's nested exec() cannot unwind into showPicker() until this
        // callback returns. Arm the picker interaction after activating the
        // menu action so it runs in the dialog's nested event loop.
        QTimer::singleShot(0, [pickerRow, &attempt] {
            auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
            attempt.pickerOpened = dialog != nullptr;
            auto *list = dialog ? dialog->findChild<QListWidget *>() : nullptr;
            attempt.pickerListResolved = list != nullptr;
            if (!list)
                return;
            list->setCurrentRow(pickerRow);
            dialog->accept();
        });
    });
    const QPointF point(fixture.xForTick(double(tick)), fixture.bandRect().height() / 2.0);
    sendMouse(fixture.input(), QEvent::MouseButtonPress, point, Qt::RightButton, Qt::RightButton);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, point, Qt::RightButton);
    pump();
    watchdog.stop();
}

int changedPixels(const QImage &before, const QImage &after, const QRect &region)
{
    const QRect bounded = region.intersected(before.rect()).intersected(after.rect());
    int changed = 0;
    for (int y = bounded.top(); y <= bounded.bottom(); ++y)
        for (int x = bounded.left(); x <= bounded.right(); ++x)
            changed += before.pixel(x, y) != after.pixel(x, y);
    return changed;
}

QRect deviceRect(const QRectF &logical, qreal dpr, const QSize &bounds)
{
    const int left = std::clamp(int(std::floor(logical.left() * dpr)), 0, bounds.width());
    const int top = std::clamp(int(std::floor(logical.top() * dpr)), 0, bounds.height());
    const int right = std::clamp(int(std::ceil(logical.right() * dpr)), 0, bounds.width());
    const int bottom = std::clamp(int(std::ceil(logical.bottom() * dpr)), 0, bounds.height());
    return {left, top, std::max(0, right - left), std::max(0, bottom - top)};
}

int changedPixelsOutside(const QImage &before, const QImage &after, const QRectF &logical,
                         qreal dpr)
{
    const QRect excluded = deviceRect(logical, dpr, before.size())
                               .intersected(before.rect())
                               .intersected(after.rect());
    int changed = 0;
    for (int y = 0; y < before.height(); ++y)
        for (int x = 0; x < before.width(); ++x)
            changed += !excluded.contains(x, y) && before.pixel(x, y) != after.pixel(x, y);
    return changed;
}

QImage labelCrop(const QImage &image, double lineX, qreal dpr)
{
    const int line = qRound(lineX * dpr);
    const int gap = std::max(2, qRound(6.0 * dpr));
    const int left = std::clamp(line + gap, 0, image.width());
    const int width = std::clamp(qRound(140.0 * dpr), 0, image.width() - left);
    return image.copy(QRect(left, 0, width, image.height()));
}

} // namespace

void DrawerPresentationTest::voiceSurfaceAndPaintLifecycle()
{
    VoiceFixture fixture;
    createVoiceFixture(fixture);
    SongView &view = fixture.rig->view();
    auto *scene = fixture.scene();
    auto *gutter = fixture.rig->quickRoot()->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineVoiceChangesGutterInput"));
    QVERIFY(scene);
    QVERIFY(gutter);
    QVERIFY(view.drawerSectionVisible(EditorDrawerPage::VoiceChanges));
    QVERIFY(!fixture.plotRect().isEmpty());
    QCOMPARE(fixture.plotRect().x(), view.timelineSplitX());
    QCOMPARE(fixture.input().bounds(), QRectF(QPointF{}, fixture.plotRect().size()));
    QCOMPARE(gutter->bounds(),
             QRectF(QPointF{}, QSizeF(fixture.fixedSpan(), fixture.bandRect().height())));

    const QImage idle = checks::support::captureQuickBand(view, fixture.bandRect());
    const Snapshot before = fixture.snapshot();
    fixture.document.addLanePoint(0, DOC_CC_VOICE, 120, 5);
    pump();
    QCOMPARE(fixture.document.revision(), before.revision + 1);
    QCOMPARE(fixture.document.undoStack()->index(), before.undoIndex + 1);
    const size_t markerCount =
        scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers).rects.size();
    QVERIFY(markerCount > 0);
    fixture.document.undoStack()->undo();
    pump();
    QVERIFY(scene->layer(songview::TimelineQuickLayer::VoiceChangesMarkers).rects.size() <
            markerCount);
    QVERIFY(fixture.document.smf().write() == before.smf);
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(16), true);
    pump();
    const QImage sameSpan = checks::support::captureQuickBand(view, fixture.bandRect());
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(32), true);
    pump();
    QCOMPARE(changedPixels(sameSpan, checks::support::captureQuickBand(view, fixture.bandRect()),
                           sameSpan.rect()),
             0);
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(64), true);
    pump();
    QVERIFY(changedPixels(sameSpan, checks::support::captureQuickBand(view, fixture.bandRect()),
                          sameSpan.rect()) > 0);
    view.setPlayheadSample(0, false);
    pump();
    QCOMPARE(changedPixels(idle, checks::support::captureQuickBand(view, fixture.bandRect()),
                           idle.rect()),
             0);
    const double zoom = view.camera().pxPerBeat();
    const double scroll = view.camera().scrollX();
    view.setSong(&fixture.rig->timeline(), &fixture.voicegroup);
    view.selectTrack(0);
    view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerSectionHeight(EditorDrawerPage::VoiceChanges, 160);
    view.setEditorTimeZoom(zoom);
    view.setEditorHorizontalScroll(scroll);
    view.setEditCursorTick(24);
    pump();
    QCOMPARE(changedPixels(idle, checks::support::captureQuickBand(view, fixture.bandRect()),
                           idle.rect()),
             0);
}

void DrawerPresentationTest::voiceHoverLifecycle()
{
    VoiceFixture fixture;
    createVoiceFixture(fixture);
    SongView &view = fixture.rig->view();
    auto *scene = fixture.scene();
    QVERIFY(scene);
    QAbstractItemModel *const labels = scene->voiceChangesTextModel();
    QAbstractItemModel *const hover = scene->voiceChangesHoverTextModel();
    QVERIFY(labels);
    QVERIFY(hover);
    const int labelsBefore = labels->rowCount();
    const QPointF empty(fixture.xForTick(96), fixture.bandRect().height() / 2.0);
    const QImage idle = checks::support::captureQuickBand(view, fixture.bandRect());
    const qreal dpr = idle.devicePixelRatio();
    const qreal imagePlotOffset = fixture.fixedSpan();
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(hover->rowCount(), 1);
    const QImage hovered = checks::support::captureQuickBand(view, fixture.bandRect());
    QCOMPARE(labels->rowCount(), labelsBefore);
    const QRectF labelRect =
        hover->data(hover->index(0, 0), songview::TimelineQuickTextModel::RectRole).toRectF();
    QVERIFY(labelRect.isValid());
    const QRectF hoverRegion =
        QRectF(imagePlotOffset + empty.x() - 2.0, 0.0, 4.0, fixture.bandRect().height())
            .united(labelRect.translated(imagePlotOffset, 0.0).adjusted(-2.0, -2.0, 2.0, 2.0));
    QVERIFY(changedPixels(idle, hovered,
                          deviceRect(hoverRegion, dpr, idle.size()).intersected(idle.rect())) > 0);
    QCOMPARE(changedPixelsOutside(idle, hovered, hoverRegion, dpr), 0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    pump();
    QCOMPARE(hover->rowCount(), 1);
    QCOMPARE(changedPixels(hovered, checks::support::captureQuickBand(view, fixture.bandRect()),
                           hovered.rect()),
             0);

    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(64), true);
    QTRY_COMPARE(hover->rowCount(), 1);
    view.setPlayheadSample(0, false);
    pump();
    sendMouse(fixture.input(), QEvent::MouseMove,
              QPointF(fixture.xForTick(48), fixture.bandRect().height() / 2.0));
    QTRY_COMPARE(hover->rowCount(), 0);
    const QImage suppressed = checks::support::captureQuickBand(view, fixture.bandRect());
    const double markerX = imagePlotOffset + fixture.xForTick(48);
    QCOMPARE(labelCrop(suppressed, markerX, dpr), labelCrop(idle, markerX, dpr));
    sendMouse(fixture.input(), QEvent::Leave, {});
    QTRY_COMPARE(hover->rowCount(), 0);
    QCOMPARE(changedPixels(suppressed, checks::support::captureQuickBand(view, fixture.bandRect()),
                           suppressed.rect()),
             0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    sendKey(fixture.input(), Qt::Key_Escape);
    QTRY_COMPARE(hover->rowCount(), 0);
    QCOMPARE(changedPixels(idle, checks::support::captureQuickBand(view, fixture.bandRect()),
                           idle.rect()),
             0);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    QTRY_COMPARE(hover->rowCount(), 0);
    QCOMPARE(changedPixels(idle, checks::support::captureQuickBand(view, fixture.bandRect()),
                           idle.rect()),
             0);
}

void DrawerPresentationTest::voiceRefreshLifecycle()
{
    VoiceFixture fixture;
    createVoiceFixture(fixture);
    SongView &view = fixture.rig->view();
    const QImage track0 = checks::support::captureQuickBand(view, fixture.bandRect());
    view.selectTrack(1);
    pump();
    QVERIFY(checks::support::captureQuickBand(view, fixture.bandRect()) != track0);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    pump();
    QVERIFY(!fixture.input().isVisible());
    view.selectTrack(0);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    QVERIFY(checks::support::captureQuickBand(view, fixture.bandRect()) == track0);
    view.setVoicegroup(nullptr);
    pump();
    QVERIFY(checks::support::captureQuickBand(view, fixture.bandRect()) != track0);
    view.setVoicegroup(&fixture.voicegroup);
    pump();
    QVERIFY(checks::support::captureQuickBand(view, fixture.bandRect()) == track0);
    const QByteArray nameBefore(fixture.voicegroup.voiceNames[3]);
    std::strncpy(fixture.voicegroup.voiceNames[3], "renamed-voice",
                 sizeof(fixture.voicegroup.voiceNames[3]) - 1);
    fixture.voicegroup.voiceNames[3][sizeof(fixture.voicegroup.voiceNames[3]) - 1] = '\0';
    view.setVoicegroup(&fixture.voicegroup);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    const QImage renamed = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(renamed != track0);
    std::strncpy(fixture.voicegroup.voiceNames[3], nameBefore.constData(),
                 sizeof(fixture.voicegroup.voiceNames[3]) - 1);
    fixture.voicegroup.voiceNames[3][sizeof(fixture.voicegroup.voiceNames[3]) - 1] = '\0';
    view.setVoicegroup(&fixture.voicegroup);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    pump();
    QVERIFY(checks::support::captureQuickBand(view, fixture.bandRect()) == track0);
}

void DrawerPresentationTest::voicePickerTransactions()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    const Snapshot baseline = fixture.snapshot();
    int initial = -1;
    PickerAttempt change;
    chooseVoice(5, initial, false, fixture, change);
    doubleClick(fixture, 48);
    QVERIFY(change.opened);
    QVERIFY(change.listResolved);
    QCOMPARE(initial, 3);
    DocLanePoint point;
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 48, &point));
    QCOMPARE(point.value, 5);
    QCOMPARE(fixture.document().revision(), baseline.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), baseline.undoIndex + 1);

    const Snapshot changed = fixture.snapshot();
    PickerAttempt same;
    chooseVoice(5, initial, false, fixture, same);
    doubleClick(fixture, 48);
    QVERIFY(same.opened);
    QVERIFY(same.listResolved);
    QVERIFY(fixture.snapshot() == changed);
    PickerAttempt cancelled;
    chooseVoice(-1, initial, false, fixture, cancelled);
    doubleClick(fixture, 48);
    QVERIFY(cancelled.opened);
    QVERIFY(cancelled.listResolved);
    QVERIFY(fixture.snapshot() == changed);

    PickerAttempt detached;
    chooseVoice(7, initial, true, fixture, detached);
    doubleClick(fixture, 48);
    QVERIFY(detached.opened);
    QVERIFY(detached.listResolved);
    QVERIFY(fixture.snapshot() == changed);
    fixture.view().setDocument(&fixture.document());
    PickerAttempt inserted;
    chooseVoice(3, initial, false, fixture, inserted);
    doubleClick(fixture, 96);
    QVERIFY(inserted.opened);
    QVERIFY(inserted.listResolved);
    QCOMPARE(initial, 5);
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &point));
    QCOMPARE(point.value, 3);
    fixture.document().undoStack()->undo();
    QVERIFY(!fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &point));
    fixture.document().undoStack()->redo();
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &point));
}

void DrawerPresentationTest::voiceContextMenuTransactions()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    const Snapshot before = fixture.snapshot();
    MenuAttempt inserted;
    openMenuAndChoose(fixture, 144, QStringLiteral("Insert voice change"), inserted, 7);
    QVERIFY(inserted.opened);
    QVERIFY(inserted.actionResolved);
    QVERIFY(inserted.actionFound);
    QVERIFY(inserted.actionEnabled);
    QVERIFY(inserted.pickerOpened);
    QVERIFY(inserted.pickerListResolved);
    QCOMPARE(inserted.actionCount, 1);
    DocLanePoint point;
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 144, &point));
    QCOMPARE(point.value, 7);
    QCOMPARE(fixture.document().revision(), before.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), before.undoIndex + 1);
    QVERIFY(!QApplication::activePopupWidget());
    QVERIFY(!QApplication::activeModalWidget());

    MenuAttempt deleted;
    openMenuAndChoose(fixture, 144, QStringLiteral("Delete"), deleted);
    QVERIFY(deleted.opened);
    QVERIFY(deleted.actionResolved);
    QVERIFY(deleted.actionFound);
    QVERIFY(deleted.actionEnabled);
    QCOMPARE(deleted.actionCount, 2);
    QVERIFY(!fixture.document().findLanePoint(0, DOC_CC_VOICE, 144, &point));
    QCOMPARE(fixture.document().undoStack()->index(), before.undoIndex + 2);
    QCOMPARE(fixture.document().revision(), before.revision + 2);
    QVERIFY(!QApplication::activePopupWidget());
    QVERIFY(!QApplication::activeModalWidget());
}

void DrawerPresentationTest::voiceMarkerDragTransactions()
{
    VoiceTransactionFixture fixture;
    createVoiceFixture(fixture);
    const Snapshot baseline = fixture.snapshot();
    const QPointF start(fixture.xForTick(48), fixture.bandRect().height() / 2.0);
    const QPointF moved(fixture.xForTick(96), start.y());
    sendMouse(fixture.input(), QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseMove, moved, Qt::NoButton, Qt::LeftButton);
    sendKey(fixture.input(), Qt::Key_Escape);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, moved, Qt::LeftButton);
    QVERIFY(fixture.snapshot() == baseline);

    sendMouse(fixture.input(), QEvent::MouseButtonPress, start, Qt::LeftButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseMove, moved, Qt::NoButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, moved, Qt::LeftButton);
    const Snapshot committed = fixture.snapshot();
    DocLanePoint atOld;
    QVERIFY(!fixture.document().findLanePoint(0, DOC_CC_VOICE, 48, &atOld));
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &atOld));
    QCOMPARE(committed.revision, baseline.revision + 1);
    QCOMPARE(committed.undoIndex, baseline.undoIndex + 1);
    QVERIFY(committed.smf != baseline.smf);
    fixture.document().undoStack()->undo();
    const Snapshot undone = fixture.snapshot();
    QCOMPARE(undone.smf, baseline.smf);
    QCOMPARE(undone.undoIndex, baseline.undoIndex);
    QCOMPARE(undone.revision, committed.revision + 1);
    fixture.document().undoStack()->redo();
    const Snapshot redone = fixture.snapshot();
    QCOMPARE(redone.smf, committed.smf);
    QCOMPARE(redone.undoIndex, committed.undoIndex);
    QCOMPARE(redone.revision, undone.revision + 1);
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &atOld));
}

void DrawerPresentationTest::voiceCameraTransactions()
{
    VoiceFixture fixture;
    createVoiceFixture(fixture);
    SongView &view = fixture.rig->view();
    const double zoom = view.camera().pxPerBeat();
    const double scroll = view.camera().scrollX();
    const QPointF anchor(fixture.input().bounds().center().x(), fixture.bandRect().height() / 2.0);
    const double tick = view.camera().tickAtContentX(anchor.x());
    checks::events::sendWheel(fixture.input(), anchor, {}, QPoint(0, 120), Qt::NoButton,
                              Qt::NoModifier, Qt::NoScrollPhase, false);
    pump();
    QVERIFY(view.camera().pxPerBeat() > zoom);
    QVERIFY(std::abs(view.camera().displayX(tick, 0.0, fixture.input().devicePixelRatio()) -
                     anchor.x()) <= 1.0 / fixture.input().devicePixelRatio());
    view.setEditorHorizontalScroll(-view.camera().leadPadPx());
    const double floor = view.camera().scrollX();
    const QPointF start(40, anchor.y());
    sendMouse(fixture.input(), QEvent::MouseButtonPress, start, Qt::MiddleButton, Qt::MiddleButton);
    sendMouse(fixture.input(), QEvent::MouseMove, start + QPointF(80, 0), Qt::NoButton,
              Qt::MiddleButton);
    QCOMPARE(view.camera().scrollX(), floor);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, start + QPointF(80, 0),
              Qt::MiddleButton);
    view.setEditorTimeZoom(zoom);
    view.setEditorHorizontalScroll(scroll);
}
