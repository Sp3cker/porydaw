import Foundation

/// Where a committed sample came from and how it was edited, so Edit can reopen the source.
public struct SampleProvenance: Sendable, Equatable {
    public var version = 1
    public var sourcePath = ""
    public var sourceSha256 = ""
    public var leftOnly = false
    public var sf2Zone = -1
    public var params = SampleEditParams()

    public init() {}

    private struct Source: Codable {
        let path: String
        let sha256: String
        let leftOnly: Bool
        let sf2Zone: Int

        private enum CodingKeys: String, CodingKey { case path, sha256, leftOnly, sf2Zone }

        init(path: String, sha256: String, leftOnly: Bool, sf2Zone: Int) {
            self.path = path; self.sha256 = sha256
            self.leftOnly = leftOnly; self.sf2Zone = sf2Zone
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            path = (try? box.decode(String.self, forKey: .path)) ?? ""
            sha256 = (try? box.decode(String.self, forKey: .sha256)) ?? ""
            leftOnly = (try? box.decode(Bool.self, forKey: .leftOnly)) ?? false
            if let value = try? box.decode(Double.self, forKey: .sf2Zone), value.isFinite,
                value >= Double(Int.min), value < Double(Int.max) {
                sf2Zone = Int(value)
            } else {
                sf2Zone = -1
            }
        }
    }

    private struct Parameters: Codable {
        let cropStart: Int
        let cropEnd: Int
        let loopOn: Bool
        let loopStart: Int
        let loopEnd: Int
        let baseKey: Int
        let fineTuneCents: Double
        let targetRate: Double
        let normalizeMode: Int
        let dcRemove: Int
        let fadeIn: Bool
        let fadeOut: Bool
        let crossfadeOn: Bool
        let ditherOn: Bool
        let exactPitchOverride: UInt32

        init(_ p: SampleEditParams) {
            cropStart = p.cropStart; cropEnd = p.cropEnd; loopOn = p.loopOn
            loopStart = p.loopStart; loopEnd = p.loopEnd; baseKey = p.baseKey
            fineTuneCents = p.fineTuneCents; targetRate = p.targetRate
            normalizeMode = p.normalizeMode.rawValue; dcRemove = p.dcRemove.rawValue
            fadeIn = p.fadeIn; fadeOut = p.fadeOut; crossfadeOn = p.crossfadeOn
            ditherOn = p.ditherOn; exactPitchOverride = p.exactPitchOverride
        }

        private enum CodingKeys: String, CodingKey {
            case cropStart, cropEnd, loopOn, loopStart, loopEnd, baseKey, fineTuneCents, targetRate
            case normalizeMode, dcRemove, fadeIn, fadeOut, crossfadeOn, ditherOn, exactPitchOverride
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            guard !box.allKeys.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "Missing sample parameters"))
            }
            // QJsonObject stores these as doubles, even when the JSON token has a decimal/exponent.
            func whole(_ key: CodingKeys, default fallback: Int = 0) -> Int {
                guard let value = try? box.decode(Double.self, forKey: key), value.isFinite,
                    value >= Double(Int.min), value < Double(Int.max)
                else { return fallback }
                return Int(value)
            }
            cropStart = whole(.cropStart)
            cropEnd = whole(.cropEnd)
            loopOn = (try? box.decode(Bool.self, forKey: .loopOn)) ?? false
            loopStart = whole(.loopStart)
            loopEnd = whole(.loopEnd)
            baseKey = whole(.baseKey, default: 60)
            fineTuneCents = (try? box.decode(Double.self, forKey: .fineTuneCents)) ?? 0
            targetRate = (try? box.decode(Double.self, forKey: .targetRate)) ?? 0
            normalizeMode = min(3, max(0, whole(.normalizeMode)))
            dcRemove = min(2, max(0, whole(.dcRemove)))
            fadeIn = (try? box.decode(Bool.self, forKey: .fadeIn)) ?? true
            fadeOut = (try? box.decode(Bool.self, forKey: .fadeOut)) ?? true
            crossfadeOn = (try? box.decode(Bool.self, forKey: .crossfadeOn)) ?? false
            ditherOn = (try? box.decode(Bool.self, forKey: .ditherOn)) ?? false
            let pitch = (try? box.decode(Double.self, forKey: .exactPitchOverride)) ?? 0
            exactPitchOverride = pitch.isFinite && pitch >= 0 && pitch < 4_294_967_296
                ? UInt32(pitch) : 0
        }

        var editParams: SampleEditParams {
            var p = SampleEditParams()
            p.cropStart = cropStart; p.cropEnd = cropEnd; p.loopOn = loopOn
            p.loopStart = loopStart; p.loopEnd = loopEnd; p.baseKey = baseKey
            p.fineTuneCents = fineTuneCents; p.targetRate = targetRate
            p.normalizeMode = .init(rawValue: normalizeMode) ?? .auto
            p.dcRemove = .init(rawValue: dcRemove) ?? .auto
            p.fadeIn = fadeIn; p.fadeOut = fadeOut; p.crossfadeOn = crossfadeOn
            p.ditherOn = ditherOn; p.exactPitchOverride = exactPitchOverride
            return p
        }
    }

    private struct Document: Codable {
        let version: Int
        let source: Source
        let params: Parameters
    }

    /// Encodes the version-one keys without depending on key order.
    public func jsonData() -> Data {
        let document = Document(version: version,
            source: Source(path: sourcePath, sha256: sourceSha256, leftOnly: leftOnly, sf2Zone: sf2Zone),
            params: Parameters(params))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(document)) ?? Data()
    }

    /// Reads a version-one record with its missing-field defaults and enum bounds.
    public static func decode(_ data: Data) -> SampleProvenance? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data),
            document.version == 1, !document.source.path.isEmpty, !document.source.sha256.isEmpty
        else { return nil }
        var provenance = SampleProvenance()
        provenance.sourcePath = document.source.path
        provenance.sourceSha256 = document.source.sha256
        provenance.leftOnly = document.source.leftOnly
        provenance.sf2Zone = document.source.sf2Zone
        provenance.params = document.params.editParams
        return provenance
    }
}
