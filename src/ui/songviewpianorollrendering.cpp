#include "ui/songviewpianorollinternal.hpp"

#include <QPainter>
#include <QPalette>
#include <QPen>

#include <algorithm>
#include <climits>

#include "core/mid2agbtables.h"
#include "ui/songview.h"

namespace songview::piano_roll_rendering {

namespace
{

constexpr int kEdgeW = 3;

QColor loopFill()
{
    return QColor(255, 200, 60, 16);
}

QColor loopEdge()
{
    return QColor(224, 168, 0);
}


int velocityHandleHeight(const QRect &noteRect)
{
    return std::clamp(noteRect.height() / 3, 2, 6);
}

} // namespace
QColor playheadColor()
{
    return QColor(226, 66, 66);
}


bool isBlackKey(int key)
{
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
}

int keyToY(const SongView &songView, int key)
{
    return (127 - key) * songView.keyHeight() - songView.scrollY();
}

int yToKey(const SongView &songView, int y)
{
    return std::clamp(127 - (y + songView.scrollY()) / songView.keyHeight(), 0, 127);
}

QRect noteRect(const SongView &songView, uint64_t startTick, uint64_t endTick, int key)
{
    const int x0 = kKeyboardW + songView.contentX(double(startTick));
    const int x1 = kKeyboardW + songView.contentX(double(endTick));
    return QRect(x0, keyToY(songView, key) + 1, std::max(2, x1 - x0),
                 std::max(2, songView.keyHeight() - 1));
}

QRect noteRect(const SongView &songView, const ViewNote &note)
{
    return noteRect(songView, note.startTick, note.endTick, note.key);
}

bool nearRightEdge(const SongView &songView, const ViewNote &note, QPoint position)
{
    const QRect rect = noteRect(songView, note);
    return position.x() >= rect.right() - kEdgeW && position.x() <= rect.right() + kEdgeW;
}

bool nearLeftEdge(const SongView &songView, const ViewNote &note, QPoint position)
{
    const QRect rect = noteRect(songView, note);
    return position.x() >= rect.left() - kEdgeW && position.x() <= rect.left() + kEdgeW;
}

bool nearVelocityHandle(const SongView &songView, const ViewNote &note, QPoint position)
{
    if (songView.keyHeight() < kVelHandleMinKeyH)
        return false;
    const QRect rect = noteRect(songView, note);
    return position.x() > rect.left() + kEdgeW && position.x() < rect.right() - kEdgeW
           && position.y() < rect.top() + velocityHandleHeight(rect);
}

void drawOverlays(QPainter &painter, const SongView &songView, const QRect &rect,
                  int origin, bool timeSelectionCovered)
{
    const MidiTimeline *timeline = songView.timeline();
    if (!timeline)
        return;
    const SongView::TimeSelection &selection = songView.timeSelection();
    if (timeSelectionCovered && selection.active()) {
        const int x0 = origin + songView.contentX(double(selection.startTick));
        const int x1 = origin + songView.contentX(double(selection.endTick));
        if (x1 > rect.left() && x0 < rect.right()) {
            QColor fill = songView.palette().color(QPalette::Highlight);
            fill.setAlpha(30);
            painter.fillRect(QRect(QPoint(std::max(x0, rect.left()), rect.top()),
                                   QPoint(std::min(x1, rect.right()), rect.bottom())),
                             fill);
            painter.setPen(QPen(songView.palette().color(QPalette::Highlight), 1));
            painter.drawLine(x0, rect.top(), x0, rect.bottom());
            painter.drawLine(x1, rect.top(), x1, rect.bottom());
        }
    }
    if (timeline->loopStartTick != UINT64_MAX || timeline->loopEndTick != UINT64_MAX) {
        const int x0 = timeline->loopStartTick != UINT64_MAX
                           ? origin + songView.contentX(double(timeline->loopStartTick))
                           : rect.left();
        const int x1 = timeline->loopEndTick != UINT64_MAX
                           ? origin + songView.contentX(double(timeline->loopEndTick))
                           : rect.right();
        if (x1 > rect.left() && x0 < rect.right()) {
            painter.fillRect(QRect(QPoint(std::max(x0, rect.left()), rect.top()),
                                   QPoint(std::min(x1, rect.right()), rect.bottom())),
                             loopFill());
            painter.setPen(loopEdge());
            if (timeline->loopStartTick != UINT64_MAX)
                painter.drawLine(x0, rect.top(), x0, rect.bottom());
            if (timeline->loopEndTick != UINT64_MAX)
                painter.drawLine(x1, rect.top(), x1, rect.bottom());
        }
    }
    const int editCursorX = origin + songView.contentX(double(songView.editCursorTick()));
    if (editCursorX >= rect.left() && editCursorX <= rect.right()) {
        painter.setPen(QPen(songView.palette().color(QPalette::WindowText), 1,
                            Qt::DashLine));
        painter.drawLine(editCursorX, rect.top(), editCursorX, rect.bottom());
    }
    const int playheadX = origin + songView.contentX(songView.playheadTick());
    if (playheadX >= rect.left() && playheadX <= rect.right()) {
        painter.setPen(QPen(playheadColor(), 1));
        painter.drawLine(playheadX, rect.top(), playheadX, rect.bottom());
    }
}

void drawKeyboard(QPainter &painter, const SongView &songView, int height,
                  int soundingKey)
{
    const int keyHeight = songView.keyHeight();
    painter.fillRect(QRect(0, 0, kKeyboardW, height), QColor(0xf4, 0xf4, 0xf4));
    QFont font = painter.font();
    font.setPixelSize(std::min(10, keyHeight));
    painter.setFont(font);
    for (int key = 0; key < 128; key++) {
        const int y = keyToY(songView, key);
        if (y + keyHeight < 0 || y > height)
            continue;
        const bool sounding = key == soundingKey;
        if (isBlackKey(key)) {
            painter.fillRect(QRect(0, y, kKeyboardW * 3 / 5, keyHeight),
                             sounding ? songView.palette().color(QPalette::Highlight)
                                      : QColor(0x2e, 0x2e, 0x2e));
        } else {
            if (sounding)
                painter.fillRect(QRect(0, y, kKeyboardW, keyHeight),
                                 songView.palette().color(QPalette::Highlight));
            if (key % 12 == 0) {
                painter.setPen(QColor(0x9a, 0x9a, 0x9a));
                painter.drawLine(0, y + keyHeight, kKeyboardW, y + keyHeight);
                painter.setPen(QColor(0x50, 0x50, 0x50));
                if (keyHeight >= 7)
                    painter.drawText(QRect(0, y, kKeyboardW - 3, keyHeight),
                                     Qt::AlignRight | Qt::AlignVCenter, midiKeyName(key));
            }
        }
    }
    painter.setPen(songView.palette().color(QPalette::Mid));
    painter.drawLine(kKeyboardW - 1, 0, kKeyboardW - 1, height);
}

} // namespace songview::piano_roll_rendering
