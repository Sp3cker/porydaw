import Foundation

extension ProjectStore {
    /// Resolves an instrument descriptor to an on-disk or memory-only symbol.
    /// - Parameter descriptor: Pulse parameters or a saw/triangle waveform.
    /// - Returns: The reusable symbol, without writing project files.
    /// - Throws: `VoicegroupStoreError` when the project cannot define the waveform.
    public func mintSynth(_ descriptor: VgSynthDesc) throws -> String {
        let catalog = VoicegroupSource.synthInstruments(projectRoot)
        if let existing = catalog.defs.first(where: { $0.descriptor == descriptor }) {
            return existing.symbol
        }
        if let pending = pendingSynths.first(where: { $0.value == descriptor }) {
            return pending.key
        }
        guard catalog.creatable(), SynthDefinitions.word(for: descriptor, in: catalog) != nil else {
            throw VoicegroupStoreError.operationFailed(
                "Cannot create synth instrument: this project does not define set_synth_* macros.")
        }
        let samples = VoicegroupSource.directSoundSymbols(projectRoot)
        let base = vgSynthSymbolName(descriptor)
        var symbol = base
        var suffix = 2
        while catalog.find(symbol) != nil || samples.contains(symbol) || pendingSynths[symbol] != nil {
            symbol = "\(base)_\(suffix)"
            suffix += 1
        }
        pendingSynths[symbol] = descriptor
        return symbol
    }

    func savePendingSynths(for id: VoicegroupId) throws -> [String] {
        guard let view = voicegroupStore?.currentPublication(id: id) else { return [] }
        let symbols = Set(view.slotViews.compactMap { $0.voice?.symbol })
        let definitions = pendingSynths.filter { symbols.contains($0.key) }.sorted { $0.key < $1.key }
        guard !definitions.isEmpty else { return [] }
        try SynthDefinitions.write(definitions.map { ($0.key, $0.value) }, root: projectRoot)
        return definitions.map(\.key)
    }

    func didSaveSynths(_ symbols: [String]) {
        for symbol in symbols { pendingSynths.removeValue(forKey: symbol) }
    }
}

/// Synth definitions are appended atomically and wired into assembly like the native writer.
private enum SynthDefinitions {
    static func word(for descriptor: VgSynthDesc, in catalog: VgSynthCatalog) -> String? {
        let options: [String]
        switch descriptor.waveform {
        case 0: options = ["set_synth_pulse", "set_synth_custom"]
        case 1: options = ["set_synth_saw", "set_synth_25"]
        default: options = ["set_synth_triangle", "set_synth_50"]
        }
        return options.first { catalog.macroWords.contains($0) }
    }

    static func write(_ definitions: [(String, VgSynthDesc)], root: String) throws {
        let catalog = VoicegroupSource.synthInstruments(root)
        let path = "\(root)/sound/direct_sound_synth_data.inc"
        let original = (try? ProjectFileStore.read(path)) ?? Data()
        let lineEnding = original.range(of: Data("\r\n".utf8)) == nil ? "\n" : "\r\n"
        let lines = String(decoding: original, as: UTF8.self).components(separatedBy: "\n")
        let alignIndent = lines.last(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".align") })
            .map(indent) ?? "\t"
        let macroIndent = lines.last(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("set_synth_")
        }).map(indent) ?? "\t"
        var appended = ""
        for (symbol, descriptor) in definitions {
            if let existing = catalog.find(symbol) {
                guard existing == descriptor else {
                    throw VoicegroupStoreError.operationFailed(
                        "Synth symbol \(symbol) already exists with different parameters.")
                }
                continue
            }
            guard let word = word(for: descriptor, in: catalog) else {
                throw VoicegroupStoreError.operationFailed(
                    "This project does not define the set_synth_* macros for \(symbol).")
            }
            if !original.isEmpty && original.last != 10 && appended.isEmpty {
                appended += lineEnding
            }
            if !original.isEmpty || !appended.isEmpty { appended += lineEnding }
            appended += "\(alignIndent).align 2\(lineEnding)\(symbol)::\(lineEnding)\(macroIndent)\(word)"
            if descriptor.waveform == 0 {
                appended += String(format: " 0x%02X, 0x%02X, 0x%02X, 0x%02X",
                                   UInt8(truncatingIfNeeded: descriptor.baseDuty),
                                   UInt8(truncatingIfNeeded: descriptor.dutyStep),
                                   UInt8(truncatingIfNeeded: descriptor.modDepth),
                                   UInt8(truncatingIfNeeded: descriptor.phase))
            }
            appended += lineEnding
        }
        let include = !appended.isEmpty || ProjectFileStore.exists(path)
            ? try assemblyInclude(root: root) : nil
        if !appended.isEmpty {
            var updated = original
            updated.append(contentsOf: appended.utf8)
            try ProjectFileStore.writeAtomic(path, data: updated)
        }
        if let include {
            try ProjectFileStore.writeAtomic(include.path, data: include.bytes)
        }
    }

    private static func indent(_ line: String) -> String {
        String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    private static func assemblyInclude(root: String) throws -> (path: String, bytes: Data)? {
        let known = ["\(root)/data/sound_data.s", "\(root)/sound/sound_data.s",
                     "\(root)/sound_data.s", "\(root)/sound/direct_sound_data.inc"]
        let files = ["\(root)/data", root].flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(atPath: directory))?.filter {
                $0.hasSuffix(".s")
            }.map { "\(directory)/\($0)" } ?? []
        }
        var anchor: (String, [String], Int)?
        for path in known + files where ProjectFileStore.exists(path) {
            guard let data = try? ProjectFileStore.read(path) else { continue }
            if data.range(of: Data("direct_sound_synth_data.inc".utf8)) != nil { return nil }
            if anchor == nil {
                let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
                if let index = lines.firstIndex(where: {
                    $0.trimmingCharacters(in: .whitespaces).hasPrefix(".include") &&
                        $0.contains("sound/direct_sound_data.inc")
                }) { anchor = (path, lines, index) }
            }
        }
        guard let (path, lines, index) = anchor else {
            throw VoicegroupStoreError.operationFailed(
                "Cannot find where sound/direct_sound_data.inc is assembled; include sound/direct_sound_synth_data.inc next to it and save again.")
        }
        let anchorLine = lines[index]
        let crlf = anchorLine.hasSuffix("\r")
        let inserted = "\(indent(anchorLine)).include \"sound/direct_sound_synth_data.inc\"" +
            (crlf ? "\r" : "")
        var updated = lines
        updated.insert(inserted, at: index + 1)
        return (path, Data(updated.joined(separator: "\n").utf8))
    }
}
