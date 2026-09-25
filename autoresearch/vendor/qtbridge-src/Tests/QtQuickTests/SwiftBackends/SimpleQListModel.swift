// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge
import Foundation

@MainActor
@QtBridgeable
public class SimpleQListModel {

    var simpleModel: QListModel<String> = ["one", "two"]

    var replacingModel: QListModel<String> = ["a", "b", "c"]

    var simpleModelMirror: [String] = []

    public func updateMirror() { simpleModelMirror = simpleModel.asArray }

    public func addString(newString: String) {
        simpleModel.append(newString)
        updateMirror()
    }

    public func removeString(at index: Int) {
        simpleModel.remove(at: index)
        updateMirror()
    }

    public func replaceString() {
        simpleModel.replaceSubrange(0..<2, with: ["four", "five"])
        updateMirror()
    }

    public func replaceAtIndex(index: Int) {
        simpleModel[index] = "alpha"
        updateMirror()
    }

    public func resetModel() {
        simpleModel.reset()
        updateMirror()
    }

    public func replaceModel() {
        simpleModel = replacingModel
        updateMirror()
    }
}
