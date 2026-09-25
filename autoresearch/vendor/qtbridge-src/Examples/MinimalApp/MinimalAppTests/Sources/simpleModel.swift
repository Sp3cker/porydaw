// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import Foundation
import QtBridge

@QtBridgeable
public class SimpleModel {
    var simpleList: QListModel<String> = ["one", "two"]

    public func addString(newString: String) {
        simpleList.append(newString)
    }
}
