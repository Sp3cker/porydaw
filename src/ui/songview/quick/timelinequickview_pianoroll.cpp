#include "ui/songview/quick/timelinequickview.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview/detail.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/pianorollquick.h"
#include "ui/songview/timecamera.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QApplication>
#include <QFontMetricsF>
#include <cstdint>
#include <optional>

#include <algorithm>

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

using timeline_quick::addDashedHorizontal;
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

void addFrame(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
              const QColor &color, int thicknessPixels, int insetPixels, qreal dpr,
              const QRectF &clip)
{
    const qreal pixel = logicalPhysicalPixel(dpr);
    const qreal inset = insetPixels * pixel;
    const qreal thickness = thicknessPixels * pixel;
    const QRectF frame = rect.adjusted(inset, inset, -inset, -inset);
    addRect(scene.layer(layer), QRectF(frame.left(), frame.top(), frame.width(), thickness), color,
            clip);
    addRect(scene.layer(layer),
            QRectF(frame.left(), frame.bottom() - thickness, frame.width(), thickness), color,
            clip);
    const qreal sideHeight = (std::max)(0.0, frame.height() - 2.0 * thickness);
    addRect(scene.layer(layer),
            QRectF(frame.left(), frame.top() + thickness, thickness, sideHeight), color, clip);
    addRect(scene.layer(layer),
            QRectF(frame.right() - thickness, frame.top() + thickness, thickness, sideHeight),
            color, clip);
}

void addDashedFrame(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &rect,
                    const QColor &color, qreal width, qreal dash, qreal gap, const QRectF &clip)
{
    addDashedHorizontal(scene.layer(layer), rect.left(), rect.right(), rect.top(), width, dash, gap,
                        color, clip);
    addDashedHorizontal(scene.layer(layer), rect.left(), rect.right(), rect.bottom(), width, dash,
                        gap, color, clip);
    addDashedVertical(scene.layer(layer), rect.left(), rect.top(), rect.bottom(), width, dash, gap,
                      color, clip);
    addDashedVertical(scene.layer(layer), rect.right(), rect.top(), rect.bottom(), width, dash, gap,
                      color, clip);
}

void addNoteBorder(TimelineQuickScene &scene, TimelineQuickLayer layer, const QRectF &noteBox,
                   int insetPixels, qreal dpr, const QRectF &clip)
{
    const int requested = noteBorderPixels(dpr);
    const int fitted = fittedFrameThickness(noteBox, requested, insetPixels, dpr);
    const qreal pixel = logicalPhysicalPixel(dpr);
    QColor color(Qt::black);
    if (fitted == 0)
        color.setAlphaF(
            std::clamp((std::min)(noteBox.width(), noteBox.height()) / (3.0 * pixel), 0.25, 0.85));
    addFrame(scene, layer, noteBox, color, std::max(1, fitted), insetPixels, dpr, clip);
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
        addHorizontalGradient(scene.layer(layer),
                              QRectF(rect.left(), rect.top(), split - rect.left(), rect.height()),
                              strong, weak, clip);
        addHorizontalGradient(scene.layer(layer),
                              QRectF(split, rect.top(), rect.right() - split, rect.height()), weak,
                              clear, clip);
    } else {
        addHorizontalGradient(scene.layer(layer),
                              QRectF(rect.left(), rect.top(), split - rect.left(), rect.height()),
                              clear, weak, clip);
        addHorizontalGradient(scene.layer(layer),
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

void TimelineQuickView::rebuildGridRows()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const qreal dpr = roll.devicePixelRatio();
    const qreal pixel = logicalPhysicalPixel(dpr);
    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());

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
            addRect(scene.layer(TimelineQuickLayer::PianoGridRows), rowRect, accidental, plot);
        addHorizontalLine(scene.layer(TimelineQuickLayer::PianoGridRows), plot.left(), plot.right(),
                          rowRect.bottom(), pixel, key % 12 == 0 ? octave : gridLineColor(50),
                          plot);
    }
    if (roll.m_sv->scaleHighlight()) {
        const QColor tint = detail::pianoRollScaleHighlightColor();
        for (int row = 0; row < projection.visibleRowCount(); ++row) {
            if (projection.isScalePitchRow(row)) {
                addRect(scene.layer(TimelineQuickLayer::PianoGridRows),
                        QRectF(plot.left(), edges[row], plot.width(), edges[row + 1] - edges[row]),
                        tint, plot);
            }
        }
    }
}

