import Foundation
import PorydawCore

func checkScaleTables(_ report: CheckReport) {
    let table = "scalecheck/ScaleCheckTest::table"
    let expected: [(ScaleID, String, UInt16)] = [
        (.major, "Major", 0xAB5),
        (.naturalMinor, "Natural Minor", 0x5AD),
        (.dorian, "Dorian", 0x6AD),
        (.phrygian, "Phrygian", 0x5AB),
        (.lydian, "Lydian", 0xAD5),
        (.mixolydian, "Mixolydian", 0x6B5),
        (.locrian, "Locrian", 0x56B),
        (.harmonicMinor, "Harmonic Minor", 0x9AD),
        (.melodicMinor, "Melodic Minor", 0xAAD),
        (.harmonicMajor, "Harmonic Major", 0x9B5),
        (.majorPentatonic, "Major Pentatonic", 0x295),
        (.minorPentatonic, "Minor Pentatonic", 0x4A9),
        (.minorBlues, "Minor Blues", 0x4E9),
        (.wholeTone, "Whole Tone", 0x555),
        (.halfWholeDiminished, "Half-Whole Diminished", 0x6DB),
        (.wholeHalfDiminished, "Whole-Half Diminished", 0xB6D),
        (.dorianSharp4, "Dorian #4", 0x6CD),
        (.phrygianDominant, "Phrygian Dominant", 0x5B3),
        (.lydianAugmented, "Lydian Augmented", 0xB55),
        (.lydianDominant, "Lydian Dominant", 0x6D5),
        (.altered, "Altered (Super Locrian)", 0x55B),
        (.eightToneSpanish, "8-Tone Spanish", 0x57B),
        (.bhairav, "Bhairav", 0x9B3),
        (.hungarianMinor, "Hungarian Minor", 0x9CD),
        (.hirajoshi, "Hirajoshi", 0x18D),
        (.inSen, "In-Sen", 0x4A3),
        (.iwato, "Iwato", 0x463),
        (.kumoi, "Kumoi", 0x28D),
    ]
    for (index, row) in expected.enumerated() {
        report.expectEqual(expected: expected.count, actual: ScaleID.scaleCount, cppID: table, what: "scale count")
        report.expectEqual(expected: index, actual: row.0.rawValue, cppID: table, what: "scale identity order")
        report.expectEqual(expected: row.1, actual: row.0.displayName, cppID: table, what: "scale name")
        report.expectEqual(expected: row.2, actual: row.0.mask, cppID: table, what: "scale mask")
        report.expectEqual(expected: row.0, actual: ScaleID.displayOrder[index], cppID: table, what: "display order")
    }

    let roots = "scalecheck/ScaleCheckTest::rootsAndDefaults"
    let rootNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    report.expectEqual(expected: rootNames.count, actual: ScaleID.rootCount, cppID: roots, what: "root count")
    for index in 0..<ScaleID.rootCount {
        report.expectEqual(expected: rootNames[index], actual: ScaleID.rootDisplayName(index), cppID: roots,
                           what: "root name")
    }
    report.expectEqual(expected: ScaleID.major, actual: ScaleID.defaultScale, cppID: roots, what: "default scale")
    report.expectEqual(expected: 0, actual: ScaleID.defaultRoot, cppID: roots, what: "default root")

    let neighbors = "scalecheck/ScaleCheckTest::membershipAndNeighbors"
    report.expect(ScaleID.major.isPitch(60, root: 0), cppID: neighbors,
                  message: "C is a C-major pitch")
    report.expect(!ScaleID.major.isPitch(61, root: 0), cppID: neighbors,
                  message: "C# is not a C-major pitch")
    report.expect(ScaleID.major.isPitch(62, root: 2), cppID: neighbors,
                  message: "D is a D-major pitch")
    report.expect(!ScaleID.major.isPitch(60, root: 2), cppID: neighbors,
                  message: "C is not a D-major pitch")
    report.expectEqual(expected: 62, actual: ScaleID.major.firstPitchAbove(61, root: 0), cppID: neighbors,
                       what: "first pitch above C#")
    report.expectEqual(expected: 60, actual: ScaleID.major.firstPitchBelow(61, root: 0), cppID: neighbors,
                       what: "first pitch below C#")
    report.expectEqual(expected: -1, actual: ScaleID.major.firstPitchAbove(127, root: 0), cppID: neighbors,
                       what: "no pitch above top")
    report.expectEqual(expected: -1, actual: ScaleID.major.firstPitchBelow(0, root: 0), cppID: neighbors,
                       what: "no pitch below bottom")
    report.expectEqual(expected: 62, actual: ScaleID.major.pitch(60, steps: 1, root: 0), cppID: neighbors,
                       what: "one degree above C")
    report.expectEqual(expected: 60, actual: ScaleID.major.pitch(62, steps: -1, root: 0), cppID: neighbors,
                       what: "one degree below D")
    report.expectEqual(expected: 65, actual: ScaleID.major.pitch(60, steps: 3, root: 0), cppID: neighbors,
                       what: "three degrees above C")
    report.expectEqual(expected: 62, actual: ScaleID.major.pitch(67, steps: -3, root: 0), cppID: neighbors,
                       what: "three degrees below G")

    let diatonic = "scalecheck/ScaleCheckTest::diatonicDestinations"
    let rows: [(sources: [UInt8], steps: [Int], expected: [UInt8], accepted: Bool)] = [
        ([0x3C, 0x3D], [0x01, 0x01], [0x3E, 0x40], true),
        ([0x3D, 0x3E], [-0x01, -0x01], [0x3B, 0x3C], true),
        ([0x3C, 0x3C, 0x3D], [0x01, 0x04, 0x01], [0x3E, 0x3E, 0x40], true),
        ([0x3C, 0x3D, 0x3E], [0x01, 0x01, 0x01], [0x3E, 0x40, 0x41], true),
        ([0x7F], [0x01], [0xFF], false),
        ([0x00], [-0x01], [0xFF], false),
        ([0x3C], [0x01, 0x01], [0x2A], false),
    ]
    for row in rows {
        var destinations = [UInt8](repeating: 42, count: row.expected.count)
        let result = ScaleID.resolveDiatonicDestinations(
            scale: .major, root: 0, sources: row.sources, steps: row.steps, dests: &destinations)
        report.expectEqual(expected: row.accepted, actual: result, cppID: diatonic, what: "diatonic resolution")
        report.expectEqual(expected: row.expected, actual: destinations, cppID: diatonic, what: "diatonic destination")
    }
}
