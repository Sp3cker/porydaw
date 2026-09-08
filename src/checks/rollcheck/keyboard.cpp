#include "checks/rollcheck/tst_pianoroll.h"

#include "checks/quickpopupguard.h"
#include "checks/rollcheck/headerchecksupport.h"
#include "checks/rollcheck/rollcheck.h"
#include "checks/trackheaders/trackheaderoracles.h"

#include <QByteArray>
#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPoint>
#include <QPointer>
#include <QRectF>
#include <QtTest>
#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/trackheadermodel.h"

using namespace checks::rollcheck;

void PianoRollTest::keyboardTranspose()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const SnappedRows rows{view, roll};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const QPoint center(
        qRound(view.camera().displayX(double(d.tick) + 0.5 * double(snapCell), 0.0, rows.dpr())),
        rows.centerY(d.key));
    click(roll, center);
    sendKeyStroke(roll, Qt::Key_Up, Qt::NoModifier, false);
    DocNote note;
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key + 1), &note),
             "Up did not transpose up a semitone");
    sendKeyStroke(roll, Qt::Key_Down, Qt::ShiftModifier, false);
    QVERIFY2(doc.findNote(check.track(), d.tick, uint8_t(d.key - 11), &note),
             "Shift+Down did not transpose down an octave");
    sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(check.track(), d.tick + snapCell, uint8_t(d.key - 11), &note),
             "Right did not nudge one snap cell right");
    doc.moveNotes({note}, int64_t(snapCell / 2), 0);
    view.selectionModel().setNoteSelection({note.noteId});
    sendKeyStroke(roll, Qt::Key_Left, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(check.track(), d.tick + snapCell, uint8_t(d.key - 11), &note),
             "Left did not snap the off-grid note back to the grid");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::keyboardKeepVisible()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const SnappedRows rows{view, roll};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "keyboard keep-visible seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "keyboard keep-visible seed did not reach the expected post-transpose state");
    view.selectionModel().setNoteSelection({transposed.noteId});

    const int keyNow = d.key - 11;
    view.scrollRollBy((129 - keyNow) * view.camera().keyHeight() - view.camera().scrollY());
    QVERIFY2((128 - keyNow) * view.camera().keyHeight() - view.camera().scrollY() <= 1e-9,
             "could not park the note's row above the viewport");
    sendKeyStroke(roll, Qt::Key_Up, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(keyNow + 1), &transposed),
             "Up did not transpose the selected note before the keep-visible check");
    QVERIFY2(rows.top(keyNow + 1) >= 0.0 && rows.bottom(keyNow + 1) <= roll.bounds().height(),
             "Up above the viewport did not keep the transposed row fully visible");
    sendKeyStroke(roll, Qt::Key_Down, Qt::NoModifier, false);

    uint64_t nStart = d.tick + snapCell;
    const qreal dpr = roll.devicePixelRatio();
    const qreal physicalPixel = dpr > 0.0 ? 1.0 / dpr : 1.0;
    view.scrollByPx(view.camera().contentX(double(nStart + snapCell)) + 40);
    QVERIFY2(view.camera().displayX(double(nStart + snapCell), 0.0, dpr) < 0.0,
             "could not park the note past the left edge");
    sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    nStart += snapCell;
    QCOMPARE(view.camera().displayX(double(nStart), 0.0, dpr), 0.0);
    const qreal vw = std::max<qreal>(50, roll.width());
    const qreal cellPx =
        view.camera().contentX(double(nStart + snapCell)) - view.camera().contentX(double(nStart));
    const int rides = (vw - view.camera().contentX(double(nStart + snapCell))) / cellPx + 2;
    for (int i = 0; i < rides; ++i)
        sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    nStart += uint64_t(rides) * snapCell;
    QVERIFY2(doc.findNote(track, nStart, uint8_t(keyNow), &transposed),
             "Right did not nudge the selected note to the expected tick");
    const qreal visibleStart = view.camera().displayX(double(transposed.tick), 0.0, dpr);
    const qreal visibleEnd =
        view.camera().displayX(double(transposed.tick + transposed.duration), 0.0, dpr);
    QVERIFY2(visibleStart >= 0.0 && visibleEnd <= vw - physicalPixel,
             "Right did not keep the nudged note fully visible");
    for (int i = 0; i < rides + 1; ++i)
        sendKeyStroke(roll, Qt::Key_Left, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "the ride right and back did not return the note home");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineRulerScope()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "timeline scope seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "timeline scope seed did not reach the expected post-transpose state");

    auto *quick =
        view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
    auto *rulerInput = quick && quick->rootObject()
                           ? quick->rootObject()->findChild<songview::TimelineInputItem *>(
                                 QStringLiteral("timelineRulerInput"))
                           : nullptr;
    const std::optional<songview::TimelineBandGeometry> rulerBand =
        view.timelineBandLayout().geometry(songview::TimelineBand::Ruler);
    auto *headers = headercheck::model(view);
    QVERIFY2(headers, "could not find the Quick track-header model");
    QVERIFY2(trackheaders_test::recordsMatchTimeline(*headers, check.timeline(), doc.canAddTrack()),
             "Quick header records did not match the current timeline");
    QVERIFY2(rulerInput && rulerBand, "could not find the time ruler");
    const qreal rulerDpr = rulerInput->devicePixelRatio();
    const uint64_t startTick = d.tick + snapCell;
    const uint64_t endTick = d.tick + 2 * snapCell;
    const QPointF start(view.camera().displayX(double(startTick), 0.0, rulerDpr),
                        rulerBand->rect.height() - 2.0);
    const QPointF end(view.camera().displayX(double(endTick), 0.0, rulerDpr),
                      rulerBand->rect.height() - 2.0);

    view.selectionModel().clearTimeSelection();
    view.selectionModel().applyTrackScopeAdjustment(
        track, 0xffffu, songview::EditorSelectionModel::TrackScopeAction::Plain);
    if (doc.engineTrackCount() > 1) {
        const int priorSecondary = track == 0 ? 1 : 0;
        view.selectionModel().applyTrackScopeAdjustment(
            priorSecondary, 0xffffu, songview::EditorSelectionModel::TrackScopeAction::Toggle);
    }
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, start, Qt::LeftButton,
                              Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
                              Qt::ControlModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                              Qt::NoButton, Qt::ControlModifier);
    QVERIFY2(view.selectionModel().timeSelection().active() &&
                 view.selectionModel().timeSelection().startTick == startTick &&
                 view.selectionModel().timeSelection().endTick == endTick &&
                 view.selectionModel().storedTrackScope() == (uint32_t{1} << track),
             "plain ruler drag did not create a primary-only time selection");

    uint32_t expectedScope = uint32_t{1} << track;
    const ViewNote *scopedGhost = nullptr;
    for (const ViewNote &note : view.model().notes) {
        if (note.startTick >= endTick)
            break;
        if (startTick < note.endTick) {
            expectedScope |= uint32_t{1} << note.track;
            if (note.track != track && !scopedGhost)
                scopedGhost = &note;
        }
    }
    const std::optional<int> secondaryRecord =
        scopedGhost ? trackheaders_test::rowForTrack(*headers, scopedGhost->track) : std::nullopt;
    const QColor plainOverlay = secondaryRecord
                                    ? headers
                                          ->data(headers->index(*secondaryRecord, 0),
                                                 songview::TrackHeaderModel::OverlayColorRole)
                                          .value<QColor>()
                                    : QColor{};
    const QImage plainHeaderFrame =
        secondaryRecord ? headercheck::captureBand(check, view) : QImage{};
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, start, Qt::LeftButton,
                              Qt::LeftButton, Qt::ControlModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, end, Qt::NoButton, Qt::LeftButton,
                              Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, end, Qt::LeftButton,
                              Qt::NoButton, Qt::NoModifier);
    QVERIFY2(view.selectionModel().timeSelection().startTick == startTick &&
                 view.selectionModel().timeSelection().endTick == endTick &&
                 view.selectionModel().storedTrackScope() == expectedScope,
             "modified ruler drag did not derive the overlapping note-track scope");
    QVERIFY2(scopedGhost, "modified ruler drag fixture has no overlapping secondary-track note");
    const SongView::ViewState priorViewState = view.viewState();
    SongView::ViewState ghostViewState = priorViewState;
    ghostViewState.scrollY = std::max(
        0.0, (127.5 - double(scopedGhost->key)) * ghostViewState.keyHeight - roll.height() / 2.0);
    view.applyViewState(ghostViewState);
    const SnappedRows ghostRows{view, roll};
    const QRectF ghostPlotBox = ghostRows.noteBox(ghostRows.noteRect(
        view.camera().displayX(double(scopedGhost->startTick), 0.0, ghostRows.dpr()),
        view.camera().displayX(double(scopedGhost->endTick), 0.0, ghostRows.dpr()),
        scopedGhost->key));
    const QRectF ghostBandBox = ghostPlotBox.translated(pianoKeyboardWidth, 0.0);
    const QRectF visibleGhostBox = ghostBandBox.intersected(
        QRectF(pianoKeyboardWidth, 0.0, qreal(roll.width()), qreal(roll.height())));
    const QImage scopedImage = check.captureQuickFramebuffer();
    QVERIFY2(!visibleGhostBox.isEmpty(),
             "time-scoped ghost note is outside the horizontal viewport");
    const qreal scopedDpr = scopedImage.devicePixelRatio();
    const int centerX = qRound(visibleGhostBox.center().x() * scopedDpr);
    const int bottomY = qRound(visibleGhostBox.bottom() * scopedDpr) - 1;
    QVERIFY2(isSelectionRingColor(scopedImage.pixel(centerX, bottomY)),
             "time-scoped ghost note did not render its selection ring");
    view.applyViewState(priorViewState);
    view.selectionModel().setTimeSelection(
        {startTick, endTick, songview::EditorSelectionModel::TimeSelection::Tracks});
    QCoreApplication::processEvents();
    QVERIFY2(secondaryRecord, "time-scoped secondary track has no TrackHeaderModel record");
    const QColor selectedOverlay = headers
                                       ->data(headers->index(*secondaryRecord, 0),
                                              songview::TrackHeaderModel::OverlayColorRole)
                                       .value<QColor>();
    QVERIFY2(plainOverlay != selectedOverlay,
             "time-scoped secondary header did not publish its selection role");
    const QImage selectedHeaderFrame = headercheck::captureBand(check, view);
    QVERIFY2(!plainHeaderFrame.isNull() && !selectedHeaderFrame.isNull(),
             "could not capture the time-scoped secondary header");
    if (plainHeaderFrame == selectedHeaderFrame) {
        QCoreApplication::processEvents();
        const QImage repaintedHeaderFrame = headercheck::captureBand(check, view);
        QVERIFY2(!repaintedHeaderFrame.isNull(),
                 "could not recapture the time-scoped secondary header");
        QVERIFY2(plainHeaderFrame != repaintedHeaderFrame,
                 "time-scoped secondary header did not render its selection indicator");
    }

    const QPointF outsideSelection(
        view.camera().displayX(double(endTick + snapCell), 0.0, rulerDpr),
        rulerBand->rect.height() - 2.0);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, outsideSelection,
                              Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, outsideSelection,
                              Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QVERIFY2(view.selectionModel().timeSelection().active(),
             "left-clicking the timeline ruler outside the time selection cleared it");
    view.selectionModel().clearTimeSelection();
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonPress, start, Qt::RightButton,
                              Qt::RightButton, Qt::NoModifier);
    checks::events::sendMouse(*rulerInput, QEvent::MouseMove, end, Qt::NoButton, Qt::RightButton,
                              Qt::NoModifier);
    QVERIFY2(!view.selectionModel().timeSelection().active(),
             "right-dragging the timeline ruler still created a time selection");
    checks::events::sendMouse(*rulerInput, QEvent::MouseButtonRelease, end, Qt::RightButton,
                              Qt::NoButton, Qt::NoModifier);
    // The release publishes the shared ruler menu instead of a nested native
    // exec, so the test continues linearly; a real Escape key dismisses it.
    const QPointer<songview::QuickPopupSession> live(quick_popup::popupSession(view));
    QVERIFY2(QTest::qWaitFor(
                 [&live] { return live && live->isOpen() && quick_popup::menuPanel(*live); }),
             "releasing the right-drag did not open the shared ruler menu");
    QTest::keyClick(live->window(), Qt::Key_Escape);
    QCoreApplication::processEvents();
    QVERIFY2(live && !live->isOpen(), "Escape did not dismiss the right-drag ruler menu");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineOtherEventsStrip()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    const std::optional<songview::TimelineBandGeometry> otherEvents =
        view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
    QVERIFY2(otherEvents, "could not find the canonical other-events band");
    const StripItem *trackEvent = nullptr;
    for (const StripItem &item : view.model().strip) {
        if (item.track >= 0) {
            trackEvent = &item;
            break;
        }
    }
    QVERIFY2(trackEvent, "timeline fixture has no track-colored other-events marker");
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    QCoreApplication::processEvents();
    const double originalScroll = view.camera().scrollX();
    const qreal visibleContentX = std::max<qreal>(1.0, otherEvents->plotRect.width() / 3.0);
    view.setEditorHorizontalScroll(
        originalScroll + view.camera().contentX(double(trackEvent->tick)) - visibleContentX);
    QCoreApplication::processEvents();
    const QImage beforeStripImage = check.captureQuickBand(otherEvents->rect);
    auto movedSelection = view.selectionModel().timeSelection();
    ++movedSelection.endTick;
    view.selectionModel().setTimeSelection(movedSelection);
    QCoreApplication::processEvents();
    const QImage afterStripImage = check.captureQuickBand(otherEvents->rect);
    QVERIFY2(!beforeStripImage.isNull() && !afterStripImage.isNull() &&
                 beforeStripImage == afterStripImage,
             "moving a time selection changed the other-events strip pixels");
    const qreal stripDpr = afterStripImage.devicePixelRatioF();
    const qreal plotOffset = otherEvents->plotRect.left() - otherEvents->rect.left();
    const int markerX = qRound(
        (plotOffset + view.camera().displayX(double(trackEvent->tick), 0.0, stripDpr)) * stripDpr);
    const int plotLeft = qRound(plotOffset * stripDpr);
    const int markerY = afterStripImage.height() / 2;
    const QRgb expected = SongView::trackColor(trackEvent->track).rgba();
    bool foundMarker = false;
    for (int y = markerY - 2; y <= markerY + 2 && !foundMarker; ++y) {
        for (int x = markerX - 2; x <= markerX + 2; ++x) {
            if (x >= plotLeft && y >= 0 && x < afterStripImage.width() &&
                y < afterStripImage.height() && afterStripImage.pixel(x, y) == expected) {
                foundMarker = true;
                break;
            }
        }
    }
    QVERIFY2(markerX >= plotLeft && markerX < afterStripImage.width(),
             "track-colored other-events marker was not positioned in the plot");
    QVERIFY2(foundMarker, "other-events strip did not render a visible track-colored diamond");
    view.setEditorHorizontalScroll(originalScroll);
    QCoreApplication::processEvents();
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelinePartialSelectionRepaint()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    QCoreApplication::processEvents();
    auto movedSelection = view.selectionModel().timeSelection();
    ++movedSelection.endTick;
    view.selectionModel().setTimeSelection(movedSelection);
    QCoreApplication::processEvents();
    const QImage partialSelectionImage = check.captureQuickFramebuffer();
    check.roll().requestQuickUpdate(songview::PianoRollQuickDirty::All);
    QCoreApplication::processEvents();
    QCOMPARE(partialSelectionImage, check.captureQuickFramebuffer());
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::keyboardTimeSelectionShortcuts()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, roll};
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "time shortcut seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "time shortcut seed did not reach the expected post-transpose state");

    songview::EditorSelectionModel::TimeSelection band;
    band.startTick = d.tick + snapCell;
    band.endTick = d.tick + 2 * snapCell;
    view.selectionModel().setTimeSelection(band);
    const QRectF selectedByTimeBox =
        rows.noteBox(
                rows.noteRect(view.camera().displayX(double(transposed.tick), 0.0, rows.dpr()),
                              view.camera().displayX(double(transposed.tick + transposed.duration),
                                                     0.0, rows.dpr()),
                              transposed.key))
            .translated(pianoKeyboardWidth, 0.0);
    const QImage selectedByTimeImage = check.captureQuickFramebuffer();
    const qreal selectedByTimeDpr = selectedByTimeImage.devicePixelRatio();
    const int centerX = qRound(selectedByTimeBox.center().x() * selectedByTimeDpr);
    const int bottomY = qRound(selectedByTimeBox.bottom() * selectedByTimeDpr) - 1;
    QVERIFY2(isSelectionRingColor(selectedByTimeImage.pixel(centerX, bottomY)),
             "time-selected note did not show the normal selection ring");
    QVERIFY2(view.selectionModel().noteSelection().empty(),
             "time-selected note leaked into the explicit note selection");
    const uint64_t emptyTick = band.startTick + (band.endTick - band.startTick) / 2;
    int emptyKey = -1;
    for (int key = 0; key < 128 && emptyKey < 0; ++key) {
        const int y = rows.centerY(key);
        if (y < 0 || y >= roll.height())
            continue;
        const bool occupied = std::any_of(view.model().notes.cbegin(), view.model().notes.cend(),
                                          [track, key, emptyTick](const ViewNote &note) {
                                              return note.track == track && note.key == key &&
                                                     note.startTick <= emptyTick &&
                                                     emptyTick < note.endTick;
                                          });
        if (!occupied)
            emptyKey = key;
    }
    QVERIFY2(emptyKey >= 0, "could not find empty roll space inside the time selection");
    const QPoint emptyInside(qRound(view.camera().displayX(double(emptyTick), 0.0, rows.dpr())),
                             rows.centerY(emptyKey));
    click(roll, emptyInside);
    QVERIFY2(!view.selectionModel().timeSelection().active(),
             "left-clicking empty space inside the time selection did not clear it");
    view.selectionModel().setTimeSelection(band);
    sendKeyStroke(roll, Qt::Key_Up, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 10), &transposed),
             "time-selection Up did not transpose the covered note");
    sendKeyStroke(roll, Qt::Key_Right, Qt::NoModifier, false);
    QVERIFY2(doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed),
             "time-selection Right did not nudge the covered note");
    QCOMPARE(view.selectionModel().timeSelection().startTick, d.tick + 2 * snapCell);
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineDuplicateTime()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem &roll = check.rollInput();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "duplicate-time seed note was not found");
    doc.moveNotes({transposed}, int64_t(snapCell), -11);
    QVERIFY2(doc.findNote(track, d.tick + snapCell, uint8_t(d.key - 11), &transposed),
             "duplicate-time seed did not reach the expected post-transpose state");
    view.selectionModel().setTimeSelection({d.tick + snapCell, d.tick + 2 * snapCell,
                                            songview::EditorSelectionModel::TimeSelection::Tracks});
    const songview::EditorSelectionModel::TimeSelection duplicateSource =
        view.selectionModel().timeSelection();
    const uint64_t duplicateSpan = duplicateSource.endTick - duplicateSource.startTick;
    const int duplicateUndoIndex = doc.undoStack()->index();
    const uint8_t duplicateKey = transposed.key;
    const auto hasNoteAt = [&](uint64_t tick) {
        DocNote note;
        return doc.findNote(track, tick, duplicateKey, &note);
    };
    sendKeyStroke(roll, Qt::Key_D, Qt::ControlModifier, false);
    const uint64_t firstStart = duplicateSource.endTick;
    const uint64_t firstEnd = firstStart + duplicateSpan;
    const songview::EditorSelectionModel::TimeSelection firstSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == duplicateUndoIndex + 1 && firstSelection.active() &&
                 firstSelection.startTick == firstStart && firstSelection.endTick == firstEnd &&
                 view.editCursorTick() == firstEnd && hasNoteAt(firstStart),
             "Ctrl+D did not duplicate once and advance the time selection");
    const qreal duplicateDpr = roll.devicePixelRatio();
    const qreal duplicateViewport = std::max<qreal>(50, roll.width());
    QVERIFY2(view.camera().displayX(double(firstStart), 0.0, duplicateDpr) >= 0.0 &&
                 view.camera().displayX(double(firstEnd), 0.0, duplicateDpr) <= duplicateViewport,
             "first duplicated range was not made visible");
    sendKeyStroke(roll, Qt::Key_D, Qt::ControlModifier, false);
    const uint64_t secondStart = firstEnd;
    const uint64_t secondEnd = secondStart + duplicateSpan;
    const songview::EditorSelectionModel::TimeSelection secondSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == duplicateUndoIndex + 2 && secondSelection.active() &&
                 secondSelection.startTick == secondStart && secondSelection.endTick == secondEnd &&
                 view.editCursorTick() == secondEnd && hasNoteAt(secondStart),
             "repeating Ctrl+D did not duplicate the newest copy");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineInsertBlankTimeTracks()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "track insertion seed note was not found");
    doc.moveNotes({transposed}, int64_t(2 * snapCell), -10);
    QVERIFY2(doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed),
             "track insertion seed did not reach the expected shortcut state");
    const uint64_t insertStart = d.tick + 2 * snapCell;
    const uint64_t insertEnd = insertStart + snapCell;
    if (doc.engineTrackCount() < 2) {
        while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        QCOMPARE(doc.smf().write(), before);
        return;
    }
    const int otherTrack = track == 0 ? 1 : 0;
    int otherKey = 12;
    while (otherKey < 128) {
        DocNote existing;
        if (!doc.findNote(otherTrack, insertStart, uint8_t(otherKey), &existing))
            break;
        ++otherKey;
    }
    QVERIFY2(otherKey < 128, "could not reserve an unselected-track insert fixture");
    const uint8_t otherPitch = uint8_t(otherKey);
    doc.addNote(otherTrack, insertStart, otherPitch, uint32_t(snapCell), 91);
    DocNote otherBefore;
    QVERIFY2(doc.findNote(otherTrack, insertStart, otherPitch, &otherBefore),
             "could not create the unselected-track insert fixture");
    view.selectTrack(track);
    songview::EditorSelectionModel::TimeSelection trackSelection;
    trackSelection.startTick = insertStart;
    trackSelection.endTick = insertEnd;
    view.selectionModel().setTimeSelectionAndTrackScope(trackSelection, 1u << track);
    const int insertUndoIndex = doc.undoStack()->index();
    view.insertBlankTime();
    DocNote otherAfter;
    DocNote selectedAfter;
    const bool otherStable =
        doc.findNote(otherTrack, insertStart, otherPitch, &otherAfter) &&
        otherAfter.tick == otherBefore.tick && otherAfter.duration == otherBefore.duration &&
        otherAfter.key == otherBefore.key && otherAfter.velocity == otherBefore.velocity;
    const bool selectedShifted = doc.findNote(track, insertEnd, transposed.key, &selectedAfter);
    const songview::EditorSelectionModel::TimeSelection insertedSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == insertUndoIndex + 1 && otherStable && selectedShifted &&
                 insertedSelection.active() && insertedSelection.startTick == insertStart &&
                 insertedSelection.endTick == insertEnd &&
                 insertedSelection.scope == songview::EditorSelectionModel::TimeSelection::Tracks &&
                 view.editCursorTick() == insertStart,
             "Insert Blank Time changed scope, cursor, or an unselected track");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}

