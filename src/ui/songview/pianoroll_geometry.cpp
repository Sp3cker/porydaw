// ---------------------------------------------------------------- PianoRoll geometry

#include "ui/songview/pianoroll.h"

#include "ui/keymap.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/detail.h"

#include <QApplication>
#include <QFontMetrics>
#include <QIcon>
#include <QPainter>
#include <QPixmap>

#include <algorithm>
#include <cmath>

namespace lyt = ::layout;
using Space = lyt::Space;

namespace songview::pianoroll_detail {
using namespace songview::detail;

PianoRollGeometry PianoRollGeometry::resolve()
{
    return {lyt::fontPx(10.0),      lyt::fontPx(13.0 / 3.0), lyt::fontPx(2.0),
            lyt::fontPx(1.0 / 6.0), lyt::fontPx(1.0 / 6.0),  lyt::fontPxF(0.25),
            lyt::fontPxF(0.5),      lyt::fontPx(1.0),        lyt::fontPx(5.0 / 3.0),
            lyt::fontPx(1.0 / 6.0), lyt::fontPx(1.0 / 6.0),  lyt::fontPxF(1.0 / 8.0),
            lyt::fontPx(1.0 / 3.0), lyt::fontPx(1.0 / 6.0),  lyt::fontPx(2.0 / 3.0),
            lyt::fontPx(1.0 / 6.0), lyt::fontPx(1.0 / 6.0),  lyt::fontPx(1.0 / 2.0),
            lyt::fontPx(0.25),      lyt::fontPx(0.25)};
}

QRectF velocityBarRect(const QRectF &noteRect, int velocity, qreal dpr,
                       const PianoRollGeometry &geometry)
{
    const qreal pixel = qreal(lyt::singlePixel()) / dpr;
    const qreal inset = geometry.velocityHandleInset * pixel;
    const qreal barH = qRound(noteRect.height() / pixel) >= geometry.velocityHandleTallNoteThreshold
                           ? geometry.velocityHandleBarThickness * pixel
                           : pixel;
    const qreal innerH = noteRect.height() - inset;
    const qreal y = std::min(noteRect.top() + pixel + (127 - velocity) * (innerH - pixel) / 127.0,
                             noteRect.bottom() - pixel - barH);
    return QRectF(noteRect.left() + pixel, y, std::max(pixel, noteRect.width() - inset), barH);
}
QCursor centeredCursor(const QPixmap &pm)
{
    const qreal dpr =
        QGuiApplication::platformName() == QLatin1String("xcb") ? 1.0 : pm.devicePixelRatio();
    return QCursor(pm, qRound(pm.width() / (2.0 * dpr)), qRound(pm.height() / (2.0 * dpr)));
}
MidiCursors loadMidiCursors(qreal devicePixelRatio, int cursorExtent)
{
    const QSize cursorSize(cursorExtent, cursorExtent);
    const QIcon leftEdge(QStringLiteral(":/cursors/left-drag.png"));
    const QIcon rightEdge(QStringLiteral(":/cursors/right-drag.png"));
    return {devicePixelRatio, centeredCursor(leftEdge.pixmap(cursorSize, devicePixelRatio)),
            centeredCursor(rightEdge.pixmap(cursorSize, devicePixelRatio))};
}
QRectF noteFrame(const QPainter &painter, const QRectF &noteRect, int insetPixels)
{
    const qreal physicalPixel = logicalPhysicalPixel(painter.device()->devicePixelRatioF());
    const qreal insetDips = insetPixels * physicalPixel;
    return noteRect
        .adjusted(lyt::space(Space::Zero), lyt::space(Space::Zero), -physicalPixel, -physicalPixel)
        .adjusted(insetDips, insetDips, -insetDips, -insetDips);
}
int fittedFrameThickness(const QPainter &painter, const QRectF &rect, int requestedPixels,
                         int insetPixels)
{
    const qreal devicePixelRatio = painter.device()->devicePixelRatioF();
    const int heightPixels = qRound(rect.height() * devicePixelRatio);
    return std::clamp((heightPixels - lyt::singlePixel()) / 2 - insetPixels,
                      lyt::space(Space::Zero), requestedPixels);
}
int drawRectFrame(QPainter &painter, const QRectF &rect, const QColor &color, int thicknessPixels,
                  int insetPixels)
{
    thicknessPixels = fittedFrameThickness(painter, rect, thicknessPixels, insetPixels);
    if (thicknessPixels <= lyt::space(Space::Zero))
        return lyt::space(Space::Zero);

    // Paint one solid ring around the note box. Separate cosmetic outlines
    // can quantize onto non-adjacent device rows at fractional scale
    // factors, exposing the note face between them.
    const qreal devicePixelRatio = painter.device()->devicePixelRatioF();
    const qreal physicalPixel = logicalPhysicalPixel(devicePixelRatio);
    const qreal insetDips = insetPixels * physicalPixel;
    const qreal thicknessDips = thicknessPixels * physicalPixel;
    const QRectF frame = rect.adjusted(insetDips, insetDips, -insetDips, -insetDips);
    painter.fillRect(QRectF(frame.left(), frame.top(), frame.width(), thicknessDips), color);
    painter.fillRect(
        QRectF(frame.left(), frame.bottom() - thicknessDips, frame.width(), thicknessDips), color);
    const qreal sideHeight = std::max(0.0, frame.height() - 2 * thicknessDips);
    painter.fillRect(QRectF(frame.left(), frame.top() + thicknessDips, thicknessDips, sideHeight),
                     color);
    painter.fillRect(QRectF(frame.right() - thicknessDips, frame.top() + thicknessDips,
                            thicknessDips, sideHeight),
                     color);
    return thicknessPixels;
}
void drawNoteBoxBorder(QPainter &painter, const QRectF &noteBox, bool unterminated, int dashLength,
                       int dashGap, int insetPixels)
{
    const int borderPixels = songview::noteBorderPixels(painter.device()->devicePixelRatioF());
    if (!unterminated) {
        drawRectFrame(painter, noteBox, Qt::black, borderPixels, insetPixels);
        return;
    }
    const int thickness = fittedFrameThickness(painter, noteBox, borderPixels, insetPixels);
    if (thickness <= 0)
        return;

    painter.save();
    QPen borderPen(Qt::black, lyt::space(Space::Zero));
    borderPen.setCapStyle(Qt::FlatCap);
    borderPen.setJoinStyle(Qt::MiterJoin);
    borderPen.setDashPattern({qreal(dashLength), qreal(dashGap)});
    painter.setPen(borderPen);
    painter.setBrush(Qt::NoBrush);
    for (int pixel = 0; pixel < thickness; ++pixel)
        painter.drawRect(noteFrame(painter, noteBox, insetPixels + pixel));
    painter.restore();
}

} // namespace songview::pianoroll_detail

