import BinaryParsing
import Foundation

public struct Sf2Zone: Sendable, Equatable {
    public var name: String = ""
    public var start: Int = 0
    public var end: Int = 0
    public var loopStart: Int = 0
    public var loopEndExclusive: Int = 0
    public var sampleRate: Int = 0
    public var originalPitch: Int = 60
    public var pitchCorrection: Int = 0
    public var sampleType: Int = 1
    public var instrument: String = ""
    public var preset: String = ""

    public var frames: Int { end - start }
    public var isStereoPair: Bool { sampleType == 2 || sampleType == 4 }
    public var hasLoop: Bool {
        loopStart >= start && loopEndExclusive <= end && loopEndExclusive - loopStart >= 2
    }
}

public struct Sf2File: Sendable {
    public var pool: Data
    public var zones: [Sf2Zone]
    public var sourcePath: String

    public init(pool: Data, zones: [Sf2Zone], sourcePath: String) {
        self.pool = pool
        self.zones = zones
        self.sourcePath = sourcePath
    }
}

public enum Sf2Reader {
    private struct Region {
        let start: Int
        let length: Int
    }

    private struct NamedRecord {
        let name: InlineArray<20, UInt8>
        let bag: Int
    }

    private struct Bag {
        let firstGenerator: Int
    }

    private struct Generator {
        let operation: Int
        let target: Int
    }

    private struct SampleHeader {
        let name: InlineArray<20, UInt8>
        let start: Int
        let end: Int
        let loopStart: Int
        let loopEndExclusive: Int
        let sampleRate: Int
        let originalPitch: Int
        let pitchCorrection: Int
        let sampleType: Int
    }