void TimelineQuickView::rebuildGridTime()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const qreal dpr = roll.devicePixelRatio();
    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
    const QColor background = themes::color(themes::Role::song_view_piano_roll_background);

    const qreal tickZero = roll.m_camera.displayX(0.0, 0.0, dpr);
    if (tickZero > plot.left()) {
        addRect(scene.layer(TimelineQuickLayer::PianoGridTime),
                QRectF(plot.left(), plot.top(), tickZero - plot.left(), plot.height()),
                mixTowardOklab(background, gridLineColor(), 0.15), plot);
    }

    // Paint the shared time grid over the piano-specific pre-roll mask.
    timeline_quick::composeBandedGrid(scene, TimelineQuickLayer::PianoGridTime, *roll.m_sv, plot,
                                      /*origin=*/0, dpr);
}

void TimelineQuickView::rebuildNoteFills()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    if (!roll.m_sv->timeline())
        return;

    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
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
                addRect(scene.layer(TimelineQuickLayer::PianoNoteFills), box,
                        ghostNoteColor(note.track, isBlackKey(note.key)), plot);
                continue;
            }
            addRect(scene.layer(TimelineQuickLayer::PianoNoteFills), box,
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

    const qreal dpr = roll.devicePixelRatio();
    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
    const int selectedTrack = roll.m_sv->selectionModel().primaryTrack();
    const qreal x0 = roll.m_camera.displayX(double(roll.m_drawTick), 0.0, dpr);
    const qreal x1 =
        roll.m_camera.displayX(double(roll.m_drawTick + uint64_t(roll.m_drawDur)), 0.0, dpr);
    const QRectF previewRect = roll.noteRect(x0, x1, roll.m_drawKey);
    const QRectF box = roll.noteBox(previewRect);
    const QColor fill = roll.m_sv->noteFillColor(selectedTrack, roll.m_lastVelocity);
    addRect(scene.layer(TimelineQuickLayer::PianoDrawPreviewFill), box, fill, plot);
}

