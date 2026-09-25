// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

enum QtBridgableOutputs {
    static let privateHolderVar : String = """
    private var _objectHolder: QtBridge.QObjectHolder?
    """

    static let holderVar : String = """
    public lazy var objectHolder: QtBridge.QObjectHolder = {
            if let object = _objectHolder {
                return object
            }
            return QtBridge.QObjectHolder(owner: self)
        }()
    """

    static func builderVar(className: String) -> String { """
    static public let metaObjectBuilder: QtBridge.QMetaObjectBuilder = {
            return QtBridge.QMetaObjectBuilder.create(from: \(className).self)
        }()
    """
    }

    static func registerMetaTypeInterface(className: String) -> String { """
    public static func registerMetaTypeInterface(for builder: QtBridge.QMetaObjectBuilder) {
            builder.registerCreateFn(objectHolderPath: \\\(className)._objectHolder)
        }
    """
    }
}
