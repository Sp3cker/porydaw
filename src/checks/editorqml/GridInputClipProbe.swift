import Foundation
import PorydawApp
import PorydawProjectService
import QtBridge

/// Clipboard probe for the grid-input and clipboard shell lanes. It moves the
/// same native clip bytes the old QWidget checks inspected
/// (`application/x-porydaw-clip` via production `pd_clipboard_read`/
/// `pd_clipboard_write` in `src/app/clipboard_host.cpp`) and decodes them
/// through production `ClipboardCodec` (`src/swift/app/commands/Clipboard.swift`).
/// QML drives real pointer/key input; this probe only writes staged payloads
/// and reads back what the production commands published.
@MainActor
@QtBridgeable
public final class GridInputClipProbe: QmlInstantiableStatus {
    public init() {}

    public func componentComplete() {}

    /// Writes one raw JSON clip payload to the native clipboard. Empty text
    /// clears the clip, matching `pd_clipboard_write(nil, 0)` semantics.
    public func writeClipJson(json: String) -> Bool {
        if json.isEmpty { return pd_clipboard_write(nil, 0) }
        guard let data = json.data(using: .utf8), !data.isEmpty else { return false }
        return data.withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            return pd_clipboard_write(pointer, bytes.count)
        }
    }

    /// Reads the native clip payload as UTF-8 JSON, or "" when the native
    /// MIME is absent. QML parses this with JSON.parse for schema assertions.
    public func readClipJson() -> String {
        let box = GridInputClipReadBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard pd_clipboard_read(context, { rawContext, bytes, count in
            guard let rawContext, let bytes else { return }
            Unmanaged<GridInputClipReadBox>.fromOpaque(rawContext)
                .takeUnretainedValue().data = Data(bytes: bytes, count: count)
        }), let data = box.data, !data.isEmpty else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Clears the native clip.
    public func clearClipboard() -> Bool {
        pd_clipboard_write(nil, 0)
    }

    /// Compact decoded summary for wait predicates:
    /// "[tracks,firstNotes,firstKey,span,ticks,lanes,tempo]".
    /// "[]" means the native MIME is absent or undecodable.
    public func clipSummary() -> String {
        let box = GridInputClipReadBox()
        let context = Unmanaged.passUnretained(box).toOpaque()
        guard pd_clipboard_read(context, { rawContext, bytes, count in
            guard let rawContext, let bytes else { return }
            Unmanaged<GridInputClipReadBox>.fromOpaque(rawContext)
                .takeUnretainedValue().data = Data(bytes: bytes, count: count)
        }), let data = box.data, let decoded = ClipboardCodec.decode(data) else { return "[]" }
        let tracks = decoded.clip.tracks
        let notes = tracks.first?.notes ?? []
        let key = notes.first.map { Int($0.key) } ?? -1
        return "[\(tracks.count),\(notes.count),\(key),\(decoded.clip.span),\(decoded.ticksPerBeat),\(decoded.clip.lanes.count),\(decoded.clip.tempo.count)]"
    }
}

private final class GridInputClipReadBox {
    var data: Data?
}
