// ---------------------------------------------------------------- PianoRoll painting

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/selectionreticle.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"
#include "ui/theme/themeruntime.h"
#include "ui/typography.h"

#include <QApplication>
#include <QFontMetrics>
#include <QPainter>

#include <algorithm>
#include <array>
#include <cmath>
#include <optional>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview {
using namespace songview::detail;
using namespace songview::pianoroll_detail;

void PianoRoll::paintContent(QPainter &p)
{
    p.fillRect(rect(), themes::color(themes::Role::song_view_piano_roll_background));
    if (!m_sv->timeline()) {
        drawKeyboard(p);
        return;
    }

    const QRect grid(m_geometry.pianoKeyboardWidth, lyt::space(Space::Zero),
                     width() - m_geometry.pianoKeyboardWidth, height());
    // Narrow, never replace: the cached-surface painter arrives clipped
    // to the dirty region and partial repaints must stay inside it.
    p.save();
    p.setClipRect(grid, Qt::IntersectClip);

    // Pitch row shading plus a hairline under every semitone row; C rows
    // keep the stronger octave delineator, on the same snapped edge as
    // the keyboard column's separators.
    const QColor accidentalRow = pianoRollAccidentalLaneColor();
    const QColor octaveLine = themes::color(themes::Role::song_view_piano_keyboard_separator);
    const QPen keyLinePen(gridLineColor(50), lyt::space(Space::Zero));
    const QPen octavePen(octaveLine, lyt::space(Space::Zero));
    const PitchProjection &projection = m_sv->pitchProjection();
    const std::array<qreal, PitchProjection::cMaxRows + 1> &edges = rowEdges();
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = pitchRowRect(row, grid.left(), grid.width());
        if (rowRect.bottom() <= lyt::space(Space::Zero) || rowRect.top() >= height())
            continue;
        if (isBlackKey(key))
            p.fillRect(rowRect, accidentalRow);
        p.setPen(key % 12 == 0 ? octavePen : keyLinePen);
        p.drawLine(QLineF(grid.left(), rowRect.bottom(), grid.right(), rowRect.bottom()));
    }

    if (m_sv->scaleHighlight()) {
        const QColor tint = pianoRollScaleHighlightColor();
        for (int row = 0; row < projection.visibleRowCount(); ++row) {
            if (projection.isScalePitchRow(row)) {
                p.fillRect(
                    QRectF(grid.left(), edges[row], grid.width(), edges[row + 1] - edges[row]),
                    tint);
            }
        }
    }

    drawPreRoll(p, m_sv, grid, m_geometry.pianoKeyboardWidth,
                themes::color(themes::Role::song_view_piano_roll_background));
    m_sv->paintGrid(p, grid, m_geometry.pianoKeyboardWidth);

    // Notes: ghost pass (unselected tracks), then the selected track.
    const SongViewModel &model = m_sv->model();
    const auto &selectionModel = m_sv->selectionModel();
    const int selected = selectionModel.primaryTrack();
    const auto &timeSelection = selectionModel.timeSelection();
    const SongDocument::TimeRange timeRange{timeSelection.startTick, timeSelection.endTick};
    const uint32_t usedTracks = usedTrackMask(m_sv->timeline());
    const uint32_t timeSelectedTracks =
        timeSelection.active() && timeSelection.scope == EditorSelectionModel::TimeSelection::Tracks
            ? selectionModel.resolvedTrackScope(usedTracks)
            : 0;
    drawNotes(p, model, selected, timeRange, timeSelectedTracks, true);
    drawNotes(p, model, selected, timeRange, timeSelectedTracks, false);
    drawDragPreview(p, model, selected);
    if (m_drag == Drag::Band) {
        paintSelectionReticle(p, QRectF(m_pressPos, m_curPos).normalized());
    }

    drawOverlays(p, m_sv, grid, m_geometry.pianoKeyboardWidth,
                 selectionModel.timeSelectionCoversTrack(selected, usedTracks));

    p.restore();
    drawKeyboard(p);
}

