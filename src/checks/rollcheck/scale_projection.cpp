#include "checks/rollcheck/rollcheck.h"

#include <QCoreApplication>
#include <QEvent>
#include <QImage>
#include <QPoint>
#include <algorithm>
#include <cmath>
#include <vector>

#include "core/songdocument.h"
#include "porydaw_scale.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"

namespace checks::rollcheck {

ScenarioContinuation runScaleProjectionScenarios(Harness &check)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const int pianoRollDefaultKeyHeight = check.pianoRollDefaultKeyHeight();
    const SnappedRows rows{view, *roll};
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    // Scale highlighting and folding scenarios. Every block drives the SongView's
    // independent scale-feature APIs and asserts against its PitchProjection, then undoes every doc
    // edit it pushed so the trailing (fully-undone) stack stays clean for
    // the blocks that follow. All queries are model-level (no gestures
    // except the ones that genuinely need the widget event system), which
    // keeps the checks deterministic across the loader's song set.
    const auto scaleMajor = porydaw_scale::ScaleId::major;
    const auto projHidden = songview::PitchProjection::cHiddenRow;
    // Fold occupancy and editing key off m_selectedTrack, and the earlier
    // revealNote scenario may have switched it; re-bind to the live scaleTrack.
    const int scaleTrack = view.selectionModel().primaryTrack();
    if (scaleTrack < 0 || doc.engineTrackCount() <= scaleTrack)
        fail("scale scenario bound an invalid selected track");
    // Fold-aware row center: SnappedRows mirrors the CHROMATIC layout, but
    // Fold collapses rows, so gesture Ys must come from the projection.
    const auto foldCenterY = [&](int pitch) -> int {
        const int r = view.pitchProjection().rowForPitch(pitch);
        if (r == songview::PitchProjection::cHiddenRow)
            return -1;
        const qreal dpr = roll->devicePixelRatio();
        const qreal top =
            std::round((double(r) * view.camera().keyHeight() - view.camera().scrollY()) * dpr) /
            dpr;
        const qreal bot =
            std::round((double(r + 1) * view.camera().keyHeight() - view.camera().scrollY()) *
                       dpr) /
            dpr;
        return int(std::floor((top + bot) / 2.0));
    };

    // Block A — Projection invariants (Wave 3): pure queries, no gestures.
    {
        const auto &proj = view.pitchProjection();
        view.setScaleHighlight(false);
        view.setScaleFold(false);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);