void PianoRollTest::timelineInsertBlankTimeLanes()
{
    PianoRollFixture &check = *m_fixture;
    const std::optional<ResizeFixture> seed = makeResizeSeed(check);
    QVERIFY(seed.has_value());
    SongDocument &doc = check.document();
    SongView &view = check.view();
    const int track = check.track();
    const Cell &d = seed->cell;
    const uint64_t snapCell = seed->snapCell;
    const QByteArray before = doc.smf().write();
    const int undo = doc.undoStack()->index();
    DocNote transposed;
    QVERIFY2(doc.findNote(track, d.tick, uint8_t(d.key), &transposed),
             "lane insertion seed note was not found");
    doc.moveNotes({transposed}, int64_t(2 * snapCell), -10);
    QVERIFY2(doc.findNote(track, d.tick + 2 * snapCell, uint8_t(d.key - 10), &transposed),
             "lane insertion seed did not reach the expected shortcut state");
    const uint64_t insertStart = d.tick + 2 * snapCell;
    const uint64_t insertEnd = insertStart + snapCell;
    const uint8_t laneCc = 7;
    const uint64_t lanePointTick = insertStart + snapCell / 2;
    doc.addLanePoint(track, laneCc, lanePointTick, 80);
    DocLanePoint laneBefore;
    DocNote laneNoteBefore;
    QVERIFY2(doc.findLanePoint(track, laneCc, lanePointTick, &laneBefore) &&
                 doc.findNote(track, insertStart, transposed.key, &laneNoteBefore),
             "could not create the lane-scoped insert fixture");
    songview::EditorSelectionModel::TimeSelection laneSelection;
    laneSelection.startTick = insertStart;
    laneSelection.endTick = insertEnd;
    laneSelection.scope = songview::EditorSelectionModel::TimeSelection::Lanes;
    laneSelection.lanes = {{track, laneCc}};
    view.selectionModel().setTimeSelection(laneSelection);
    const int insertUndoIndex = doc.undoStack()->index();
    view.insertBlankTime();
    DocLanePoint shiftedLanePoint;
    DocNote laneNoteAfter;
    const bool laneShifted =
        doc.findLanePoint(track, laneCc, lanePointTick + snapCell, &shiftedLanePoint);
    const bool noteStable = doc.findNote(track, insertStart, transposed.key, &laneNoteAfter) &&
                            laneNoteAfter.tick == laneNoteBefore.tick &&
                            laneNoteAfter.duration == laneNoteBefore.duration &&
                            laneNoteAfter.key == laneNoteBefore.key &&
                            laneNoteAfter.velocity == laneNoteBefore.velocity;
    const songview::EditorSelectionModel::TimeSelection insertedSelection =
        view.selectionModel().timeSelection();
    QVERIFY2(doc.undoStack()->index() == insertUndoIndex + 1 && laneShifted && noteStable &&
                 insertedSelection.active() &&
                 insertedSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
                 insertedSelection.lanes == laneSelection.lanes &&
                 insertedSelection.startTick == insertStart &&
                 insertedSelection.endTick == insertEnd && view.editCursorTick() == insertStart,
             "lane-scoped Insert Blank Time widened its scope or moved the band");
    while (doc.undoStack()->index() > undo && doc.undoStack()->canUndo())
        doc.undoStack()->undo();
    QCOMPARE(doc.smf().write(), before);
}