void PianoRoll::drawNotes(QPainter &painter, const SongViewModel &model, int selectedTrack,
                          const SongDocument::TimeRange &timeRange, uint32_t timeSelectedTracks,
                          bool drawingGhostNotes)
{
    const bool velocityShortcut = keymap::Registry::instance().matchesModifier(
        QApplication::queryKeyboardModifiers(), QStringLiteral("roll.velocity_drag"));
    const bool showVelocityValues =
        !drawingGhostNotes && (m_drag == Drag::Velocity || velocityShortcut);
    // Velocity values are optional at tight zoom levels; never force a
    // minimum face that can clip vertically. The face fits the note box,
    // not the row pitch: the row includes the hairline gap under the box,
    // and a face fitted to the rounded pitch pushes digit ink across the
    // note's bottom border on 1x displays.
    const bool velocityFontVisible = showVelocityValues && m_velocityLabelFont.has_value();
    if (velocityFontVisible)
        painter.setFont(*m_velocityLabelFont);

    // Note-name labels use a fixed face two layout pixels below caption.
    // Each visible active-track note independently shows its label only
    // when its complete name fits with two trailing spaces; the velocity
    // shortcut replaces it with the note's velocity value.
    const bool nameFontVisible = !drawingGhostNotes && !showVelocityValues &&
                                 m_sv->noteNameMode() && m_noteNameFont.has_value();
    if (nameFontVisible)
        painter.setFont(*m_noteNameFont);

    const auto drawSelectionRing = [&](const QRectF &noteBox, const ViewNote &note) {
        const QColor selectionColor = themes::color(themes::Role::item_selected_background);
        // The ring thins before it disappears; the black border insets by
        // whatever ring actually fit. Insets are physical pixels too, so
        // fractional display scale cannot change either thickness.
        const int ringThickness =
            drawRectFrame(painter, noteBox, selectionColor,
                          std::max(lyt::singlePixel(),
                                   qRound(m_geometry.selectionRingDipWidth * devicePixelRatioF())));
        if (ringThickness > 0) {
            drawNoteBoxBorder(painter, noteBox, note.unterminated, m_geometry.noteBorderDashLength,
                              m_geometry.noteBorderDashGap, ringThickness);
        } else {
            // At extreme zoom there is no room for a frame plus a face.
            // Keep the note visible as a solid selection mark.
            painter.fillRect(noteBox, selectionColor);
        }
    };

    for (size_t noteIndex = 0; noteIndex < model.notes.size(); ++noteIndex) {
        const ViewNote &note = model.notes[noteIndex];
        const bool isGhostNote = note.track != selectedTrack;
        const int renderedVelocity = m_sv->previewVelocity(note.noteId).value_or(note.velocity);
        if (isGhostNote != drawingGhostNotes)
            continue;
        if (isGhostNote && m_sv->scaleFold() &&
            m_sv->pitchProjection().rowForPitch(note.key) == PitchProjection::cHiddenRow) {
            continue;
        }
        const QRectF noteRect = displayedNoteRect(note);
        if (noteRect.right() < m_geometry.pianoKeyboardWidth || noteRect.left() > width())
            continue;
        if (noteRect.bottom() < lyt::space(Space::Zero) || noteRect.top() > height())
            continue;

        const QRectF noteBox = this->noteBox(noteRect);
        const bool timeSelected = (timeSelectedTracks & (1u << note.track)) &&
                                  timeRange.overlaps(note.startTick, note.endTick);
        if (isGhostNote) {
            painter.fillRect(noteBox, ghostNoteColor(note.track, isBlackKey(note.key)));
            if (timeSelected)
                drawSelectionRing(noteBox, note);
            continue;
        }

        const QColor fill = m_sv->noteFillColor(note.track, renderedVelocity);
        painter.fillRect(noteBox, fill);

        if (nameFontVisible)
            drawNoteName(painter, noteRect, noteBox, displayedNoteKey(note), fill);

        // While velocity is active, every current-track note shows its
        // value instead of the pitch label.
        if (velocityFontVisible) {
            const QString velocityText = QString::number(renderedVelocity);
            if (noteRect.width() >= painter.fontMetrics().horizontalAdvance(velocityText) +
                                        m_geometry.velocityLabelFitAllowance) {
                painter.save();
                painter.setClipRect(noteBox, Qt::IntersectClip);
                painter.setPen(contrastingTextColor(fill));
                painter.drawText(noteBox, Qt::AlignCenter, velocityText);
                painter.restore();
            }
        }

        const bool selected =
            timeSelected ||
            (note.track == selectedTrack && note.noteId.isAssigned() &&
             m_sv->selectionModel().isNoteSelected(note.noteId)) ||
            (m_drag == Drag::Band &&
             std::any_of(m_bandAud.begin(), m_bandAud.end(), [&note](const ViewNote &covered) {
                 return covered.noteId == note.noteId;
             }));
        if (selected) {
            drawSelectionRing(noteBox, note);
        } else {
            drawNoteBoxBorder(painter, noteBox, note.unterminated, m_geometry.noteBorderDashLength,
                              m_geometry.noteBorderDashGap, 0);
        }
    }
}

