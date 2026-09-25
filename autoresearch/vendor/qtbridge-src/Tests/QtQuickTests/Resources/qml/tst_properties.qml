// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtQuick 2.15
import QtTest 1.3
import QtBridgeTest 1.0

TestCase {
    name: "Properties Test Suite"
    when: windowShown

    SignalSpy {
        id: spy
        target: PropertiesModel
        signalName: "variantMapPropChanged"
    }

    function test_variantMap() {
        spy.clear()

        compare(Object.keys(PropertiesModel.variantMapProp).length, 0)

        PropertiesModel.updateVariantMap({
            "name": "Matcha Latte",
            "isAvailable": true,
            "cost": 64.99
        })

        spy.wait()
        compare(spy.count, 1)
        compare(Object.keys(PropertiesModel.variantMapProp).length, 3)
        compare(PropertiesModel.variantMapProp["name"], "Matcha Latte")
        compare(PropertiesModel.variantMapProp["isAvailable"], true)
        compare(PropertiesModel.variantMapProp["cost"], 64.99)

        spy.clear()
        PropertiesModel.variantMapProp = {
            "score": 23
        }

        spy.wait()
        compare(spy.count, 1)
        compare(Object.keys(PropertiesModel.variantMapProp).length, 1)
        compare(PropertiesModel.variantMapProp["score"], 23)
    }
}
