#include "ui/songview/quick/timelinequickview.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QApplication>
#include <QFontInfo>
#include <QFontMetricsF>
#include <cstdint>
#include <optional>

#include <algorithm>
#include <array>
#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
namespace {

using detail::contrastingTextColor;
using detail::ghostNoteColor;
using detail::gridLineColor;
using detail::isBlackKey;
using detail::keyName;
using detail::logicalPhysicalPixel;
using detail::usedTrackMask;

using timeline_quick::addDashedVertical;
using timeline_quick::addHorizontalGradient;
using timeline_quick::addHorizontalLine;
using timeline_quick::addRect;
using timeline_quick::addVerticalLine;
using timeline_quick::resetLayer;

int fittedFrameThickness(const QRectF &rect, int requestedPixels, int insetPixels, qreal dpr)
{
    const int minDimPixels = qRound((std::min)(rect.width(), rect.height()) * dpr);
    return std::clamp((minDimPixels - lyt::singlePixel()) / 2 - insetPixels,
                      lyt::space(Space::Zero), requestedPixels);
}

int addFrame(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
             const QColor &color, int requestedPixels, int insetPixels, qreal dpr,
             const QRectF &clip)
{
    const int thicknessPixels = fittedFrameThickness(rect, requestedPixels, insetPixels, dpr);
    if (thicknessPixels <= 0)
        return 0;
    const qreal pixel = logicalPhysicalPixel(dpr);
    const qreal inset = insetPixels * pixel;
    const qreal thickness = thicknessPixels * pixel;
    const QRectF frame = rect.adjusted(inset, inset, -inset, -inset);
    addRect(scene, layer, QRectF(frame.left(), frame.top(), frame.width(), thickness), color, clip);
    addRect(scene, layer,
            QRectF(frame.left(), frame.bottom() - thickness, frame.width(), thickness), color,
            clip);
    const qreal sideHeight = (std::max)(0.0, frame.height() - 2.0 * thickness);
    addRect(scene, layer, QRectF(frame.left(), frame.top() + thickness, thickness, sideHeight),
            color, clip);
    addRect(scene, layer,
            QRectF(frame.right() - thickness, frame.top() + thickness, thickness, sideHeight),
            color, clip);
    return thicknessPixels;
}

void addDashedHorizontal(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &clip,
                         qreal x0, qreal x1, qreal y, qreal width, qreal dash, qreal gap,
                         const QColor &color)
{
    for (qreal x = x0; x < x1; x += dash + gap)
        addRect(scene, layer, QRectF(x, y - width / 2.0, (std::min)(dash, x1 - x), width), color,
                clip);
}

void addDashedFrame(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                    const QColor &color, qreal width, qreal dash, qreal gap, const QRectF &clip)
{
    addDashedHorizontal(scene, layer, clip, rect.left(), rect.right(), rect.top(), width, dash, gap,
                        color);
    addDashedHorizontal(scene, layer, clip, rect.left(), rect.right(), rect.bottom(), width, dash,
                        gap, color);
    addDashedVertical(scene, layer, rect.left(), rect.top(), rect.bottom(), width, dash, gap, color,
                      clip);
    addDashedVertical(scene, layer, rect.right(), rect.top(), rect.bottom(), width, dash, gap,
                      color, clip);
}

void addNoteBorder(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &noteBox,
                   bool unterminated, int dashLength, int dashGap, int insetPixels, qreal dpr,
                   const QRectF &clip)
{
    const int requested = noteBorderPixels(dpr);
    const int fitted = fittedFrameThickness(noteBox, requested, insetPixels, dpr);
    const qreal pixel = logicalPhysicalPixel(dpr);
    if (fitted > 0 && !unterminated) {
        addFrame(scene, layer, noteBox, Qt::black, requested, insetPixels, dpr, clip);
        return;
    }
    if (fitted > 0) {
        for (int framePixel = 0; framePixel < fitted; ++framePixel) {
            const qreal inset = (insetPixels + framePixel) * pixel;
            const QRectF frame =
                noteBox.adjusted(0, 0, -pixel, -pixel).adjusted(inset, inset, -inset, -inset);
            addDashedFrame(scene, layer, frame, Qt::black, pixel, dashLength, dashGap, clip);
        }
        return;
    }
    QColor color(Qt::black);
    color.setAlphaF(
        std::clamp((std::min)(noteBox.width(), noteBox.height()) / (3.0 * pixel), 0.25, 0.85));
    const qreal inset = insetPixels * pixel;
    const QRectF frame = noteBox.adjusted(inset, inset, -inset, -inset);
    if (unterminated) {
        addDashedFrame(scene, layer, frame, color, pixel, dashLength, dashGap, clip);
    } else {
        addRect(scene, layer, QRectF(frame.left(), frame.top(), frame.width(), pixel), color, clip);
        addRect(scene, layer, QRectF(frame.left(), frame.bottom() - pixel, frame.width(), pixel),
                color, clip);
        addRect(scene, layer,
                QRectF(frame.left(), frame.top() + pixel, pixel, frame.height() - 2.0 * pixel),
                color, clip);
        addRect(
            scene, layer,
            QRectF(frame.right() - pixel, frame.top() + pixel, pixel, frame.height() - 2.0 * pixel),
            color, clip);
    }
}

void addLoopGlow(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                 bool fadesRight, const QRectF &clip)
{
    auto strong = themes::color(themes::Role::song_view_loop_marker);
    auto weak = strong;
    auto clear = strong;
    strong.setAlpha(150);
    weak.setAlpha(18);
    clear.setAlpha(0);
    const qreal split = rect.left() + rect.width() * (fadesRight ? 0.2 : 0.8);
    if (fadesRight) {
        addHorizontalGradient(scene, layer,
                              QRectF(rect.left(), rect.top(), split - rect.left(), rect.height()),
                              strong, weak, clip);
        addHorizontalGradient(scene, layer,
                              QRectF(split, rect.top(), rect.right() - split, rect.height()), weak,
                              clear, clip);
    } else {
        addHorizontalGradient(scene, layer,
                              QRectF(rect.left(), rect.top(), split - rect.left(), rect.height()),
                              clear, weak, clip);
        addHorizontalGradient(scene, layer,
                              QRectF(split, rect.top(), rect.right() - split, rect.height()), weak,
                              strong, clip);
    }
}

TimelineQuickTextKey noteTextKey(TimelineQuickTextKeyKind kind, const ViewNote &note,
                                 std::size_t index)
{
    return {kind, note.noteId, note.noteId.isAssigned() ? 0 : static_cast<quint64>(index)};
}

constexpr TimelineQuickTextKey drawPreviewTextKey{TimelineQuickTextKeyKind::PianoDrawPreview};
constexpr TimelineQuickTextKey loadingTextKey{TimelineQuickTextKeyKind::PianoLoading};

QFont resolvedFont(const QFont &font)
{
    const QFontInfo info(font);
    QFont resolved;
    resolved.setFamily(info.family());
    resolved.setStyleName(info.styleName());
    resolved.setPixelSize(info.pixelSize());
    resolved.setWeight(font.weight());
    resolved.setItalic(font.italic());
    return resolved;
}

void appendTextRecord(std::vector<TimelineQuickTextModel::Record> &records,
                      const TimelineQuickTextKey &key, const QRectF &rect, const QString &text,
                      const QFont &font, const QColor &color, Qt::Alignment horizontal,
                      Qt::Alignment vertical)
{
    if (rect.width() <= 0.0 || rect.height() <= 0.0)
        return;
    records.push_back({key, rect, text, color, font, horizontal, vertical});
}

} // namespace

