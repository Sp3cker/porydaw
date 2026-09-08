#include "checks/trackheaders/tst_trackheaders.h"

#include "checks/voicepickerdriver.h"

#include <QApplication>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QMetaObject>
#include <QQuickItem>
#include <QScopeGuard>

#include <QtTest>

#include <algorithm>
#include <optional>

#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/trackheadermodel.h"

namespace {

constexpr qreal kGeometryTolerance = 0.01;
constexpr qreal kProbeExtent = 2.0;
constexpr auto kRenamedTitle = "HdrSrc";
constexpr int kAddedVoice = 127;

QVariant rowData(const songview::TrackHeaderModel &model, int row, int role)
{
    return model.data(model.index(row, 0), role);
}

songview::TimelinePointerInput pointerInput(const songview::TimelineInputItem &input,
                                            QPointF position, Qt::MouseButton button,
                                            Qt::MouseButtons buttons)
{
    return {position, input.mapToGlobal(position), button, buttons, Qt::NoModifier};
}

bool near(qreal actual, qreal expected)
{
    return qAbs(actual - expected) <= kGeometryTolerance;
}

std::vector<int> modelTracks(const songview::TrackHeaderModel &model)
{
    std::vector<int> tracks;
    for (int row = 0; row < model.rowCount(); ++row) {
        if (!rowData(model, row, songview::TrackHeaderModel::IsAddTrackRole).toBool())
            tracks.push_back(rowData(model, row, songview::TrackHeaderModel::TrackRole).toInt());
    }
    return tracks;
}

void sendKey(QQuickItem &target, int key, Qt::KeyboardModifiers modifiers = Qt::NoModifier,
             QString text = QString{})
{
    checks::events::sendKey(target, QEvent::KeyPress, key, modifiers, text, false, 1);
    checks::events::sendKey(target, QEvent::KeyRelease, key, modifiers, text, false, 1);
}

void commitRename(TrackHeadersFixture &fixture, int track)
{
    songview::TrackHeaderModel &headers = fixture.headers();
    QVERIFY(fixture.view().focusTimelineBand(songview::TimelineBand::TrackHeaders,
                                             Qt::OtherFocusReason));
    QTRY_VERIFY(fixture.input().hasActiveFocus());
    headers.beginRename(track);
    checks::support::pumpQuick();
    QTRY_VERIFY(fixture.rename().isVisible());
    QTRY_VERIFY(fixture.rename().hasActiveFocus());

    for (const QChar character : QString::fromLatin1(kRenamedTitle))
        sendKey(fixture.rename(), character.toUpper().unicode(), Qt::NoModifier,
                QString{character});
    QCOMPARE(headers.renameDraft(), QString::fromLatin1(kRenamedTitle));

    sendKey(fixture.rename(), Qt::Key_Return);
    QTRY_COMPARE(headers.renamingTrack(), -1);
}

bool ensurePickerSearchFocus(const checks::voicepicker::Picker &picker)
{
    // The prompt publishes search focus from activateInitialFocus() via
    // Qt.callLater, which only owns scope-local focus. Window-level active
    // focus additionally needs the canvas to be the Qt focus window; every
    // header gesture here is synthetic, so the native song tab still owns Qt
    // focus when the picker opens. Requesting our own already-visible canvas
    // is local key-window ordering (the application itself stays as-is), not
    // OS-global activation. Re-request both while waiting, bounded.
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (picker.search && picker.search->hasActiveFocus())
            return true;
        if (picker.window && QGuiApplication::focusWindow() != picker.window)
            picker.window->requestActivate();
        if (picker.root)
            QMetaObject::invokeMethod(picker.root, "activateInitialFocus");
        if (QTest::qWaitFor([&picker] { return picker.search && picker.search->hasActiveFocus(); },
                            50))
            return true;
    }
    return picker.search && picker.search->hasActiveFocus();
}

} // namespace

