// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge
import Foundation

@MainActor
@QtBridgeable
public final class SlotsModel {
    public func addInts(first: Int, second: Int) -> Int {
        return first + second
    }
    public func addUInts(first: UInt, second: UInt) -> UInt {
        return first + second
    }
    public func checkTruth(first: Bool, second: Bool) -> Bool {
        return first == second ? true : false
    }
    public func addDoubles(first: Double, second: Double) -> Double {
        return first + second
    }
    public func addFloats(first: Float, second: Float) -> Float {
        return first + second
    }
    public func concatStrings(first: String, second: String) -> String {
        return first + ", " + second
    }
    public func makeList(first: String, second: String) -> [String] {
        return [first, second]
    }
    public func addElementToMap(map: [String: QVariantSettable], key: String, value: String) -> [String: QVariantSettable] {
        var newMap = map
        newMap[key] = value as QVariantSettable
        return newMap
    }
}
