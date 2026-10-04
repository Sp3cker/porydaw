import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class SamplePickerRow {
    public var symbol: String = ""
    public var label: String = ""
    public var split: Bool = false
    public var typed: Bool = false
    public var loops: Bool = false
    public var detail: String = ""
    @QtIgnored
    func apply(_ value: SamplePickerEntry) -> Bool {
        let changed =
            symbol != value.symbol || label != value.label
            || split != value.split || typed != value.typed
            || loops != value.loops || detail != value.detail
        guard changed else { return false }
        setPublished(symbol, value.symbol) { symbol = $0 }
        setPublished(label, value.label) { label = $0 }
        setPublished(split, value.split) { split = $0 }
        setPublished(typed, value.typed) { typed = $0 }
        setPublished(loops, value.loops) { loops = $0 }
        setPublished(detail, value.detail) { detail = $0 }
        return true
    }
}

struct SamplePickerEntry {
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
        samplePickerRows.update {
            for (index, value) in entries.enumerated() {
                if index < samplePickerRows.count {
                    let row = samplePickerRows[index]
                    if row.apply(value) { samplePickerRows[index] = row }
                } else {
                    let row = SamplePickerRow()
                    _ = row.apply(value)
                    samplePickerRows.append(row)
                }
            }
            if samplePickerRows.count > entries.count {
                samplePickerRows.removeSubrange(entries.count..<samplePickerRows.count)
            }
        }
        setPublished(samplePickerCount, entries.count) { samplePickerCount = $0 }
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