void TimelineQuickView::rebuildGrid()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const qreal dpr = roll.devicePixelRatioF();
    const qreal pixel = logicalPhysicalPixel(dpr);
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                      roll.height());
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);

    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const auto &edges = roll.rowEdges();
    const QColor accidental = detail::pianoRollAccidentalLaneColor();
    const QColor octave = themes::color(themes::Role::song_view_piano_keyboard_separator);
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = roll.pitchRowRect(row, plot.left(), plot.width());
        if (!rowRect.intersects(plot))
            continue;
        if (isBlackKey(key))
            addRect(scene, TimelineQuickLayer::PianoGrid, rowRect, accidental, plot);
        addHorizontalLine(scene, TimelineQuickLayer::PianoGrid, plot.left(), plot.right(),
                          rowRect.bottom(), pixel, key % 12 == 0 ? octave : gridLineColor(50),
                          plot);
    }
    if (roll.m_sv->scaleHighlight()) {
        const QColor tint = detail::pianoRollScaleHighlightColor();
        for (int row = 0; row < projection.visibleRowCount(); ++row) {
            if (projection.isScalePitchRow(row)) {
                addRect(scene, TimelineQuickLayer::PianoGrid,
                        QRectF(plot.left(), edges[row], plot.width(), edges[row + 1] - edges[row]),
                        tint, plot);
            }
        }
    }

    const qreal tickZero = roll.m_sv->displayX(0.0, keyboardWidth, dpr);
    if (tickZero > plot.left()) {
        addRect(scene, TimelineQuickLayer::PianoGrid,
                QRectF(plot.left(), plot.top(), tickZero - plot.left(), plot.height()),
                mixTowardOklab(background, gridLineColor(), 0.15), plot);
    }

    const qreal roundingMargin = pixel / 2.0;
    const double t0 =
        (std::max)(0.0, roll.m_sv->tickAtContentX(plot.left() - keyboardWidth - roundingMargin));
    const double t1 =
        roll.m_sv->tickAtContentX(plot.right() - pixel - keyboardWidth + roundingMargin) + 1.0;
    // During the first narrow resize pass the plot can end before the keyboard.
    // Keep its negative/reversed tick range from converting to UINT64_MAX below.
    if (!std::isfinite(t0) || !std::isfinite(t1) || t1 <= t0)
        return;
    const std::array<QColor, 6> gridColors = {gridLineColor(125), gridLineColor(100),
                                              gridLineColor(75),  gridLineColor(160),
                                              gridLineColor(200), gridLineColor()};
    // Keep these values aligned with the corresponding SongView geometry metrics.
    const int detailMinimumPixelsPerBeat = lyt::fontPx(5.0 / 6.0);
    const qreal gridWidth = lyt::fontPx(1.0 / 6.0) * pixel;
    detail::forEachSubGridLine(
        roll.m_sv, t0, t1, detailMinimumPixelsPerBeat, [&](uint64_t tick, int level) {
            const qreal x = roll.m_sv->displayX(double(tick), keyboardWidth, dpr);
            addVerticalLine(scene, TimelineQuickLayer::PianoGrid, x, plot.top(), plot.bottom(),
                            gridWidth, gridColors[std::size_t(level - 1)], plot);
        });
    const bool drawBeats = roll.m_sv->pxPerBeat() >= detailMinimumPixelsPerBeat;
    roll.m_sv->forEachGridLine(
        uint64_t(t0), uint64_t(t1), [&](uint64_t tick, bool isBar, int, int) {
            if (!isBar && !drawBeats)
                return;
            const bool finest =
                roll.m_sv->document() && roll.m_sv->gridTicksAt(tick) == roll.m_sv->fineGridTicks();
            const auto colorIndex = isBar ? 5u : finest ? 4u : 3u;
            const qreal x = roll.m_sv->displayX(double(tick), keyboardWidth, dpr);
            addVerticalLine(scene, TimelineQuickLayer::PianoGrid, x, plot.top(), plot.bottom(),
                            gridWidth, gridColors[colorIndex], plot);
        });
}

