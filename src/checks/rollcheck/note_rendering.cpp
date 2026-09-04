#include "checks/rollcheck/rollcheck.h"

#include <QColor>
#include <QCoreApplication>
#include <QEvent>
#include <QFontMetrics>
#include <QImage>
#include <QPoint>
#include <QRect>
#include <QRectF>
#include <algorithm>
#include <cmath>
#include <vector>

#include "checks/support/eventsynth.h"
#include "core/songdocument.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/theme/color_math.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

namespace checks::rollcheck {

ScenarioContinuation runPencilNoteRenderingScenarios(Harness &check,
                                                     const PencilPaintingFixture &fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const SnappedRows rows{view, *roll};
    const Cell &a = fixture.a;
    const DocNote &noteA = fixture.noteA;
    const int undoBaseline = doc.undoStack()->index();
    const qreal displayDpr = roll->devicePixelRatio();
    const auto plotToBandX = [pianoKeyboardWidth](qreal x) {
        return qreal(pianoKeyboardWidth) + x;
    };
    const qreal noteLeftX = view.camera().displayX(double(noteA.tick), 0, displayDpr);
    const qreal noteRightX =
        view.camera().displayX(double(noteA.tick + noteA.duration), 0, displayDpr);
    const QRectF noteFrame = rows.noteRect(noteLeftX, noteRightX, noteA.key);
    const QRectF paintedNoteBox = rows.noteBox(noteFrame);
    const QColor expectedNoteColor = SongView::noteColor(track, 100);
    const qreal abuttingRightX =
        view.camera().displayX(double(noteA.tick + 2 * noteA.duration), 0, displayDpr);
    auto fail = [&](const char *what) { check.fail(what); };
    // Timeline overlays are composited above notes and can tint frame colors
    // by a few channel values.
    const auto isBlackBorder = [](QRgb pixel) {
        return qRed(pixel) <= 16 && qGreen(pixel) <= 16 && qBlue(pixel) <= 16;
    };
    // At a key height where only ~3 face pixels remain, the border thins to
    // one pixel instead of vanishing while neighboring larger notes keep
    // theirs.
    {
        const SongView::ViewState originalView = view.viewState();
        const std::vector<NoteId> selectedNotes = view.selectionModel().noteSelection();
        view.selectionModel().clearNoteSelection();
        SongView::ViewState tinyView = originalView;
        tinyView.keyHeight = 5.0;
        tinyView.scrollY =
            std::max(0.0, (127.5 - double(noteA.key)) * tinyView.keyHeight - roll->height() / 2.0);
        view.applyViewState(tinyView);
        const SnappedRows tinyRows{view, *roll};
        const QRectF tinyBox =
            tinyRows.noteBox(tinyRows.noteRect(noteRightX, abuttingRightX, noteA.key));
        const QImage tinyImage = check.captureQuickFramebuffer();
        const qreal tinyDpr = tinyImage.devicePixelRatio();
        const auto toTinyPixel = [tinyDpr](qreal position) { return qRound(position * tinyDpr); };
        const int tinyCenterX = toTinyPixel(plotToBandX(tinyBox.center().x()));
        const int tinyTopPixel = toTinyPixel(tinyBox.top());
        // Quick thins the border to the widest frame that leaves a face
        // (fittedFrameThickness), not the painter's fixed single pixel.
        const int fittedBorder =
            std::clamp((qRound(std::min(tinyBox.width(), tinyBox.height()) * tinyDpr) -
                        layout::singlePixel()) /
                           2,
                       layout::space(layout::Space::Zero), songview::noteBorderPixels(tinyDpr));
        if (fittedBorder <= 0) {
            fail("tiny note probe has no fitted border");
        } else {
            for (int borderPixel = 0; borderPixel < fittedBorder; ++borderPixel) {
                if (!isBlackBorder(tinyImage.pixel(tinyCenterX, tinyTopPixel + borderPixel)))
                    fail("tiny note lost its border instead of thinning it");
            }
            if (tinyImage.pixel(tinyCenterX, tinyTopPixel + fittedBorder) !=
                expectedNoteColor.rgba())
                fail("tiny note border swallowed the note face");
        }
        view.selectionModel().setNoteSelection(selectedNotes);
        view.applyViewState(originalView);
    }

    // Probe the selected 3px ring, its 2px black inset, and the unselected
    // bottom edge with the camera centered at a fractional scale.
    {
        const SongView::ViewState originalView = view.viewState();
        SongView::ViewState fractionalView = originalView;
        fractionalView.keyHeight = 16.375;
        fractionalView.scrollY = std::max(
            0.0, (127.5 - double(noteA.key)) * fractionalView.keyHeight - roll->height() / 2.0);
        view.applyViewState(fractionalView);

        const SnappedRows fractionalRows{view, *roll};
        const QRectF fractionalNoteBox =
            fractionalRows.noteBox(fractionalRows.noteRect(noteLeftX, noteRightX, noteA.key));
        const QImage selectedNoteImage = check.captureQuickFramebuffer();
        const qreal devicePixelRatio = selectedNoteImage.devicePixelRatio();
        const auto toPhysicalPixel = [devicePixelRatio](qreal position) {
            return qRound(position * devicePixelRatio);
        };
        const int leftPixel = toPhysicalPixel(plotToBandX(fractionalNoteBox.left()));
        const int rightPixel = toPhysicalPixel(plotToBandX(fractionalNoteBox.right()));
        const int topPixel = toPhysicalPixel(fractionalNoteBox.top());
        const int bottomPixel = toPhysicalPixel(fractionalNoteBox.bottom());
        const int centerPixelX = toPhysicalPixel(plotToBandX(fractionalNoteBox.center().x()));
        const int centerPixelY = toPhysicalPixel(fractionalNoteBox.center().y());
        // Frame weights scale with the display ratio (1-DIP border, 1.5-DIP
        // ring) — assert the display-scaled pixel counts.
        const int ringPixels = songview::selectionRingPixels(devicePixelRatio);
        const int borderPixels = songview::noteBorderPixels(devicePixelRatio);
        for (int ringPixel = 0; ringPixel < ringPixels; ++ringPixel) {
            if (!isSelectionRingColor(
                    selectedNoteImage.pixel(centerPixelX, topPixel + ringPixel)) ||
                !isSelectionRingColor(
                    selectedNoteImage.pixel(centerPixelX, bottomPixel - 1 - ringPixel))) {
                fail("selected note frame is not a contiguous selection ring");
            }
        }
        for (int borderPixel = 0; borderPixel < borderPixels; ++borderPixel) {
            if (!isBlackBorder(
                    selectedNoteImage.pixel(centerPixelX, topPixel + ringPixels + borderPixel)))
                fail("selected note did not have an inset black top border");
            if (!isBlackBorder(selectedNoteImage.pixel(centerPixelX,
                                                       bottomPixel - 1 - ringPixels - borderPixel)))
                fail("selected note did not have an inset black bottom border");
            if (!isBlackBorder(
                    selectedNoteImage.pixel(leftPixel + ringPixels + borderPixel, centerPixelY)))
                fail("selected note did not have an inset black left border");
            if (!isBlackBorder(selectedNoteImage.pixel(rightPixel - 1 - ringPixels - borderPixel,
                                                       centerPixelY)))
                fail("selected note did not have an inset black right border");
        }
        // The ring must stop where the black border starts.
        if (isSelectionRingColor(selectedNoteImage.pixel(centerPixelX, topPixel + ringPixels)))
            fail("selection ring is thicker than its display-scaled weight");

        view.selectionModel().clearNoteSelection();
        const QImage unselectedNoteImage = check.captureQuickFramebuffer();
        for (int borderPixel = 0; borderPixel < borderPixels; ++borderPixel) {
            if (!isBlackBorder(
                    unselectedNoteImage.pixel(centerPixelX, bottomPixel - 1 - borderPixel)))
                fail("unselected note lacks its black bottom border");
        }
        if (QColor(unselectedNoteImage.pixel(centerPixelX, bottomPixel)) == expectedNoteColor) {
            fail("unselected note face appears below its black bottom border");
        }

        view.applyViewState(originalView);
        QCoreApplication::processEvents();
    }

    const int selectedTrackBeforeGhostProbe = view.selectionModel().primaryTrack();
    const int ghostTrack = (selectedTrackBeforeGhostProbe + 1) % doc.engineTrackCount();
    view.selectTrack(ghostTrack);
    const QImage ghostNoteRender = check.captureQuickFramebuffer();
    const qreal ghostDpr = ghostNoteRender.devicePixelRatio();
    const auto toGhostPixel = [ghostDpr](qreal position) { return qRound(position * ghostDpr); };
    const QPoint noteInteriorSample(toGhostPixel(plotToBandX(paintedNoteBox.center().x())),
                                    toGhostPixel(paintedNoteBox.center().y()));
    const int ghostCenterX = toGhostPixel(plotToBandX(paintedNoteBox.center().x()));
    const int ghostTopPixel = toGhostPixel(paintedNoteBox.top());
    const int ghostBottomPixel = toGhostPixel(paintedNoteBox.bottom()) - 1;
    const QRgb ghostTopEdge = ghostNoteRender.pixel(ghostCenterX, ghostTopPixel);
    const QRgb ghostTopInterior = ghostNoteRender.pixel(ghostCenterX, ghostTopPixel + 2);
    const QRgb ghostBottomEdge = ghostNoteRender.pixel(ghostCenterX, ghostBottomPixel);
    const QRgb ghostBottomInterior = ghostNoteRender.pixel(ghostCenterX, ghostBottomPixel - 2);

    if (ghostTopEdge != ghostTopInterior || ghostBottomEdge != ghostBottomInterior)
        fail("ghost note face edge does not match adjacent interior pixel");

    // Velocity-color display mode (View menu, app-wide): the active track's
    // note fills take their hue from velocity — exact purple and red
    // endpoints, the hue falling monotonically through the spectrum between
    // — while ghost notes keep the identity rendering byte-for-byte.
    if (SongView::velocityNoteColor(1) != QColor(0x5f, 0x44, 0xe9))
        fail("velocity 1 fill is not the purple endpoint #5f44e9");
    if (SongView::velocityNoteColor(127) != QColor(0xe9, 0x09, 0x04))
        fail("velocity 127 fill is not the red endpoint #e90904");
    if (SongView::velocityNoteColor(0) != themes::color(themes::Role::song_view_note_velocity_zero))
        fail("velocity 0 fill is not the theme neutral");
    for (int velocity = 2; velocity <= 127; ++velocity) {
        const QColor lower = SongView::velocityNoteColor(velocity - 1);
        const QColor upper = SongView::velocityNoteColor(velocity);
        if (upper.alpha() != 255) {
            fail("velocity fill is not opaque");
            break;
        }
        if (upper.hsvHueF() > lower.hsvHueF()) {
            fail("velocity hue does not fall monotonically from purple to red");
            break;
        }
    }

    // noteA is a ghost while ghostTrack is selected: flipping the mode must
    // not move a single sampled ghost pixel.
    view.setVelocityColorMode(true);
    const QImage ghostVelocityRender = check.captureQuickFramebuffer();
    if (ghostVelocityRender.pixel(ghostCenterX, ghostTopPixel) != ghostTopEdge ||
        ghostVelocityRender.pixel(ghostCenterX, ghostTopPixel + 2) != ghostTopInterior ||
        ghostVelocityRender.pixel(ghostCenterX, ghostBottomPixel) != ghostBottomEdge ||
        ghostVelocityRender.pixel(ghostCenterX, ghostBottomPixel - 2) != ghostBottomInterior)
        fail("velocity-color mode changed a ghost note's rendering");

    view.selectTrack(selectedTrackBeforeGhostProbe);
    const QImage velocityModeRender = check.captureQuickFramebuffer();
    if (QColor(velocityModeRender.pixel(noteInteriorSample)) != SongView::velocityNoteColor(100))
        fail("velocity-mode note interior does not match velocityNoteColor(100)");

    view.setVelocityColorMode(false);
    const QImage identityRestoredRender = check.captureQuickFramebuffer();
    if (QColor(identityRestoredRender.pixel(noteInteriorSample)) != expectedNoteColor)
        fail("disabling velocity-color mode did not restore identity fills");

    // Note-name display mode (View menu, app-wide): with rows tall enough
    // for legible text, each visible active-track note independently carries
    // its pitch name when its face fits the complete name plus two trailing
    // spaces; ghost notes never do; below the key-height floor, labels vanish
    // individually.
    {
        const auto differingPixels = [](const QImage &before, const QImage &after,
                                        const QRect &region) {
            int count = 0;
            for (int y = region.top(); y <= region.bottom(); ++y)
                for (int x = region.left(); x <= region.right(); ++x)
                    count += before.pixel(x, y) != after.pixel(x, y);
            return count;
        };
        const SongView::ViewState viewBeforeNames = view.viewState();
        SongView::ViewState namedState = viewBeforeNames;
        namedState.keyHeight = 24.0;
        namedState.scrollY = std::max(0.0, (127.5 - double(noteA.key)) * namedState.keyHeight -
                                               roll->height() / 2.0);
        view.applyViewState(namedState);
        const SnappedRows namedRows{view, *roll};
        const QRectF namedNoteBox =
            namedRows.noteBox(namedRows.noteRect(noteLeftX, noteRightX, noteA.key));
        view.setNoteNameMode(true);
        const QImage namesOnRender = check.captureQuickFramebuffer();
        const qreal namesDpr = namesOnRender.devicePixelRatio();
        const auto toNamesPixel = [namesDpr](qreal position) {
            return qRound(position * namesDpr);
        };
        const QRect noteARegion(QPoint(toNamesPixel(plotToBandX(namedNoteBox.left())),
                                       toNamesPixel(namedNoteBox.top())),
                                QPoint(toNamesPixel(plotToBandX(namedNoteBox.right())) - 1,
                                       toNamesPixel(namedNoteBox.bottom()) - 1));

        // With the other track selected note A is a ghost, and its face must
        // render identically with the mode on or off.
        view.selectTrack(ghostTrack);
        const QImage ghostNamedRender = check.captureQuickFramebuffer();
        view.setNoteNameMode(false);
        if (differingPixels(check.captureQuickFramebuffer(), ghostNamedRender, noteARegion) != 0)
            fail("note-name mode changed a ghost note's rendering");
        view.setNoteNameMode(true);
        view.selectTrack(selectedTrackBeforeGhostProbe);

        // The fixed label face and its padded height, shared with the
        // short-row probes below (which need a label-wide note in view, so
        // they run inside the width-probe scene).
        const auto labelPadding = layout::space(layout::Space::Half);
        auto fixedLabelFont = typography::noteName(roll->font());
        fixedLabelFont.setPixelSize(std::max(layout::singlePixel(), fixedLabelFont.pixelSize() -
                                                                        2 * layout::singlePixel()));
        const auto fixedLabelMetrics = QFontMetrics(fixedLabelFont);
        const auto fixedLabelHeight = fixedLabelMetrics.ascent() + fixedLabelMetrics.descent();

        // Per-note width probe: an abutting short pair followed by a distant
        // note wide enough for its name. The pair stays unlabeled while the
        // distant wide note keeps its label.
        const qreal pxPerTick = view.camera().contentX(1.0) - view.camera().contentX(0.0);
        const auto closeTicks = uint64_t(std::max(1.0, std::ceil(5.0 / pxPerTick)));
        const auto labelProbeWidth = 3 * layout::space(layout::Space::Eight);
        const auto labelTicks = uint64_t(std::ceil(labelProbeWidth / pxPerTick));
        const auto farTicks = uint64_t(std::ceil(90.0 / pxPerTick));
        const uint64_t runTick2 = a.tick + closeTicks;
        const uint64_t runTick3 = runTick2 + farTicks;
        const uint64_t runTick4 = runTick3 + labelTicks + closeTicks;
        int runKey = -1;
        for (int key = 115; key >= 24 && runKey < 0; --key) {
            if (namedRows.top(key) < 0.0 || namedRows.bottom(key) > roll->height())
                continue;
            if (!check.isOccupied(a.tick, 3 * closeTicks + farTicks + 2 * labelTicks, key))
                runKey = key;
        }
        const int stripW = qRound(12.0 * namesDpr);
        const QRectF runRowBox =
            namedRows.noteBox(namedRows.noteRect(0.0, 1.0, runKey < 0 ? 60 : runKey));
        const int runRowTop = toNamesPixel(runRowBox.top());
        const int runRowBottom = toNamesPixel(runRowBox.bottom()) - 1;
        const auto labelStrip = [&](uint64_t tick, int width) {
            const int left =
                toNamesPixel(plotToBandX(view.camera().displayX(double(tick), 0, namedRows.dpr())));
            return QRect(QPoint(left, runRowTop), QPoint(left + width - 1, runRowBottom));
        };
        if (runKey < 0 || closeTicks * pxPerTick > 12.0 ||
            labelStrip(runTick4, stripW).right() >= namesOnRender.width()) {
            fail("no room for the note-name width probe");
        } else {
            const int undoIndexBeforeRun = doc.undoStack()->index();
            doc.addNotes(track, {{a.tick, uint8_t(runKey), uint32_t(closeTicks), 100},
                                 {runTick2, uint8_t(runKey), uint32_t(closeTicks), 100},
                                 {runTick3, uint8_t(runKey), uint32_t(labelTicks), 100},
                                 {runTick4, uint8_t(runKey), uint32_t(labelTicks), 1}});
            const QImage runNamed = check.captureQuickFramebuffer();
            view.setNoteNameMode(false);
            const QImage runUnnamed = check.captureQuickFramebuffer();
            const QRect firstStrip(QPoint(labelStrip(a.tick, 1).left(), runRowTop),
                                   QPoint(labelStrip(runTick2, 1).left() - 1, runRowBottom));
            if (differingPixels(runUnnamed, runNamed, firstStrip) != 0)
                fail("a short same-pitch note was labeled");
            if (differingPixels(runUnnamed, runNamed, labelStrip(runTick2, stripW)) != 0)
                fail("a short same-pitch note was labeled");
            const auto wideLabelRegion = labelStrip(runTick3, stripW);
            if (differingPixels(runUnnamed, runNamed, wideLabelRegion) == 0) {
                fail("a distant note with enough label width lost its label");
            } else {
                bool wideLabelContrasts = false;
                for (int y = wideLabelRegion.top();
                     y <= wideLabelRegion.bottom() && !wideLabelContrasts; ++y)
                    for (int x = wideLabelRegion.left();
                         x <= wideLabelRegion.right() && !wideLabelContrasts; ++x)
                        wideLabelContrasts = runNamed.pixel(x, y) != runUnnamed.pixel(x, y) &&
                                             themes::contrastRatio(QColor(runNamed.pixel(x, y)),
                                                                   expectedNoteColor) >= 2.5;
                if (!wideLabelContrasts)
                    fail("no clearly contrasting label ink on a wide note face");
            }

            // The width probe's last grab left the mode off.
            view.setNoteNameMode(true);

            // The fixed face labels the wide note at its exact padded fit...
            const auto centeredOnRun = [&](double keyHeight) {
                SongView::ViewState state = namedState;
                state.keyHeight = keyHeight;
                state.scrollY =
                    std::max(0.0, (127.5 - double(runKey)) * keyHeight - roll->height() / 2.0);
                return state;
            };
            view.applyViewState(centeredOnRun(double(fixedLabelHeight + 2 * labelPadding + 1)));
            const QImage fitRowsNamed = check.captureQuickFramebuffer();
            view.setNoteNameMode(false);
            const QImage fitRowsUnnamed = check.captureQuickFramebuffer();
            if (fitRowsUnnamed == fitRowsNamed)
                fail("no label at the exact padded label fit");
            view.setNoteNameMode(true);

            // ...and one layout pixel shorter it hides rather than shrinks.
            view.applyViewState(centeredOnRun(double(fixedLabelHeight + 2 * labelPadding)));
            const QImage shortRowsNamed = check.captureQuickFramebuffer();
            view.setNoteNameMode(false);
            if (check.captureQuickFramebuffer() != shortRowsNamed)
                fail("note names shrank to fit a short row");
            view.setNoteNameMode(true);
            view.applyViewState(namedState);

            // Velocity-color fills span the whole spectrum, so label ink must
            // be picked per fill: both the bright high-velocity note and the
            // dark low-velocity note need clearly readable ink. The piano-key
            // ink pick clears 4:1 on both probed fills (its floor across the
            // whole ramp is ~3.8:1, in the deep reds near velocity 121);
            // either fixed ink drops below 4:1 on one of the two fills.
            view.setVelocityColorMode(true);
            const QImage velNamed = check.captureQuickFramebuffer();
            view.setNoteNameMode(false);
            const QImage velUnnamed = check.captureQuickFramebuffer();
            view.setNoteNameMode(true);
            view.setVelocityColorMode(false);
            const auto bestInkContrast = [&](const QRect &region, const QColor &fill) {
                double best = 0.0;
                for (int y = region.top(); y <= region.bottom(); ++y)
                    for (int x = region.left(); x <= region.right(); ++x)
                        if (velNamed.pixel(x, y) != velUnnamed.pixel(x, y))
                            best = std::max(
                                best, themes::contrastRatio(QColor(velNamed.pixel(x, y)), fill));
                return best;
            };
            if (bestInkContrast(labelStrip(runTick3, stripW), SongView::velocityNoteColor(100)) <
                4.0)
                fail("label ink is not picked against the bright velocity fill");
            if (bestInkContrast(labelStrip(runTick4, stripW), SongView::velocityNoteColor(1)) < 4.0)
                fail("label ink is not picked against the dark velocity fill");

            while (doc.undoStack()->index() > undoIndexBeforeRun && doc.undoStack()->canUndo())
                doc.undoStack()->undo();
        }
        view.applyViewState(viewBeforeNames);
    }
    if (doc.undoStack()->index() != undoBaseline)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

ScenarioContinuation runSelectionRasterScenarios(Harness &check,
                                                 const PencilVelocityFixture &fixture)
{
    SongDocument &doc = check.document();
    SongView &view = check.view();
    songview::TimelineInputItem *roll = &check.rollInput();
    const int track = check.track();
    const int pianoKeyboardWidth = check.pianoKeyboardWidth();
    const auto plotToBandX = [pianoKeyboardWidth](qreal x) {
        return qreal(pianoKeyboardWidth) + x;
    };
    const Cell &a = fixture.a;
    const int undoBaseline = doc.undoStack()->index();
    auto fail = [&](const char *what) { check.fail(what); };
    {
        const uint64_t overlayTick = a.tick + 3 * a.dur;
        const SongView::ViewState originalView = view.viewState();
        for (const double shortKeyHeight : {8.6, 9.0}) {
            SongView::ViewState shortView = originalView;
            shortView.keyHeight = shortKeyHeight;
            view.applyViewState(shortView);
            QCoreApplication::processEvents();

            // The probed note stays unselected (values show on every
            // current-track note during a drag), so its interior carries only
            // the 1-DIP black border, not the selection ring — the drag runs
            // on a sacrificial second note, placed FIRST so the isolation
            // scan below keeps the probed note's guarded rows clear of it.
            const int undoIndexBefore = doc.undoStack()->index();
            const Cell dragCell = check.findFreeCell(8, true);
            if (dragCell.key < 0) {
                fail("no free cell for the short-note velocity drag note");
                continue;
            }
            doc.addNote(track, dragCell.tick, uint8_t(dragCell.key), uint32_t(dragCell.dur), 100);

            Cell cell;
            const SnappedRows shortRows{view, *roll};
            for (int key = 115; key >= 24 && cell.key < 0; --key) {
                if (shortRows.top(key) < 3.0 || shortRows.bottom(key) > roll->height() - 3.0)
                    continue;
                for (int probe = 8; probe < roll->width() - 40; probe += 24) {
                    const uint64_t tick =
                        view.grid().snapTickDown(view.camera().tickAtContentX(probe));
                    const uint64_t dur = view.grid().gridTicksAt(tick);
                    const int x0 = view.camera().contentX(double(tick));
                    const int xs =
                        view.camera().contentX(double(tick + view.grid().snapTicksAt(tick)));
                    const int x2 = view.camera().contentX(double(tick + 2 * dur));
                    if (x0 < 0 || xs - x0 < 8 || x2 - x0 < 24 || x2 >= roll->width())
                        continue;
                    bool blocked = false;
                    for (int neighborKey = key - 1; neighborKey <= key + 1; ++neighborKey)
                        blocked = blocked || check.isOccupied(tick, 2 * dur, neighborKey, true);
                    const auto nearSpan = [&](uint64_t overlay) {
                        return overlay != UINT64_MAX && overlay + dur >= tick &&
                               overlay <= tick + 3 * dur;
                    };
                    if (blocked || nearSpan(check.timeline().loopStartTick) ||
                        nearSpan(check.timeline().loopEndTick) || nearSpan(overlayTick))
                        continue;
                    cell.tick = tick;
                    cell.dur = dur;
                    cell.key = key;
                    cell.center = QPoint((x0 + xs) / 2, shortRows.centerY(key));
                    break;
                }
            }
            if (cell.key < 0) {
                fail("no isolated cell for the short-note velocity value probe");
                while (doc.undoStack()->index() > undoIndexBefore && doc.undoStack()->canUndo())
                    doc.undoStack()->undo();
                continue;
            }

            doc.addNote(track, cell.tick, uint8_t(cell.key), uint32_t(2 * cell.dur), 10);
            QCoreApplication::processEvents();
            const QImage shortIdleImage = check.captureQuickFramebuffer();

            checks::events::sendMouse(*roll, QEvent::MouseButtonPress, dragCell.center,
                                      Qt::LeftButton, Qt::LeftButton, Qt::ControlModifier);
            checks::events::sendMouse(*roll, QEvent::MouseMove, dragCell.center + QPoint(0, 12),
                                      Qt::NoButton, Qt::LeftButton, Qt::ControlModifier);
            const QImage shortDragImage = check.captureQuickFramebuffer();
            const qreal rasterDpr = shortDragImage.devicePixelRatio();
            const auto toRasterPixel = [rasterDpr](qreal position) {
                return qRound(position * rasterDpr);
            };
            checks::events::sendMouse(*roll, QEvent::MouseButtonRelease,
                                      dragCell.center + QPoint(0, 12), Qt::LeftButton, Qt::NoButton,
                                      Qt::ControlModifier);

            const int shortLeftX = view.camera().contentX(double(cell.tick));
            const int shortRightX = view.camera().contentX(double(cell.tick + 2 * cell.dur));
            const QRectF shortRect = shortRows.noteRect(shortLeftX, shortRightX, cell.key);
            const QRectF shortBox = shortRows.noteBox(shortRect);

            const int frameMargin = songview::noteBorderPixels(rasterDpr);
            const int boxLeftPixel = toRasterPixel(plotToBandX(shortBox.left()));
            const int boxRightPixel = toRasterPixel(plotToBandX(shortBox.right()));
            const int boxTopPixel = toRasterPixel(shortBox.top());
            const int boxBottomPixel = toRasterPixel(shortBox.bottom());
            const int inkTop = boxTopPixel + frameMargin;
            const int inkBottom = boxBottomPixel - frameMargin;
            if (inkTop >= inkBottom)
                fail("short-note velocity probe has no frame-free interior row");
            bool valueInkFound = false;
            for (int y = inkTop; y < inkBottom; ++y) {
                for (int x = boxLeftPixel + frameMargin; x < boxRightPixel - frameMargin; ++x)
                    valueInkFound |= shortDragImage.pixel(x, y) != shortIdleImage.pixel(x, y);
            }
            if (!valueInkFound)
                fail("short-note velocity drag rendered no value ink inside the note box");

            const QRect imageBounds = shortDragImage.rect();
            const QRect noteBoxPixels(QPoint(boxLeftPixel, boxTopPixel),
                                      QPoint(boxRightPixel - 1, boxBottomPixel - 1));
            const int escapeMargin = noteBoxPixels.height();
            const QRect clipProbe =
                noteBoxPixels.adjusted(-escapeMargin, -escapeMargin, escapeMargin, escapeMargin)
                    .intersected(imageBounds);
            bool pixelsEscapedClip = false;
            for (int y = clipProbe.top(); y <= clipProbe.bottom(); ++y) {
                for (int x = clipProbe.left(); x <= clipProbe.right(); ++x) {
                    if (!noteBoxPixels.contains(x, y) &&
                        shortDragImage.pixel(x, y) != shortIdleImage.pixel(x, y)) {
                        pixelsEscapedClip = true;
                        break;
                    }
                }
                if (pixelsEscapedClip)
                    break;
            }
            if (pixelsEscapedClip)
                fail("short-note velocity drag changed pixels outside the note box clip");

            while (doc.undoStack()->index() > undoIndexBefore && doc.undoStack()->canUndo())
                doc.undoStack()->undo();
            view.selectionModel().clearNoteSelection();
        }
        view.applyViewState(originalView);
        QCoreApplication::processEvents();
    }
    if (doc.undoStack()->index() != undoBaseline)
        fail("gesture pass pushed an unexpected number of undo commands");
    return ScenarioContinuation::Continue;
}

} // namespace checks::rollcheck
