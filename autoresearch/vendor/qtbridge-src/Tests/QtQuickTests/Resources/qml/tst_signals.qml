// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "SignalsTest"
    when: windowShown

    SignalSpy {
        id: triggerNewStringSpy
        target: SignalsModel
        signalName: "triggerNewString"
    }
    SignalSpy {
        id: newStringAddedSpy
        target: SignalsModel
        signalName: "newStringAdded"
    }
    SignalSpy {
        id: rowsInsertedSpy
        target: SignalsModel.sigModel
        signalName: "rowsInserted"
    }
    SignalSpy {
        id: sigModelChangedSpy
        target: SignalsModel
        signalName: "sigModelChanged"
    }
    SignalSpy {
        id: changeBoolSpy
        target: SignalsModel
        signalName: "changeBool"
    }
    SignalSpy {
        id: changeIntSpy
        target: SignalsModel
        signalName: "changeInt"
    }
    SignalSpy {
        id: changeUIntSpy
        target: SignalsModel
        signalName: "changeUInt"
    }
    SignalSpy {
        id: changeDoubleSpy
        target: SignalsModel
        signalName: "changeDouble"
    }
    SignalSpy {
        id: changeFloatSpy
        target: SignalsModel
        signalName: "changeFloat"
    }
    SignalSpy {
        id: changeStringSpy
        target: SignalsModel
        signalName: "changeString"
    }
    SignalSpy {
        id: changeStringListSpy
        target: SignalsModel
        signalName: "changeStringList"
    }
    SignalSpy {
        id: changeVariantMapSpy
        target: SignalsModel
        signalName: "changeVariantMap"
    }
    SignalSpy {
        id: changeMultipleParamsSpy
        target: SignalsModel
        signalName: "changeMultipleParams"
    }
    SignalSpy {
        id: signalOneSpy
        target: SignalsModel
        signalName: "signalOne"
    }

    ListView {
        id: view
        width: 8
        height: 8
        model: SignalsModel.sigModel
        delegate: Item {
            width: 1
            height: 1
        }
    }

    Connections {
        target: SignalsModel
        // Signals Chain
        function onTriggerNewString(newString) {
            SignalsModel.addString(newString)
        }
        function onNewStringAdded() {
            SignalsModel.chainEnded()
        }
        function onChainEnded() {
            SignalsModel.chainCompleted = true
        }
    }

    function test_a_initSetup() {
        compare(view.count, 2)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "one")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "two")
    }

    function test_signalsChain() {
        // Verifies that signal queuing prevents
        // a "Simultaneous access" error
        triggerNewStringSpy.clear()
        newStringAddedSpy.clear()
        rowsInsertedSpy.clear()
        sigModelChangedSpy.clear()
        compare(SignalsModel.chainCompleted, false)

        SignalsModel.triggerNewStringSignal("three")

        tryCompare(view, "count", 3, 200)
        compare(view.model.data(view.model.index(0,0), Qt.DisplayRole), "one")
        compare(view.model.data(view.model.index(1,0), Qt.DisplayRole), "two")
        compare(view.model.data(view.model.index(2,0), Qt.DisplayRole), "three")
        tryCompare(triggerNewStringSpy, "count", 1, 200)
        tryCompare(rowsInsertedSpy, "count", 1, 200)
        tryCompare(newStringAddedSpy, "count", 1, 200)
        tryCompare(sigModelChangedSpy, "count", 1, 200)
        compare(SignalsModel.chainCompleted, true)
    }

    function test_signalsFromSwift() {
        signalOneSpy.clear()
        changeBoolSpy.clear()
        changeIntSpy.clear()
        changeUIntSpy.clear()
        changeDoubleSpy.clear()
        changeFloatSpy.clear()
        changeStringSpy.clear()
        changeStringListSpy.clear()
        changeVariantMapSpy.clear()
        changeMultipleParamsSpy.clear()

        SignalsModel.triggerSignals(true, 42, 4, 4.2222, 4.2,
                                    "Forty-two", ["Forty", "Two"],
                                    {"score": 42})
        // No arguments
        tryCompare(signalOneSpy, "count", 1, 200)

        // Bool
        compare(changeBoolSpy.count, 1)
        compare(changeBoolSpy.signalArguments[0].length, 1)
        compare(changeBoolSpy.signalArguments[0][0], true)

        // Int
        compare(changeIntSpy.count, 1)
        compare(changeIntSpy.signalArguments[0].length, 1)
        compare(changeIntSpy.signalArguments[0][0], 42)

        // UInt
        compare(changeUIntSpy.count, 1)
        compare(changeUIntSpy.signalArguments[0].length, 1)
        compare(changeUIntSpy.signalArguments[0][0], 4)

        //Double
        compare(changeDoubleSpy.count, 1)
        compare(changeDoubleSpy.signalArguments[0].length, 1)
        compare(changeDoubleSpy.signalArguments[0][0], 4.2222)

        // Float
        compare(changeFloatSpy.count, 1)
        compare(changeFloatSpy.signalArguments[0].length, 1)
        compare(changeFloatSpy.signalArguments[0][0], 4.2)

        // String
        compare(changeStringSpy.count, 1)
        compare(changeStringSpy.signalArguments[0].length, 1)
        compare(changeStringSpy.signalArguments[0][0], "Forty-two")

        // String List
        compare(changeStringListSpy.count, 1)
        compare(changeStringListSpy.signalArguments[0].length, 1)
        compare(changeStringListSpy.signalArguments[0][0], ["Forty", "Two"])

        // QVariantMap
        compare(changeVariantMapSpy.count, 1)
        compare(changeVariantMapSpy.signalArguments[0].length, 1)
        let mapArg = changeVariantMapSpy.signalArguments[0][0]
        compare(Object.keys(mapArg).length, 1)
        compare(mapArg["score"], 42)

        // Multiple Args
        compare(changeMultipleParamsSpy.count, 1)
        compare(changeMultipleParamsSpy.signalArguments[0].length, 3)
        compare(changeMultipleParamsSpy.signalArguments[0][0], true)
        compare(changeMultipleParamsSpy.signalArguments[0][1], 4)
        compare(changeMultipleParamsSpy.signalArguments[0][2], "Forty-two")
    }

    function test_signalsFromQml() {
        signalOneSpy.clear()
        changeBoolSpy.clear()
        changeIntSpy.clear()
        changeUIntSpy.clear()
        changeDoubleSpy.clear()
        changeFloatSpy.clear()
        changeStringSpy.clear()
        changeStringListSpy.clear()
        changeVariantMapSpy.clear()
        changeMultipleParamsSpy.clear()

        // No arguments
        SignalsModel.signalOne()
        tryCompare(signalOneSpy, "count", 1, 200)

        // Bool
        SignalsModel.changeBool(true)
        tryCompare(changeBoolSpy, "count", 1, 200)
        compare(changeBoolSpy.signalArguments[0].length, 1)
        compare(changeBoolSpy.signalArguments[0][0], true)

        // Int
        SignalsModel.changeInt(130000)
        tryCompare(changeIntSpy, "count", 1, 200)
        compare(changeIntSpy.signalArguments[0].length, 1)
        compare(changeIntSpy.signalArguments[0][0], 130000)

        // UInt
        SignalsModel.changeUInt(13)
        tryCompare(changeUIntSpy, "count", 1, 200)
        compare(changeUIntSpy.signalArguments[0].length, 1)
        compare(changeUIntSpy.signalArguments[0][0], 13)

        // Double
        SignalsModel.changeDouble(1.33333)
        tryCompare(changeDoubleSpy, "count", 1, 200)
        compare(changeDoubleSpy.signalArguments[0].length, 1)
        compare(changeDoubleSpy.signalArguments[0][0], 1.33333)

        // Float
        SignalsModel.changeFloat(1.33)
        tryCompare(changeFloatSpy, "count", 1, 200)
        compare(changeFloatSpy.signalArguments[0].length, 1)
        compare(changeFloatSpy.signalArguments[0][0], 1.33)

        // String
        SignalsModel.changeString("Hello!")
        tryCompare(changeStringSpy, "count", 1, 200)
        compare(changeStringSpy.signalArguments[0].length, 1)
        compare(changeStringSpy.signalArguments[0][0], "Hello!")

        // String List
        SignalsModel.changeStringList(["Hi!", "Bye!"])
        tryCompare(changeStringListSpy, "count", 1, 200)
        compare(changeStringListSpy.signalArguments[0].length, 1)
        compare(changeStringListSpy.signalArguments[0][0], ["Hi!", "Bye!"])

        // QVariantMap
        SignalsModel.changeVariantMap({"name": "Rue"})
        tryCompare(changeVariantMapSpy, "count", 1, 200)
        compare(changeVariantMapSpy.signalArguments[0].length, 1)
        let mapArg = changeVariantMapSpy.signalArguments[0][0]
        compare(Object.keys(mapArg).length, 1)
        compare(mapArg["name"], "Rue")

        // Multiple arguments
        SignalsModel.changeMultipleParams(true, 13, "Bye")
        tryCompare(changeMultipleParamsSpy, "count", 1, 200)
        compare(changeMultipleParamsSpy.signalArguments[0].length, 3)
        compare(changeMultipleParamsSpy.signalArguments[0][0], true)
        compare(changeMultipleParamsSpy.signalArguments[0][1], 13)
        compare(changeMultipleParamsSpy.signalArguments[0][2], "Bye")
    }
}
