// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import Foundation
import QmlImports
import QtBridge
import XCTest

@MainActor
final class QtBridgeQuickTest: XCTestCase {
    func testQtQuick() async {
        var testModule = QmlTestModule(uri: "QtBridgeTest",
                                       major: 1, minor: 0,
                                       singletons: [:])

        testModule.singletons["PhoneBookModel"] = PhoneBookModel()
        testModule.singletons["ListModel"] = ListModel()
        testModule.singletons["PropertiesModel"] = PropertiesModel()
        testModule.singletons["SimpleQListModel"] = SimpleQListModel()
        testModule.singletons["SignalsModel"] = SignalsModel()
        testModule.singletons["SlotsModel"] = SlotsModel()
        testModule.singletons["TableModel"] = TableModel()

        QmlType1.registerQmlElement()
        QmlType2.registerQmlElement()
        QmlType3.registerQmlElement()
        QmlType4.registerQmlElement()

        let config = QtQuickTestConfiguration(
            testName: "qtbridge-autotest",
            inputDir: Bundle.module.url(forResource: "qml", withExtension: nil)!,
            registrations: [testModule],
            arguments: ["-platform", "offscreen"])

        XCTAssertEqual(QtQuickTestRunner.run(config: config), 0)
    }
}
