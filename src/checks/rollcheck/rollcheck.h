#pragma once

#include <QColor>
#include <QImage>
#include <QPoint>
#include <QRect>
#include <QRectF>
#include <QString>
#include <QtGlobal>
#include <optional>

#include "core/songdocument.h"
#include "ui/songview.h"

class MidiTimeline;
class QQuickItem;

class SongTab;

namespace songview {
class PianoRoll;
class TimelineInputItem;
} // namespace songview

namespace checks::rollcheck {

struct Cell;

// Per-slot view fixture. SongTab owns the production documentChanged ->
// timeline rebuild connection, so test code never installs a mirror refresh.
class PianoRollFixture final
{
  public:
    PianoRollFixture(SongTab &tab, const QString &songLabel);
    ~PianoRollFixture() = default;

    PianoRollFixture(const PianoRollFixture &) = delete;
    PianoRollFixture &operator=(const PianoRollFixture &) = delete;

    bool prepare();

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    const MidiTimeline &timeline() const noexcept;
    // The roll interaction object (hover-key property, Quick update requests)
    // and the physically split Quick input items for the plot and key column.
    songview::PianoRoll &roll() noexcept;
    songview::TimelineInputItem &rollInput() noexcept;
    songview::TimelineInputItem &rollGutterInput() noexcept;
    QImage captureQuickFramebuffer();
    QImage captureQuickBand(const QRect &bandRect);
    QRect rollBandRect() const noexcept;
    int track() const noexcept;
    int pianoKeyboardWidth() const noexcept;
    int pianoRollDefaultKeyHeight() const noexcept;

    const QString &songLabel() const noexcept;
    bool isOccupied(uint64_t tick, uint64_t dur, int key, bool checkAllTracks = false);
    Cell findFreeCell(int firstProbe = 8, bool checkAllTracks = false, uint64_t seedDuration = 12);

  private:
    SongTab &m_tab;
    QString m_songLabel;
    songview::PianoRoll *m_roll = nullptr;
    songview::TimelineInputItem *m_rollInput = nullptr;
    songview::TimelineInputItem *m_rollGutterInput = nullptr;
    int m_track = -1;
    int m_pianoKeyboardWidth = 0;
    int m_pianoRollDefaultKeyHeight = 0;
};

// Test-side mirror of the roll's vertical projection. It intentionally samples
// the independently-snapped row bounds without exposing SongView paint geometry.
struct SnappedRows {
    const SongView &view;
    const songview::TimelineInputItem &roll;

    qreal dpr() const;
    qreal pixel() const;
    qreal edge(int row) const;
    qreal top(int key) const;
    qreal bottom(int key) const;
    int keyAt(qreal y) const;
    int centerY(int key) const;
    QRectF noteRect(qreal x0, qreal x1, int key) const;
    QRectF noteBox(const QRectF &rect) const;
};

bool isSelectionRingColor(QRgb pixel);

struct Cell {
    uint64_t tick = 0;
    uint64_t dur = 0;
    int key = -1;
    QPoint center;
};

struct PencilPaintingFixture {
    Cell a;
    DocNote noteA;
};

struct PencilVelocityFixture {
    Cell a;
    Cell b;
    DocNote noteA;
    DocNote noteB;
};

struct ResizeFixture {
    Cell cell;
    uint64_t snapCell = 0;
};

std::optional<PencilPaintingFixture> makePaintingSeed(PianoRollFixture &fixture);
std::optional<PencilVelocityFixture> makeVelocitySeed(PianoRollFixture &fixture);
std::optional<ResizeFixture> makeResizeSeed(PianoRollFixture &fixture);

void click(QQuickItem &item, QPoint position);
void drawNote(QQuickItem &item, QPoint position);
void sendKeyStroke(QObject &target, int key, Qt::KeyboardModifiers modifiers, bool autoRepeat);

} // namespace checks::rollcheck