void TrackHeadersTest::renameCommitsAndRebuildsHeader()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const std::optional<QPointF> sourceTitle = fx.titlePoint(*sourceRow);
    QVERIFY(sourceTitle);
    const QString original = fx.tab().document().trackName(fx.sourceTrack());

    QVERIFY(headers.pointerDoubleClick(
        pointerInput(fx.input(), *sourceTitle, Qt::LeftButton, Qt::LeftButton)));
    QCOMPARE(headers.renamingTrack(), fx.sourceTrack());
    checks::support::pumpQuick();
    QVERIFY(fx.rename().isVisible());
    QQuickItem *const editor = fx.rename().parentItem();
    QVERIFY(editor);
    QVERIFY(near(editor->x(), headers.renameEditorRect().x()));
    QVERIFY(near(editor->y(), *sourceRow * headers.rowHeight() - headers.scrollY() +
                                  headers.renameEditorRect().y()));
    headers.finishRename(false, false);
    checks::support::pumpQuick();
    QCOMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), original);
    QVERIFY(!fx.rename().isVisible());

    headers.beginRename(fx.sourceTrack());
    headers.setRenameDraft(QStringLiteral("Discard direct cancellation"));
    headers.cancelRename();
    QCOMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), original);
    headers.beginRename(fx.sourceTrack());
    headers.setRenameDraft(QStringLiteral("Discard transient cancellation"));
    headers.cancelTransientState();
    checks::support::pumpQuick();
    QCOMPARE(headers.renamingTrack(), -1);
    QCOMPARE(fx.tab().document().trackName(fx.sourceTrack()), original);
    QVERIFY(!fx.rename().isVisible());

    commitRename(fx, fx.sourceTrack());
    QTRY_COMPARE(fx.tab().document().trackName(fx.sourceTrack()),
                 QString::fromLatin1(kRenamedTitle));
    QString error;
    QVERIFY2(fx.rebuild(error), qPrintable(error));
    const std::optional<int> renamedRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(renamedRow);
    QVERIFY(rowData(headers, *renamedRow, songview::TrackHeaderModel::TitleRole)
                .toString()
                .contains(QString::fromLatin1(kRenamedTitle)));
}

