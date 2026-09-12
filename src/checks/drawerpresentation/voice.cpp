#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QtTest>

#include "checks/voicepickerdriver.h"

#include <QImage>
#include <QQuickItem>
#include <QScopeGuard>

#include <algorithm>
#include <cmath>
#include <cstring>

#include "checks/drawerpresentation/fixtures.h"
#include "checks/support/editorrig.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickscene.h"

using namespace checks::drawerpresentation;

namespace {

void doubleClick(VoiceTransactionFixture &fixture, Tick tick)
{
    const QPointF point(fixture.xForTick(double(tick)), fixture.bandRect().height() / 2.0);
    sendMouse(fixture.input(), QEvent::MouseButtonDblClick, point, Qt::LeftButton, Qt::LeftButton);
    sendMouse(fixture.input(), QEvent::MouseButtonRelease, point, Qt::LeftButton);
    pump();
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
    const QPointF empty(fixture.xForTick(96), fixture.bandRect().height() / 2.0);
    const QImage idle = checks::support::captureQuickBand(view, fixture.bandRect());
    // Text records publish on the Quick flush, so the baseline follows the
    // first staged frame; hover itself only touches the hover model and layer.
    const int labelsBefore = labels->rowCount();
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
    quick_popup::PromptGuard guard(fixture.view());
    const Snapshot baseline = fixture.snapshot();

    doubleClick(fixture, 48);
    checks::voicepicker::Picker picker;
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    QTRY_VERIFY(picker.search->hasActiveFocus());
    QCOMPARE(picker.list->property("currentIndex").toInt(), 3);
    checks::voicepicker::filter(picker, QStringLiteral("005"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 5));
    checks::voicepicker::accept(picker);
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    DocLanePoint point;
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 48, &point));
    QCOMPARE(point.value, 5);
    QCOMPARE(fixture.document().revision(), baseline.revision + 1);
    QCOMPARE(fixture.document().undoStack()->index(), baseline.undoIndex + 1);

    const Snapshot changed = fixture.snapshot();
    doubleClick(fixture, 48);
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    checks::voicepicker::filter(picker, QStringLiteral("005"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 5));
    checks::voicepicker::accept(picker);
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QVERIFY(fixture.snapshot() == changed);

    doubleClick(fixture, 48);
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    checks::voicepicker::filter(picker, QStringLiteral("not-a-voice"));
    QTRY_VERIFY(!picker.accept->isEnabled());
    checks::voicepicker::filter(picker, QStringLiteral("007"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 7));
    checks::voicepicker::cancel(picker);
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QVERIFY(fixture.snapshot() == changed);

    QSignalSpy audition(&fixture.view(), &SongView::auditionVoice);
    QVERIFY(audition.isValid());
    doubleClick(fixture, 48);
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    checks::voicepicker::filter(picker, QStringLiteral("007"));
    QQuickItem *const escapeHeldRow = checks::voicepicker::row(picker, 7);
    QVERIFY(escapeHeldRow);
    const QPoint escapeHeldPoint = checks::voicepicker::center(*escapeHeldRow);
    bool escapePressHeld = true;
    const auto releaseEscapePress =
        qScopeGuard([window = picker.window, escapeHeldPoint, &escapePressHeld] {
            if (escapePressHeld)
                QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, escapeHeldPoint);
        });
    checks::voicepicker::hold(picker, 7);
    QTRY_COMPARE(audition.count(), 1);
    QTest::keyClick(picker.window, Qt::Key_Escape);
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QTRY_COMPARE(audition.count(), 2);
    QCOMPARE(audition.at(1).at(0).toInt(), 7);
    QCOMPARE(audition.at(1).at(1).toInt(), 60);
    QCOMPARE(audition.at(1).at(2).toInt(), 0);
    // Escape releases the picker audition but does not manufacture the
    // physical release corresponding to the test's held mouse press.
    QTest::mouseRelease(picker.window, Qt::LeftButton, Qt::NoModifier, escapeHeldPoint);
    escapePressHeld = false;
    QCOMPARE(audition.count(), 2);
    QVERIFY(fixture.snapshot() == changed);

    audition.clear();
    doubleClick(fixture, 48);
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    checks::voicepicker::filter(picker, QStringLiteral("007"));
    QQuickItem *const outsideHeldRow = checks::voicepicker::row(picker, 7);
    QVERIFY(outsideHeldRow);
    const QPoint outsideHeldPoint = checks::voicepicker::center(*outsideHeldRow);
    bool outsidePressHeld = true;
    const auto releaseOutsidePress =
        qScopeGuard([window = picker.window, outsideHeldPoint, &outsidePressHeld] {
            if (outsidePressHeld)
                QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, outsideHeldPoint);
        });
    checks::voicepicker::hold(picker, 7);
    QTRY_COMPARE(audition.count(), 1);
    QTest::mouseRelease(picker.window, Qt::LeftButton, Qt::NoModifier, outsideHeldPoint);
    outsidePressHeld = false;
    QTRY_COMPARE(audition.count(), 2);
    QCOMPARE(audition.at(1).at(0).toInt(), 7);
    QCOMPARE(audition.at(1).at(1).toInt(), 60);
    QCOMPARE(audition.at(1).at(2).toInt(), 0);
    QVERIFY(checks::voicepicker::dismissOutside(picker));
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QCOMPARE(audition.count(), 2);
    QVERIFY(fixture.snapshot() == changed);

    doubleClick(fixture, 48);
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    checks::voicepicker::filter(picker, QStringLiteral("007"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 7));
    const Snapshot frozen = fixture.snapshot();
    fixture.view().setDocument(nullptr);
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QVERIFY(fixture.snapshot() == frozen);
    fixture.view().setDocument(&fixture.document());

    doubleClick(fixture, 96);
    QTRY_VERIFY((picker = checks::voicepicker::active(fixture.view())));
    QCOMPARE(picker.list->property("currentIndex").toInt(), 5);
    checks::voicepicker::filter(picker, QStringLiteral("003"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 3));
    checks::voicepicker::accept(picker);
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &point));
    QCOMPARE(point.value, 3);
    fixture.document().undoStack()->undo();
    QVERIFY(!fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &point));
    fixture.document().undoStack()->redo();
    QVERIFY(fixture.document().findLanePoint(0, DOC_CC_VOICE, 96, &point));
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
