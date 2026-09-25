// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "ListModelView"
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

    ListView {
        id: view
        width: 8
        height: 8
        model: ListModel.list
        delegate: Item { }
    }

    QtObject {
        id: mirror
        property var list: ListModel.list
        property string duplicate: ListModel.duplicateStringFound
    }

    function test_a_initialSetup() {
        compare(view.count, 1)
        compare(mirror.list.length, 1)
        compare(listChangedSpy.count, 0)
        compare(duplicateChangedSpy.count, 0)
    }

    function test_addDuplicate() {
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.addString("milk")
        ListModel.addString("milk")
        tryCompare(view, "count", 2, 200)
        tryCompare(mirror, "duplicate", "milk", 200)
        compare(listChangedSpy.count, 1)
        compare(duplicateChangedSpy.count,  1)
    }

    function test_addUnique() {
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.addString("tomato")
        tryCompare(view, "count", 3, 200)
        tryCompare(mirror, "list", ["lemon", "milk", "tomato"], 200)
        compare(listChangedSpy.count, 1)
        compare(duplicateChangedSpy.count,  0)
    }

    function test_editString() {
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.editString(0, "lime")
        tryCompare(view, "count", 3, 200)
        tryCompare(mirror, "list", ["lime", "milk", "tomato"], 200)
        compare(listChangedSpy.count, 1)
        compare(duplicateChangedSpy.count,  0)
    }

    function test_removeString() {
        listChangedSpy.clear()
        duplicateChangedSpy.clear()
        ListModel.removeString(1)
        tryCompare(view, "count", 2, 200)
        tryCompare(mirror, "list", ["lime", "tomato"], 200)
        compare(listChangedSpy.count, 1)
        compare(duplicateChangedSpy.count,  0)
    }
}