void TrackHeadersTest::reorderCommitsAndRebuildsHeader()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    commitRename(fx, fx.sourceTrack());
    QTRY_COMPARE(fx.tab().document().trackName(fx.sourceTrack()),
                 QString::fromLatin1(kRenamedTitle));
    const std::optional<int> sourceRow = fx.rowForTrack(fx.sourceTrack());
    QVERIFY(sourceRow);
    const std::optional<QPointF> start = fx.titlePoint(*sourceRow);
    QVERIFY(start);

    const QPointF noOpDrop{start->x(), 0.0};
    const uint64_t noOpRevision = fx.tab().document().revision();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(headers.pointerMove(pointerInput(fx.input(), noOpDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.reorderIndicatorVisible());
    QVERIFY(near(headers.reorderIndicatorY(), 0.0));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), noOpDrop, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(fx.tab().document().revision(), noOpRevision);

    const int trackRows = int(modelTracks(headers).size());
    const QPointF bottomDrop{start->x(), qreal(trackRows * headers.rowHeight())};
    const uint64_t cancelRevision = fx.tab().document().revision();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), bottomDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.reorderIndicatorVisible());
    QVERIFY(near(headers.reorderIndicatorY(), trackRows * headers.rowHeight()));
    checks::support::pumpQuick();
    QVERIFY(fx.marker().isVisible());
    QVERIFY(fx.marker().y() >= 0.0);
    QVERIFY(fx.marker().y() + fx.marker().height() <= fx.input().height() + kGeometryTolerance);
    headers.inputCancelled(songview::TimelineInputCancelReason::PointerUngrabbed);
    QVERIFY(!headers.reorderIndicatorVisible());
    QVERIFY(!headers.pointerRelease(
        pointerInput(fx.input(), bottomDrop, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(fx.tab().document().revision(), cancelRevision);

    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), bottomDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(headers.pointerRelease(
        pointerInput(fx.input(), bottomDrop, Qt::RightButton, Qt::LeftButton)));
    QVERIFY(!headers.reorderIndicatorVisible());
    QCOMPARE(fx.tab().document().revision(), cancelRevision);

    const uint64_t commitRevision = fx.tab().document().revision();
    QVERIFY(headers.pointerPress(pointerInput(fx.input(), *start, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerMove(pointerInput(fx.input(), bottomDrop, Qt::NoButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), bottomDrop, Qt::LeftButton, Qt::NoButton)));
    QTRY_VERIFY(fx.tab().document().revision() > commitRevision);
    QCOMPARE(fx.tab().document().trackName(fx.reorderTargetTrack()),
             QString::fromLatin1(kRenamedTitle));
    QString error;
    QVERIFY2(fx.rebuild(error), qPrintable(error));
    const std::optional<int> movedRow = fx.rowForTrack(fx.reorderTargetTrack());
    QVERIFY(movedRow);
    QVERIFY(rowData(headers, *movedRow, songview::TrackHeaderModel::TitleRole)
                .toString()
                .contains(QString::fromLatin1(kRenamedTitle)));
}

void TrackHeadersTest::addTrackOpensPickerAndRebuildsHeader()
{
    TrackHeadersFixture &fx = fixture();
    songview::TrackHeaderModel &headers = fx.headers();
    headers.setScrollY(headers.maximumScrollY());
    const std::optional<int> row = fx.addTrackRow();
    QVERIFY(row);
    const qreal halfProbe = kProbeExtent / 2.0;
    const std::optional<QPointF> addPoint = fx.pointForRow(
        *row, QRectF{fx.input().width() / 2.0 - halfProbe, headers.rowHeight() / 2.0 - halfProbe,
                     kProbeExtent, kProbeExtent});
    QVERIFY(addPoint);
    const int undoIndex = fx.tab().document().undoStack()->index();

    const uint64_t revision = fx.tab().document().revision();
    const int rowCount = headers.rowCount();
    const std::vector<int> before = modelTracks(headers);
    const int selected = fx.view().selectionModel().primaryTrack();

    QVERIFY(headers.pointerMove(pointerInput(fx.input(), *addPoint, Qt::NoButton, Qt::NoButton)));
    QVERIFY(rowData(headers, *row, songview::TrackHeaderModel::AddHoveredRole).toBool());
    headers.pointerLeave();
    QVERIFY(!rowData(headers, *row, songview::TrackHeaderModel::AddHoveredRole).toBool());
    QVERIFY(headers.pointerPress(
        pointerInput(fx.input(), *addPoint, Qt::RightButton, Qt::RightButton)));
    QCOMPARE(fx.view().selectionModel().primaryTrack(), selected);
    QCOMPARE(fx.tab().document().revision(), revision);

    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(rowData(headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool());
    headers.inputCancelled(songview::TimelineInputCancelReason::FocusLost);
    QVERIFY(!rowData(headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool());
    QCOMPARE(fx.tab().document().revision(), revision);
    QVERIFY(
        !headers.pointerRelease(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::NoButton)));

    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    const QPointF outsideRow = *addPoint - QPointF{0.0, qreal(headers.rowHeight())};
    QVERIFY(fx.input().bounds().contains(outsideRow));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), outsideRow, Qt::LeftButton, Qt::NoButton)));
    QCOMPARE(fx.tab().document().revision(), revision);
    QVERIFY(!rowData(headers, *row, songview::TrackHeaderModel::AddPressedRole).toBool());
    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::NoButton)));
    QTRY_VERIFY(static_cast<bool>(checks::voicepicker::active(fx.view())));
    const checks::voicepicker::Picker cancelled = checks::voicepicker::active(fx.view());
    QVERIFY2(ensurePickerSearchFocus(cancelled), "voice picker search never took local focus");
    checks::voicepicker::filter(cancelled, QStringLiteral("127"));
    QTRY_VERIFY(checks::voicepicker::row(cancelled, 127) &&
                checks::voicepicker::row(cancelled, 127)->isVisible());
    const QPoint cancelledHeldPoint =
        checks::voicepicker::center(*checks::voicepicker::row(cancelled, 127));
    bool cancelledPressHeld = true;
    const auto releaseCancelledPress =
        qScopeGuard([window = cancelled.window, cancelledHeldPoint, &cancelledPressHeld] {
            if (cancelledPressHeld)
                QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, cancelledHeldPoint);
        });
    QSignalSpy cancelledAudition(&fx.view(), &SongView::auditionVoice);
    checks::voicepicker::hold(cancelled, 127);
    QTRY_COMPARE(cancelledAudition.count(), 1);
    QCOMPARE(cancelledAudition.at(0).at(0).toInt(), 127);
    QCOMPARE(cancelledAudition.at(0).at(1).toInt(), 60);
    QCOMPARE(cancelledAudition.at(0).at(2).toInt(), 112);
    checks::voicepicker::release(cancelled, 127);
    cancelledPressHeld = false;
    QTRY_COMPARE(cancelledAudition.count(), 2);
    QCOMPARE(cancelledAudition.at(1).at(0).toInt(), 127);
    QCOMPARE(cancelledAudition.at(1).at(1).toInt(), 60);
    QCOMPARE(cancelledAudition.at(1).at(2).toInt(), 0);
    QVERIFY(checks::voicepicker::dismissOutside(cancelled));
    QTRY_VERIFY(!quick_popup::popupSession(fx.view())->isOpen());
    QCOMPARE(cancelledAudition.count(), 2);
    QCOMPARE(fx.tab().document().revision(), revision);
    QCOMPARE(fx.tab().document().undoStack()->index(), undoIndex);

    QVERIFY(
        headers.pointerPress(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::LeftButton)));
    QVERIFY(
        headers.pointerRelease(pointerInput(fx.input(), *addPoint, Qt::LeftButton, Qt::NoButton)));
    QTRY_VERIFY(static_cast<bool>(checks::voicepicker::active(fx.view())));
    const checks::voicepicker::Picker picker = checks::voicepicker::active(fx.view());
    QVERIFY2(ensurePickerSearchFocus(picker), "voice picker search never took local focus");

    checks::voicepicker::filter(picker, QStringLiteral("zz-no-such-voice"));
    QTRY_VERIFY(!picker.accept->property("enabled").toBool());
    QTest::keyClick(picker.window, Qt::Key_Return);
    QCoreApplication::processEvents();
    QVERIFY(quick_popup::popupSession(fx.view())->isOpen());
    QCOMPARE(fx.tab().document().revision(), revision);

    checks::voicepicker::filter(picker, QStringLiteral("127"));
    QTRY_VERIFY(checks::voicepicker::row(picker, 127) &&
                checks::voicepicker::row(picker, 127)->isVisible());
    const QPoint pickerHeldPoint =
        checks::voicepicker::center(*checks::voicepicker::row(picker, 127));
    bool pickerPressHeld = true;
    const auto releasePickerPress =
        qScopeGuard([window = picker.window, pickerHeldPoint, &pickerPressHeld] {
            if (pickerPressHeld)
                QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, pickerHeldPoint);
        });
    QSignalSpy audition(&fx.view(), &SongView::auditionVoice);
    checks::voicepicker::hold(picker, 127);
    QTRY_COMPARE(audition.count(), 1);
    QCOMPARE(audition.at(0).at(0).toInt(), 127);
    QCOMPARE(audition.at(0).at(1).toInt(), 60);
    QCOMPARE(audition.at(0).at(2).toInt(), 112);

    QTest::keyClick(picker.window, Qt::Key_Return);
    QTRY_VERIFY(!quick_popup::popupSession(fx.view())->isOpen());
    QTest::mouseRelease(picker.window, Qt::LeftButton, Qt::NoModifier, pickerHeldPoint);
    pickerPressHeld = false;
    QTRY_COMPARE(audition.count(), 2);
    QCOMPARE(audition.at(1).at(0).toInt(), 127);
    QCOMPARE(audition.at(1).at(1).toInt(), 60);
    QCOMPARE(audition.at(1).at(2).toInt(), 0);
    QCOMPARE(fx.tab().document().revision(), revision + 1);
    QCOMPARE(fx.tab().document().undoStack()->index(), undoIndex + 1);
    QTRY_COMPARE(fx.view().currentProgram(fx.view().selectionModel().primaryTrack()), 127);
    QString error;
    QVERIFY2(fx.rebuild(error), qPrintable(error));
    const std::vector<int> after = modelTracks(headers);
    const std::optional<int> afterRow = fx.addTrackRow();
    QCOMPARE(headers.rowCount(), rowCount + 1);
    QCOMPARE(after.size(), before.size() + 1);
    QVERIFY(std::is_sorted(after.cbegin(), after.cend()));
    QVERIFY(std::includes(after.cbegin(), after.cend(), before.cbegin(), before.cend()));
    QVERIFY(std::adjacent_find(after.cbegin(), after.cend()) == after.cend());
    const auto added = std::find_if(after.cbegin(), after.cend(), [&before](int track) {
        return std::find(before.cbegin(), before.cend(), track) == before.cend();
    });
    QVERIFY(added != after.cend());
    QCOMPARE(fx.view().currentProgram(*added), kAddedVoice);
    QVERIFY(afterRow && *afterRow == headers.rowCount() - 1);

    const int remapUndoIndex = fx.tab().document().undoStack()->index();
    const std::optional<int> remapRow = fx.rowForTrack(0);
    QVERIFY(remapRow);
    headers.setScrollY(qreal(*remapRow * fx.rowHeight()));
    const std::optional<QPointF> remapVoice = fx.voicePoint(*remapRow);
    QVERIFY(remapVoice);
    QVERIFY(headers.pointerDoubleClick(
        pointerInput(fx.input(), *remapVoice, Qt::LeftButton, Qt::LeftButton)));
    QTRY_VERIFY(static_cast<bool>(checks::voicepicker::active(fx.view())));
    const checks::voicepicker::Picker remapped = checks::voicepicker::active(fx.view());
    QVERIFY2(ensurePickerSearchFocus(remapped), "voice picker search never took local focus");
    checks::voicepicker::filter(remapped, QStringLiteral("127"));
    QTRY_VERIFY(checks::voicepicker::row(remapped, 127) &&
                checks::voicepicker::row(remapped, 127)->isVisible());
    const QPoint remapHeldPoint =
        checks::voicepicker::center(*checks::voicepicker::row(remapped, 127));
    bool remapPressHeld = true;
    const auto releaseRemapPress =
        qScopeGuard([window = remapped.window, remapHeldPoint, &remapPressHeld] {
            if (remapPressHeld)
                QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, remapHeldPoint);
        });
    QSignalSpy remapAudition(&fx.view(), &SongView::auditionVoice);
    // Qt delivers MouseButtonDblClick instead of Press when this hold
    // re-presses the same row point within the double-click interval of the
    // previous session's release; the row would then accept instead of only
    // auditioning. Suppress pairing for the press itself, then restore.
    const int doubleClickInterval = QApplication::doubleClickInterval();
    QApplication::setDoubleClickInterval(0);
    checks::voicepicker::hold(remapped, 127);
    QApplication::setDoubleClickInterval(doubleClickInterval);
    QTRY_COMPARE(remapAudition.count(), 1);
    QCOMPARE(remapAudition.at(0).at(0).toInt(), 127);
    QCOMPARE(remapAudition.at(0).at(1).toInt(), 60);
    QCOMPARE(remapAudition.at(0).at(2).toInt(), 112);

    fx.tab().document().moveTrack(0, 1);
    const QByteArray afterRemap = fx.tab().document().smf().write();
    QTRY_VERIFY(!quick_popup::popupSession(fx.view())->isOpen());
    QTRY_COMPARE(remapAudition.count(), 2);
    QCOMPARE(remapAudition.at(1).at(0).toInt(), 127);
    QCOMPARE(remapAudition.at(1).at(1).toInt(), 60);
    QCOMPARE(remapAudition.at(1).at(2).toInt(), 0);
    QTest::mouseRelease(remapped.window, Qt::LeftButton, Qt::NoModifier, remapHeldPoint);
    remapPressHeld = false;
    QCOMPARE(fx.tab().document().undoStack()->index(), remapUndoIndex + 1);
    QCoreApplication::processEvents();
    QCOMPARE(fx.tab().document().smf().write(), afterRemap);
}
