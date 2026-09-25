// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtBridge
import Foundation

@main
struct MyApp: QApp {
    let qmlFileName: String = "ColorPalette/Main"
    var instantiableTypes: [QmlInstantiable.Type] = [
        PaginatedResourceColors.self,
        PaginatedResourceUsers.self,
        RestService.self,
        BasicLogin.self
    ]
}
