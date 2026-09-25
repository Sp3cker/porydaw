// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge

@MainActor
@QtBridgeable
public class PropertiesModel {
    public var variantMapProp: [String: QVariantSettable] = [:]

    public func updateVariantMap(map: [String: QVariantSettable]) {
        variantMapProp = map
    }
}
