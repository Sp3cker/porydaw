// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge
import Foundation

@MainActor
@QtBridgeable
public class ListModel {
    var list: [String] = ["lemon"]
    var duplicateStringFound : String = ""

    public func editString(index: Int, newString: String) {
        if list.contains(newString) {
            postDuplicateNotification(with: newString)
        } else {
            list[index] = newString
        }
    }

    public func addString(newString: String) {
        if list.contains(newString) {
            postDuplicateNotification(with: newString)
        } else {
            list.append(newString)
        }
    }

    public func removeString(index: Int) {
        list.remove(at: index)
    }

    private func postDuplicateNotification(with duplicateString: String) {
        duplicateStringFound = duplicateString
    }
}
