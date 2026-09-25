// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import MyQuickTest 1.0

TestCase {
    name: "SimpleModel"
    when: windowShown

    SignalSpy {
        id: rowsInsertedSpy
        target: SimpleModel.simpleList
        signalName: "rowsInserted"
    }

    ListView {
        id: view
        width: 8
        height: 8
        model: SimpleModel.simpleList
        delegate: Item { }
    }

    function test_a_initialSetup() {
        compare(view.count, 2)
        compare(rowsInsertedSpy.count, 0)
    }

    function test_addString() {
        rowsInsertedSpy.clear()
        SimpleModel.addString("three")
        compare(view.count, 3)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "one")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "two")
        compare(view.model.data(view.model.index(2,0), Qt.DisplayRole), "three")
        compare(rowsInsertedSpy.count, 1)
    }
}
