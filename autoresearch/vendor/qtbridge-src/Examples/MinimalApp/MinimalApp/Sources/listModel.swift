// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import Foundation
import QtBridge

@MainActor
@QtBridgeable
public class ListModel {
    var list: QListModel<String> = ["test string"]
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
