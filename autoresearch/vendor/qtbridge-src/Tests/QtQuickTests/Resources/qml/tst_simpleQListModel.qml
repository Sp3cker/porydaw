// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "SimpleQListModel"
    when: windowShown

    SignalSpy {
        id: rowsInsertedSpy
        target: SimpleQListModel.simpleModel
        signalName: "rowsInserted"
    }
    SignalSpy {
        id: rowsRemovedSpy
        target: SimpleQListModel.simpleModel
        signalName: "rowsRemoved"
    }
    SignalSpy {
        id: modelResetSpy
        target: SimpleQListModel.simpleModel
        signalName: "modelReset"
    }
    SignalSpy {
        id: dataChangedSpy
        target: SimpleQListModel.simpleModel
        signalName: "dataChanged"
    }
    SignalSpy {
        id: simpleModelChangedSpy
        target: SimpleQListModel
        signalName: "simpleModelChanged"
    }

    QtObject {
        id: mirror
        property var simpleModelMirror: SimpleQListModel.simpleModelMirror
    }

    ListView {
        id: view
        width: 8
        height: 8
        model: SimpleQListModel.simpleModel
        delegate: Item {
            width: 1
            height: 1
            // With a single named role ("display"), QML mirrors it as modelData,
            // so modelData == display. Added as two properties for testing.
            required property string modelData
            required property string display
        }
    }

    function test_a_initialSetup() {
        compare(view.count, 2, 200)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "one")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "two")
    }

    function test_addString() {
        rowsInsertedSpy.clear()
        SimpleQListModel.addString("three")
        tryCompare(view, "count", 3, 200)
        compare(rowsInsertedSpy.count, 1)
    }

    function test_areplaceString() {
        rowsInsertedSpy.clear()
        rowsRemovedSpy.clear()
        SimpleQListModel.replaceString()
        tryCompare(view, "count", 3, 200)
        tryCompare(mirror, "simpleModelMirror", ["four", "five", "three"], 200)
        compare(rowsInsertedSpy.count, 1)
        compare(rowsRemovedSpy.count, 1)
    }

    function test_checkRowCount() {
        compare(view.count, 3, 200)
        compare(view.model.rowCount(), 3)
    }

    function test_readDataFunc() {
        // Read data via data() and DisplayRole
        compare(view.count, 3, 200)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "four")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "five")
        compare(view.model.data(view.model.index(2,0), Qt.DisplayRole), "three")
    }

    function test_readDataProp() {
        // Read data via delegate properties
        compare(view.count, 3)
        view.currentIndex = 0
        compare(view.currentItem.modelData, "four")
        view.currentIndex = 1
        compare(view.currentItem.display, "five")
        view.currentIndex = 2
        compare(view.currentItem.modelData, "three")
    }

    function test_removeString() {
        rowsRemovedSpy.clear()
        SimpleQListModel.removeString(0)
        tryCompare(view, "count", 2, 200)
        tryCompare(mirror, "simpleModelMirror", ["five", "three"], 200)
        compare(rowsRemovedSpy.count, 1)
    }

    function test_replaceAt() {
        dataChangedSpy.clear()
        SimpleQListModel.replaceAtIndex(0)
        tryCompare(view, "count", 2, 200)
        tryCompare(mirror, "simpleModelMirror", ["alpha", "three"], 200)
        compare(dataChangedSpy.count, 1)
    }

    function test_replaceModel() {
        simpleModelChangedSpy.clear()
        SimpleQListModel.replaceModel()
        tryCompare(view, "count", 3, 200)
        tryCompare(mirror, "simpleModelMirror", ["a", "b", "c"], 200)
        compare(simpleModelChangedSpy.count, 1)
    }

    function test_setData() {
        dataChangedSpy.clear()
        compare(mirror.simpleModelMirror, ["a", "b", "c"], 200)
        view.model.setData(view.model.index(0,0), "lemon", Qt.DisplayRole)
        view.model.setData(view.model.index(1,0), "milk", Qt.DisplayRole)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "lemon")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "milk")
        SimpleQListModel.updateMirror()
        tryCompare(mirror, "simpleModelMirror", ["lemon", "milk", "c"], 200)
        compare(dataChangedSpy.count, 2)
    }

    function test_xresetModel() {
        modelResetSpy.clear()
        SimpleQListModel.resetModel()
        tryCompare(view, "count", 0, 200)
        tryCompare(mirror, "simpleModelMirror", [], 200)
        compare(modelResetSpy.count, 1)
    }
}