namespace songview {
using namespace songview::detail;
using namespace songview::pianoroll_detail;

QRectF velBarRect(const QRectF &noteRect, int velocity, qreal dpr)
{
    return velocityBarRect(noteRect, velocity, dpr, PianoRollGeometry::resolve());
}

int noteBorderPixels(qreal dpr)
{
    return std::max(lyt::singlePixel(), qRound(dpr));
}

int selectionRingPixels(qreal dpr)
{
    return std::max(lyt::singlePixel(),
                    qRound(PianoRollGeometry::resolve().selectionRingDipWidth * dpr));
}

bool PianoRoll::insideTimeSelection(qreal x) const
{
    const auto &sel = m_sv->selectionModel().timeSelection();
    if (!sel.active() ||
        !m_sv->selectionModel().timeSelectionCoversTrack(m_sv->selectionModel().primaryTrack(),
                                                         usedTrackMask(m_sv->timeline())))
        return false;
    const qreal dpr = devicePixelRatioF();
    const qreal startX = m_sv->displayX(double(sel.startTick), m_geometry.pianoKeyboardWidth, dpr);
    const qreal endX = m_sv->displayX(double(sel.endTick), m_geometry.pianoKeyboardWidth, dpr);
    return x >= startX && x < endX;
}

const std::array<qreal, PitchProjection::cMaxRows + 1> &PianoRoll::rowEdges() const
{
    const qreal dpr = devicePixelRatioF();
    const qreal keyHeight = m_sv->keyHeight();
    const qreal scrollY = m_sv->scrollY();
    const PitchProjection &projection = m_sv->pitchProjection();
    if (!m_rowEdgesValid || m_rowEdgesDpr != dpr || m_rowEdgesKeyHeight != keyHeight ||
        m_rowEdgesScrollY != scrollY || m_rowEdgesProjectionRevision != projection.revision()) {
        projection.buildRowEdges(m_rowEdges, m_rowEdgeCount, keyHeight, scrollY, dpr);
        m_rowEdgesDpr = dpr;
        m_rowEdgesKeyHeight = keyHeight;
        m_rowEdgesScrollY = scrollY;
        m_rowEdgesProjectionRevision = projection.revision();
        m_rowEdgesValid = true;
    }
    return m_rowEdges;
}

QRectF PianoRoll::pitchRowRect(int row, qreal x, qreal width) const
{
    const auto &edges = rowEdges();
    return QRectF(x, edges[row], width, edges[row + 1] - edges[row]);
}

qreal PianoRoll::keyTop(int key) const
{
    const int row = m_sv->pitchProjection().rowForPitch(key);
    return row == PitchProjection::cHiddenRow ? rowEdges()[0] : rowEdges()[row];
}

qreal PianoRoll::keyBottom(int key) const
{
    const int row = m_sv->pitchProjection().rowForPitch(key);
    return row == PitchProjection::cHiddenRow ? rowEdges()[0] : rowEdges()[row + 1];
}

QRectF PianoRoll::keyRect(int key, qreal x, qreal width) const
{
    const qreal top = keyTop(key);
    return QRectF(x, top, width, keyBottom(key) - top);
}

int PianoRoll::yToKey(qreal y) const
{
    return m_sv->pitchProjection().yToPitch(y, m_sv->keyHeight(), m_sv->scrollY(),
                                            devicePixelRatioF());
}

int PianoRoll::foldDegreeDeltaForPointer(qreal y) const
{
    const PitchProjection &projection = m_sv->pitchProjection();
    const int pointerRow =
        projection.yToRow(y, m_sv->keyHeight(), m_sv->scrollY(), devicePixelRatioF());
    const int grabRow = projection.rowForPitch(m_pressKey);
    if (pointerRow == PitchProjection::cHiddenRow || grabRow == PitchProjection::cHiddenRow)
        return 0;
    int degreeDelta = 0;
    if (pointerRow < grabRow) {
        for (int row = pointerRow; row < grabRow; row++) {
            if (projection.isScalePitchRow(row))
                degreeDelta++;
        }
    } else {
        for (int row = grabRow + 1; row <= pointerRow; row++) {
            if (projection.isScalePitchRow(row))
                degreeDelta--;
        }
    }
    return degreeDelta;
}

qreal PianoRoll::physicalPixel() const
{
    return logicalPhysicalPixel(devicePixelRatioF());
}

std::optional<PianoRoll::KeyboardHoverGeometry> PianoRoll::keyboardHoverGeometry(int key) const
{
    if (key < 0 || key >= int(m_keyboardHoverNameWidths.size()) ||
        m_sv->pitchProjection().rowForPitch(key) == PitchProjection::cHiddenRow)
        return std::nullopt;

    const QRectF highlight = keyRect(key, lyt::space(Space::Zero), m_geometry.pianoKeyboardWidth);
    const QString name = midiKeyName(key);
    const int chipWidth =
        m_keyboardHoverNameWidths[std::size_t(key)] + m_geometry.keyboardHoverChipHorizontalPadding;
    const int chipHeight = m_keyboardHoverChipHeight;
    const qreal chipY =
        std::clamp(highlight.center().y() - chipHeight / 2.0, qreal(lyt::space(Space::Zero)),
                   qreal(std::max(lyt::space(Space::Zero), height() - chipHeight)));
    const QRectF chip(m_geometry.pianoKeyboardWidth - m_geometry.keyboardHoverChipRightInset -
                          chipWidth,
                      chipY, chipWidth, chipHeight);
    QRegion paintRegion(chip.toAlignedRect());
    if (key != m_soundingKey)
        paintRegion |= QRegion(highlight.toAlignedRect());
    paintRegion &= QRegion(lyt::space(Space::Zero), lyt::space(Space::Zero),
                           m_geometry.pianoKeyboardWidth, height());
    return KeyboardHoverGeometry{highlight, name, m_keyboardHoverChipFont, chip, paintRegion};
}

void PianoRoll::setHoverKey(int key)
{
    if (key == m_hoverKey)
        return;
    const auto oldGeometry = keyboardHoverGeometry(m_hoverKey);
    const QRegion oldRegion = oldGeometry ? oldGeometry->paintRegion : QRegion();
    m_hoverKey = key;
    setProperty("hoverKey", m_hoverKey);
    const auto newGeometry = keyboardHoverGeometry(m_hoverKey);
    const QRegion newRegion = newGeometry ? newGeometry->paintRegion : QRegion();
    invalidateContent(oldRegion | newRegion);
}

void PianoRoll::invalidateTimeSelection(const SongDocument::TimeRange &previousRange,
                                        uint32_t previousTrackMask,
                                        const SongDocument::TimeRange &range, uint32_t trackMask)
{
    const QRect plotRect(m_geometry.pianoKeyboardWidth, lyt::space(Space::Zero),
                         width() - m_geometry.pianoKeyboardWidth, height());
    const auto bandRegion = [this, &plotRect](const SongDocument::TimeRange &timeRange,
                                              uint32_t tracks) {
        if (tracks == 0 || timeRange.endTick <= timeRange.startTick)
            return QRegion();
        const qreal dpr = devicePixelRatioF();
        const qreal x0 =
            m_sv->displayX(double(timeRange.startTick), m_geometry.pianoKeyboardWidth, dpr);
        const qreal x1 =
            m_sv->displayX(double(timeRange.endTick), m_geometry.pianoKeyboardWidth, dpr);
        return QRegion(QRectF(x0, lyt::space(Space::Zero), x1 - x0, height()).toAlignedRect())
            .intersected(plotRect);
    };
    const auto edgeRegion = [this, &plotRect](const SongDocument::TimeRange &timeRange,
                                              uint32_t tracks) {
        if (tracks == 0 || timeRange.endTick <= timeRange.startTick)
            return QRegion();
        const qreal dpr = devicePixelRatioF();
        const qreal edgeWidth = std::max<qreal>(physicalPixel(), lyt::singlePixel());
        QRegion edges;
        for (const uint64_t tick : {timeRange.startTick, timeRange.endTick}) {
            const qreal x = m_sv->displayX(double(tick), m_geometry.pianoKeyboardWidth, dpr);
            edges |= QRegion(QRectF(x - edgeWidth, lyt::space(Space::Zero), 2 * edgeWidth, height())
                                 .toAlignedRect());
        }
        return edges.intersected(plotRect);
    };
    const QRegion previousBand = bandRegion(previousRange, previousTrackMask);
    const QRegion band = bandRegion(range, trackMask);
    QRegion dirty = previousBand.subtracted(band) | band.subtracted(previousBand) |
                    edgeRegion(previousRange, previousTrackMask) | edgeRegion(range, trackMask);
    const auto selected = [](const SongDocument::TimeRange &timeRange, uint32_t tracks,
                             const ViewNote &note) {
        return note.track >= 0 && note.track < 16 && (tracks & (uint32_t{1} << note.track)) != 0 &&
               timeRange.overlaps(note.startTick, note.endTick);
    };
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.startTick >= previousRange.endTick && note.startTick >= range.endTick)
            break;
        if (selected(previousRange, previousTrackMask, note) == selected(range, trackMask, note)) {
            continue;
        }
        const QRect outerFrame = noteBox(displayedNoteRect(note)).toAlignedRect();
        const qreal dpr = devicePixelRatioF();
        const int frameInset = qCeil((selectionRingPixels(dpr) + noteBorderPixels(dpr)) / dpr);
        const QRect innerFrame =
            outerFrame.adjusted(frameInset, frameInset, -frameInset, -frameInset);
        QRegion frameRegion(outerFrame);
        if (!innerFrame.isEmpty())
            frameRegion -= innerFrame;
        dirty |= frameRegion;
    }
    dirty &= plotRect;
    if (dirty.isEmpty())
        return;
    qint64 dirtyArea = 0;
    for (const QRect &dirtyRect : dirty)
        dirtyArea += qint64(dirtyRect.width()) * qint64(dirtyRect.height());
    if (dirtyArea * 2 >= qint64(plotRect.width()) * qint64(plotRect.height()))
        invalidateContent();
    else
        invalidateContent(dirty);
}

