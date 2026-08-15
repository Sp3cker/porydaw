#pragma once

#include <QRectF>

#include <array>
#include <cstdint>

namespace songview {

// A pure row-to-pitch mapping for the piano roll. Fixed 128-pitch capacity,
// no heap allocation.
class PitchProjection
{
  public:
    static constexpr int cMaxRows = 128;
    static constexpr int cHiddenRow = -1;

    PitchProjection();

    // Build the full chromatic 0-127 projection (Off / Highlight mode).
    void buildChromatic();

    // Build from an explicit ascending set of visible pitches (Fold mode from
    // another wave). Pitches must be sorted unique; max 128.
    void buildFromPitches(const uint8_t *pitches, int count);

    int visibleRowCount() const { return m_visibleRowCount; }
    int visiblePitchAt(int row) const; // 0-based row index (top = row 0 = highest pitch)
    int rowForPitch(int midiPitch) const; // cHiddenRow if not visible

    // Set which pitches are scale pitches. By default all are scale pitches
    // (meaningful in Off/Highlight where every row is a scale row).
    void setScalePitchClassification(const bool *isScalePitch /* 128 entries */);
    bool isScalePitchRow(int row) const;

    // Nearest visible pitch for anchoring; lower pitch wins on tie.
    int nearestVisiblePitch(int midiPitch) const;

    // Total content height in DIPs at the given keyHeight.
    double totalHeight(double keyHeight) const { return m_visibleRowCount * keyHeight; }

    // Row-edge generation equivalent to the current rowEdges().
    // edges[0..visibleRowCount] at the given keyHeight and scrollY, DPR-snapped.
    void buildRowEdges(std::array<qreal, cMaxRows + 1> &edges, int &edgeCount,
                       double keyHeight, double scrollY, qreal dpr) const;

    // Top-edge position of a visible row (0-indexed).
    qreal rowTop(int row, double keyHeight, double scrollY, qreal dpr) const;
    qreal rowBottom(int row, double keyHeight, double scrollY, qreal dpr) const;

    // Row rect (keyboard column width).
    QRectF rowRect(int row, qreal x, qreal width, double keyHeight, double scrollY, qreal dpr) const;

    // Hit test: which visible row contains this y, or -1.
    int yToRow(qreal y, double keyHeight, double scrollY, qreal dpr) const;

    // MIDI pitch for the visible row under this y, or -1.
    int yToPitch(qreal y, double keyHeight, double scrollY, qreal dpr) const;

    uint64_t revision() const { return m_revision; }

  private:
    // Sorted high-to-low (key 127 at row 0).
    uint8_t m_visiblePitches[cMaxRows] = {};
    // Reverse lookup: pitch -> row index or sentinel.
    int8_t m_pitchToRow[128] = {};
    // Scale membership per row.
    bool m_scalePitchRow[cMaxRows] = {};
    int m_visibleRowCount = 0;
    uint64_t m_revision = 0;
};

} // namespace songview
