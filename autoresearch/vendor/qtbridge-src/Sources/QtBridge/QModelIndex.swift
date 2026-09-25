// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import QtBridgeCpp

internal class QModelIndex {
    var cppModel: QtBridgeCpp.QModelIndex

    init() { self.cppModel = QtBridgeCpp.QModelIndex() }

    internal init(_ cppModel: QtBridgeCpp.QModelIndex) { self.cppModel = cppModel }

    func row() -> Int32 { return cppModel.row() }

    func column() -> Int32 { return cppModel.column() }

    func isValid() -> Bool { return cppModel.isValid() }

    func internalId() -> UInt64 { return cppModel.internalId() }
}
