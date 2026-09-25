// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "SlotsTest"
    when: windowShown

    ListView {
        id: view
        width: 8
        height: 8
        model: SlotsModel
        delegate: Item {
            width: 1
            height: 1
        }
    }

    function test_returnValues() {
        compare(SlotsModel.addInts(1, 1), 2)
        compare(SlotsModel.addUInts(2, 2), 4)
        compare(SlotsModel.checkTruth(true, false), false)
        compare(SlotsModel.addDoubles(2.2002, 1.1001), 3.3003)
        compare(SlotsModel.addFloats(2.2, 1.1), 3.3)
        compare(SlotsModel.concatStrings("Hello", "World"), "Hello, World")
        compare(SlotsModel.makeList("Hi", "Bye"), ["Hi","Bye"])

        let map = {
            "name": "Alice",
            "isActive": true,
            "score": 77
        }
        let returnValue = SlotsModel.addElementToMap(map, "username", "alice123")
        compare(Object.keys(returnValue).length, 4)
        compare(returnValue["name"], "Alice")
        compare(returnValue["isActive"], true)
        compare(returnValue["score"], 77)
        compare(returnValue["username"], "alice123")
    }
}
