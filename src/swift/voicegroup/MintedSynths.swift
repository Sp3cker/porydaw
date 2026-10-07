import Foundation

/// Decodes the canonical Golden Sun synth symbol and optional decimal collision suffix.
/// - Parameter symbol: The voice's exact assembler symbol.
/// - Returns: Its pulse, saw, or triangle descriptor, or nil for a non-minted symbol.
public func mintedSynthDesc(symbol: String) -> VgSynthDesc? {
    let stem = "DirectSoundSynth_GoldenSun_"
    guard symbol.hasPrefix(stem) else { return nil }
    let suffix = symbol.dropFirst(stem.count)
    if suffix == "Saw" || (suffix.hasPrefix("Saw") && mintedCollisionSuffix(suffix.dropFirst(3))) {
        return VgSynthDesc(waveform: 1)
    }
    if suffix == "Triangle" || (suffix.hasPrefix("Triangle") && mintedCollisionSuffix(suffix.dropFirst(8))) {
        return VgSynthDesc(waveform: 2)
    }
    let hex = suffix.prefix(8)
    guard hex.utf8.count == 8,
        hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
        mintedCollisionSuffix(suffix.dropFirst(8)),
        let packed = UInt32(hex, radix: 16)
    else { return nil }
    return VgSynthDesc(
        waveform: 0, baseDuty: Int((packed >> 24) & 0xff),
        dutyStep: Int((packed >> 16) & 0xff),
        modDepth: Int((packed >> 8) & 0xff), phase: Int(packed & 0xff))
}

private func mintedCollisionSuffix(_ suffix: Substring) -> Bool {
    if suffix.isEmpty { return true }
    guard suffix.first == "_" else { return false }
    let digits = suffix.dropFirst()
    return !digits.isEmpty && digits.utf8.allSatisfy { (48...57).contains($0) }
}
