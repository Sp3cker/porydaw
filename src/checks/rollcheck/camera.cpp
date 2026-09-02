#include "checks/rollcheck/rollcheck.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPoint>
#include <algorithm>
#include <cmath>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/songview.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"

namespace checks::rollcheck {

ScenarioContinuation runCameraScenarios(Harness &check)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const int plotOrigin = check.plotOrigin();
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // The Y camera is continuous: partial wheel deltas are immediately
    // multiplicative, preserve the cursor's content row, and remain precise
    // through the integer-native scrollbar projection.
    {
        const SongView::ViewState original = view.viewState();
        SongView::ViewState zoom = original;
        zoom.keyHeight = 8.0;
        zoom.scrollY = 300.0;
        view.applyViewState(zoom);
        zoom = view.viewState();
        const QPointF anchor(pianoKeyboardWidth + 40.0, 200.0);

        for (int i = 0; i < 4; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 30), Qt::NoButton,
                                      Qt::ControlModifier, Qt::NoScrollPhase, false);
        const double partialHeight = view.camera().keyHeight();
        const double partialScroll = view.camera().scrollY();

        view.applyViewState(zoom);
        checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 120), Qt::NoButton,
                                  Qt::ControlModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().keyHeight() - partialHeight) > 1e-12 ||
            std::abs(view.camera().scrollY() - partialScroll) > 1e-10)
            fail("four partial Ctrl-wheel deltas differ from one full notch");

        const double settledHeight = view.camera().keyHeight();
        const double settledScroll = view.camera().scrollY();
        checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 120), Qt::NoButton,
                                  Qt::ControlModifier, Qt::ScrollMomentum, false);
        if (std::abs(view.camera().keyHeight() - settledHeight) > 1e-12 ||
            std::abs(view.camera().scrollY() - settledScroll) > 1e-10)
            fail("Ctrl-wheel momentum changed the settled key-height camera");

        view.applyViewState(zoom);
        const double anchoredRow =
            (anchor.y() + view.camera().scrollY()) / view.camera().keyHeight();
        checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 30), Qt::NoButton,
                                  Qt::ControlModifier, Qt::NoScrollPhase, false);
        if (std::abs((anchor.y() + view.camera().scrollY()) / view.camera().keyHeight() -
                     anchoredRow) > 1e-12)
            fail("Ctrl-wheel zoom moved the cursor's content row");

        view.applyViewState(zoom);
        for (int i = 0; i < 10; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 120), Qt::NoButton,
                                      Qt::ControlModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().keyHeight() - 16.0) > 1e-12)
            fail("ten Ctrl-wheel notches did not double key height");

        view.applyViewState(zoom);
        checks::events::sendWheel(*roll, anchor, QPoint(0, 240), QPoint(0, 0), Qt::NoButton,
                                  Qt::ControlModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().keyHeight() - 16.0) > 1e-12)
            fail("240-pixel Ctrl-wheel zoom did not double key height");

        view.applyViewState(zoom);
        const double keyboardScroll = view.camera().scrollY();
        checks::events::sendWheel(*roll, QPointF(pianoKeyboardWidth - 1.0, anchor.y()),
                                  QPoint(0, 1), QPoint(0, 0), Qt::NoButton, Qt::NoModifier,
                                  Qt::NoScrollPhase, false);
        if (std::abs(view.camera().scrollY() - (keyboardScroll - 0.5)) > 1e-12)
            fail("pixel-only wheel over keyboard did not scroll note range");
        view.applyViewState(zoom);
        for (int i = 0; i < 4; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 30), Qt::NoButton,
                                      Qt::ControlModifier, Qt::NoScrollPhase, false);
        for (int i = 0; i < 4; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, -30), Qt::NoButton,
                                      Qt::ControlModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().keyHeight() - zoom.keyHeight) > 1e-12 ||
            std::abs(view.camera().scrollY() - zoom.scrollY) > 1e-10)
            fail("equal Ctrl-wheel zoom in/out did not restore the camera");

        zoom.keyHeight = 9.375;
        zoom.scrollY = 257.625;
        view.applyViewState(zoom);
        const SongView::ViewState fractional = view.viewState();
        if (std::abs(fractional.keyHeight - zoom.keyHeight) > 1e-12 ||
            std::abs(fractional.scrollY - zoom.scrollY) > 1e-12)
            fail("fractional vertical view state did not round-trip");

        const int boundaryRow = 40;
        const qreal dpr = roll->devicePixelRatio();
        const qreal boundary =
            std::round((boundaryRow * view.camera().keyHeight() - view.camera().scrollY()) * dpr) /
            dpr;
        checks::events::sendMouse(*roll, QEvent::MouseMove,
                                  QPointF(pianoKeyboardWidth + 40.0, boundary - 0.25), Qt::NoButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (check.roll().property("hoverKey").toInt() != 128 - boundaryRow)
            fail("hovering above a snapped pitch boundary chose the wrong key");
        checks::events::sendMouse(*roll, QEvent::MouseMove,
                                  QPointF(pianoKeyboardWidth + 40.0, boundary + 0.25), Qt::NoButton,
                                  Qt::NoButton, Qt::NoModifier);
        if (check.roll().property("hoverKey").toInt() != 127 - boundaryRow)
            fail("hovering below a snapped pitch boundary chose the wrong key");

        // Integer-valued legacy vertical state still applies unchanged after the
        // type migration.
        zoom.keyHeight = 11;
        zoom.scrollY = 217;
        view.applyViewState(zoom);
        const SongView::ViewState legacy = view.viewState();
        if (legacy.keyHeight != 11.0 || legacy.scrollY != 217.0)
            fail("legacy integer vertical view state no longer applies");
        view.applyViewState(original);
        (void)view.grab(); // consume the restoration repaint before later probes
        QCoreApplication::processEvents();
    }

    // The X camera follows the same continuous contract as the Y camera:
    // wheel deltas compose, the exact qreal cursor anchor stays pinned, and
    // the integer scrollbar is only a projection of the fractional camera.
    {
        const SongView::ViewState original = view.viewState();
        SongView::ViewState zoom = original;
        zoom.pxPerBeat = 500.125;
        zoom.scrollPx = 23.625;
        const QPointF anchor(pianoKeyboardWidth + 73.375, 200.0);
        const qreal anchorContentX = anchor.x() - pianoKeyboardWidth;

        view.applyViewState(zoom);
        for (int i = 0; i < 4; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 30), Qt::NoButton,
                                      Qt::NoModifier, Qt::NoScrollPhase, false);
        const double partialScale = view.camera().pxPerBeat();
        const double partialScroll = view.camera().scrollX();

        view.applyViewState(zoom);
        checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 120), Qt::NoButton,
                                  Qt::NoModifier, Qt::NoScrollPhase, false);
        const double fullScale = view.camera().pxPerBeat();
        const double fullScroll = view.camera().scrollX();
        const double expectedFullScale = zoom.pxPerBeat * std::pow(1.0015, 120.0);
        if (std::abs(fullScale - expectedFullScale) > 1e-10)
            fail("timeline-wheel notch changed horizontal zoom sensitivity");
        if (std::abs(fullScale - partialScale) > 1e-12 ||
            std::abs(fullScroll - partialScroll) > 1e-9)
            fail("four partial timeline-wheel deltas differ from one full notch");

        view.applyViewState(zoom);
        checks::events::sendWheel(*roll, anchor, QPoint(0, 24), QPoint(0, 0), Qt::NoButton,
                                  Qt::NoModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().pxPerBeat() - fullScale) > 1e-12 ||
            std::abs(view.camera().scrollX() - fullScroll) > 1e-9)
            fail("timeline pixel-wheel delta was not consumed continuously");

        view.applyViewState(zoom);
        const double horizontalScroll = view.camera().scrollX();
        const double horizontalScale = view.camera().pxPerBeat();
        checks::events::sendWheel(*roll, anchor, QPoint(8, 0), QPoint(0, 0), Qt::NoButton,
                                  Qt::NoModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().scrollX() - (horizontalScroll - 8.0)) > 1e-12 ||
            std::abs(view.camera().pxPerBeat() - horizontalScale) > 1e-12)
            fail("pixel-only horizontal wheel did not scroll timeline");
        view.applyViewState(zoom);
        const double anchoredTick = view.camera().tickAtContentX(anchorContentX);
        checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 30), Qt::NoButton,
                                  Qt::NoModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().tickAtContentX(anchorContentX) - anchoredTick) > 1e-9)
            fail("timeline-wheel zoom moved the cursor's fractional anchor tick");

        view.applyViewState(zoom);
        for (int i = 0; i < 4; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, 30), Qt::NoButton,
                                      Qt::NoModifier, Qt::NoScrollPhase, false);
        for (int i = 0; i < 4; ++i)
            checks::events::sendWheel(*roll, anchor, QPoint(0, 0), QPoint(0, -30), Qt::NoButton,
                                      Qt::NoModifier, Qt::NoScrollPhase, false);
        if (std::abs(view.camera().pxPerBeat() - zoom.pxPerBeat) > 1e-10 ||
            std::abs(view.camera().scrollX() - zoom.scrollPx) > 1e-9)
            fail("equal timeline-wheel zoom in/out did not restore the camera");

        zoom.pxPerBeat = 311.375;
        zoom.scrollPx = 47.625;
        view.applyViewState(zoom);
        const SongView::ViewState fractional = view.viewState();
        if (std::abs(fractional.pxPerBeat - zoom.pxPerBeat) > 1e-12 ||
            std::abs(fractional.scrollPx - zoom.scrollPx) > 1e-12)
            fail("fractional horizontal view state did not round-trip");

        // Integer-valued legacy horizontal state remains a valid sidecar value
        // after scrollPx becomes fractional.
        zoom.pxPerBeat = 320.0;
        zoom.scrollPx = 17.0;
        view.applyViewState(zoom);
        const SongView::ViewState legacy = view.viewState();
        if (legacy.pxPerBeat != 320.0 || legacy.scrollPx != 17.0)
            fail("legacy integer horizontal view state no longer applies");

        view.applyViewState(original);
        (void)view.grab();
        QCoreApplication::processEvents();
    }

    // Exact tick geometry rounds once, after adding the destination widget's
    // origin. Its affine inverse must still snap every visible snap-grid tick
    // back to itself at both one- and two-device-pixel scaling.
    {
        const SongView::ViewState original = view.viewState();
        const QSize originalSize = view.size();
        view.resize(180, originalSize.height());
        (void)view.grab();
        QCoreApplication::processEvents();

        struct CameraProbe {
            double pxPerBeat;
            double scrollPx;
        };
        const CameraProbe probes[] = {
            {37.125, 0.375},
            {37.375, 13.625},
            {512.5, 71.3125},
        };
        const qreal origins[] = {
            qreal(pianoKeyboardWidth),
            qreal(plotOrigin) + 0.25,
        };
        const qreal dprs[] = {1.0, 2.0};

        for (const CameraProbe &probe : probes) {
            SongView::ViewState state = original;
            state.pxPerBeat = probe.pxPerBeat;
            state.scrollPx = probe.scrollPx;
            state.gridMinDenom = 0;
            view.applyViewState(state);
            const SongView::ViewState applied = view.viewState();
            if (std::abs(applied.pxPerBeat - probe.pxPerBeat) > 1e-12 ||
                std::abs(applied.scrollPx - probe.scrollPx) > 1e-12)
                fail("fractional projection camera did not apply exactly");

            const qreal visibleWidth = roll->bounds().width() - pianoKeyboardWidth;
            uint64_t tick = view.snapTickUp(std::max(0.0, view.camera().tickAtContentX(0.0)));
            int visibleTicks = 0;
            bool mappingFailed = false;
            const double affineTick = view.camera().tickAtContentX(visibleWidth * 0.371) + 0.375;
            if (std::abs(view.camera().tickAtContentX(view.camera().contentX(affineTick)) -
                         affineTick) > 1e-9)
                fail("raw horizontal projection lost fractional tick precision");
            for (int guard = 0; guard < 10000; ++guard) {
                const qreal rawX = view.camera().contentX(double(tick));
                if (rawX > visibleWidth)
                    break;
                if (rawX >= 0.0) {
                    visibleTicks++;
                    for (qreal origin : origins) {
                        for (qreal dpr : dprs) {
                            const qreal displayed =
                                view.camera().displayX(double(tick), origin, dpr);
                            const qreal expected = std::round((origin + rawX) * dpr) / dpr;
                            if (std::abs(displayed - expected) > 1e-12)
                                mappingFailed = true;
                            const uint64_t roundTrip =
                                view.snapTick(view.camera().tickAtContentX(displayed - origin));
                            if (roundTrip != tick)
                                mappingFailed = true;
                        }
                    }
                }
                const uint64_t next = view.snapTickUp(double(tick) + 1.0);
                if (next <= tick) {
                    mappingFailed = true;
                    break;
                }
                tick = next;
            }
            if (visibleTicks < 2)
                fail("fractional projection camera exposed too few snap ticks");
            if (mappingFailed)
                fail("display/inverse projection changed a visible snap-grid tick");
        }

        view.resize(originalSize);
        (void)view.grab();
        view.applyViewState(original);
        QCoreApplication::processEvents();
    }
    const SnappedRows rows{view, *roll};

    // The horizontal camera range: a lead pad of dead space before tick 0
    // (the scroll floor, where zooming near the song start comes to rest
    // with tick 0 still on screen) and a full viewport of scratch space
    // past the song's end (the ceiling rests the end at the content area's
    // left edge). The pad region paints as a flat shade distinct from the
    // roll background, and a negative camera round-trips through the
    // sidecar view state.
    {
        const SongView::ViewState original = view.viewState();
        const double pad = view.camera().leadPadPx();
        if (pad <= 0.0)
            fail("lead pad is not positive");

        SongView::ViewState state = original;
        state.scrollPx = -1.0e9;
        view.applyViewState(state);
        if (std::abs(view.camera().scrollX() + pad) > 1e-9)
            fail("horizontal scroll floor is not the lead pad");

        // Zooming in anchored inside the pad clamps at the floor instead of
        // pushing tick 0 off the left edge.
        checks::events::sendWheel(*roll, QPointF(pianoKeyboardWidth + 2.0, 200.0), QPoint(0, 0),
                                  QPoint(0, 120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase,
                                  false);
        if (std::abs(view.camera().scrollX() + pad) > 1e-9)
            fail("zoom near the song start left the lead-pad floor");
        view.applyViewState(state);

        state.scrollPx = 1.0e9;
        view.applyViewState(state);
        const double ceiling = double(check.timeline().lengthTicks) * view.camera().pxPerTick();
        if (std::abs(view.camera().scrollX() - ceiling) > 1e-9)
            fail("scroll ceiling is not a full viewport past the song end");

        view.goToStart();
        if (std::abs(view.camera().scrollX() + pad) > 1e-9 || view.editCursorTick() != 0)
            fail("go-to-start did not home the camera to the lead pad");

        // A pixel wheel pans left into the pad from the classic origin.
        state.scrollPx = 0.0;
        view.applyViewState(state);
        checks::events::sendWheel(*roll, QPointF(pianoKeyboardWidth + 40.0, 200.0), QPoint(8, 0),
                                  QPoint(0, 0), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase,
                                  false);
        if (std::abs(view.camera().scrollX() + 8.0) > 1e-12)
            fail("wheel pan could not enter the lead pad");

        state.scrollPx = -pad / 2.0;
        view.applyViewState(state);
        if (std::abs(view.viewState().scrollPx + pad / 2.0) > 1e-12)
            fail("negative scroll did not round-trip through view state");

        // The pre-roll shade: flat (same color on natural and accidental
        // rows, hiding the row stripes) and distinct from the plain roll
        // background right of tick 0.
        state.scrollPx = -pad;
        view.applyViewState(state);
        const auto isBlackKey = [](int key) {
            switch (key % 12) {
            case 1:
            case 3:
            case 6:
            case 8:
            case 10:
                return true;
            default:
                return false;
            }
        };
        int naturalKey = -1, accidentalKey = -1;
        const int midKey = rows.keyAt(roll->height() / 2.0);
        for (int key = midKey - 4; key <= midKey + 4; ++key) {
            if (key < 0 || key > 127 || rows.top(key) < 0 || rows.bottom(key) > roll->height())
                continue;
            (isBlackKey(key) ? accidentalKey : naturalKey) = key;
        }
        if (naturalKey < 0 || accidentalKey < 0) {
            fail("no visible natural/accidental row pair for the pre-roll probe");
        } else {
            const QImage padImage = check.captureQuickFramebuffer();
            const qreal padDpr = padImage.devicePixelRatio();
            const auto raster = [padDpr](qreal position) { return qRound(position * padDpr); };
            const qreal inPadX = pianoKeyboardWidth + pad / 2.0;
            // Mid snap-cell right of tick 0, clear of the 2px grid lines.
            const qreal outPadX = pianoKeyboardWidth + pad + 20.0;
            const QRgb padNatural =
                padImage.pixel(raster(inPadX), raster(rows.centerY(naturalKey)));
            const QRgb padAccidental =
                padImage.pixel(raster(inPadX), raster(rows.centerY(accidentalKey)));
            const QRgb plainNatural =
                padImage.pixel(raster(outPadX), raster(rows.centerY(naturalKey)));
            if (padNatural != padAccidental)
                fail("pre-roll shade is not flat across row stripes");
            if (padNatural == plainNatural)
                fail("pre-roll shade does not differ from the roll background");
        }

        view.applyViewState(original);
        (void)view.grab();
        QCoreApplication::processEvents();
    }

    // The scratch space past the song's end is editable: from the ceiling
    // camera a pencil draw lands beyond the pre-edit song length, and the
    // rebuilt timeline grows to include it (renewing the overshoot range).
    {
        const SongView::ViewState original = view.viewState();
        const uint64_t lengthBefore = check.timeline().lengthTicks;
        const QByteArray beforeProbe = doc.smf().write();
        const int undoIndex = doc.undoStack()->index();

        SongView::ViewState state = original;
        state.scrollPx = 1.0e9;
        view.applyViewState(state);

        // Mid-viewport at the ceiling is all past the song end.
        const double probeX = pianoKeyboardWidth + (roll->width() - pianoKeyboardWidth) / 2.0;
        const uint64_t tick =
            view.snapTickDown(view.camera().tickAtContentX(probeX - pianoKeyboardWidth));
        const int key = rows.keyAt(roll->height() / 2.0);
        const qreal x0 = pianoKeyboardWidth + view.camera().contentX(double(tick));
        const qreal xs =
            pianoKeyboardWidth + view.camera().contentX(double(tick + view.snapTicksAt(tick)));
        drawNote(*roll, QPoint(int((x0 + xs) / 2.0), int(rows.centerY(key))));

        DocNote scratch;
        if (tick < lengthBefore)
            fail("ceiling-camera probe cell is not past the song end");
        else if (!doc.findNote(track, tick, uint8_t(key), &scratch))
            fail("pencil draw in the scratch space produced no note");
        else if (check.timeline().lengthTicks <= lengthBefore)
            fail("scratch-space note did not grow the rebuilt timeline");

        while (doc.undoStack()->index() > undoIndex && doc.undoStack()->canUndo())
            doc.undoStack()->undo();
        if (doc.smf().write() != beforeProbe)
            fail("undo did not restore the document after the scratch-space draw");

        view.applyViewState(original);
        (void)view.grab();
        QCoreApplication::processEvents();
    }

    // Hover readout: the cursor anywhere over the roll marks its key row
    // on the keyboard column (mirrored in the hoverKey property); leaving
    // the widget clears the mark.
    {
        const int y = int(roll->height()) / 2;
        const int expected = rows.keyAt(y);
        checks::events::sendMouse(*roll, QEvent::MouseMove, QPoint(pianoKeyboardWidth + 40, y),
                                  Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        if (check.roll().property("hoverKey").toInt() != expected)
            fail("hovering the notes area did not mark its key row");
        checks::events::sendMouse(*roll, QEvent::MouseMove, QPoint(4, rows.centerY(expected - 1)),
                                  Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        if (check.roll().property("hoverKey").toInt() != expected - 1)
            fail("hovering the keyboard column did not follow the key row");
        events::sendMouse(*roll, QEvent::Leave, QPointF(pianoKeyboardWidth + 40, y), Qt::NoButton,
                          Qt::NoButton, Qt::NoModifier);
        if (check.roll().property("hoverKey").toInt() != -1)
            fail("leaving the roll did not clear the hover mark");
    }

    if (doc.undoStack()->index() != undoBaseline)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