QRectF PianoRoll::noteRect(qreal x0, qreal x1, int key) const
{
    const int row = m_sv->pitchProjection().rowForPitch(key);
    if (row == PitchProjection::cHiddenRow)
        return QRectF(x0, rowEdges()[0],
                      std::max<qreal>(m_geometry.pianoRollNoteMinimumWidth, x1 - x0), 0.0);
    const qreal pixel = physicalPixel();
    const std::array<qreal, PitchProjection::cMaxRows + 1> &edges = rowEdges();
    return QRectF(x0, edges[row] + pixel,
                  std::max<qreal>(m_geometry.pianoRollNoteMinimumWidth, x1 - x0),
                  std::max(m_geometry.pianoRollNoteMinimumHeight * pixel,
                           edges[row + 1] - edges[row] - pixel));
}

QRectF PianoRoll::noteRect(const ViewNote &note) const
{
    const qreal dpr = devicePixelRatioF();
    return noteRect(m_sv->displayX(double(note.startTick), m_geometry.pianoKeyboardWidth, dpr),
                    m_sv->displayX(double(note.endTick), m_geometry.pianoKeyboardWidth, dpr),
                    note.key);
}

QRectF PianoRoll::noteBox(const QRectF &rect) const
{
    return rect.adjusted(lyt::space(Space::Zero), lyt::space(Space::Zero), lyt::space(Space::Zero),
                         -physicalPixel());
}

