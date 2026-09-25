// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import Foundation
import QtBridge
import XCTest

final class MyQuickTest: XCTestCase {
    func testQtQuick() {
        let listModel = ListModel()
        let simpleModel = SimpleModel()

        let testModule = QmlTestModule(uri: "MyQuickTest",
                                       major: 1, minor: 0,
                                       singletons: ["ListModel": listModel,
                                                    "SimpleModel": simpleModel])

        let config = QtQuickTestConfiguration(
            testName: "minimalapp-autotest",
            inputDir: Bundle(for: MyQuickTest.self).resourceURL!.path,
            registrations: [testModule], arguments: ["-platform", "offscreen"])

        XCTAssertEqual(QtQuickTestRunner.run(config: config), 0)
    }
}