void TimelineQuickView::rebuildNoteFills()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    if (!roll.m_sv->timeline())
        return;

    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                      roll.height());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const int selectedTrack = roll.m_sv->selectionModel().primaryTrack();
    const auto &notes = roll.m_sv->model().notes;

    for (int pass = 0; pass < 2; ++pass) {
        const bool ghostPass = pass == 0;
        for (const ViewNote &note : notes) {
            const bool ghost = note.track != selectedTrack;
            if (ghost != ghostPass)
                continue;
            if (ghost && roll.m_sv->scaleFold() &&
                projection.rowForPitch(note.key) == PitchProjection::cHiddenRow) {
                continue;
            }
            const QRectF noteRect = roll.displayedNoteRect(note);
            if (!noteRect.intersects(plot))
                continue;
            const QRectF box = roll.noteBox(noteRect);
            const int velocity = roll.m_sv->previewVelocity(note.noteId).value_or(note.velocity);
            if (ghost) {
                addRect(scene, TimelineQuickLayer::PianoNoteFills, box,
                        ghostNoteColor(note.track, isBlackKey(note.key)), plot);
                continue;
            }
            addRect(scene, TimelineQuickLayer::PianoNoteFills, box,
                    roll.m_sv->noteFillColor(note.track, velocity), plot);
        }
    }
}

