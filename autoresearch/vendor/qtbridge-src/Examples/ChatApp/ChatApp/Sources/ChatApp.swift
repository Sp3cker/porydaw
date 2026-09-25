// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import Foundation
import QtBridge

@main
struct ChatApp: QApp {
    let qmlFileName: String = "chatUI"
    var initialProperties: [String : QtBridge.QObjectBuildable] = [
        "chatModel" : ChatModel()
    ]
}
