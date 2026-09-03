#pragma once

#include <QFont>
#include <QFontMetrics>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <QWidget>
#include <cstdint>
#include <vector>

class QComboBox;
class QMouseEvent;
class QWheelEvent;
class SongView;

namespace songview {

class TimelineQuickScene;
class TimelineQuickView;

class TimeRuler : public QWidget
{
  private:
    struct Geometry {
        int plotOrigin;
        int timelineDetailMinimumPixelsPerBeat;
        int timeRulerMinimumFontPixelSize;
        qreal timeRulerLetterSpacing;
        qreal timeRulerBeatLabelZoomFactor;

        static Geometry resolve();
    };

  public:
    explicit TimeRuler(SongView *sv);
    void syncGridControls();
    void cancelTransientInput();
    bool gestureActive() const;

  protected:
    void wheelEvent(QWheelEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;

  private:
    friend class TimelineQuickView;
    void rebuildQuickScene(TimelineQuickScene &scene);
    void requestQuickUpdate();
    QRect markerRow() const;
    QRect tickRow() const;
    int textBaseline(const QRect &row, const QFontMetrics &metrics) const;

    // Loop-marker and selection-edge grab zones live in the marker row —
    // where the bracket glyphs and edge handles are drawn — so the tick row
    // always scrubs the edit cursor even directly on a marker line.

    // 0 = start marker, 1 = end marker, -1 = neither near pos.
    int hitMarker(QPointF pos) const;

    // One time-signature chip as laid out in the marker row.
    struct SigChip {
        uint64_t tick;
        int numerator;
        int denomPow2;
        bool implicit; // no 0x58 meta behind it (editing one creates the event)
        qreal x;       // stem position (widget coords)
        qreal labelX;  // label left edge, nudged right past a loop bracket
        qreal labelW;  // 0: label hidden behind the next chip (stem only)
    };

    // Chip layout shared by the Quick scene builder and hit-testing: shadowed
    // same-tick duplicates dropped, labels nudged past a loop bracket glyph
    // sitting on the same spot, and a label hidden (stem only) when it would
    // run into the next chip — zooming in separates them again.
    std::vector<SigChip> sigChips() const;

    // Chip hit-test in the ruler's top half, including the placeholder 4/4
    // at tick 0. Fills the chip's tick and values.
    bool hitTimeSigChip(QPointF pos, uint64_t *tick, int *numerator, int *denomPow2,
                        bool *implicit) const;

    // Values in effect at tick (4/4 before any 0x58 meta).
    void sigAtTick(uint64_t tick, int *numerator, int *denomPow2) const;

    // 0 = selection start edge, 1 = end edge, -1 = neither near pos.
    int hitSelEdge(QPointF pos) const;

    void showRulerMenu(uint64_t clickTick, const QPoint &globalPos);

    QFont m_signatureFont;
    QFont m_rulerFont;
    QFont m_beatFont;
    QFont m_boldRulerFont;
    // Metrics of the fixed fonts above, built once in the constructor;
    // row heights, label widths, and baselines reuse them.
    QFontMetrics m_rulerMetrics{QFont{}};
    QFontMetrics m_beatMetrics{QFont{}};
    QFontMetrics m_boldRulerMetrics{QFont{}};
    QFontMetrics m_signatureMetrics{QFont{}};
    SongView *m_sv;
    Geometry m_geometry;
    int m_markerHeight = 0;
    int m_dragMarker = -1;
    uint64_t m_dragTick = 0;
    bool m_dragTimeSig = false;     // chip drag is live; commits moveTimeSig
    uint64_t m_dragTimeSigFrom = 0; // the dragged signature's original tick
    bool m_leftPress = false;       // plain click vs. time-selection sweep undecided
    bool m_rightPress = false;      // right click held until the ruler menu opens
    bool m_selSweep = false;        // left-drag time-selection sweep is live
    bool m_multiTrackSweep = false; // modifier intent captured when the sweep is armed
    QPointF m_leftPressPos;
    QPointF m_rightPressPos;
    uint64_t m_selAnchor = 0;         // snapped tick of the pending press
    int m_dragSelEdge = -1;           // selection edge being left-dragged (0/1)
    QComboBox *m_divCombo = nullptr;  // minimum snap subdivision (gutter)
    QComboBox *m_feelCombo = nullptr; // straight / triplet
    QWidget *m_gridBox = nullptr;
};

} // namespace songview