void TimelineQuickView::rebuildDrawPreviewFill()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    if (!roll.m_sv->timeline() || roll.m_leftDrag != PianoRoll::LeftDrag::Draw)
        return;

    const qreal dpr = roll.devicePixelRatioF();
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                      roll.height());
    const int selectedTrack = roll.m_sv->selectionModel().primaryTrack();
    const qreal x0 = roll.m_sv->displayX(double(roll.m_drawTick), keyboardWidth, dpr);
    const qreal x1 =
        roll.m_sv->displayX(double(roll.m_drawTick + uint64_t(roll.m_drawDur)), keyboardWidth, dpr);
    const QRectF previewRect = roll.noteRect(x0, x1, roll.m_drawKey);
    const QRectF box = roll.noteBox(previewRect);
    const QColor fill = roll.m_sv->noteFillColor(selectedTrack, roll.m_lastVelocity);
    addRect(scene, TimelineQuickLayer::PianoDrawPreviewFill, box, fill, plot);
}

void TimelineQuickView::rebuildNoteBordersAndSelection()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    if (!roll.m_sv->timeline())
        return;

    const qreal dpr = roll.devicePixelRatioF();
    const qreal pixel = logicalPhysicalPixel(dpr);
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                      roll.height());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const auto &selection = roll.m_sv->selectionModel();
    const int selectedTrack = selection.primaryTrack();
    const auto &timeSelection = selection.timeSelection();
    const SongDocument::TimeRange timeRange{timeSelection.startTick, timeSelection.endTick};
    const uint32_t usedTracks = usedTrackMask(roll.m_sv->timeline());
    const uint32_t timeSelectedTracks =
        timeSelection.active() && timeSelection.scope == EditorSelectionModel::TimeSelection::Tracks
            ? selection.resolvedTrackScope(usedTracks)
            : 0;

    const auto addSelectionRing = [&](const QRectF &box, const ViewNote &note) {
        const int requested =
            (std::max)(lyt::singlePixel(), qRound(roll.m_geometry.selectionRingDipWidth * dpr));
        const int ring = addFrame(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box,
                                  themes::color(themes::Role::item_selected_background), requested,
                                  0, dpr, plot);
        if (ring > 0) {
            addNoteBorder(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box,
                          note.unterminated, roll.m_geometry.noteBorderDashLength,
                          roll.m_geometry.noteBorderDashGap, ring, dpr, plot);
        } else {
            addRect(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box,
                    themes::color(themes::Role::item_selected_background), plot);
        }
    };

    for (int pass = 0; pass < 2; ++pass) {
        const bool ghostPass = pass == 0;
        for (const ViewNote &note : roll.m_sv->model().notes) {
            const bool ghost = note.track != selectedTrack;
            if (ghost != ghostPass)
                continue;
            if (ghost && roll.m_sv->scaleFold() &&
                projection.rowForPitch(note.key) == PitchProjection::cHiddenRow) {
                continue;
            }
            const QRectF noteRect = roll.displayedNoteRect(note);
            if (!noteRect.intersects(plot))
                continue;
            const QRectF box = roll.noteBox(noteRect);
            const bool timeSelected = (timeSelectedTracks & (1u << note.track)) &&
                                      timeRange.overlaps(note.startTick, note.endTick);
            if (ghost) {
                if (timeSelected)
                    addSelectionRing(box, note);
                continue;
            }
            const bool selected =
                timeSelected ||
                (note.noteId.isAssigned() && selection.isNoteSelected(note.noteId)) ||
                (roll.m_rightDrag == PianoRoll::RightDrag::Band &&
                 std::any_of(
                     roll.m_bandAud.begin(), roll.m_bandAud.end(),
                     [&](const ViewNote &covered) { return covered.noteId == note.noteId; }));
            if (selected) {
                addSelectionRing(box, note);
            } else {
                addNoteBorder(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box,
                              note.unterminated, roll.m_geometry.noteBorderDashLength,
                              roll.m_geometry.noteBorderDashGap, 0, dpr, plot);
            }
        }
    }
}