int PianoRoll::velocityLabelHeight() const
{
    return int(std::floor(m_sv->keyHeight() - physicalPixel()));
}

const ViewNote *PianoRoll::hitNote(QPointF pos) const
{
    const int selected = m_sv->selectionModel().primaryTrack();
    const ViewNote *hit = nullptr;
    bool hitInside = false;
    const ViewNote *gripHit = nullptr; // pos inside the note, on an edge grip
    const qreal reach = m_geometry.pianoRollNoteEdgeGripReach;
    for (const ViewNote &note : m_sv->model().notes) {
        if (note.track != selected)
            continue;
        const QRectF r = noteRect(note);
        if (pos.y() < r.top() || pos.y() >= r.bottom())
            continue;
        const bool inside = pos.x() >= r.left() && pos.x() < r.right();
        if (inside || (pos.x() >= r.left() - reach && pos.x() < r.right() + reach)) {
            hit = &note;
            hitInside = inside;
        }
        if (inside && (nearRightEdge(note, pos) || nearLeftEdge(note, pos)))
            gripHit = &note;
    }
    return (gripHit && !hitInside) ? gripHit : hit;
}

bool PianoRoll::nearRightEdge(const ViewNote &note, QPointF pos) const
{
    const QRectF r = noteRect(note);
    return pos.x() >= r.right() - edgeGripInnerReach(r,
                                                     m_geometry.pianoRollNoteMoveZoneMinimumWidth,
                                                     m_geometry.pianoRollNoteEdgeGripReach) &&
           pos.x() <= r.right() + m_geometry.pianoRollNoteEdgeGripReach;
}