void TimelineQuickView::rebuildNoteBordersAndSelection()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    if (!roll.m_sv->timeline())
        return;

    const qreal dpr = roll.devicePixelRatio();
    const qreal pixel = logicalPhysicalPixel(dpr);
    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
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

    const auto addSelectionRing = [&](const QRectF &box) {
        const int requested =
            (std::max)(lyt::singlePixel(), qRound(roll.m_geometry.selectionRingDipWidth * dpr));
        const int ring = fittedFrameThickness(box, requested, 0, dpr);
        if (ring > 0) {
            addFrame(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box,
                     themes::color(themes::Role::item_selected_background), ring, 0, dpr, plot);
            addNoteBorder(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box, ring, dpr,
                          plot);
        } else {
            addRect(scene.layer(TimelineQuickLayer::PianoNoteBordersAndSelection), box,
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
                                      timeRange.overlaps(note.startTick, note.endTick());
            if (ghost) {
                if (timeSelected)
                    addSelectionRing(box);
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
                addSelectionRing(box);
            } else {
                addNoteBorder(scene, TimelineQuickLayer::PianoNoteBordersAndSelection, box, 0, dpr,
                              plot);
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

    const qreal dpr = roll.devicePixelRatio();
    const qreal pixel = logicalPhysicalPixel(dpr);
    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
    const int selectedTrack = roll.m_sv->selectionModel().primaryTrack();

    if (roll.m_leftDrag == PianoRoll::LeftDrag::Draw) {
        const qreal x0 = roll.m_camera.displayX(double(roll.m_drawTick), 0.0, dpr);
        const qreal x1 =
            roll.m_camera.displayX(double(roll.m_drawTick + uint64_t(roll.m_drawDur)), 0.0, dpr);
        const QRectF previewRect = roll.noteRect(x0, x1, roll.m_drawKey);
        const QRectF box = roll.noteBox(previewRect);
        addNoteBorder(scene, TimelineQuickLayer::PianoOverlay, box, 0, dpr, plot);
    }

    const auto &selection = roll.m_sv->selectionModel();
    const auto &timeSelection = selection.timeSelection();
    const uint32_t usedTracks = usedTrackMask(roll.m_sv->timeline());
    if (roll.m_rightDrag == PianoRoll::RightDrag::Band) {
        const QRectF band = QRectF(roll.m_pressPos, roll.m_curPos).normalized().intersected(plot);
        QColor fill = themes::color(themes::Role::song_view_selection_fill);
        fill.setAlpha(30);
        addRect(scene.layer(TimelineQuickLayer::PianoOverlay), band, fill, plot);
        addDashedFrame(scene, TimelineQuickLayer::PianoOverlay, band,
                       themes::color(themes::Role::song_view_selection_edge), pixel,
                       lyt::space(Space::One), lyt::space(Space::One), plot);
    }

    if (selection.timeSelectionCoversTrack(selectedTrack, usedTracks) && timeSelection.active()) {
        const qreal x0 = roll.m_camera.displayX(double(timeSelection.startTick), 0.0, dpr);
        const qreal x1 = roll.m_camera.displayX(double(timeSelection.endTick), 0.0, dpr);
        QColor fill = themes::color(themes::Role::song_view_selection_fill);
        fill.setAlpha(30);
        addRect(scene.layer(TimelineQuickLayer::PianoOverlay),
                QRectF(x0, plot.top(), x1 - x0, plot.height()), fill, plot);
        addVerticalLine(scene.layer(TimelineQuickLayer::PianoOverlay), x0, plot.top(),
                        plot.bottom(), pixel, themes::color(themes::Role::song_view_selection_edge),
                        plot);
        addVerticalLine(scene.layer(TimelineQuickLayer::PianoOverlay), x1, plot.top(),
                        plot.bottom(), pixel, themes::color(themes::Role::song_view_selection_edge),
                        plot);
    }

    const MidiTimeline *timeline = roll.m_sv->timeline();
    if (timeline->loopStartTick != UINT64_MAX || timeline->loopEndTick != UINT64_MAX) {
        const bool hasStart = timeline->loopStartTick != UINT64_MAX;
        const bool hasEnd = timeline->loopEndTick != UINT64_MAX;
        const qreal x0 = hasStart
                             ? roll.m_camera.displayX(double(timeline->loopStartTick), 0.0, dpr)
                             : plot.left();
        const qreal x1 =
            hasEnd ? roll.m_camera.displayX(double(timeline->loopEndTick), 0.0, dpr) : plot.right();
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
                addVerticalLine(scene.layer(TimelineQuickLayer::PianoOverlay), x0, plot.top(),
                                plot.bottom(), pixel, detail::loopEdge(), plot);
            if (hasEnd)
                addVerticalLine(scene.layer(TimelineQuickLayer::PianoOverlay), x1, plot.top(),
                                plot.bottom(), pixel, detail::loopEdge(), plot);
        }
    }
}

void TimelineQuickView::rebuildKeyboardKeys()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF viewport(0, 0, keyboardWidth, roll.bounds().height());
    const qreal pixel = logicalPhysicalPixel(roll.devicePixelRatio());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const auto &edges = roll.rowEdges();
    if (projection.visibleRowCount() > 0) {
        addRect(scene.layer(TimelineQuickLayer::PianoKeyboardKeys),
                QRectF(0, edges[0], keyboardWidth, edges[projection.visibleRowCount()] - edges[0]),
                themes::color(themes::Role::song_view_piano_keyboard_natural_key), viewport);
    }
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = roll.pitchRowRect(row, 0, keyboardWidth);
        if (!rowRect.intersects(viewport))
            continue;
        if (isBlackKey(key)) {
            addRect(scene.layer(TimelineQuickLayer::PianoKeyboardKeys), rowRect,
                    themes::color(themes::Role::song_view_piano_keyboard_black_key), viewport);
        } else if (key % 12 == 0 || key % 12 == 5) {
            addHorizontalLine(scene.layer(TimelineQuickLayer::PianoKeyboardKeys), 0, keyboardWidth,
                              rowRect.bottom(), pixel,
                              themes::color(themes::Role::song_view_piano_keyboard_separator),
                              viewport);
        }
    }
}

