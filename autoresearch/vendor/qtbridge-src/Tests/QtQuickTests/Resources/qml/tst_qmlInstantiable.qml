// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtQuickTests 1.0

TestCase {
    name: "QML Types Test Suite"
    when: windowShown

    QmlType1 {
        id: qmlType1
    }

    QmlType2 {
        id: qmlType2
    }

    QmlType2 {
        id: qmlType2Unchanged
    }

    SignalSpy {
        id: qmlType1StrPropChangedSpy
        target: qmlType1
        signalName: "strPropChanged"
    }

    SignalSpy {
        id: qmlType2IntPropChangedSpy
        target: qmlType2
        signalName: "intPropChanged"
    }

    SignalSpy {
        id: qmlType2UnchangedIntPropChangedSpy
        target: qmlType2Unchanged
        signalName: "intPropChanged"
    }

    // default property
    QmlType1 {
        id: containing1

        QmlType1 { id: nested1 }
        QmlType2 { id: nested2 }
    }

    // qmlChildren
    QmlType4 {
        id: containing2

        QmlType1 {
            strId: "child1"
        }
        QmlType2 {
            strId: "child2"
            intProp: 11
        }
        QmlType2 {
            strId: "child3"
            intProp: 22
        }
        Rectangle {}
        QmlType2 {
            id: containing2nested
            strId: "containing2nested"
            intProp: 33
        }
    }

    // dynamic instantiations
    Component {
        id: qmlType1Component
        QmlType1 {}
    }

    Component {
        id: qmlType2Component
        QmlType2 {}
    }

    // componentComplete()
    QmlType3 {
        id: qmlComponent

        prop1: 21
        prop2: 42
        prop3: 63
    }

    SignalSpy {
        id: sumChangedSpy
        target: qmlComponent
        signalName: "sumChanged"
    }

    function test_initialSetup() {
        compare(qmlType1.strProp, "testString")
        compare(qmlType2.intProp, 0)
        compare(qmlType2Unchanged.intProp, 0)
    }

    function test_properties() {
        qmlType1StrPropChangedSpy.clear()
        qmlType2IntPropChangedSpy.clear()
        qmlType2UnchangedIntPropChangedSpy.clear()

        let expectedStr = "testString1"
        qmlType1.strProp = expectedStr
        qmlType1StrPropChangedSpy.wait()
        compare(qmlType1StrPropChangedSpy.count, 1)
        compare(qmlType1.strProp, expectedStr)

        let expectedInt = 10
        qmlType2.intProp = expectedInt
        qmlType2IntPropChangedSpy.wait()
        compare(qmlType2IntPropChangedSpy.count, 1)
        compare(qmlType2.intProp, expectedInt)

        compare(qmlType2Unchanged.intProp, 0)
        tryCompare(qmlType2UnchangedIntPropChangedSpy, "count", 0)
    }

    function test_slots() {
        qmlType1StrPropChangedSpy.clear()
        qmlType2IntPropChangedSpy.clear()
        qmlType2UnchangedIntPropChangedSpy.clear()

        let expectedStr = "testString2"
        qmlType1.updateStrProp(expectedStr)
        qmlType1StrPropChangedSpy.wait()
        compare(qmlType1StrPropChangedSpy.count, 1)
        compare(qmlType1.strProp, expectedStr)

        let expectedInt = 20
        qmlType2.updateIntProp(expectedInt)
        qmlType2IntPropChangedSpy.wait()
        compare(qmlType2IntPropChangedSpy.count, 1)
        compare(qmlType2.intProp, expectedInt)

        compare(qmlType2Unchanged.intProp, 0)
        tryCompare(qmlType2UnchangedIntPropChangedSpy, "count", 0)
    }

    function test_defaultProperty() {
        compare(qmlType1.children.length, 0)
        compare(qmlType2.children.length, 0)

        compare(containing1.children.length, 2)
        compare(nested1.strProp, "testString")
        compare(nested2.intProp, 0)

        let expectedStr = "testString3"
        let expectedInt = 30
        nested1.strProp = expectedStr
        nested2.intProp = expectedInt
        compare(nested1.strProp, expectedStr)
        compare(nested2.intProp, expectedInt)
    }

    function test_qmlChildren() {
        compare(containing2.children.length, 5)

        // qmlChildren contains only Swift objects
        compare(containing2.qmlChildrenCount, 4)

        // QmlType1 children
        compare(containing2.type1ChildrenCount, 1)
        // QmlType2 children
        compare(containing2.type2ChildrenCount, 3)
        // QmlType3 children
        compare(containing2.type3ChildrenCount, 0)

        // Sum of QmlType2 children properties
        containing2.updateIntPropSum()
        compare(containing2.intPropSum, 11 + 22 + 33)

        let newValue = 44
        containing2nested.intProp = newValue
        containing2.updateIntPropSum()
        compare(containing2.intPropSum, 11 + 22 + newValue)

        // Ensure correct order of children objects
        var ids = []
        for (var i = 0; i < containing2.children.length; i++) {
            var child = containing2.children[i]
            if (child.strId !== undefined)
                ids.push(child.strId)
        }
        containing2.updateChildrenIds()
        compare(containing2.childrenIds, ids)
    }

    function test_dynamicInstantiation() {
        var instance1 = qmlType1Component.createObject(null)
        verify(instance1)
        compare(instance1.strProp, "testString")

        let expectedStr = "testString4"
        instance1.updateStrProp(expectedStr)
        compare(instance1.strProp, expectedStr)

        var instance2 = qmlType2Component.createObject(null, { intProp: 42 })
        verify(instance2)
        compare(instance2.intProp, 42)

        let expectedInt = 40
        instance2.intProp = expectedInt
        compare(instance2.intProp, expectedInt)

        instance1.destroy()
        instance2.destroy()
    }

    function test_componentComplete() {
        // qmlComponent is now complete, check if the callback was called
        // after the properties were initialized

        let expectedSum = qmlComponent.prop1
                        + qmlComponent.prop2
                        + qmlComponent.prop3
        compare(qmlComponent.sum, expectedSum)
        compare(sumChangedSpy.count, 1)
    }
}