bool PianoRoll::noteNameFits(const QRectF &noteRect, int key, const QFontMetricsF &metrics) const
{
    const auto textInset = lyt::space(Space::Half);
    const QString name = keyName(key);
    return noteRect.width() >= textInset + metrics.horizontalAdvance(name) + lyt::space(Space::Two);
}

void PianoRoll::drawNoteName(QPainter &painter, const QRectF &noteRect, const QRectF &noteBox,
                             int key, const QColor &fill)
{
    const QString name = keyName(key);
    if (!noteNameFits(noteRect, key, QFontMetricsF(painter.font())))
        return;
    const auto textInset = lyt::space(Space::Half);
    const QRectF labelRect(noteBox.left() + textInset, noteBox.top() + textInset, 512.0,
                           noteBox.height() - 2.0 * textInset);
    painter.save();
    painter.setClipRect(noteBox, Qt::IntersectClip);
    painter.setPen(contrastingTextColor(fill));
    painter.drawText(labelRect, Qt::AlignLeft | Qt::AlignVCenter, name);
    painter.restore();
}

void PianoRoll::drawDragPreview(QPainter &p, const SongViewModel &model, int selected)
{
    Q_UNUSED(model);
    if (m_drag != Drag::Draw)
        return;
    const qreal dpr = p.device()->devicePixelRatioF();
    const qreal x0 = m_sv->displayX(double(m_drawTick), m_geometry.pianoKeyboardWidth, dpr);
    const qreal x1 = m_sv->displayX(double(m_drawTick + uint64_t(m_drawDur)),
                                    m_geometry.pianoKeyboardWidth, dpr);
    const QRectF r = noteRect(x0, x1, m_drawKey);
    const QRectF box = noteBox(r);
    const QColor fill = m_sv->noteFillColor(selected, m_lastVelocity);
    p.fillRect(box, fill);
    drawNoteBoxBorder(p, box, false, m_geometry.noteBorderDashLength, m_geometry.noteBorderDashGap,
                      0);
    // While the velocity shortcut is held, the pending note follows the
    // same value-instead-of-pitch policy as existing notes.
    const auto &keys = keymap::Registry::instance();
    if (keys.matchesModifier(QApplication::queryKeyboardModifiers(),
                             QStringLiteral("roll.velocity_drag"))) {
        if (m_velocityLabelFont) {
            p.setFont(*m_velocityLabelFont);
            const auto velocityText = QString::number(m_lastVelocity);
            if (r.width() >= p.fontMetrics().horizontalAdvance(velocityText) + 4) {
                p.save();
                p.setClipRect(box, Qt::IntersectClip);
                p.setPen(contrastingTextColor(fill));
                p.drawText(box, Qt::AlignCenter, velocityText);
                p.restore();
            }
        }
    }
}

