#include "checks/drawerpresentation/tst_drawerpresentation.h"

#include <QtTest>

#include "checks/voicepickerdriver.h"

#include <QImage>
#include <QQuickItem>
#include <QScopeGuard>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <initializer_list>

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
    // These are positive, region-specific rendering checks. Compare visible RGB,
    // not alpha rounding at glyph/clip edges (254 versus 255 on the same RGB).
    const QRect bounded = region.intersected(before.rect()).intersected(after.rect());
    int changed = 0;
    for (int y = bounded.top(); y <= bounded.bottom(); ++y)
        for (int x = bounded.left(); x <= bounded.right(); ++x)
            changed += before.pixelColor(x, y).rgb() != after.pixelColor(x, y).rgb();
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

QStringList voiceTexts(const QAbstractItemModel &model, Qt::Alignment alignment = Qt::AlignLeft)
{
    QStringList result;
    for (int row = 0; row < model.rowCount(); ++row) {
        const QModelIndex index = model.index(row, 0);
        if (model.data(index, songview::TimelineQuickTextModel::HorizontalAlignmentRole).toInt() ==
            int(alignment))
            result.push_back(
                model.data(index, songview::TimelineQuickTextModel::TextRole).toString());
    }
    return result;
}

QRectF voiceTextRect(const QAbstractItemModel &model, const QString &text,
                     Qt::Alignment alignment = Qt::AlignLeft)
{
    for (int row = 0; row < model.rowCount(); ++row) {
        const QModelIndex index = model.index(row, 0);
        if (model.data(index, songview::TimelineQuickTextModel::TextRole).toString() == text &&
            model.data(index, songview::TimelineQuickTextModel::HorizontalAlignmentRole).toInt() ==
                int(alignment))
            return model.data(index, songview::TimelineQuickTextModel::RectRole).toRectF();
    }
    return {};
}

bool hasVoiceMarkers(const VoiceFixture &fixture, std::initializer_list<Tick> ticks)
{
    const auto &markers =
        fixture.scene()->layer(songview::TimelineQuickLayer::VoiceChangesMarkers).rects;
    if (markers.size() != ticks.size())
        return false;
    auto marker = markers.begin();
    for (const Tick tick : ticks) {
        if (!marker->rect.contains(
                QPointF(fixture.xForTick(double(tick)), fixture.plotRect().height() / 2.0)))
            return false;
        ++marker;
    }
    return true;
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

    const auto &labels = *scene->voiceChangesTextModel();
    QTRY_COMPARE(voiceTexts(labels).size(), 2);
    const QStringList markers = voiceTexts(labels);
    QVERIFY(markers.at(0).startsWith(QStringLiteral("000 ")));
    QVERIFY(markers.at(1).contains(QStringLiteral("voice-check")));
    QVERIFY(hasVoiceMarkers(fixture, {0, 48}));
    const auto readout = [&] { return voiceTexts(labels, Qt::AlignRight); };
    QTRY_COMPARE(readout(), QStringList{markers.at(0)});
    const Snapshot before = fixture.snapshot();
    fixture.document.addLanePoint(0, DOC_CC_VOICE, 120, 5);
    QTRY_COMPARE(voiceTexts(labels).size(), 3);
    QVERIFY(voiceTexts(labels).last().contains(QStringLiteral("alt-voice")));
    QVERIFY(hasVoiceMarkers(fixture, {0, 48, 120}));
    QCOMPARE(fixture.document.revision(), before.revision + 1);
    QCOMPARE(fixture.document.undoStack()->index(), before.undoIndex + 1);
    fixture.document.undoStack()->undo();
    QTRY_COMPARE(voiceTexts(labels), markers);
    QVERIFY(hasVoiceMarkers(fixture, {0, 48}));
    QVERIFY(fixture.document.smf().write() == before.smf);

    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(16), true);
    pump();
    QTRY_COMPARE(readout(), QStringList{markers.at(0)});
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(32), true);
    pump();
    QTRY_COMPARE(readout(), QStringList{markers.at(0)});
    const QImage sameSpan = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(!sameSpan.isNull());
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(64), true);
    QTRY_COMPARE(readout(), QStringList{markers.at(1)});
    QCOMPARE(voiceTexts(labels), markers);
    const QRectF readoutRect =
        voiceTextRect(labels, markers.at(1), Qt::AlignRight).translated(fixture.fixedSpan(), 0);
    QVERIFY(readoutRect.isValid());
    const QImage nextSpan = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(!nextSpan.isNull());
    QVERIFY(changedPixels(sameSpan, nextSpan,
                          deviceRect(readoutRect, nextSpan.devicePixelRatio(), nextSpan.size())) >
            0);
    view.setPlayheadSample(0, false);
    QTRY_COMPARE(readout(), QStringList{markers.at(0)});
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
    QTRY_COMPARE(voiceTexts(labels), markers);
    QTRY_COMPARE(readout(), QStringList{markers.at(0)});
}

