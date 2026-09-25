// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import QtBridgeCpp

/// A list of arguments passed from QML to a Swift method.
///
/// `QMetaParamsList` is used internally by the Qt Bridge
/// bridging system and is not intended to be created or used
/// directly.
///
/// ## Supported Types
///
/// Qt Bridge provides support for methods with the arguments
/// of the following types:
///
/// | Swift | Qt |
/// |---|---|
/// | `Bool` | `bool` |
/// | `Int` | `int` |
/// | `UInt` | `uint` |
/// | `Double` | `double` |
/// | `Float` | `float` |
/// | `String` | `QString` |
/// | `[String]` | `QStringList` |
/// | `[String: QVariantSettable]` | `QVariantMap` |
///
@MainActor
public class QMetaParamsList {
    private let args: MetaParamsList

    internal init(args: MetaParamsList) {
        self.args = args
    }

    /// Returns the argument at the given index as the
    /// inferred Swift type.
    ///
    /// - Parameter index: The zero-based position
    /// of the argument in the list.
    /// - Returns: The argument at `index` as type `T`.
    public func get<T: QMetaParamsGettable>(_ index: Int) -> T {
        return T.get(from: self, index: index)
    }

    fileprivate func getBool(_ index: Int) -> Bool { return args.getBool(index) }
    fileprivate func getInt(_ index: Int) -> Int { return Int(args.getInt(index)) }
    fileprivate func getUInt(_ index: Int) -> UInt { return UInt(args.getUInt(index)) }
    fileprivate func getDouble(_ index: Int) -> Double { return args.getDouble(index) }
    fileprivate func getFloat(_ index: Int) -> Float { return args.getFloat(index) }
    fileprivate func getString(_ index: Int) -> String { return String(args.getString(index)) }
    fileprivate func getStringList(_ index: Int) -> [String] {
        var result : [String] = []
        let list = args.getStringList(index)
        for i in 0..<list.size() {
            result.append(list[i].toSwiftString())
        }
        return result
    }
    fileprivate func getMap(_ index: Int) -> [String: QVariantSettable] {
        return args.getVariantMap(index).toBridgeMap()
    }
}

/// A type that can be extracted from a ``QMetaParamsList``.
@MainActor
public protocol QMetaParamsGettable {

    /// Extracts a value of this type from the parameter list.
    ///
    /// - Parameters:
    ///   - params: The parameter list received from QML.
    ///   - index: The zero-based position of the argument
    ///   to extract.
    /// - Returns: The extracted value as `Self`.
    static func get(from params: QMetaParamsList, index: Int) -> Self
}

extension Bool: QMetaParamsGettable {
    public static func get(from params: QMetaParamsList, index: Int) -> Bool {
        return params.getBool(index)
    }
}

extension Int: QMetaParamsGettable {
    public static func get(from params: QMetaParamsList, index: Int) -> Int {
        return params.getInt(index)
    }
}

extension UInt: QMetaParamsGettable {
    public static func get(from params: QMetaParamsList, index: Int) -> UInt {
        return params.getUInt(index)
    }
}

extension Double: QMetaParamsGettable {
    public static func get(from params: QMetaParamsList, index: Int) -> Double {
        return params.getDouble(index)
    }
}

extension Float: QMetaParamsGettable {
    public static func get(from params: QMetaParamsList, index: Int) -> Float {
        return params.getFloat(index)
    }
}

extension String: QMetaParamsGettable {
    public static func get(from params: QMetaParamsList, index: Int) -> String {
        return params.getString(index)
    }
}

extension Array: QMetaParamsGettable where Element == String {
    public static func get(from params: QMetaParamsList, index: Int) -> [String] {
        return params.getStringList(index)
    }
}

extension Dictionary: QMetaParamsGettable where Key == String, Value == any QVariantSettable {
    public static func get(from params: QMetaParamsList, index: Int) -> [String: QVariantSettable] {
        return params.getMap(index)
    }
}
