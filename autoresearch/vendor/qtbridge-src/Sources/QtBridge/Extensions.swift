// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import QtBridgeCpp

extension QtBridgeCpp.QVariantMap {
    @MainActor
    internal func toBridgeMap() -> [String: QVariantSettable] {
        var result : [String: QVariantSettable] = [:]
        let keys = self.keys()
        for i in 0..<keys.size() {
            let key = keys[i]
            let value = self[key]
            guard let settable = QVariant(value: value).toSettable() else {
                continue
            }
            result[String(key.toStdString())] = settable
        }
        return result
    }
}

extension QtBridgeCpp.QString {
    internal func toSwiftString() -> String {
        return String(self.toStdString())
    }
}

extension String {
    internal func toQString() -> QtBridgeCpp.QString {
#if QT_IS_CXX_20
            // QString.init(_:) becomes ambiguous with C++20
            let stdStr = std.string(self)
            return QString.fromStdString(stdStr)
#else
            return QString(self)
#endif
    }
}