void TimelineQuickView::rebuildKeyboardHighlights()
{
    PianoRoll &roll = *m_roll;
    TimelineQuickScene &scene = *m_scene;
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF viewport(0, 0, keyboardWidth, roll.bounds().height());
    const qreal pixel = logicalPhysicalPixel(roll.devicePixelRatio());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    const auto hoverGeometry = roll.keyboardHoverGeometry(roll.m_hoverKey);
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = roll.pitchRowRect(row, 0, keyboardWidth);
        if (!rowRect.intersects(viewport))
            continue;
        const bool sounding = key == roll.m_soundingKey;
        if (sounding) {
            addRect(scene.layer(TimelineQuickLayer::PianoKeyboardHighlights), rowRect,
                    themes::color(themes::Role::song_view_piano_keyboard_active_key), viewport);
            if (!isBlackKey(key) && (key % 12 == 0 || key % 12 == 5)) {
                addHorizontalLine(scene.layer(TimelineQuickLayer::PianoKeyboardHighlights), 0,
                                  keyboardWidth, rowRect.bottom(), pixel,
                                  themes::color(themes::Role::song_view_piano_keyboard_separator),
                                  viewport);
            }
        }
        if (key == roll.m_hoverKey && !sounding && hoverGeometry) {
            QColor highlight = roll.palette().color(QPalette::Highlight);
            highlight.setAlpha(80);
            addRect(scene.layer(TimelineQuickLayer::PianoKeyboardHighlights),
                    hoverGeometry->highlightRect, highlight, viewport);
        }
    }
    addVerticalLine(scene.layer(TimelineQuickLayer::PianoKeyboardHighlights), 0, 0,
                    roll.bounds().height(), pixel, themes::color(themes::Role::song_view_separator),
                    viewport);
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

    const qreal dpr = roll.devicePixelRatio();
    const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
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

    std::optional<QFontMetricsF> velocityMetrics = std::nullopt;
    if (velocityFontVisible) {
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
        if (nameFontVisible && roll.noteNameFits(noteRect, roll.displayedNoteKey(note))) {
            const qreal inset = lyt::space(Space::Half);
            appendTextRecord(records,
                             noteTextKey(TimelineQuickTextKeyKind::PianoNoteName, note, noteIndex),
                             QRectF(box.left() + inset, box.top() + inset,
                                    std::max<qreal>(0, box.width() - 2.0 * inset),
                                    std::max<qreal>(0, box.height() - 2.0 * inset)),
                             keyName(roll.displayedNoteKey(note)), *roll.m_noteNameFont,
                             contrastingTextColor(fill), Qt::AlignLeft, Qt::AlignVCenter);
        }
        if (velocityFontVisible) {
            const QString text = QString::number(velocity);
            if (noteRect.width() >= velocityMetrics->horizontalAdvance(text) +
                                        roll.m_geometry.velocityLabelFitAllowance) {
                appendTextRecord(
                    records,
                    noteTextKey(TimelineQuickTextKeyKind::PianoNoteVelocity, note, noteIndex), box,
                    text, *roll.m_velocityLabelFont, contrastingTextColor(fill), Qt::AlignHCenter,
                    Qt::AlignVCenter);
            }
        }
    }

    if (roll.m_leftDrag == PianoRoll::LeftDrag::Draw && velocityShortcut &&
        roll.m_velocityLabelFont) {
        const qreal x0 = roll.m_camera.displayX(double(roll.m_drawTick), 0.0, dpr);
        const qreal x1 =
            roll.m_camera.displayX(double(roll.m_drawTick + uint64_t(roll.m_drawDur)), 0.0, dpr);
        const QRectF previewRect = roll.noteRect(x0, x1, roll.m_drawKey);
        const QRectF box = roll.noteBox(previewRect);
        const QString text = QString::number(roll.m_lastVelocity);
        const QColor fill = roll.m_sv->noteFillColor(selectedTrack, roll.m_lastVelocity);
        if (previewRect.width() >=
            velocityMetrics->horizontalAdvance(text) + roll.m_geometry.velocityLabelFitAllowance) {
            appendTextRecord(records, drawPreviewTextKey, box, text, *roll.m_velocityLabelFont,
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
        const QRectF plot(0, 0, roll.bounds().width(), roll.bounds().height());
        appendTextRecord(records, loadingTextKey, plot, SongView::tr("Loading..."),
                         typography::caption(roll.font()),
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
    const qreal keyboardWidth = roll.m_geometry.pianoKeyboardWidth;
    const QRectF viewport(0, 0, keyboardWidth, roll.bounds().height());
    const PitchProjection &projection = roll.m_sv->pitchProjection();
    if (roll.m_keyboardLabelFont) {
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
                keyName(key), *roll.m_keyboardLabelFont, color, Qt::AlignRight, Qt::AlignVCenter);
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
                          QColor(0x30, 0x30, 0x30, 230), hoverGeometry->chipFont,
                          roll.m_geometry.keyboardHoverChipCornerRadius);
}

void TimelineQuickView::syncPianoRoll(PianoRollQuickDirtySet dirty)
{
    if (!m_roll)
        return;
    TimelineQuickScene &scene = *m_scene;
    const auto rebuild = [&](PianoRollQuickDirty flag, TimelineQuickLayer layer,
                             void (TimelineQuickView::*builder)()) {
        if (!(dirty & flag))
            return;
        resetLayer(scene.layer(layer));
        (this->*builder)();
        if (TimelineQuickItem *item = m_items[static_cast<std::size_t>(layer)])
            item->update();
    };

    rebuild(PianoRollQuickDirty::GridRows, TimelineQuickLayer::PianoGridRows,
            &TimelineQuickView::rebuildGridRows);
    rebuild(PianoRollQuickDirty::GridTime, TimelineQuickLayer::PianoGridTime,
            &TimelineQuickView::rebuildGridTime);
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
