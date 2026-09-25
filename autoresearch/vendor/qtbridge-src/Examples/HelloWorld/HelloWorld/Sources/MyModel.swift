// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import Foundation
import QtBridge

@MainActor
@QtBridgeable
public class MyModel {
    public var name: String = ""
    public var greeting: String = "Hello, World!"

    public init() {}

    public func greet() {
        greeting = name.isEmpty ? "Hello, World!" : "Hello, \(name)!"
    }
}
