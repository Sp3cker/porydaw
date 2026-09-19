import QtQuick
import SwiftQtMlCheck 1.0

Item {
    id: root
    objectName: "bridgeProbeRoot"
    width: 320
    height: 240

    property int delegateSerialCounter: 0

    function issueDelegateSerial() {
        delegateSerialCounter += 1
        return delegateSerialCounter
    }

    function seedDefaultRows() {
        probe.clearActionLog()
        probe.selectedIndex = -1
        state.capturedRow = null
        state.returnedRow = null
        state.selectedObject = null
        state.selectedIsNull = true
        state.objectArgumentCallSucceeded = false
        state.objectArgumentError = ""
        probe.resetToDefaultRows()
    }

    function captureRow(index) {
        probe.selectedIndex = index
        state.capturedRow = probe.selectedRow()
    }

    function mutateMiddleDirect() {
        captureRow(1)
        probe.mutateSelectedRowInPlace("Beta direct")
    }

    function replaceMiddleSameRow() {
        captureRow(1)
        probe.replaceSelectedRowWithSame(1)
    }

    function replaceMiddleWithNewRow() {
        captureRow(1)
        probe.replaceRowWithNew(1, "Delta", 44, 404)
    }

    function insertHeadRemoveMiddle() {
        captureRow(2)
        probe.insertRowWithNew(0, "Head", 5, 100)
        probe.removeRow(2)
    }

    function removeInsertFirstToLast() {
        captureRow(0)
        probe.removeInsertRow(0, 2)
    }

    function resetWithFreshRows() {
        captureRow(1)
        probe.resetToFreshRows()
    }

    function inspectMadeRow() {
        state.returnedRow = probe.makeRow("Returned", 77, 707)
    }

    function inspectSelectedPresent() {
        probe.selectedIndex = 1
        state.selectedObject = probe.selectedRow()
        state.selectedIsNull = !state.selectedObject
    }

    function inspectSelectedMissing() {
        probe.selectedIndex = -1
        state.selectedObject = probe.selectedRow()
        state.selectedIsNull = !state.selectedObject
    }

    // Unsafe future bridge fix probe point — invoke and assert success only when object-argument slots are supported; today it crashes the process (see contract ledger).
    function unsafeAttemptObjectArgumentCall() {
        state.objectArgumentCallSucceeded = false
        state.objectArgumentError = ""
        try {
            probe.actViaRow(state.selectedObject)
            state.objectArgumentCallSucceeded = true
        } catch (error) {
            state.objectArgumentError = String(error)
        }
    }

    BridgeProbe {
        id: probe
        objectName: "bridgeProbe"
    }

    QtObject {
        id: state
        objectName: "probeState"
        property var capturedRow: null
        property var returnedRow: null
        property var selectedObject: null
        property bool selectedIsNull: true
        property bool objectArgumentCallSucceeded: false
        property string objectArgumentError: ""
    }

    Text {
        objectName: "statusText"
        text: probe.statusText
    }

    Text {
        objectName: "actionLogText"
        text: probe.actionLog
    }

    Text {
        objectName: "returnedTitleText"
        text: state.returnedRow ? state.returnedRow.title : "<null>"
    }

    Text {
        objectName: "selectedTitleText"
        text: state.selectedObject ? state.selectedObject.title : "<null>"
    }

    Repeater {
        id: rowRepeater
        objectName: "rowRepeater"
        model: probe.rows

        delegate: Item {
            id: delegateRoot
            required property int index
            required property string title
            required property int value
            required property int domainKey

            property int delegateSerial: -1
            width: root.width
            height: 24

            Text {
                id: delegateText
                objectName: "rowText_" + delegateRoot.domainKey
                text: delegateRoot.title + ":" + delegateRoot.value
            }

            Component.onCompleted: delegateSerial = root.issueDelegateSerial()
        }
    }

    // Repeater delegates are visual children, not a QObject registry. This
    // single named seam lets C++ enumerate the real delegates through itemAt().
    QtObject {
        id: delegateProbe
        objectName: "delegateProbe"
        readonly property int count: rowRepeater.count

        function itemAt(slot) {
            return rowRepeater.itemAt(slot)
        }
    }
}