void TimelineQuickView::rebuildOverlay()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    if (!roll.m_sv->timeline())
        return;

    const qreal dpr = roll.devicePixelRatioF();
    const qreal pixel = logicalPhysicalPixel(dpr);
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                      roll.height());
    const int selectedTrack = roll.m_sv->selectionModel().primaryTrack();

    if (roll.m_leftDrag == PianoRoll::LeftDrag::Draw) {
        const qreal x0 = roll.m_sv->displayX(double(roll.m_drawTick), keyboardWidth, dpr);
        const qreal x1 = roll.m_sv->displayX(double(roll.m_drawTick + uint64_t(roll.m_drawDur)),
                                             keyboardWidth, dpr);
        const QRectF previewRect = roll.noteRect(x0, x1, roll.m_drawKey);
        const QRectF box = roll.noteBox(previewRect);
        addNoteBorder(scene, TimelineQuickLayer::PianoOverlay, box, false,
                      roll.m_geometry.noteBorderDashLength, roll.m_geometry.noteBorderDashGap, 0,
                      dpr, plot);
    }

    const auto &selection = roll.m_sv->selectionModel();
    const auto &timeSelection = selection.timeSelection();
    const uint32_t usedTracks = usedTrackMask(roll.m_sv->timeline());
    if (roll.m_rightDrag == PianoRoll::RightDrag::Band) {
        const QRectF band = QRectF(roll.m_pressPos, roll.m_curPos).normalized().intersected(plot);
        QColor fill = themes::color(themes::Role::song_view_selection_fill);
        fill.setAlpha(30);
        addRect(scene, TimelineQuickLayer::PianoOverlay, band, fill, plot);
        addDashedFrame(scene, TimelineQuickLayer::PianoOverlay, band,
                       themes::color(themes::Role::song_view_selection_edge), pixel,
                       lyt::space(Space::One), lyt::space(Space::One), plot);
    }

    if (selection.timeSelectionCoversTrack(selectedTrack, usedTracks) && timeSelection.active()) {
        const qreal x0 = roll.m_sv->displayX(double(timeSelection.startTick), keyboardWidth, dpr);
        const qreal x1 = roll.m_sv->displayX(double(timeSelection.endTick), keyboardWidth, dpr);
        QColor fill = themes::color(themes::Role::song_view_selection_fill);
        fill.setAlpha(30);
        addRect(scene, TimelineQuickLayer::PianoOverlay,
                QRectF(x0, plot.top(), x1 - x0, plot.height()), fill, plot);
        addVerticalLine(scene, TimelineQuickLayer::PianoOverlay, x0, plot.top(), plot.bottom(),
                        pixel, themes::color(themes::Role::song_view_selection_edge), plot);
        addVerticalLine(scene, TimelineQuickLayer::PianoOverlay, x1, plot.top(), plot.bottom(),
                        pixel, themes::color(themes::Role::song_view_selection_edge), plot);
    }

    const MidiTimeline *timeline = roll.m_sv->timeline();
    if (timeline->loopStartTick != UINT64_MAX || timeline->loopEndTick != UINT64_MAX) {
        const bool hasStart = timeline->loopStartTick != UINT64_MAX;
        const bool hasEnd = timeline->loopEndTick != UINT64_MAX;
        const qreal x0 =
            hasStart ? roll.m_sv->displayX(double(timeline->loopStartTick), keyboardWidth, dpr)
                     : plot.left();
        const qreal x1 =
            hasEnd ? roll.m_sv->displayX(double(timeline->loopEndTick), keyboardWidth, dpr)
                   : plot.right();
        if (x1 > plot.left() && x0 < plot.right()) {
            const qreal glowWidth = std::min<qreal>(lyt::space(Space::Eight), x1 - x0);
            if (hasStart && glowWidth > 0)
                addLoopGlow(scene, TimelineQuickLayer::PianoOverlay,
                            QRectF(x0, plot.top(), glowWidth, plot.height()), true, plot);
            if (hasEnd && glowWidth > 0)
                addLoopGlow(scene, TimelineQuickLayer::PianoOverlay,
                            QRectF(x1 - glowWidth, plot.top(), glowWidth, plot.height()), false,
                            plot);
            if (hasStart)
                addVerticalLine(scene, TimelineQuickLayer::PianoOverlay, x0, plot.top(),
                                plot.bottom(), pixel, detail::loopEdge(), plot);
            if (hasEnd)
                addVerticalLine(scene, TimelineQuickLayer::PianoOverlay, x1, plot.top(),
                                plot.bottom(), pixel, detail::loopEdge(), plot);
        }
    }

    const qreal cursorX =
        roll.m_sv->displayX(double(roll.m_sv->editCursorTick()), keyboardWidth, dpr);
    if (cursorX >= plot.left() && cursorX <= plot.right()) {
        addDashedVertical(scene, TimelineQuickLayer::PianoOverlay, cursorX, plot.top(),
                          plot.bottom(), pixel, lyt::space(Space::One), lyt::space(Space::One),
                          themes::color(themes::Role::song_view_edit_cursor), plot);
    }
}