    private static func name(_ bytes: InlineArray<20, UInt8>) -> String {
        var scalars = String.UnicodeScalarView()
        for index in 0..<20 {
            let byte = bytes[index]
            if byte == 0 { break }
            // Every Latin-1 byte has a Unicode scalar; no intermediate byte array.
            if let scalar = UnicodeScalar(UInt32(byte)) { scalars.append(scalar) }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isSoundFont(_ bytes: Data) -> Bool {
        bytes.count >= 12 && bytes.prefix(4).elementsEqual("RIFF".utf8)
            && bytes.dropFirst(8).prefix(4).elementsEqual("sfbk".utf8)
    }

    public static func read(_ bytes: Data, sourcePath: String) throws(SampleImportFailure) -> Sf2File {
        guard isSoundFont(bytes) else { throw SampleImportFailure("not a SoundFont (.sf2) file.") }
        return try bytes.withParserSpan { (input: inout ParserSpan) throws(SampleImportFailure) in
            let data = input.bytes
            let corrupt = SampleImportFailure("the SoundFont file is corrupt or truncated.")
            var regions: [String: Region] = [:]

            // Parse each chunk header sequentially off one bounded span. Sizes are checked
            // before constructing a payload span or looking up any cross-record index.
            func header(_ offset: Int) throws(SampleImportFailure) -> (String, Int) {
                guard offset >= 0 && offset <= data.byteCount - 8 else { throw corrupt }
                var cursor = ParserSpan(data.extracting(offset..<(offset + 8)))
                var id = InlineArray<4, UInt8>(repeating: 0)
                for i in 0..<4 {
                    guard let byte = try? UInt8(parsing: &cursor) else { throw corrupt }
                    id[i] = byte
                }
                guard let size = try? UInt32(parsing: &cursor, endianness: .little) else { throw corrupt }
                let tag = String(decoding: [id[0], id[1], id[2], id[3]], as: UTF8.self)
                return (tag, Int(size))
            }

            var position = 12
            while position <= data.byteCount - 8 {
                let (id, size) = try header(position)
                let start = position + 8
                guard size <= data.byteCount - start else { throw corrupt }
                if id == "LIST" && size >= 4 {
                    let end = start + size
                    var sub = start + 4
                    while sub <= end - 8 {
                        let (subID, length) = try header(sub)
                        let payload = sub + 8
                        guard length <= end - payload else { throw corrupt }
                        if ["smpl", "phdr", "pbag", "pgen", "inst", "ibag", "igen", "shdr"].contains(subID),
                            regions[subID] == nil
                        {
                            regions[subID] = Region(start: payload, length: length)
                        }
                        sub = payload + length + (length & 1)
                    }
                }
                position = start + size + (size & 1)
            }
            guard let smpl = regions["smpl"] else {
                throw SampleImportFailure("the SoundFont has no sample data (smpl chunk).")
            }
            guard let shdr = regions["shdr"], shdr.length >= 46 else {
                throw SampleImportFailure("the SoundFont has no sample headers (shdr chunk).")
            }

            func records<T>(
                _ id: String, width: Int,
                decode: (inout ParserSpan) throws -> T
            ) throws(SampleImportFailure) -> [T] {
                guard let region = regions[id] else { return [] }
                var result: [T] = []
                result.reserveCapacity(region.length / width)
                for index in 0..<(region.length / width) {
                    let start = region.start + index * width
                    var record = ParserSpan(data.extracting(start..<(start + width)))
                    guard let value = try? decode(&record) else { throw corrupt }
                    result.append(value)
                }
                return result
            }
            func name(_ reader: inout ParserSpan) throws -> InlineArray<20, UInt8> {
                try InlineArray<20, UInt8>(parsing: &reader) { try UInt8(parsing: &$0) }
            }
            func u16(_ reader: inout ParserSpan) throws -> Int {
                Int(try UInt16(parsing: &reader, endianness: .little))
            }
            func u32(_ reader: inout ParserSpan) throws -> Int {
                Int(try UInt32(parsing: &reader, endianness: .little))
            }
            let presets = try records("phdr", width: 38) { reader in
                let label = try name(&reader)
                _ = try u16(&reader)  // preset
                _ = try u16(&reader)  // bank
                let bag = try u16(&reader)
                _ = try u32(&reader)  // library
                _ = try u32(&reader)  // genre
                _ = try u32(&reader)  // morphology
                return NamedRecord(name: label, bag: bag)
            }
            let presetBags = try records("pbag", width: 4) { reader in
                let first = try u16(&reader)
                _ = try u16(&reader)  // modulator
                return Bag(firstGenerator: first)
            }
            let presetGenerators = try records("pgen", width: 4) { reader in
                Generator(operation: try u16(&reader), target: try u16(&reader))
            }
            let instruments = try records("inst", width: 22) { reader in
                NamedRecord(name: try name(&reader), bag: try u16(&reader))
            }
            let instrumentBags = try records("ibag", width: 4) { reader in
                let first = try u16(&reader)
                _ = try u16(&reader)
                return Bag(firstGenerator: first)
            }
            let instrumentGenerators = try records("igen", width: 4) { reader in
                Generator(operation: try u16(&reader), target: try u16(&reader))
            }
            let headers = try records("shdr", width: 46) { reader in
                let label = try name(&reader)
                let start = try u32(&reader)
                let end = try u32(&reader)
                let loopStart = try u32(&reader)
                let loopEnd = try u32(&reader)
                let rate = try u32(&reader)
                let pitch = Int(try UInt8(parsing: &reader))
                let correction = Int(Int8(bitPattern: try UInt8(parsing: &reader)))
                _ = try u16(&reader)  // linked sample
                let kind = try u16(&reader)
                return SampleHeader(
                    name: label, start: start, end: end, loopStart: loopStart,
                    loopEndExclusive: loopEnd, sampleRate: rate, originalPitch: pitch,
                    pitchCorrection: correction, sampleType: kind)
            }
            var sampleInstrument = [Int](repeating: -1, count: headers.count)
            if instruments.count > 1 && instrumentBags.count > 1 {
                for i in 0..<(instruments.count - 1) {
                    let low = instruments[i].bag
                    let high = min(instruments[i + 1].bag, instrumentBags.count - 1)
                    if low >= high { continue }
                    for bag in low..<high {
                        let genLow = instrumentBags[bag].firstGenerator
                        let genHigh = min(instrumentBags[bag + 1].firstGenerator, instrumentGenerators.count)
                        if genLow >= genHigh { continue }
                        for gen in genLow..<genHigh where instrumentGenerators[gen].operation == 53 {
                            let sample = instrumentGenerators[gen].target
                            if sample < headers.count && sampleInstrument[sample] < 0 { sampleInstrument[sample] = i }
                        }
                    }
                }
            }
            var instrumentPreset = [Int](repeating: -1, count: instruments.count)
            if presets.count > 1 && presetBags.count > 1 {
                for i in 0..<(presets.count - 1) {
                    let low = presets[i].bag
                    let high = min(presets[i + 1].bag, presetBags.count - 1)
                    if low >= high { continue }
                    for bag in low..<high {
                        let genLow = presetBags[bag].firstGenerator
                        let genHigh = min(presetBags[bag + 1].firstGenerator, presetGenerators.count)
                        if genLow >= genHigh { continue }
                        for gen in genLow..<genHigh where presetGenerators[gen].operation == 41 {
                            let inst = presetGenerators[gen].target
                            if inst < instruments.count && instrumentPreset[inst] < 0 { instrumentPreset[inst] = i }
                        }
                    }
                }
            }
            var zones: [Sf2Zone] = []
            for (index, header) in headers.enumerated() {
                if header.sampleType & 0x8000 != 0 || header.end <= header.start
                    || header.end > (smpl.length & ~1) / 2 || header.sampleRate == 0
                {
                    continue
                }
                var zone = Sf2Zone()
                zone.name = Self.name(header.name)
                zone.start = header.start
                zone.end = header.end
                zone.loopStart = header.loopStart
                zone.loopEndExclusive = header.loopEndExclusive
                zone.sampleRate = header.sampleRate
                zone.originalPitch = header.originalPitch
                zone.pitchCorrection = header.pitchCorrection
                zone.sampleType = header.sampleType
                if sampleInstrument[index] >= 0 {
                    let inst = sampleInstrument[index]
                    zone.instrument = Self.name(instruments[inst].name)
                    if instrumentPreset[inst] >= 0 { zone.preset = Self.name(presets[instrumentPreset[inst]].name) }
                }
                zones.append(zone)
            }
            guard !zones.isEmpty else { throw SampleImportFailure("the SoundFont contains no importable samples.") }
            let pool = bytes.subdata(in: smpl.start..<(smpl.start + (smpl.length & ~1)))
            return Sf2File(pool: pool, zones: zones, sourcePath: sourcePath)
        }
    }

    public static func readFile(path: String) throws(SampleImportFailure) -> Sf2File {
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            throw SampleImportFailure("cannot read \(path).")
        }
        return try read(bytes, sourcePath: path)
    }

    public static func extractZone(_ file: Sf2File, index: Int) throws(SampleImportFailure) -> ImportedSample {
        guard file.zones.indices.contains(index) else { throw SampleImportFailure("no SoundFont zone selected.") }
        let zone = file.zones[index]
        guard zone.start >= 0, zone.end >= zone.start, zone.end <= file.pool.count / 2 else {
            throw SampleImportFailure("the SoundFont file is corrupt or truncated.")
        }
        var sample = ImportedSample(sourcePath: file.sourcePath, sourceKind: .sf2, sourceBits: 16)
        sample.suggestedName = SampleNames.sanitize(zone.name)
        if sample.suggestedName.isEmpty {
            sample.suggestedName = SampleNames.sanitize(
                URL(fileURLWithPath: file.sourcePath).deletingPathExtension().lastPathComponent)
        }
        sample.buffer = file.pool.withParserSpan { (input: inout ParserSpan) in
            let pcm = input.bytes
            return [Float](unsafeUninitializedCapacity: zone.frames) { output, initialized in
                for i in 0..<zone.frames {
                    let offset = (zone.start + i) * 2
                    let word = UInt16(pcm[offset]) | (UInt16(pcm[offset + 1]) << 8)
                    output[i] = Float(Double(Int16(bitPattern: word)) / 32768)
                }
                initialized = zone.frames
            }
        }
        sample.sampleRate = Double(zone.sampleRate)
        sample.playLength = zone.frames
        if zone.originalPitch <= 127 {
            let key = min(127.99, max(0, Double(zone.originalPitch) + Double(zone.pitchCorrection) / 100))
            sample.baseKey = Int(floor(key))
            sample.fracSemitone = key - floor(key)
            sample.hasPitchMetadata = true
        }
        if zone.hasLoop {
            sample.hasLoop = true
            sample.loopStart = zone.loopStart - zone.start
            sample.loopEndInclusive = zone.loopEndExclusive - zone.start - 1
        }
        if zone.isStereoPair { sample.warnings.append("stereo pair — imported one channel.") }
        return sample
    }
}