bool PianoRoll::nearLeftEdge(const ViewNote &note, QPointF pos) const
{
    const QRectF r = noteRect(note);
    return pos.x() >= r.left() - m_geometry.pianoRollNoteEdgeGripReach &&
           pos.x() <= r.left() + edgeGripInnerReach(r, m_geometry.pianoRollNoteMoveZoneMinimumWidth,
                                                    m_geometry.pianoRollNoteEdgeGripReach);
}

bool PianoRoll::nearVelocityHandle(const ViewNote &note, QPointF pos) const
{
    if (m_sv->keyHeight() < m_geometry.velocityHandleMinimumKeyHeight)
        return false;
    const QRectF r = noteRect(note);
    // The bar itself is 1-2px; grab within a few pixels of it, more
    // generously on taller notes.
    const QRectF bar = velocityBarRect(r, note.velocity, devicePixelRatioF(), m_geometry);
    const qreal pad = velocityHandlePointerHitPadding(r.height(), physicalPixel());
    const qreal inner = edgeGripInnerReach(r, m_geometry.pianoRollNoteMoveZoneMinimumWidth,
                                           m_geometry.pianoRollNoteEdgeGripReach);
    return pos.x() > r.left() + inner && pos.x() < r.right() - inner &&
           pos.y() >= bar.top() - pad && pos.y() < bar.bottom() + pad;
}