void TimelineQuickView::rebuildKeyboardKeys()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const QRectF viewport(roll.rect());
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const qreal pixel = logicalPhysicalPixel(roll.devicePixelRatioF());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const auto &edges = roll.rowEdges();
    if (projection.visibleRowCount() > 0) {
        addRect(scene, TimelineQuickLayer::PianoKeyboardKeys,
                QRectF(0, edges[0], keyboardWidth, edges[projection.visibleRowCount()] - edges[0]),
                themes::color(themes::Role::song_view_piano_keyboard_natural_key), viewport);
    }
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = roll.pitchRowRect(row, 0, keyboardWidth);
        if (!rowRect.intersects(viewport))
            continue;
        if (isBlackKey(key)) {
            addRect(scene, TimelineQuickLayer::PianoKeyboardKeys, rowRect,
                    themes::color(themes::Role::song_view_piano_keyboard_black_key), viewport);
        } else if (key % 12 == 0 || key % 12 == 5) {
            addHorizontalLine(
                scene, TimelineQuickLayer::PianoKeyboardKeys, 0, keyboardWidth, rowRect.bottom(),
                pixel, themes::color(themes::Role::song_view_piano_keyboard_separator), viewport);
        }
    }
}

void TimelineQuickView::rebuildKeyboardHighlights()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const QRectF viewport(roll.rect());
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const qreal pixel = logicalPhysicalPixel(roll.devicePixelRatioF());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const auto hoverGeometry = roll.keyboardHoverGeometry(roll.m_hoverKey);
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = roll.pitchRowRect(row, 0, keyboardWidth);
        if (!rowRect.intersects(viewport))
            continue;
        const bool sounding = key == roll.m_soundingKey;
        if (sounding) {
            addRect(scene, TimelineQuickLayer::PianoKeyboardHighlights, rowRect,
                    themes::color(themes::Role::song_view_piano_keyboard_active_key), viewport);
            if (!isBlackKey(key) && (key % 12 == 0 || key % 12 == 5)) {
                addHorizontalLine(scene, TimelineQuickLayer::PianoKeyboardHighlights, 0,
                                  keyboardWidth, rowRect.bottom(), pixel,
                                  themes::color(themes::Role::song_view_piano_keyboard_separator),
                                  viewport);
            }
        }
        if (key == roll.m_hoverKey && !sounding && hoverGeometry) {
            QColor highlight = roll.palette().color(QPalette::Highlight);
            highlight.setAlpha(80);
            addRect(scene, TimelineQuickLayer::PianoKeyboardHighlights,
                    hoverGeometry->highlightRect, highlight, viewport);
        }
    }
    addVerticalLine(scene, TimelineQuickLayer::PianoKeyboardHighlights, 0, 0, roll.height(), pixel,
                    themes::color(themes::Role::song_view_separator), viewport);
}