void DrawerPresentationTest::voiceHoverLifecycle()
{
    VoiceFixture fixture;
    createVoiceFixture(fixture);
    SongView &view = fixture.rig->view();
    auto *scene = fixture.scene();
    QVERIFY(scene);
    const auto &labels = *scene->voiceChangesTextModel();
    const auto &hover = *scene->voiceChangesHoverTextModel();
    QTRY_COMPARE(voiceTexts(labels).size(), 2);
    const QStringList markers = voiceTexts(labels);
    const QPointF empty(fixture.xForTick(96), fixture.bandRect().height() / 2.0);
    const QImage idle = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(!idle.isNull());
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(hover.rowCount(), 1);
    const QStringList hoveredText = voiceTexts(hover);
    QCOMPARE(hoveredText.size(), 1);
    QVERIFY(hoveredText.first().contains(QStringLiteral("voice-check")));
    QCOMPARE(voiceTexts(labels), markers);
    const QRectF hoverRect =
        voiceTextRect(hover, hoveredText.first()).translated(fixture.fixedSpan(), 0);
    QVERIFY(hoverRect.isValid());
    const QImage hovered = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(!hovered.isNull());
    QVERIFY(changedPixels(idle, hovered,
                          deviceRect(hoverRect, hovered.devicePixelRatio(), hovered.size())) > 0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    pump();
    QCOMPARE(voiceTexts(hover), hoveredText);

    // Movement within a voice span preserves hover. Crossing a voice change
    // refreshes the displayed context and cancels the old hover.
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(16), true);
    pump();
    QCOMPARE(voiceTexts(hover), hoveredText);
    view.setPlayheadSample(fixture.rig->timeline().sampleForTick(64), true);
    QTRY_COMPARE(hover.rowCount(), 0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(voiceTexts(hover), hoveredText);
    view.setPlayheadSample(0, false);
    QTRY_COMPARE(hover.rowCount(), 0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(voiceTexts(hover), hoveredText);
    sendMouse(fixture.input(), QEvent::MouseMove,
              QPointF(fixture.xForTick(48), fixture.bandRect().height() / 2.0));
    QTRY_COMPARE(hover.rowCount(), 0);
    QCOMPARE(voiceTexts(labels), markers);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(voiceTexts(hover), hoveredText);
    sendMouse(fixture.input(), QEvent::Leave, {});
    QTRY_COMPARE(hover.rowCount(), 0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(voiceTexts(hover), hoveredText);
    sendKey(fixture.input(), Qt::Key_Escape);
    QTRY_COMPARE(hover.rowCount(), 0);
    sendMouse(fixture.input(), QEvent::MouseMove, empty);
    QTRY_COMPARE(voiceTexts(hover), hoveredText);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    pump();
    QVERIFY(!fixture.input().isVisible());
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    QTRY_VERIFY(fixture.input().isVisible());
    QTRY_COMPARE(hover.rowCount(), 0);
    QTRY_COMPARE(voiceTexts(labels), markers);
}

void DrawerPresentationTest::voiceRefreshLifecycle()
{
    VoiceFixture fixture;
    createVoiceFixture(fixture);
    SongView &view = fixture.rig->view();
    const auto &labels = *fixture.scene()->voiceChangesTextModel();
    QTRY_COMPARE(voiceTexts(labels).size(), 2);
    const QStringList track0 = voiceTexts(labels);
    QVERIFY(track0.at(1).contains(QStringLiteral("voice-check")));
    view.selectTrack(1);
    QTRY_COMPARE(voiceTexts(labels).size(), 1);
    QVERIFY(voiceTexts(labels).first().contains(QStringLiteral("alt-voice")));
    QTRY_COMPARE(voiceTexts(labels, Qt::AlignRight), voiceTexts(labels));
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    pump();
    QVERIFY(!fixture.input().isVisible());
    view.selectTrack(0);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    QTRY_VERIFY(fixture.input().isVisible());
    QTRY_COMPARE(voiceTexts(labels), track0);
    QTRY_COMPARE(voiceTexts(labels, Qt::AlignRight), QStringList{track0.at(0)});
    view.setVoicegroup(nullptr);
    QTRY_VERIFY(!voiceTexts(labels).join(' ').contains(QStringLiteral("voice-check")));
    QCOMPARE(voiceTexts(labels).size(), 2);
    QVERIFY(voiceTexts(labels).at(1).startsWith(QStringLiteral("003 ")));
    view.setVoicegroup(&fixture.voicegroup);
    QTRY_COMPARE(voiceTexts(labels), track0);
    const QImage original = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(!original.isNull());
    const QRectF originalRect = voiceTextRect(labels, track0.at(1));
    QVERIFY(originalRect.isValid());
    const QByteArray nameBefore(fixture.voicegroup.voiceNames[3]);
    std::strncpy(fixture.voicegroup.voiceNames[3], "renamed-voice",
                 sizeof(fixture.voicegroup.voiceNames[3]) - 1);
    fixture.voicegroup.voiceNames[3][sizeof(fixture.voicegroup.voiceNames[3]) - 1] = '\0';
    view.setVoicegroup(&fixture.voicegroup);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    QStringList renamedLabels = track0;
    renamedLabels[1].replace(QStringLiteral("voice-check"), QStringLiteral("renamed-voice"));
    QTRY_COMPARE(voiceTexts(labels), renamedLabels);
    const QRectF renamedRect = voiceTextRect(labels, renamedLabels.at(1));
    QVERIFY(renamedRect.isValid());
    const QImage renamed = checks::support::captureQuickBand(view, fixture.bandRect());
    QVERIFY(!renamed.isNull());
    QVERIFY(changedPixels(
                original, renamed,
                deviceRect(originalRect.united(renamedRect).translated(fixture.fixedSpan(), 0),
                           renamed.devicePixelRatio(), renamed.size())) > 0);
    std::strncpy(fixture.voicegroup.voiceNames[3], nameBefore.constData(),
                 sizeof(fixture.voicegroup.voiceNames[3]) - 1);
    fixture.voicegroup.voiceNames[3][sizeof(fixture.voicegroup.voiceNames[3]) - 1] = '\0';
    view.setVoicegroup(&fixture.voicegroup);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    QTRY_COMPARE(voiceTexts(labels), track0);
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
    fixture.view().prepareForSongReplacement();
    QTRY_VERIFY(!checks::voicepicker::active(fixture.view()));
    QVERIFY(fixture.snapshot() == frozen);
    fixture.view().setSong(fixture.view().timeline(), fixture.view().voicegroup());

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