void PianoRoll::refreshHoverCursor(QPointF pos, Qt::KeyboardModifiers modifiers)
{
    if (m_cursors.dpr != devicePixelRatioF())
        m_cursors = loadMidiCursors(devicePixelRatioF(), m_geometry.midiCursorExtent);
    const ViewNote *hit =
        m_sv->document() && pos.x() >= m_geometry.pianoKeyboardWidth ? hitNote(pos) : nullptr;
    // Resize edges win over both velocity-hover paths.
    const auto &keys = keymap::Registry::instance();
    if (hit && nearRightEdge(*hit, pos))
        setCursor(m_cursors.rightEdge);
    else if (hit && nearLeftEdge(*hit, pos))
        setCursor(m_cursors.leftEdge);
    else if (hit && keys.matchesModifier(modifiers, QStringLiteral("roll.velocity_drag")))
        setCursor(Qt::SizeVerCursor);
    else if (hit && nearVelocityHandle(*hit, pos))
        setCursor(Qt::SizeVerCursor);
    else
        setCursor(Qt::ArrowCursor);
}

void PianoRoll::refreshHoverAtCursor()
{
    const QPoint local = mapFromGlobal(QCursor::pos());
    if (rect().contains(local))
        refreshHoverCursor(local, QApplication::keyboardModifiers());
}

QRectF PianoRoll::displayedNoteRect(const ViewNote &note) const
{
    const bool dragging =
        m_drag == Drag::Move || m_drag == Drag::Resize || m_drag == Drag::ResizeLeft;
    if (!dragging || note.track != m_sv->selectionModel().primaryTrack() ||
        !note.noteId.isAssigned() || !m_sv->selectionModel().isNoteSelected(note.noteId))
        return noteRect(note);
    int64_t tick, endTick;
    if (m_drag == Drag::ResizeLeft) {
        // The note-off pins the gesture; only the start moves.
        endTick = int64_t(note.endTick);
        tick = std::clamp<int64_t>(int64_t(note.startTick) + m_dTick, 0, endTick - 1);
    } else {
        tick = std::max<int64_t>(0, int64_t(note.startTick) + m_dTick);
        endTick = std::max<int64_t>(tick + 1, int64_t(note.endTick) + m_dTick + m_dDur);
    }
    const int key = displayedNoteKey(note);
    const qreal dpr = devicePixelRatioF();
    const qreal x0 = m_sv->displayX(double(tick), m_geometry.pianoKeyboardWidth, dpr);
    const qreal x1 = m_sv->displayX(double(endTick), m_geometry.pianoKeyboardWidth, dpr);
    return noteRect(x0, x1, key);
}

int PianoRoll::displayedNoteKey(const ViewNote &note) const
{
    const bool dragging =
        m_drag == Drag::Move || m_drag == Drag::Resize || m_drag == Drag::ResizeLeft;
    if (!dragging || note.track != m_sv->selectionModel().primaryTrack() ||
        !note.noteId.isAssigned() || !m_sv->selectionModel().isNoteSelected(note.noteId))
        return note.key;
    if (m_sv->scaleFold()) {
        const int destination = m_sv->nextScalePitch(note.key, m_dKey);
        return destination >= 0 ? destination : note.key;
    }
    return std::clamp(int(note.key) + m_dKey, 0, 127);
}

} // namespace songview
