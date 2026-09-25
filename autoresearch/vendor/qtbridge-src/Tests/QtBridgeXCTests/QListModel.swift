// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge
import QtBridgeMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class QListModelTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "QtBridgeable": QtBridgeableMacro.self,
        "QtTracked": QtTrackedMacro.self,
        "QtIgnored": QtIgnoredMacro.self
    ]

    func testQtListModelWithSupportedTypes() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                public var intModel: QListModel<Int> = [1, 2, 3]
                public var uintModel: QListModel<UInt> = [1, 2, 3]
                public var boolModel: QListModel<Bool> = [true, false, true]
                public var doubleModel: QListModel<Double> = [1.22, 2.33, 3.44]
                public var floatModel: QListModel<Float> = [1.2, 2.3, 3.4]
                public var stringModel: QListModel<String> = ["One, two, three", "four, five, six"]
                public var arrayModel: QListModel<[String]> = [["one", "two"], ["three","four"]]
                public var arrayTwoModel: QListModel<Array<String>> = [["four", "five"], ["six","seven"]]
            }
            """,
            expandedSource:
            """
            public class TestModel {
                public var intModel: QListModel<Int> = [1, 2, 3] {
                    didSet {
                        self.emitSignal(for: "intModel")
                    }
                }
                public var uintModel: QListModel<UInt> = [1, 2, 3] {
                    didSet {
                        self.emitSignal(for: "uintModel")
                    }
                }
                public var boolModel: QListModel<Bool> = [true, false, true] {
                    didSet {
                        self.emitSignal(for: "boolModel")
                    }
                }
                public var doubleModel: QListModel<Double> = [1.22, 2.33, 3.44] {
                    didSet {
                        self.emitSignal(for: "doubleModel")
                    }
                }
                public var floatModel: QListModel<Float> = [1.2, 2.3, 3.4] {
                    didSet {
                        self.emitSignal(for: "floatModel")
                    }
                }
                public var stringModel: QListModel<String> = ["One, two, three", "four, five, six"] {
                    didSet {
                        self.emitSignal(for: "stringModel")
                    }
                }
                public var arrayModel: QListModel<[String]> = [["one", "two"], ["three","four"]] {
                    didSet {
                        self.emitSignal(for: "arrayModel")
                    }
                }
                public var arrayTwoModel: QListModel<Array<String>> = [["four", "five"], ["six","seven"]] {
                    didSet {
                        self.emitSignal(for: "arrayTwoModel")
                    }
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "intModel",
                    keyPath: \\TestModel.intModel
                    )

                    builder.registerProperty(
                        name: "uintModel",
                        keyPath: \\TestModel.uintModel
                    )

                    builder.registerProperty(
                        name: "boolModel",
                        keyPath: \\TestModel.boolModel
                    )

                    builder.registerProperty(
                        name: "doubleModel",
                        keyPath: \\TestModel.doubleModel
                    )

                    builder.registerProperty(
                        name: "floatModel",
                        keyPath: \\TestModel.floatModel
                    )

                    builder.registerProperty(
                        name: "stringModel",
                        keyPath: \\TestModel.stringModel
                    )

                    builder.registerProperty(
                        name: "arrayModel",
                        keyPath: \\TestModel.arrayModel
                    )

                    builder.registerProperty(
                        name: "arrayTwoModel",
                        keyPath: \\TestModel.arrayTwoModel
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testQListModelCustomType() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class Message {
                var author: String
                var textmessage: String
                var date: String

                public init(author: String, textmessage: String, date: String) {
                    self.author = author
                    self.textmessage = textmessage
                    self.date = date
                }
            }

            @QtBridgeable
            public class ChatModel {

                public var msgs: QListModel<Message> = []
            }
            """,
            expandedSource:
            """
            public class Message {
                var author: String {
                    didSet {
                        self.emitSignal(for: "author")
                    }
                }
                var textmessage: String {
                    didSet {
                        self.emitSignal(for: "textmessage")
                    }
                }
                var date: String {
                    didSet {
                        self.emitSignal(for: "date")
                    }
                }

                public init(author: String, textmessage: String, date: String) {
                    self.author = author
                    self.textmessage = textmessage
                    self.date = date
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "Message"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "author",
                    keyPath: \\Message.author
                    )

                    builder.registerProperty(
                        name: "textmessage",
                        keyPath: \\Message.textmessage
                    )

                    builder.registerProperty(
                        name: "date",
                        keyPath: \\Message.date
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "Message"))
            }
            public class ChatModel {

                public var msgs: QListModel<Message> = [] {
                    didSet {
                        self.emitSignal(for: "msgs")
                    }
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "ChatModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "msgs",
                    keyPath: \\ChatModel.msgs
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "ChatModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testQListModelQtIgnored() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class Message {
                var author: String
                var textmessage: String
                var date: String

                public init(author: String, textmessage: String, date: String) {
                    self.author = author
                    self.textmessage = textmessage
                    self.date = date
                }
            }

            @QtBridgeable
            public class ChatModel {

                @QtIgnored
                public var msgs: QListModel<Message> = []
            }
            """,
            expandedSource:
            """
            public class Message {
                var author: String {
                    didSet {
                        self.emitSignal(for: "author")
                    }
                }
                var textmessage: String {
                    didSet {
                        self.emitSignal(for: "textmessage")
                    }
                }
                var date: String {
                    didSet {
                        self.emitSignal(for: "date")
                    }
                }

                public init(author: String, textmessage: String, date: String) {
                    self.author = author
                    self.textmessage = textmessage
                    self.date = date
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "Message"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "author",
                    keyPath: \\Message.author
                    )

                    builder.registerProperty(
                        name: "textmessage",
                        keyPath: \\Message.textmessage
                    )

                    builder.registerProperty(
                        name: "date",
                        keyPath: \\Message.date
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "Message"))
            }
            public class ChatModel {
                public var msgs: QListModel<Message> = []

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "ChatModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)

                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "ChatModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    @MainActor
    func testQListModelCollectionBehavior() async {
        var simpleModel = QListModel<Int>([1, 2, 3])
        XCTAssertEqual(simpleModel.startIndex, 0)
        XCTAssertEqual(simpleModel.endIndex, 3)
        XCTAssertEqual(simpleModel[2], 3)
        simpleModel.insert(contentsOf: [4, 5], at: 0)
        XCTAssertEqual(simpleModel.asArray, [4,5,1,2,3])

        simpleModel.removeLast()
        XCTAssertEqual(simpleModel.asArray, [4,5,1,2])

        simpleModel.replaceSubrange(0..<4, with: [4,4,4,4])
        XCTAssertEqual(simpleModel.asArray, [4,4,4,4])

        simpleModel[2] = 0
        XCTAssertEqual(simpleModel.asArray, [4, 4, 0, 4])

        simpleModel.reset()
        XCTAssertEqual(simpleModel.asArray, [])
    }
}
