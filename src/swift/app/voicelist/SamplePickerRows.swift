import Foundation
import QtBridge
import PorydawAppPresentation

@MainActor
@QtBridgeable
public final class SamplePickerRow {
    public var symbol: String = ""
    public var label: String = ""
    public var split: Bool = false
    public var typed: Bool = false
    public var loops: Bool = false
    public var detail: String = ""
    @QtIgnored var current = SamplePickerEntry()
    @QtIgnored
    func apply(_ value: SamplePickerEntry) -> Bool {
        guard current != value else { return false }
        current = value
        publish(\.symbol, value.symbol)
        publish(\.label, value.label)
        publish(\.split, value.split)
        publish(\.typed, value.typed)
        publish(\.loops, value.loops)
        publish(\.detail, value.detail)
        return true
    }
}

struct SamplePickerEntry: Equatable {
    var symbol = ""
    var label = ""
    var split = false
    var typed = false
    var loops = false
    var detail = ""
}

extension VoiceListController {
    func refreshSamplePickerDetails() {
        samplePickerDetails = pickerSampleInfo.mapValues { info in
            let mode = info.looped ? "Loops" : "One-shot"
            let seconds = String(
                format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), info.seconds)
            return "\(mode) · \(info.rateHz) Hz · \(seconds) s"
        }
    }

    func refreshSamplePickerRows() {
        let query = samplePickerFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = query.lowercased()
        let sections: [(title: String, symbols: [String], split: Bool)]
        if samplePickerWaveMode {
            sections = [("Waves", waveSymbols, false)]
        } else {
            sections = [
                ("Keysplits", keysplitTables.keys.sorted(), true),
                ("Samples", sampleChoices.filter { !$0.contains("Phoneme") }, false),
                ("Phonemes", sampleChoices.filter { $0.contains("Phoneme") }, false),
            ]
        }
        let sectionCount = sections.reduce(0) { $0 + ($1.symbols.isEmpty ? 0 : 1) }
        var entries: [SamplePickerEntry] = []
        var exact = false
        for section in sections {
            var headingAdded = false
            for symbol in section.symbols {
                let displayName = Self.sampleDisplayName(symbol)
                guard
                    filter.isEmpty || symbol.lowercased().contains(filter)
                        || displayName.lowercased().contains(filter)
                else { continue }
                if !headingAdded && sectionCount > 1 {
                    entries.append(SamplePickerEntry(label: section.title))
                    headingAdded = true
                }
                exact = exact || symbol == query
                entries.append(
                    SamplePickerEntry(
                        symbol: symbol, label: samplePickerWaveMode ? symbol : displayName,
                        split: section.split,
                        loops: !section.split && (pickerSampleInfo[symbol]?.looped ?? false),
                        detail: section.split ? "Keysplit instrument" : samplePickerDetails[symbol] ?? ""))
            }
        }
        if !filter.isEmpty && !exact {
            entries.append(
                SamplePickerEntry(
                    symbol: query, label: "Use \"\(query)\"", typed: true, detail: "Unlisted symbol"))
        }
        syncRetained(
            samplePickerRows, entries,
            make: {
                let row = SamplePickerRow()
                _ = row.apply($0)
                return row
            }, update: { $0.apply($1) })
        publish(\.samplePickerCount, entries.count)
    }

    static func sampleDisplayName(_ symbol: String) -> String {
        for prefix in ["DirectSoundWaveData_", "ProgrammableWaveData_", "voicegroup_"] {
            if symbol.hasPrefix(prefix), symbol.count > prefix.count {
                return String(symbol.dropFirst(prefix.count))
            }
        }
        return symbol
    }
}
