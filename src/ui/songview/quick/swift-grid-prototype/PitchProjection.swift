// PitchProjection.swift — Swift port of the songview row↔pitch mapping
// (src/ui/pitchprojection.h/.cpp, the production oracle). Pure Swift value
// type; no Qt, no Foundation. Row 0 is the TOP row = HIGHEST pitch.
// Later epics (TimeCamera feed, roll/paint surfaces) build on this at cutover.
//
// Deliberately deferred (spec §8): rowRect, buildRowEdges, revision().
// Equatable replaces revision; consumers compare values instead of a counter.

/// Piano-roll row↔pitch mapping; mirrors C++ `songview::PitchProjection`.
struct PitchProjection: Equatable {
    static let cMaxRows = 128
    static let cHiddenRow = -1

    /// Sorted high-to-low (pitch 127 at row 0).
    private var visiblePitches: [UInt8] = []
    /// Reverse lookup: pitch → row index or cHiddenRow; always 128 entries.
    private var pitchToRow: [Int] = Array(repeating: cHiddenRow, count: cMaxRows)
    /// Scale membership per visible row.
    private var scalePitchRow: [Bool] = []

    /// Default init = the chromatic build.
    init() {
        buildChromatic()
    }

    /// Full chromatic 0–127 projection; every row is a scale row.
    mutating func buildChromatic() {
        pitchToRow = Array(repeating: PitchProjection.cHiddenRow, count: PitchProjection.cMaxRows)
        scalePitchRow = Array(repeating: true, count: PitchProjection.cMaxRows)
        visiblePitches = Array(repeating: 0, count: PitchProjection.cMaxRows)
        for row in 0..<PitchProjection.cMaxRows {
            let pitch = PitchProjection.cMaxRows - 1 - row
            visiblePitches[row] = UInt8(pitch)
            pitchToRow[pitch] = row
        }
    }

    /// Fold build over an explicit ascending pitch set. Preconditions (fail
    /// loud in debug AND release — `precondition`, not `assert`): sorted
    /// strictly ascending (hence unique), at most 128 entries, each < 128.
    mutating func buildFromPitches(_ pitches: [UInt8]) {
        precondition(pitches.count <= PitchProjection.cMaxRows, "fold exceeds cMaxRows")
        for pitch in pitches {
            precondition(pitch < 128, "fold pitch out of 0–127")
        }
        if pitches.count > 1 {
            for i in 1..<pitches.count {
                precondition(pitches[i] > pitches[i - 1], "fold pitches must be strictly ascending")
            }
        }
        pitchToRow = Array(repeating: PitchProjection.cHiddenRow, count: PitchProjection.cMaxRows)
        scalePitchRow = Array(repeating: true, count: pitches.count)
        visiblePitches = Array(repeating: 0, count: pitches.count)
        let count = pitches.count
        for row in 0..<count {
            let pitch = pitches[count - 1 - row]
            visiblePitches[row] = pitch
            pitchToRow[Int(pitch)] = row
        }
    }

    var visibleRowCount: Int { visiblePitches.count }

    /// Pitch at a visible row; row 0 = highest pitch.
    func visiblePitch(at row: Int) -> Int {
        precondition(row >= 0 && row < visiblePitches.count, "row out of range")
        return Int(visiblePitches[row])
    }

    /// Row for a MIDI pitch, or cHiddenRow when hidden/out of 0–127.
    func row(forPitch midiPitch: Int) -> Int {
        if midiPitch < 0 || midiPitch >= 128 {
            return PitchProjection.cHiddenRow
        }
        return pitchToRow[midiPitch]
    }

    /// Scale classification indexed BY PITCH (128 entries), mirroring
    /// `m_scalePitchRow[row] = isScalePitch[m_visiblePitches[row]]`.
    mutating func setScalePitchClassification(_ isScalePitch: [Bool]) {
        precondition(isScalePitch.count == PitchProjection.cMaxRows, "classification needs 128 by-pitch entries")
        for row in 0..<visiblePitches.count {
            scalePitchRow[row] = isScalePitch[Int(visiblePitches[row])]
        }
    }

    func isScalePitch(row: Int) -> Bool {
        precondition(row >= 0 && row < visiblePitches.count, "row out of range")
        return scalePitchRow[row]
    }

    /// Nearest visible pitch for anchoring; lower pitch wins ties,
    /// below range → lowest visible, above range → highest visible,
    /// empty build → cHiddenRow.
    func nearestVisiblePitch(to midiPitch: Int) -> Int {
        if visiblePitches.isEmpty {
            return PitchProjection.cHiddenRow
        }
        // Binary search over the descending array for the first row whose
        // pitch is not higher than the query (mirrors the C++ oracle loop).
        var firstNotHigher = 0
        var end = visiblePitches.count
        while firstNotHigher < end {
            let middle = firstNotHigher + (end - firstNotHigher) / 2
            if Int(visiblePitches[middle]) > midiPitch {
                firstNotHigher = middle + 1
            } else {
                end = middle
            }
        }
        if firstNotHigher == 0 {
            return Int(visiblePitches[0])
        }
        if firstNotHigher == visiblePitches.count {
            return Int(visiblePitches[visiblePitches.count - 1])
        }
        let lower = Int(visiblePitches[firstNotHigher])
        let higher = Int(visiblePitches[firstNotHigher - 1])
        return abs(midiPitch - lower) <= abs(higher - midiPitch) ? lower : higher
    }

    /// Total content height at the given keyHeight.
    func totalHeight(keyHeight: Double) -> Double {
        return Double(visiblePitches.count) * keyHeight
    }

    /// DPR-snapped top edge of a row boundary (mirrors the C++ oracle's
    /// snappedRowEdge: half AWAY from zero, scale 1 when dpr ≤ 0).
    private func snappedRowEdge(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double {
        let scale = dpr > 0 ? dpr : 1
        return ((Double(row) * keyHeight - scrollY) * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    func rowTop(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double {
        precondition(row >= 0 && row < visiblePitches.count, "row out of range")
        return snappedRowEdge(row, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
    }

    func rowBottom(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double {
        precondition(row >= 0 && row < visiblePitches.count, "row out of range")
        return snappedRowEdge(row + 1, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
    }

    /// Visible row containing y (half-open rows), or cHiddenRow.
    func yToRow(_ y: Double, keyHeight: Double, scrollY: Double, dpr: Double) -> Int {
        if visiblePitches.isEmpty || y < rowTop(0, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
            || y >= rowBottom(visiblePitches.count - 1, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
        {
            return PitchProjection.cHiddenRow
        }
        var first = 0
        var end = visiblePitches.count
        while first < end {
            let middle = first + (end - first) / 2
            if y < snappedRowEdge(middle + 1, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr) {
                end = middle
            } else {
                first = middle + 1
            }
        }
        return first
    }

    /// MIDI pitch for the visible row under y, or cHiddenRow.
    func yToPitch(_ y: Double, keyHeight: Double, scrollY: Double, dpr: Double) -> Int {
        let row = yToRow(y, keyHeight: keyHeight, scrollY: scrollY, dpr: dpr)
        return row == PitchProjection.cHiddenRow ? PitchProjection.cHiddenRow : visiblePitch(at: row)
    }
}
