import Foundation
import QtBridge
import SwiftGrid

@MainActor
@QtBridgeable
public final class BridgeRow {
    public var title: String
    public var value: Int
    public let domainKey: Int

    public init(title: String, value: Int, domainKey: Int) {
        self.title = title
        self.value = value
        self.domainKey = domainKey
    }
}

@MainActor
@QtBridgeable
public final class BridgeProbe: QmlInstantiableStatus {
    public var statusText: String = "idle"
    // QListModel storage owns every live row until removal or reset.
    public var rows: QListModel<BridgeRow> = QListModel()
    public var actionLog: String = ""
    public var selectedIndex: Int = -1
    // An explicit stale-reference holder. selectedRow() replaces it for a
    // valid index and clears it for an invalid index; model mutations do not
    // clear it, so detached-row scenarios remain alive until the next
    // selection lookup or presenter teardown.
    private var selectedReference: BridgeRow?
    // A QML var retains only the C++ proxy for a returned bridged object; it
    // does not retain the Swift instance that owns that proxy. The presenter
    // must therefore retain the harness's single standalone return while QML
    // may dereference it. makeRow() replaces this when QML replaces that
    // return slot, and presenter teardown releases the final retained row.
    private var lastReturnedRow: BridgeRow?

    required public init() {}

    public func componentComplete() {}

    public func setStatusText(text: String) {
        statusText = text
    }

    private func newRow(title: String, value: Int, key: Int) -> BridgeRow {
        BridgeRow(title: title, value: value, domainKey: key)
    }

    public func makeRow(title: String, value: Int, key: Int) -> BridgeRow {
        let row = newRow(title: title, value: value, key: key)
        lastReturnedRow = row
        return row
    }

    public func selectedRow() -> Optional<BridgeRow> {
        guard selectedIndex >= rows.startIndex, selectedIndex < rows.endIndex else {
            selectedReference = nil
            return nil
        }
        let row = rows[selectedIndex]
        selectedReference = row
        return row
    }

    public func mutateRowInPlace(row: BridgeRow, title: String) {
        row.title = title
    }

    public func replaceRow(index: Int, row: BridgeRow) {
        guard rows.indices.contains(index) else { return }
        rows[index] = row
    }

    public func insertRow(at index: Int, row: BridgeRow) {
        guard index >= rows.startIndex, index <= rows.endIndex else { return }
        rows.replaceSubrange(index..<index, with: CollectionOfOne(row))
    }

    public func removeRow(at index: Int) {
        guard rows.indices.contains(index) else { return }
        rows.replaceSubrange(index..<(index + 1), with: EmptyCollection())
    }

    public func removeInsertRow(from source: Int, to destination: Int) {
        guard rows.indices.contains(source), rows.indices.contains(destination), source != destination else {
            return
        }
        let row = rows[source]
        rows.replaceSubrange(source..<(source + 1), with: EmptyCollection())
        rows.replaceSubrange(destination..<destination, with: CollectionOfOne(row))
    }

    public func resetRows(_ newRows: [BridgeRow]) {
        rows.reset(to: newRows)
    }

    // QtBridge slots currently accept primitive parameters but not bridged
    // object or object-array parameters. These harness-only slots drive the
    // object-taking operations above without changing what those operations
    // prove through QML.
    public func resetToDefaultRows() {
        resetRows([
            newRow(title: "Alpha", value: 10, key: 101),
            newRow(title: "Beta", value: 20, key: 202),
            newRow(title: "Gamma", value: 30, key: 303),
        ])
    }

    public func mutateSelectedRowInPlace(title: String) {
        guard let selectedReference else { return }
        mutateRowInPlace(row: selectedReference, title: title)
    }

    public func replaceSelectedRowWithSame(index: Int) {
        guard let selectedReference else { return }
        replaceRow(index: index, row: selectedReference)
    }

    public func replaceRowWithNew(index: Int, title: String, value: Int, key: Int) {
        replaceRow(index: index, row: newRow(title: title, value: value, key: key))
    }

    public func insertRowWithNew(at index: Int, title: String, value: Int, key: Int) {
        insertRow(at: index, row: newRow(title: title, value: value, key: key))
    }

    public func resetToFreshRows() {
        resetRows([
            newRow(title: "Fresh A", value: 91, key: 901),
            newRow(title: "Fresh B", value: 92, key: 902),
        ])
    }

    public func actViaSelectedRow() {
        guard let selectedReference else { return }
        actViaRow(row: selectedReference)
    }

    public func clearActionLog() {
        actionLog = ""
    }

    public func actViaRow(row: BridgeRow) {
        let entry = "\(row.domainKey):\(row.title)"
        actionLog = actionLog.isEmpty ? entry : "\(actionLog)|\(entry)"
    }
}

@MainActor
private let probeTypesRegistered: Void = BridgeProbe.registerQmlElement()

@_cdecl("sqp_register_probe_types")
public func sqpRegisterProbeTypes() {
    MainActor.assumeIsolated {
        _ = probeTypesRegistered
    }
}
