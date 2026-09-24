import Foundation
import PorydawCore

/// Effective reverb when a song has no explicit reverb flag.
public let kDefaultReverb: Int = 50

/// Parses and merges mid2agb options without losing unrelated raw flags.
public enum SongFlags {
    /// Parses known options while retaining the original flags, including duplicates.
    /// - Parameter flags: The option strings in file order.
    /// - Returns: The parsed song configuration.
    public static func fromRaw(_ flags: [String]) -> SongConfig {
        var cfg = SongConfig(rawFlags: flags, voicegroupArgument: "")
        for flag in flags {
            guard flag.first == "-", let option = flag.dropFirst().first else { continue }
            let arg = String(flag.dropFirst(2))
            switch option.uppercased() {
            case "G": cfg.voicegroupArgument = arg
            case "V": cfg.masterVolume = clamp(arg)
            case "R": cfg.reverb = clamp(arg)
            case "P": cfg.priority = Int(arg) ?? 0
            case "E": cfg.exactGate = true
            case "X": cfg.extendedClocks = true
            case "N": cfg.noCompression = true
            default: break
            }
        }
        return cfg
    }

    /// Updates the first matching raw option per letter, preserving unrelated flags and their order.
    /// - Parameter cfg: The configuration and its original raw flags.
    /// - Returns: The merged option strings.
    public static func merge(_ cfg: SongConfig) -> [String] {
        var flags = cfg.rawFlags
        func setValue(_ letter: String, _ value: String?) {
            if let index = flags.firstIndex(where: {
                $0.first == "-" && $0.dropFirst().first?.uppercased() == letter
            }) {
                if let value {
                    flags[index] = "-" + letter + value
                } else {
                    flags.remove(at: index)
                }
            } else if let value {
                flags.append("-" + letter + value)
            }
        }

        setValue("E", cfg.exactGate ? "" : nil)
        setValue("R", cfg.reverb.map(String.init))
        setValue("G", cfg.voicegroupArgument.isEmpty ? nil : cfg.voicegroupArgument)
        setValue("V", String(format: "%03d", cfg.masterVolume))
        setValue("P", cfg.priority == 0 ? nil : String(cfg.priority))
        setValue("X", cfg.extendedClocks ? "" : nil)
        setValue("N", cfg.noCompression ? "" : nil)
        return flags
    }

    private static func clamp(_ arg: String) -> Int {
        min(127, max(0, Int(arg) ?? 0))
    }
}