void PianoRoll::drawKeyboard(QPainter &p)
{
    const int keyH = int(std::lround(m_sv->keyHeight()));
    const PitchProjection &projection = m_sv->pitchProjection();
    const std::array<qreal, PitchProjection::cMaxRows + 1> &edges = rowEdges();
    if (projection.visibleRowCount() > 0) {
        p.fillRect(QRectF(0, edges[0], m_geometry.pianoKeyboardWidth,
                          edges[projection.visibleRowCount()] - edges[0]),
                   themes::color(themes::Role::song_view_piano_keyboard_natural_key));
    }
    // Natural-key labels disappear when no real font face fits the lane.
    if (m_keyboardLabelFont)
        p.setFont(*m_keyboardLabelFont);
    const int hovered = m_hoverKey;
    const QPen separatorPen(themes::color(themes::Role::song_view_piano_keyboard_separator),
                            lyt::space(Space::Zero));
    const auto hoverGeometry = keyboardHoverGeometry(hovered);
    for (int row = 0; row < projection.visibleRowCount(); ++row) {
        const int key = projection.visiblePitchAt(row);
        const QRectF rowRect = pitchRowRect(row, 0, m_geometry.pianoKeyboardWidth);
        if (rowRect.bottom() <= lyt::space(Space::Zero) || rowRect.top() >= height())
            continue;
        const bool sounding = key == m_soundingKey;
        if (isBlackKey(key)) {
            p.fillRect(rowRect,
                       sounding ? themes::color(themes::Role::song_view_piano_keyboard_active_key)
                                : themes::color(themes::Role::song_view_piano_keyboard_black_key));
        } else {
            if (sounding) {
                p.fillRect(rowRect,
                           themes::color(themes::Role::song_view_piano_keyboard_active_key));
            }
            // B/C and E/F are the only spots where two natural
            // keys touch, so those bottom edges get a separator.
            if (key % 12 == 0 || key % 12 == 5) {
                p.setPen(separatorPen);
                p.drawLine(QLineF(lyt::space(Space::Zero), rowRect.bottom(),
                                  m_geometry.pianoKeyboardWidth, rowRect.bottom()));
            }
            if (key % 12 == 0) {
                p.setPen(themes::color(themes::Role::song_view_piano_keyboard_label));
                if (m_keyboardLabelFont) {
                    p.drawText(QRectF(lyt::space(Space::Zero), rowRect.top(),
                                      m_geometry.pianoKeyboardWidth -
                                          m_geometry.pianoKeyboardLabelRightInset,
                                      rowRect.height()),
                               Qt::AlignRight | Qt::AlignVCenter, keyName(key));
                }
            }
        }
        if (key == hovered && !sounding && hoverGeometry) {
            QColor h = m_sv->palette().color(QPalette::Highlight);
            h.setAlpha(80);
            p.fillRect(hoverGeometry->highlightRect, h);
        }
    }
    // Note-name chip on the hovered row: keys can be as short as 4px,
    // so the name gets its own fixed-size readout instead of in-row
    // text, vertically clamped so edge rows stay readable.
    if (hoverGeometry) {
        p.setFont(hoverGeometry->chipFont);
        p.save();
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0x30, 0x30, 0x30, 230));
        p.drawRoundedRect(hoverGeometry->chipRect, m_geometry.keyboardHoverChipCornerRadius,
                          m_geometry.keyboardHoverChipCornerRadius);
        p.setPen(Qt::white);
        p.drawText(hoverGeometry->chipRect, Qt::AlignCenter, hoverGeometry->name);
        p.restore();
    }
    p.setPen(themes::color(themes::Role::song_view_separator));
    p.drawLine(lyt::space(Space::Zero), lyt::space(Space::Zero), lyt::space(Space::Zero), height());
}

void PianoRoll::auditionBandEntrants(const QRectF &band)
{
    std::vector<ViewNote> inBand;
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track != m_sv->selectionModel().primaryTrack() || !noteRect(note).intersects(band))
            continue;
        const auto found =
            std::find_if(m_bandAud.begin(), m_bandAud.end(),
                         [&](const ViewNote &old) { return old.noteId == note.noteId; });
        if (found == m_bandAud.end())
            m_sv->auditionTimed(note.track, note.key, note.velocity, note.startTick, note.endTick);
        inBand.push_back(note);
    }
    for (const ViewNote &old : m_bandAud) {
        const auto found = std::find_if(inBand.begin(), inBand.end(), [&](const ViewNote &note) {
            return note.noteId == old.noteId;
        });
        if (found != inBand.end())
            continue;
        // Previews are one-per-key: keep the key sounding while the band
        // still covers another note of the same pitch.
        const bool keyCovered =
            std::any_of(inBand.begin(), inBand.end(),
                        [&](const ViewNote &note) { return note.key == old.key; });
        if (!keyCovered)
            m_sv->auditionTimedOff(m_sv->selectionModel().primaryTrack(), old.key);
    }
    m_bandAud = std::move(inBand);
}

void PianoRoll::stopBandAuditions()
{
    for (const ViewNote &note : m_bandAud)
        m_sv->auditionTimedOff(m_sv->selectionModel().primaryTrack(), note.key);
    m_bandAud.clear();
}

} // namespace songview
