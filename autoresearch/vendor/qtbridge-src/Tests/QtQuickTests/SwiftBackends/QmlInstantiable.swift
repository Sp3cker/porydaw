// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge

@QtBridgeable
public class QmlType1: QmlInstantiable {
    public var strProp : String = "testString"
    public var strId : String = ""

    func updateStrProp(newStr: String) {
        strProp = newStr
    }

    required public init() {
    }
}

@QtBridgeable
public class QmlType2: QmlInstantiable {
    public var intProp : Int = 0
    public var strId : String = ""

    func updateIntProp(newInt: Int) {
        intProp = newInt
    }

    required public init() {
    }
}

@QtBridgeable
public class QmlType3: QmlInstantiableStatus {
    public var prop1 : Int = 0
    public var prop2 : Int = 0
    public var prop3 : Int = 0
    public var sum : Int = 0

    required public init() {
    }

    public func componentComplete() {
        sum = prop1 + prop2 + prop3
    }
}

@QtBridgeable
public class QmlType4: QmlInstantiableStatus {
    public var qmlChildrenCount : Int = 0

    public var type1ChildrenCount : Int = 0
    public var type2ChildrenCount : Int = 0
    public var type3ChildrenCount: Int = 0

    public var intPropSum : Int = 0

    public var childrenIds: [String] = []

    required public init() {
    }

    public func updateChildrenIds() {
        for child in qmlChildren {
            if let qmlType1 = child as? QmlType1 {
                childrenIds.append(qmlType1.strId)
            }
            if let qmlType2 = child as? QmlType2 {
                childrenIds.append(qmlType2.strId)
            }
        }
    }

    public func updateIntPropSum() {
        intPropSum = 0
        for child in qmlChildren {
            if let qmlType2 = child as? QmlType2 {
                intPropSum += qmlType2.intProp
            }
        }
    }

    public func componentComplete() {
        qmlChildrenCount = qmlChildren.count

        for child in qmlChildren {
            if child is QmlType1 {
                type1ChildrenCount += 1
            }

            if child is QmlType2 {
                type2ChildrenCount += 1
            }

            if child is QmlType3 {
                type3ChildrenCount += 1
            }
        }
    }
}