void TimelineQuickView::synchronizeNoteText()
{
    PianoRoll &roll = *m_roll;
    std::vector<TimelineQuickTextModel::Record> &records = m_noteTextRecords;
    records.clear();
    if (!roll.m_sv->timeline()) {
        m_scene->m_pianoNoteTextModel->setRecords(records);
        return;
    }

    const qreal dpr = roll.devicePixelRatioF();
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                      roll.height());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const int selectedTrack = roll.m_sv->selectionModel().primaryTrack();
    const auto &notes = roll.m_sv->model().notes;
    const bool velocityShortcut = keymap::Registry::instance().matchesModifier(
        QApplication::queryKeyboardModifiers(), QStringLiteral("roll.velocity_drag"));
    const bool showVelocityValues =
        roll.m_leftDrag == PianoRoll::LeftDrag::Velocity || velocityShortcut;
    const bool nameFontVisible =
        !showVelocityValues && roll.m_sv->noteNameMode() && roll.m_noteNameFont.has_value();
    const bool velocityFontVisible = showVelocityValues && roll.m_velocityLabelFont.has_value();

    std::optional<QFont> noteNameFont = std::nullopt;
    std::optional<QFont> velocityFont = std::nullopt;
    std::optional<QFontMetricsF> noteNameMetrics = std::nullopt;
    std::optional<QFontMetricsF> velocityMetrics = std::nullopt;
    if (nameFontVisible) {
        noteNameFont = resolvedFont(*roll.m_noteNameFont);
        noteNameMetrics.emplace(*roll.m_noteNameFont);
    }
    if (velocityFontVisible) {
        velocityFont = resolvedFont(*roll.m_velocityLabelFont);
        velocityMetrics.emplace(*roll.m_velocityLabelFont);
    }

    for (std::size_t noteIndex = 0; noteIndex < notes.size(); ++noteIndex) {
        const ViewNote &note = notes[noteIndex];
        const bool ghost = note.track != selectedTrack;
        if (ghost)
            continue;
        const QRectF noteRect = roll.displayedNoteRect(note);
        if (!noteRect.intersects(plot))
            continue;
        const QRectF box = roll.noteBox(noteRect);
        const int velocity = roll.m_sv->previewVelocity(note.noteId).value_or(note.velocity);
        const QColor fill = roll.m_sv->noteFillColor(note.track, velocity);
        if (nameFontVisible &&
            roll.noteNameFits(noteRect, roll.displayedNoteKey(note), *noteNameMetrics)) {
            const qreal inset = lyt::space(Space::Half);
            appendTextRecord(records,
                             noteTextKey(TimelineQuickTextKeyKind::PianoNoteName, note, noteIndex),
                             QRectF(box.left() + inset, box.top() + inset,
                                    std::max<qreal>(0, box.width() - 2.0 * inset),
                                    std::max<qreal>(0, box.height() - 2.0 * inset)),
                             keyName(roll.displayedNoteKey(note)), *noteNameFont,
                             contrastingTextColor(fill), Qt::AlignLeft, Qt::AlignVCenter);
        }
        if (velocityFontVisible) {
            const QString text = QString::number(velocity);
            if (noteRect.width() >= velocityMetrics->horizontalAdvance(text) +
                                        roll.m_geometry.velocityLabelFitAllowance) {
                appendTextRecord(
                    records,
                    noteTextKey(TimelineQuickTextKeyKind::PianoNoteVelocity, note, noteIndex), box,
                    text, *velocityFont, contrastingTextColor(fill), Qt::AlignHCenter,
                    Qt::AlignVCenter);
            }
        }
    }

    if (roll.m_leftDrag == PianoRoll::LeftDrag::Draw && velocityShortcut &&
        roll.m_velocityLabelFont) {
        const qreal x0 = roll.m_sv->displayX(double(roll.m_drawTick), keyboardWidth, dpr);
        const qreal x1 = roll.m_sv->displayX(double(roll.m_drawTick + uint64_t(roll.m_drawDur)),
                                             keyboardWidth, dpr);
        const QRectF previewRect = roll.noteRect(x0, x1, roll.m_drawKey);
        const QRectF box = roll.noteBox(previewRect);
        const QString text = QString::number(roll.m_lastVelocity);
        const QColor fill = roll.m_sv->noteFillColor(selectedTrack, roll.m_lastVelocity);
        if (previewRect.width() >=
            velocityMetrics->horizontalAdvance(text) + roll.m_geometry.velocityLabelFitAllowance) {
            appendTextRecord(records, drawPreviewTextKey, box, text, *velocityFont,
                             contrastingTextColor(fill), Qt::AlignHCenter, Qt::AlignVCenter);
        }
    }

    m_scene->m_pianoNoteTextModel->setRecords(records);
}

void TimelineQuickView::synchronizeLoadingText()
{
    PianoRoll &roll = *m_roll;
    std::vector<TimelineQuickTextModel::Record> &records = m_loadingTextRecords;
    records.clear();
    if (!roll.m_sv->timeline()) {
        const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
        const QRectF plot(keyboardWidth, 0, std::max<qreal>(0, roll.width() - keyboardWidth),
                          roll.height());
        const QFont font = resolvedFont(typography::caption(roll.font()));
        appendTextRecord(records, loadingTextKey, plot, SongView::tr("Loading..."), font,
                         themes::color(themes::Role::song_view_secondary_text), Qt::AlignHCenter,
                         Qt::AlignVCenter);
    }
    m_scene->m_pianoLoadingTextModel->setRecords(records);
}

