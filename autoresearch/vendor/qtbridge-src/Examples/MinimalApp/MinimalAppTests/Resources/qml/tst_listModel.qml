// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import MyQuickTest 1.0

TestCase {
    name: "MinimalAppTest"
    when: windowShown

    SignalSpy {
        id: listChangedSpy
        target: ListModel
        signalName: "listChanged"
    }

    SignalSpy {
        id: duplicateChangedSpy
        target: ListModel
        signalName: "duplicateStringFoundChanged"
    }

    SignalSpy {
        id: rowsInsertedSpy
        target: ListModel.list
        signalName: "rowsInserted"
    }

    SignalSpy {
        id: rowsRemovedSpy
        target: ListModel.list
        signalName: "rowsRemoved"
    }

    SignalSpy {
        id: dataChangedSpy
        target: ListModel.list
        signalName: "dataChanged"
    }

    ListView {
        id: view
        width: 8
        height: 8
        model: ListModel.list
        delegate: Item { }
    }

    function test_a_initialSetup() {
        compare(view.count, 1)
        compare(listChangedSpy.count, 0)
        compare(duplicateChangedSpy.count, 0)
    }

    function test_addDuplicate() {
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.addString("milk")
        ListModel.addString("milk")
        compare(view.count, 2)
        tryCompare(listChangedSpy, "count", 1, 200)
        compare(duplicateChangedSpy.count,  1)
    }

    function test_addUnique() {
        rowsInsertedSpy.clear()
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.addString("tomato")
        compare(view.count, 3)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "test string")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "milk")
        compare(view.model.data(view.model.index(2,0), Qt.DisplayRole), "tomato")
        compare(rowsInsertedSpy.count, 1)
        tryCompare(listChangedSpy, "count", 1, 200)
        compare(duplicateChangedSpy.count, 0)
    }

    function test_editString() {
        dataChangedSpy.clear()
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.editString(0, "lime")
        compare(view.count, 3)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "lime")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "milk")
        compare(view.model.data(view.model.index(2,0), Qt.DisplayRole), "tomato")
        compare(dataChangedSpy.count, 1)
        compare(duplicateChangedSpy.count, 0)
        compare(listChangedSpy.count,  0)
    }

    function test_removeString() {
        rowsRemovedSpy.clear()
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.removeString(1)
        compare(view.count, 2)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "lime")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "tomato")
        compare(rowsRemovedSpy.count, 1)
        tryCompare(listChangedSpy, "count", 1, 200)
        compare(duplicateChangedSpy.count, 0)
    }
}
