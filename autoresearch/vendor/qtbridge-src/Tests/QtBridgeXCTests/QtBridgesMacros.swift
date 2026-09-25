// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

import QtBridge
import QtBridgeMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class QtBridgeableExpansionTest: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "QtBridgeable": QtBridgeableMacro.self,
        "QtTracked": QtTrackedMacro.self,
        "QtIgnored": QtIgnoredMacro.self,
        "QtSignal": QtSignalMacro.self
    ]

    func testQtBridgeableOnUnsupportedTypeEmitsError() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public struct TestModel {
                var someVar: [String] = ["test String"]
            }
            """,
            expandedSource:
            """
            public struct TestModel {
                var someVar: [String] = ["test String"] {
                    didSet {
                        self.emitSignal(for: "someVar")
                    }
                }
            }
            """,
            diagnostics: [
                .init(
                    message: "'@QtBridgeable' can only be applied to class type",
                    line: 1, column: 1, severity: .error
                )
            ],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testIsQtTrackedAttached() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                var someVar: [String] = ["test String"]
            }
            """,
            expandedSource:
            """
            public class TestModel {
                @QtTracked
                var someVar: [String] = ["test String"]

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "someVar",
                    keyPath: \\TestModel.someVar
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: ["QtBridgeable": QtBridgeableMacro.self],
            indentationWidth: .spaces(4)
            )
    }

    func testQtBridgeableMacroFullExpansion() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestType {
                var name: String = ""
                public init(name: String) {
                    self.name = name
                }
            }

            @QtBridgeable
            public class TestModel {
                var someVar: [String] = ["test String"]

                @QtTracked
                var userType: [TestType] = []

                var userTypeNotTracked: [TestType] = []
            }
            """,
            expandedSource:
            """
            public class TestType {
                var name: String = "" {
                    didSet {
                        self.emitSignal(for: "name")
                    }
                }
                public init(name: String) {
                    self.name = name
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestType"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "name",
                    keyPath: \\TestType.name
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestType"))
            }
            public class TestModel {
                var someVar: [String] = ["test String"] {
                    didSet {
                        self.emitSignal(for: "someVar")
                    }
                }
                var userType: [TestType] = [] {
                    didSet {
                        self.emitSignal(for: "userType")
                    }
                }

                var userTypeNotTracked: [TestType] = []

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "someVar",
                    keyPath: \\TestModel.someVar
                    )

                    builder.registerProperty(
                        name: "userType",
                        keyPath: \\TestModel.userType
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testQtTrackedExpansion() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class Person {
                var name: String = ""
                var lastName: String = ""
                var phone: Int = 0
                public init(name: String, lastName: String, phone: Int) {
                    self.name = name
                    self.lastName = lastName
                    self.phone = phone
                }
            }

            @QtBridgeable
            public class PhoneBook {
                @QtTracked
                var contacts: [Person] = []
            }
            """,
            expandedSource:
            """
            @QtBridgeable
            public class Person {
                var name: String = ""
                var lastName: String = ""
                var phone: Int = 0
                public init(name: String, lastName: String, phone: Int) {
                    self.name = name
                    self.lastName = lastName
                    self.phone = phone
                }
            }

            @QtBridgeable
            public class PhoneBook {
                var contacts: [Person] = [] {
                    didSet {
                        self.emitSignal(for: "contacts")
                    }
                }
            }
            """,
            macros: ["QtTracked": QtTrackedMacro.self],
            indentationWidth: .spaces(4)
        )
    }

    func testQtIgnored() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                @QtIgnored
                var someVar: [String] = ["test String"]
            }
            """,
            expandedSource:
            """
            public class TestModel {
                var someVar: [String] = ["test String"]

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)

                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testConstantProp() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                let someConst: [String] = ["test String"]
                private var somePrivate: [String] = ["test String"]
                static var someStatic: [String] = ["test String"]
            }
            """,
            expandedSource:
            """
            public class TestModel {
                let someConst: [String] = ["test String"]
                private var somePrivate: [String] = ["test String"]
                static var someStatic: [String] = ["test String"]

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "someConst",
                    keyPath: \\TestModel.someConst
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testSupportedBasicTypes() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                var someInt: Int = 1
                var someUInt: UInt = 3
                var someBool: Bool = true
                var someDouble: Double = 1.33
                var someFloat: Float = 1.3
                var someString: String = "some String"
                var someArray: [ String] = ["some Array"]
                var someArrayTwo: Array< String > = ["some Array"]
                var someVariantMap1: [ String : QVariantSettable ] = [:]
                var someVariantMap2: Dictionary< String, QVariantSettable > /* some comment */ = [:]
            }
            """,
            expandedSource:
            """
            public class TestModel {
                @QtTracked
                var someInt: Int = 1
                @QtTracked
                var someUInt: UInt = 3
                @QtTracked
                var someBool: Bool = true
                @QtTracked
                var someDouble: Double = 1.33
                @QtTracked
                var someFloat: Float = 1.3
                @QtTracked
                var someString: String = "some String"
                @QtTracked
                var someArray: [ String] = ["some Array"]
                @QtTracked
                var someArrayTwo: Array< String > = ["some Array"]
                @QtTracked
                var someVariantMap1: [ String : QVariantSettable ] = [:]
                @QtTracked
                var someVariantMap2: Dictionary< String, QVariantSettable > /* some comment */ = [:]

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "someInt",
                    keyPath: \\TestModel.someInt
                    )

                    builder.registerProperty(
                        name: "someUInt",
                        keyPath: \\TestModel.someUInt
                    )

                    builder.registerProperty(
                        name: "someBool",
                        keyPath: \\TestModel.someBool
                    )

                    builder.registerProperty(
                        name: "someDouble",
                        keyPath: \\TestModel.someDouble
                    )

                    builder.registerProperty(
                        name: "someFloat",
                        keyPath: \\TestModel.someFloat
                    )

                    builder.registerProperty(
                        name: "someString",
                        keyPath: \\TestModel.someString
                    )

                    builder.registerProperty(
                        name: "someArray",
                        keyPath: \\TestModel.someArray
                    )

                    builder.registerProperty(
                        name: "someArrayTwo",
                        keyPath: \\TestModel.someArrayTwo
                    )

                    builder.registerProperty(
                        name: "someVariantMap1",
                        keyPath: \\TestModel.someVariantMap1
                    )

                    builder.registerProperty(
                        name: "someVariantMap2",
                        keyPath: \\TestModel.someVariantMap2
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: ["QtBridgeable": QtBridgeableMacro.self],
            indentationWidth: .spaces(4)
        )
    }

    func testUnsupportedBasicTypes() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                var someInt8: Int8 = 1
                var someUInt8: UInt8 = 3
                var someInt16: Int16 = 1
                var someUInt16: UInt16 = 3
                var someInt32: Int32 = 1
                var someUInt32: UInt32 = 3
                var someInt64: Int64 = 1
                var someUInt64: UInt64 = 3
                var someChar: Character = "M"
                var someSubstring: Substring = "Hello, Qt!".prefix(5)
                var someAny: Any = 13
                var someAnyObject: AnyObject = NSObject()
                var someData: Data = Data([0x51, 0x74])
                var someDate: Date = Date(timeIntervalSince1970: 0)
                var someURL: URL = URL(string: "https://example.com")!
                var someUUID: UUID = UUID(uuidString: "1234-1234-1234-1234")!
                var someDecimal: Decimal = Decimal(string: "123456.789")!
                var someDictionary: [String: Int] = ["one": 1, "two": 2]
                var someSet: Set<String> = ["apple", "banana", "cherry"]
                var someOptional: String? = "Hello Optional"
                var someIntList: [Int] = [1, 3]
                var someCharList: [Character] = ["M", "L"]
                var someAnyList: [Any] = ["M", 13]
            }
            """,
            expandedSource:
            """
            public class TestModel {
                var someInt8: Int8 = 1
                var someUInt8: UInt8 = 3
                var someInt16: Int16 = 1
                var someUInt16: UInt16 = 3
                var someInt32: Int32 = 1
                var someUInt32: UInt32 = 3
                var someInt64: Int64 = 1
                var someUInt64: UInt64 = 3
                var someChar: Character = "M"
                var someSubstring: Substring = "Hello, Qt!".prefix(5)
                var someAny: Any = 13
                var someAnyObject: AnyObject = NSObject()
                var someData: Data = Data([0x51, 0x74])
                var someDate: Date = Date(timeIntervalSince1970: 0)
                var someURL: URL = URL(string: "https://example.com")!
                var someUUID: UUID = UUID(uuidString: "1234-1234-1234-1234")!
                var someDecimal: Decimal = Decimal(string: "123456.789")!
                var someDictionary: [String: Int] = ["one": 1, "two": 2]
                var someSet: Set<String> = ["apple", "banana", "cherry"]
                var someOptional: String? = "Hello Optional"
                var someIntList: [Int] = [1, 3]
                var someCharList: [Character] = ["M", "L"]
                var someAnyList: [Any] = ["M", 13]

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)

                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: ["QtBridgeable": QtBridgeableMacro.self],
            indentationWidth: .spaces(4)
        )
    }

    func testQSignalMacroExpansionNoParams() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                @QtSignal
                func mySignal()
            }
            """,
            expandedSource:
            """
            public class TestModel {
                func mySignal() {
                    emitSignal(signalName: "mySignal", args: [])
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    let signalArgTypes1 : [QVariantGettable.Type] = []

                    builder.registerSignal(signalName: "mySignal", argTypes: signalArgTypes1)
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testQSignalMacroExpansionWithParams() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                @QtSignal
                func mySignal(text: String)

                @QtSignal
                func mySignal2(intParam: Int, boolParam: Bool, doubleParam: Double)
            }
            """,
            expandedSource:
            """
            public class TestModel {
                func mySignal(text: String) {
                    emitSignal(signalName: "mySignal", args: [text.toVariant()])
                }
                func mySignal2(intParam: Int, boolParam: Bool, doubleParam: Double) {
                    emitSignal(signalName: "mySignal2", args: [intParam.toVariant(), boolParam.toVariant(), doubleParam.toVariant()])
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    var signalArgTypes1 : [QVariantGettable.Type] = []
                    signalArgTypes1.append(String.self)
                    builder.registerSignal(signalName: "mySignal", argTypes: signalArgTypes1)

                    var signalArgTypes2 : [QVariantGettable.Type] = []
                    signalArgTypes2.append(Int.self)
                    signalArgTypes2.append(Bool.self)
                    signalArgTypes2.append(Double.self)
                    builder.registerSignal(signalName: "mySignal2", argTypes: signalArgTypes2)
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testQtSignalWithFunctionBody() {
        assertMacroExpansion(
            """
            public class TestModel {
                @QtSignal
                func mySignal() {
                    print("Signal!")
                }
            }
            """,
            expandedSource:
            """
            public class TestModel {
                func mySignal() {
                    print("Signal!")
                }
            }
            """,
            diagnostics: [
                .init(
                    message: "'@QtSignal' functions must not have a body",
                    line: 2, column: 5, severity: .error
                )
            ],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testQtSignalUnSupportedParameterType() {
        assertMacroExpansion(
            """
            public class TestModel {
                @QtSignal
                func mySignal(someVar: Any)
            }
            """,
            expandedSource:
            """
            public class TestModel {
                func mySignal(someVar: Any)
            }
            """,
            diagnostics: [
                .init(
                    message: "Unsupported parameter type: Any",
                    line: 2, column: 5, severity: .error
                )
            ],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testSlotsWithSupportedReturnType() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                public func addInts(first: Int, second: Int) -> Int {
                    return first + second
                }
                public func concatStrings(first: String, second: String) -> String {
                    return first + " " + second
                }
                public func explicitVoid() -> Void {
                    explicitVoid()
                }
                public func emptyTuple() -> () {
                    emptyTuple()
                }
                public func implicitVoid() {
                    implicitVoid()
                }
            }
            """,
            expandedSource:
            """
            public class TestModel {
                public func addInts(first: Int, second: Int) -> Int {
                    return first + second
                }
                public func concatStrings(first: String, second: String) -> String {
                    return first + " " + second
                }
                public func explicitVoid() -> Void {
                    explicitVoid()
                }
                public func emptyTuple() -> () {
                    emptyTuple()
                }
                public func implicitVoid() {
                    implicitVoid()
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    var argTypes1 : [QVariantGettable.Type] = []
                    argTypes1.append(Int.self)
                    argTypes1.append(Int.self)
                    builder.registerSlot(
                        name: "addInts",
                        returnType: Int.self,
                        argTypes: argTypes1,
                        method: { (owner: Any, args: QMetaParamsList) in
                        guard let self = owner as? TestModel else {
                            return QVariant()
                        }
                        let first : Int = args.get(0)
                        let second : Int = args.get(1)
                        return QVariant(value: self.addInts(first: first, second: second))
                    })

                    var argTypes2 : [QVariantGettable.Type] = []
                    argTypes2.append(String.self)
                    argTypes2.append(String.self)
                    builder.registerSlot(
                        name: "concatStrings",
                        returnType: String.self,
                        argTypes: argTypes2,
                        method: { (owner: Any, args: QMetaParamsList) in
                        guard let self = owner as? TestModel else {
                            return QVariant()
                        }
                        let first : String = args.get(0)
                        let second : String = args.get(1)
                        return QVariant(value: self.concatStrings(first: first, second: second))
                    })

                    let argTypes3 : [QVariantGettable.Type] = []

                    builder.registerSlot(
                        name: "explicitVoid",
                        returnType: nil,
                        argTypes: argTypes3,
                        method: { (owner: Any, args: QMetaParamsList) in
                        guard let self = owner as? TestModel else {
                            return QVariant()
                        }

                        self.explicitVoid()
                        return QVariant()
                    })

                    let argTypes4 : [QVariantGettable.Type] = []

                    builder.registerSlot(
                        name: "emptyTuple",
                        returnType: nil,
                        argTypes: argTypes4,
                        method: { (owner: Any, args: QMetaParamsList) in
                        guard let self = owner as? TestModel else {
                            return QVariant()
                        }

                        self.emptyTuple()
                        return QVariant()
                    })

                    let argTypes5 : [QVariantGettable.Type] = []

                    builder.registerSlot(
                        name: "implicitVoid",
                        returnType: nil,
                        argTypes: argTypes5,
                        method: { (owner: Any, args: QMetaParamsList) in
                        guard let self = owner as? TestModel else {
                            return QVariant()
                        }

                        self.implicitVoid()
                        return QVariant()
                    })
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testSlotsWithUnsupportedReturnType() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class TestModel {
                public func returnAny(first: Int, second: Int) -> Any {
                    return first + second
                }
            }
            """,
            expandedSource:
            """
            public class TestModel {
                public func returnAny(first: Int, second: Int) -> Any {
                    return first + second
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "TestModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)

                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "TestModel"))
            }
            """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }
    func testQTableModelIsTracked() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class MyModel {
                public var table: QTableModel<Person>

                public var people = [
                    Person(givenName: "Harry", number: 1, lastName: "Potter"),
                    Person(givenName: "Hermione", number: 2, lastName: "Granger"),
                    Person(givenName: "Ron", number: 3, lastName: "Weasley")
                ]

                public init() {
                    self.table = QTableModel(people) {
                        [
                            QTableColumn("Name:", value: \\.givenName),
                            QTableColumn("Last Name:", value: \\.lastName),
                            QTableColumn("Number: ", value: \\.number)
                        ]
                    }
                }
            }
            """,
            expandedSource:
            """
            public class MyModel {
                public var table: QTableModel<Person> {
                    didSet {
                        self.emitSignal(for: "table")
                    }
                }

                public var people = [
                    Person(givenName: "Harry", number: 1, lastName: "Potter"),
                    Person(givenName: "Hermione", number: 2, lastName: "Granger"),
                    Person(givenName: "Ron", number: 3, lastName: "Weasley")
                ]

                public init() {
                    self.table = QTableModel(people) {
                        [
                            QTableColumn("Name:", value: \\.givenName),
                            QTableColumn("Last Name:", value: \\.lastName),
                            QTableColumn("Number: ", value: \\.number)
                        ]
                    }
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "MyModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)
                    builder.registerProperty(
                    name: "table",
                    keyPath: \\MyModel.table
                    )
                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "MyModel"))
            }
            """,
            macros: macros
        )
    }

    func testQTableModelIsIgnored() {
        assertMacroExpansion(
            """
            @QtBridgeable
            public class MyModel {
                @QtIgnored
                public var table: QTableModel<Person>

                public var people = [
                    Person(givenName: "Harry", number: 1, lastName: "Potter"),
                    Person(givenName: "Hermione", number: 2, lastName: "Granger"),
                    Person(givenName: "Ron", number: 3, lastName: "Weasley")
                ]

                public init() {
                    self.table = QTableModel(people) {
                        [
                            QTableColumn("Name:", value: \\.givenName),
                            QTableColumn("Last Name:", value: \\.lastName),
                            QTableColumn("Number: ", value: \\.number)
                        ]
                    }
                }
            }
            """,
            expandedSource:
            """
            public class MyModel {
                public var table: QTableModel<Person>

                public var people = [
                    Person(givenName: "Harry", number: 1, lastName: "Potter"),
                    Person(givenName: "Hermione", number: 2, lastName: "Granger"),
                    Person(givenName: "Ron", number: 3, lastName: "Weasley")
                ]

                public init() {
                    self.table = QTableModel(people) {
                        [
                            QTableColumn("Name:", value: \\.givenName),
                            QTableColumn("Last Name:", value: \\.lastName),
                            QTableColumn("Number: ", value: \\.number)
                        ]
                    }
                }

                \(QtBridgableOutputs.privateHolderVar)

                \(QtBridgableOutputs.holderVar)

                \(QtBridgableOutputs.builderVar(className: "MyModel"))

                public static func registerMethodsAndProperties(for builder: QtBridge.QMetaObjectBuilder) {
                    builder.startRegistration(for: self)

                }

                \(QtBridgableOutputs.registerMetaTypeInterface(className: "MyModel"))
            }
            """,
            macros: macros
        )
    }
}