void TimelineQuickView::synchronizeKeyboardText()
{
    PianoRoll &roll = *m_roll;
    std::vector<TimelineQuickTextModel::Record> &records = m_keyboardTextRecords;
    records.clear();
    const QRectF viewport(roll.rect());
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    if (roll.m_keyboardLabelFont) {
        const QFont font = resolvedFont(*roll.m_keyboardLabelFont);
        const QColor color = themes::color(themes::Role::song_view_piano_keyboard_label);
        records.reserve(static_cast<std::size_t>(projection.visibleRowCount()));
        for (int row = 0; row < projection.visibleRowCount(); ++row) {
            const int key = projection.visiblePitchAt(row);
            const QRectF rowRect = roll.pitchRowRect(row, 0, keyboardWidth);
            if (!rowRect.intersects(viewport) || isBlackKey(key) || key % 12 != 0)
                continue;
            appendTextRecord(
                records,
                TimelineQuickTextKey{TimelineQuickTextKeyKind::PianoMidiLabel, {}, quint64(key)},
                QRectF(0, rowRect.top(),
                       keyboardWidth - roll.m_geometry.pianoKeyboardLabelRightInset,
                       rowRect.height()),
                keyName(key), font, color, Qt::AlignRight, Qt::AlignVCenter);
        }
    }
    m_scene->m_pianoKeyboardTextModel->setRecords(records);
}

void TimelineQuickView::synchronizeHoverChip()
{
    PianoRoll &roll = *m_roll;
    const auto hoverGeometry = roll.keyboardHoverGeometry(roll.m_hoverKey);
    if (!hoverGeometry) {
        m_scene->setHoverChip(false, {}, {}, {}, {}, 0.0);
        return;
    }
    m_scene->setHoverChip(true, hoverGeometry->chipRect, hoverGeometry->name,
                          QColor(0x30, 0x30, 0x30, 230), resolvedFont(hoverGeometry->chipFont),
                          roll.m_geometry.keyboardHoverChipCornerRadius);
}

void TimelineQuickView::synchronize(PianoRollQuickDirtySet dirty)
{
    if (!m_roll)
        return;
    TimelineQuickScene &scene = *m_scene;
    const auto rebuild = [&](PianoRollQuickDirty flag, TimelineQuickLayer layer,
                             void (TimelineQuickView::*builder)()) {
        if (!(dirty & flag))
            return;
        resetLayer(scene, layer);
        (this->*builder)();
        if (TimelineQuickItem *item = m_items[static_cast<std::size_t>(layer)])
            item->update();
    };

    rebuild(PianoRollQuickDirty::Grid, TimelineQuickLayer::PianoGrid,
            &TimelineQuickView::rebuildGrid);
    rebuild(PianoRollQuickDirty::NoteFills, TimelineQuickLayer::PianoNoteFills,
            &TimelineQuickView::rebuildNoteFills);
    rebuild(PianoRollQuickDirty::DrawPreviewFill, TimelineQuickLayer::PianoDrawPreviewFill,
            &TimelineQuickView::rebuildDrawPreviewFill);
    rebuild(PianoRollQuickDirty::NoteBordersAndSelection,
            TimelineQuickLayer::PianoNoteBordersAndSelection,
            &TimelineQuickView::rebuildNoteBordersAndSelection);
    rebuild(PianoRollQuickDirty::Overlay, TimelineQuickLayer::PianoOverlay,
            &TimelineQuickView::rebuildOverlay);
    rebuild(PianoRollQuickDirty::KeyboardKeys, TimelineQuickLayer::PianoKeyboardKeys,
            &TimelineQuickView::rebuildKeyboardKeys);
    rebuild(PianoRollQuickDirty::KeyboardHighlights, TimelineQuickLayer::PianoKeyboardHighlights,
            &TimelineQuickView::rebuildKeyboardHighlights);

    if (dirty & PianoRollQuickDirty::NoteText)
        synchronizeNoteText();
    if (dirty & PianoRollQuickDirty::LoadingText)
        synchronizeLoadingText();
    if (dirty & PianoRollQuickDirty::KeyboardText)
        synchronizeKeyboardText();
    if (dirty & PianoRollQuickDirty::HoverChip)
        synchronizeHoverChip();
}

} // namespace songview
