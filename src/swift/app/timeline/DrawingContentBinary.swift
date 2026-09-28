import Foundation
import PorydawCore

enum DrawingContentBinary {
    static func frame<Kind>(_ sections: [(Kind, Data)], kindValue: (Kind) -> UInt16) -> Data {
        var data = Data()
        data.reserveCapacity(8 + sections.reduce(0) { $0 + 6 + $1.1.count })
        append(&data, UInt32(0x5054_4452))
        append(&data, UInt16(1))
        append(&data, UInt16(sections.count))
        for (kind, payload) in sections {
            append(&data, kindValue(kind))
            append(&data, UInt32(payload.count))
            data.append(payload)
        }
        return data
    }

    static func timeAxis(_ axis: TimeAxis, grid: RollGrid) -> Data {
        var d = Data()
        append(&d, grid.feel == .triplet ? UInt8(1) : UInt8(0))
        append(&d, grid.clockTicks)
        let selectionMode: UInt8
        let musicalDenominator: UInt32
        switch grid.selection {
        case .auto:
            selectionMode = 0
            musicalDenominator = 0
        case .clock:
            selectionMode = 2
            musicalDenominator = 0
        case .musical(let denominator):
            selectionMode = 1
            musicalDenominator = UInt32(clamping: denominator)
        }
        append(&d, selectionMode)
        append(&d, musicalDenominator)
        append(&d, UInt64(axis.loopStartTick))
        append(&d, UInt64(axis.loopEndTick))
        var segmentStarts: [Tick] = [0]
        for sig in axis.explicitTimeSignatures where sig.tick != segmentStarts.last {
            segmentStarts.append(sig.tick)
        }
        append(&d, UInt16(segmentStarts.count))
        for index in segmentStarts.indices {
            let start = segmentStarts[index]
            let next: Tick =
                index + 1 < segmentStarts.count
                ? segmentStarts[index + 1] : TimeDefaults.noTick
            let segment = axis.segmentAt(start)
            let signature = axis.signatureAt(start)
            append(&d, UInt64(start))
            append(&d, UInt64(next))
            append(&d, segment.beatTicks)
            append(&d, segment.beatsPerBar)
            append(&d, UInt32(clamping: signature.numerator))
            append(&d, UInt8(clamping: signature.denomPow2))
            append(&d, signature.implicit ? UInt8(1) : UInt8(0))
        }
        append(&d, grid.axis.ticksPerBeat)
        return d
    }

    static func append(_ data: inout Data, _ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
    static func append(_ data: inout Data, _ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
    static func append(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }
    static func append(_ data: inout Data, _ value: UInt8) {
        data.append(value)
    }
    static func append(_ data: inout Data, _ value: Int32) {
        append(&data, UInt32(bitPattern: value))
    }
    static func append(_ data: inout Data, _ value: Double) {
        append(&data, value.bitPattern)
    }
    static func append(_ data: inout Data, _ value: Float) {
        append(&data, value.bitPattern)
    }
}