        // A1. Off is full chromatic whatever the root/scale.
        if (proj.visibleRowCount() != 128)
            fail("Off projection does not expose 128 rows");
        bool anyHidden = false;
        for (int p = 0; p < 128; p++)
            if (proj.rowForPitch(p) == projHidden)
                anyHidden = true;
        if (anyHidden)
            fail("Off projection hides a pitch");
        // A2. Drift the root/scale; Off must stay chromatic.
        view.setScaleRoot(2);
        view.setScaleId(porydaw_scale::ScaleId::dorian);
        if (proj.visibleRowCount() != 128)
            fail("Off mode root/scale change altered the row count");
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);

        // A3. Fold geometry is the selected track's exact occupied-pitch
        // set, strictly descending and unique.
        bool initialOccupancy[128] = {};
        int occupiedPitchCount = 0;
        for (const DocNote &n : doc.notesForTrack(scaleTrack)) {
            if (!initialOccupancy[n.key]) {
                initialOccupancy[n.key] = true;
                occupiedPitchCount++;
            }
        }
        view.setScaleHighlight(false);
        view.setScaleFold(true);
        if (proj.visibleRowCount() != occupiedPitchCount)
            fail("Fold row count does not match selected-track occupancy");
        int prevPitch = 128; // above the highest MIDI pitch; rows descend
        for (int r = 0; r < proj.visibleRowCount(); r++) {
            const int p = proj.visiblePitchAt(r);
            if (p >= prevPitch) { // row 0 is the HIGHEST pitch: descending
                fail("Fold visible pitches are not strictly descending");
                break;
            }
            prevPitch = p;
        }
        for (int p = 0; p < 128; p++) {
            if ((proj.rowForPitch(p) != projHidden) != initialOccupancy[p]) {
                fail("Fold visible pitches do not exactly match selected-track occupancy");
                break;
            }
        }

        // A4. Inverses: the row<->pitch maps round-trip.
        for (int r = 0; r < proj.visibleRowCount(); r++) {
            if (proj.rowForPitch(proj.visiblePitchAt(r)) != r) {
                fail("Fold visible row does not map back to itself");
                break;
            }
        }
        for (int p = 0; p < 128; p++) {
            const int r = proj.rowForPitch(p);
            if (r != projHidden && proj.visiblePitchAt(r) != p) {
                fail("Fold visible pitch does not map back to itself");
                break;
            }
        }

        // A5-A7. Occupancy is exact per MIDI pitch; adding a note exposes
        // only that pitch, while every unused pitch stays hidden.
        bool noteOnSelected[128] = {};
        for (const DocNote &n : doc.notesForTrack(scaleTrack))
            noteOnSelected[n.key] = true;
        const uint64_t aTick =
            uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
        int exceptBase = -1;
        for (int k = 1; k + 12 < 128; k += 12) { // C#/Db classes
            if (!noteOnSelected[k] && !noteOnSelected[k + 12]) {
                exceptBase = k;
                break;
            }
        }
        if (exceptBase < 0) {
            fail("no free C#-class octave pair for the Fold occupancy exception");
        } else {
            const int cmd0 = doc.undoStack()->index();
            doc.addNote(scaleTrack, aTick, uint8_t(exceptBase), doc.ticksPerClock(), 100);
            if (proj.rowForPitch(exceptBase) == projHidden)
                fail("Fold did not expose an occupied off-scale pitch");
            if (proj.rowForPitch(exceptBase + 12) != projHidden)
                fail("Fold exposed an unoccupied off-scale octave");
            int freePitch = -1;
            for (int p = 1; p < 128; p += 12) {
                if (porydaw_scale::isScalePitch(scaleMajor, 0, p))
                    continue;
                if (!noteOnSelected[p] && proj.rowForPitch(p) == projHidden) {
                    freePitch = p;
                    break;
                }
            }
            if (freePitch >= 0 && proj.rowForPitch(freePitch) != projHidden)
                fail("Fold revealed an off-scale unused pitch");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }

        // A8. nearestVisiblePitch uses the lower pitch on an equal-distance
        // tie, independent of the current track's occupied set.
        {
            songview::PitchProjection tieProjection;
            const uint8_t tiePitches[] = {60, 62};
            tieProjection.buildFromPitches(tiePitches);
            if (tieProjection.nearestVisiblePitch(61) != 60)
                fail("nearestVisiblePitch tie did not pick the lower pitch");
        }

        // A9. Fold vertical scroll is bounded by the folded content height.
        {
            SongView::ViewState big = view.viewState();
            big.valid = true;
            big.scrollY = 1.0e9;
            view.applyViewState(big);
            double maxScroll = proj.totalHeight(view.camera().keyHeight()) - double(roll->height());
            if (maxScroll < 0.0)
                maxScroll = 0.0;
            if (view.camera().scrollY() < -1e-9 || view.camera().scrollY() > maxScroll + 1e-9)
                fail("Fold scroll Y is not bounded by the folded content height");
        }

        view.setScaleHighlight(false);
        view.setScaleFold(false);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);
    }

    // Block B — Highlight pixel checks (Wave 5): the tint lands on scale
    // rows only, and never on the keyboard or a painted note face.
    {
        const auto pixelAt = [](const QImage &image, int x, int y) -> QRgb {
            const qreal dpr = image.devicePixelRatio();
            return image.pixel(qRound(x * dpr), qRound(y * dpr));
        };
        const int laneX =
            pianoKeyboardWidth + qRound(view.camera().leadPadPx()) + 20; // off the gridlines
        const int kbdX = pianoKeyboardWidth - 10;

        view.setScaleHighlight(false);
        view.setScaleFold(false);
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);

        bool noteOnSelected[128] = {};
        for (const DocNote &n : doc.notesForTrack(scaleTrack))
            noteOnSelected[n.key] = true;

        // Pick an octave whose C, C# and D are all empty on the selected
        // scaleTrack, then center its rows in the viewport.
        int rootKey = -1, scaleKey = -1, nonScaleKey = -1;
        for (int base = 0; base + 2 <= 127 && rootKey < 0; base += 12) {
            if (!noteOnSelected[base] && !noteOnSelected[base + 1] && !noteOnSelected[base + 2]) {
                rootKey = base;
                scaleKey = base + 2;
                nonScaleKey = base + 1;
            }
        }
        if (rootKey < 0) {
            fail("no empty octave for the Highlight pixel probe");
        } else {
            const double kh = pianoRollDefaultKeyHeight;
            const double scrollY =
                (127 - nonScaleKey) * kh + kh / 2.0 - double(roll->height()) / 2.0;
            SongView::ViewState st = view.viewState();
            st.valid = true;
            st.keyHeight = kh;
            st.scrollY = scrollY;
            view.applyViewState(st);
            (void)view.grab();
            QCoreApplication::processEvents();

            const QImage offPm = check.captureQuickFramebuffer();
            const QRgb offScale = pixelAt(offPm, laneX, rows.centerY(scaleKey));
            const QRgb offNon = pixelAt(offPm, laneX, rows.centerY(nonScaleKey));
            const QRgb offKbd = pixelAt(offPm, kbdX, rows.centerY(scaleKey));

            view.setScaleHighlight(true);
            view.setScaleFold(false);
            const QImage hlPm = check.captureQuickFramebuffer();
            const QRgb hlScale = pixelAt(hlPm, laneX, rows.centerY(scaleKey));
            const QRgb hlNon = pixelAt(hlPm, laneX, rows.centerY(nonScaleKey));
            const QRgb hlKbd = pixelAt(hlPm, kbdX, rows.centerY(scaleKey));
            const QRgb hlRoot = pixelAt(hlPm, laneX, rows.centerY(rootKey));

            if (hlScale == offScale)
                fail("Highlight did not tint the scale row");
            const auto blendedChannel = [](int background, int source) {
                return (source * 51 + background * 204 + 127) / 255;
            };
            const QRgb expectedTint =
                qRgb(blendedChannel(qRed(offScale), 0xb5), blendedChannel(qGreen(offScale), 0x95),
                     blendedChannel(qBlue(offScale), 0xfc));
            if (std::abs(qRed(hlScale) - qRed(expectedTint)) > 1 ||
                std::abs(qGreen(hlScale) - qGreen(expectedTint)) > 1 ||
                std::abs(qBlue(hlScale) - qBlue(expectedTint)) > 1) {
                fail("Highlight tint is not #b595fc at 20% opacity");
            }
            if (hlNon != offNon)
                fail("Highlight tinted a non-scale row");
            if (hlKbd != offKbd)
                fail("Highlight repainted the keyboard column");
            if (hlRoot != hlScale)
                fail("Highlight emphasized the root degree differently");

            view.setScaleRoot(1); // C# Major: the former non-scale C# row becomes the root.
            const QImage shiftedPm = check.captureQuickFramebuffer();
            const QRgb shiftedRoot = pixelAt(shiftedPm, laneX, rows.centerY(nonScaleKey));
            const QRgb expectedShiftedTint =
                qRgb(blendedChannel(qRed(offNon), 0xb5), blendedChannel(qGreen(offNon), 0x95),
                     blendedChannel(qBlue(offNon), 0xfc));
            if (std::abs(qRed(shiftedRoot) - qRed(expectedShiftedTint)) > 1 ||
                std::abs(qGreen(shiftedRoot) - qGreen(expectedShiftedTint)) > 1 ||
                std::abs(qBlue(shiftedRoot) - qBlue(expectedShiftedTint)) > 1) {
                fail("changing the scale root did not update Highlight lanes");
            }
            view.setScaleRoot(0);
            view.setScaleId(porydaw_scale::ScaleId::phrygian);
            const QImage changedScalePm = check.captureQuickFramebuffer();
            const QRgb changedScalePitch =
                pixelAt(changedScalePm, laneX, rows.centerY(nonScaleKey));
            if (std::abs(qRed(changedScalePitch) - qRed(expectedShiftedTint)) > 1 ||
                std::abs(qGreen(changedScalePitch) - qGreen(expectedShiftedTint)) > 1 ||
                std::abs(qBlue(changedScalePitch) - qBlue(expectedShiftedTint)) > 1) {
                fail("changing the scale type did not update Highlight lanes");
            }
            view.setScaleId(scaleMajor);

            // Highlight and Fold compose: a visible, occupied scale row keeps
            // Fold's projection and receives the same Highlight tint.
            const int cmd0 = doc.undoStack()->index();
            constexpr int foldTintKey = 127; // G9 in C Major; always the top Fold row.
            const uint64_t tintTick =
                uint64_t(check.timeline().lengthTicks) + uint64_t(doc.ticksPerClock()) * 8;
            doc.addNote(scaleTrack, tintTick, uint8_t(foldTintKey), doc.ticksPerClock(), 100);
            view.setScaleHighlight(false);
            view.setScaleFold(true);
            const int foldRow = view.pitchProjection().rowForPitch(foldTintKey);
            if (foldRow == projHidden) {
                fail("Fold hid the occupied scale row for the Highlight tint probe");
            } else {
                SongView::ViewState folded = view.viewState();
                folded.valid = true;
                folded.keyHeight = kh;
                folded.scrollY = std::max(0.0, double(foldRow) * kh + kh / 2.0 - 100.0);
                view.applyViewState(folded);
                (void)view.grab();
                QCoreApplication::processEvents();
                const int foldY = foldCenterY(foldTintKey);
                if (foldY < 0 || foldY >= roll->height()) {
                    fail("Fold did not make the occupied scale row visible for the Highlight tint "
                         "probe");
                } else {
                    const QImage foldOffPm = check.captureQuickFramebuffer();
                    const QRgb foldOff = pixelAt(foldOffPm, laneX, foldY);
                    view.setScaleHighlight(true);
                    if (!view.scaleHighlight() || !view.scaleFold())
                        fail("enabling Highlight disabled Fold");
                    const QImage foldHighlightPm = check.captureQuickFramebuffer();
                    const QRgb foldHighlight = pixelAt(foldHighlightPm, laneX, foldY);
                    if (foldHighlight == foldOff)
                        fail("Highlight did not tint a visible occupied Fold scale row");
                    const QRgb expectedFoldTint = qRgb(blendedChannel(qRed(foldOff), 0xb5),
                                                       blendedChannel(qGreen(foldOff), 0x95),
                                                       blendedChannel(qBlue(foldOff), 0xfc));
                    if (std::abs(qRed(foldHighlight) - qRed(expectedFoldTint)) > 1 ||
                        std::abs(qGreen(foldHighlight) - qGreen(expectedFoldTint)) > 1 ||
                        std::abs(qBlue(foldHighlight) - qBlue(expectedFoldTint)) > 1) {
                        fail("Highlight tint on a Fold row is not #b595fc at 20% opacity");
                    }
                }
            }
            view.setScaleHighlight(false);
            view.setScaleFold(false);
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
        }

        // Note face is untouched: paint the same note in Off and Highlight
        // and compare the pixels inside its rect.
        if (scaleKey >= 0) {
            view.setScaleHighlight(false);
            view.setScaleFold(false);
            view.ensureKeyVisible(scaleKey);
            (void)view.grab();
            QCoreApplication::processEvents();
            const QPoint notePos(laneX, rows.centerY(scaleKey));
            const int cmd0 = doc.undoStack()->index();
            drawNote(*roll, notePos); // commits a C-major-scale note (empty row)
            const QImage offPm = check.captureQuickFramebuffer();
            const QRgb offFace = pixelAt(offPm, notePos.x(), notePos.y());
            view.setScaleHighlight(true);
            view.setScaleFold(false);
            const QImage hlPm = check.captureQuickFramebuffer();
            const QRgb hlFace = pixelAt(hlPm, notePos.x(), notePos.y());
            view.setScaleHighlight(false);
            view.setScaleFold(false);
            if (hlFace != offFace)
                fail("Highlight changed the painted note face");
            while (doc.undoStack()->index() > cmd0)
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }
        view.setScaleRoot(0);
        view.setScaleId(scaleMajor);
    }

    if (doc.undoStack()->index() != undoBaseline)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
