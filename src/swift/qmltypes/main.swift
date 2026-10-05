import Foundation
import PorydawApp
import PorydawQmlTypesQt
import QtBridge
import QtBridgeCpp

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(ucrt)
    import ucrt
#endif

// Swift imports these enum types, but not their named C++ enumerators.
private let qtMethodTypeMethod = QMetaMethod.MethodType(rawValue: numericCast(pd_qmltypes_method_kind_method()))
    .rawValue
private let qtMethodTypeSignal = QMetaMethod.MethodType(rawValue: numericCast(pd_qmltypes_method_kind_signal()))
    .rawValue
private let qtMethodTypeSlot = QMetaMethod.MethodType(rawValue: numericCast(pd_qmltypes_method_kind_slot())).rawValue
private let qtMethodAccessPublic = QMetaMethod.Access(rawValue: numericCast(pd_qmltypes_method_access_public()))
    .rawValue

private enum QmlTypesError: Error, CustomStringConvertible {
    case invalidMetadata(String)

    var description: String {
        switch self {
        case .invalidMetadata(let message): message
        }
    }
}

private struct Export {
    let name: String
    let uri: String
    let creatable: Bool
}

private struct ToolingType {
    let name: String
    let isList: Bool
    let isPointer: Bool

    init(_ runtimeName: String) {
        var elementName = runtimeName
        if runtimeName.hasPrefix("QQmlListProperty<"), runtimeName.hasSuffix(">") {
            elementName = String(runtimeName.dropFirst("QQmlListProperty<".count).dropLast())
            isList = true
        } else if runtimeName.hasPrefix("QList<"), runtimeName.hasSuffix(">") {
            elementName = String(runtimeName.dropFirst("QList<".count).dropLast())
            isList = true
        } else {
            isList = false
        }
        isPointer = elementName.hasSuffix("*")
        name = isPointer ? String(elementName.dropLast()).trimmingCharacters(in: .whitespaces) : elementName
    }

    func fields(indent: String) -> String {
        var result = "\(indent)type: \(quoted(name))\n"
        if isList {
            result += "\(indent)isList: true\n"
        }
        if isPointer {
            result += "\(indent)isPointer: true\n"
        }
        return result
    }
}

private func quoted(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
        switch scalar.value {
        case 0x22: result += "\\\""
        case 0x5C: result += "\\\\"
        case 0x0A: result += "\\n"
        case 0x0D: result += "\\r"
        case 0x09: result += "\\t"
        case 0..<0x20: result += String(format: "\\u%04x", scalar.value)
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}

private func runtimeType(named name: String) -> QMetaType {
    name.withCString { pointer in
        QMetaType(pd_qmltypes_metatype_id(pointer))
    }
}

private func typeName(_ type: QMetaType, context: String) throws -> String {
    guard type.isValid(), let name = type.name() else {
        throw QmlTypesError.invalidMetadata("Unresolved runtime type for \(context)")
    }
    return String(cString: name)
}

private struct MetaObjectWalk {
    private var objects: [String: UnsafePointer<QMetaObject>] = [:]
    private var pending: [UnsafePointer<QMetaObject>] = []
    private let qObject = runtimeType(named: "QObject*").metaObject()

    mutating func add(_ object: UnsafePointer<QMetaObject>) {
        let name = String(cString: object.pointee.className())
        guard objects[name] == nil else { return }
        objects[name] = object
        pending.append(object)
    }

    mutating func add(_ type: QMetaType) {
        if let object = type.metaObject(), let qObject, object.pointee.inherits(qObject) {
            add(object)
        } else if let runtimeName = type.name() {
            let toolingType = ToolingType(String(cString: runtimeName))
            if toolingType.isList {
                let pointerType = runtimeType(named: toolingType.name + "*")
                if let object = pointerType.metaObject(),
                    let qObject, object.pointee.inherits(qObject)
                {
                    add(object)
                }
            }
        }
    }

    mutating func collect() {
        var cursor = 0
        while cursor < pending.count {
            let object = pending[cursor]
            cursor += 1
            if let superclass = object.pointee.superClass() {
                add(superclass)
            }
            for index in object.pointee.propertyOffset()..<object.pointee.propertyCount() {
                add(object.pointee.property(index).metaType())
            }
            for index in object.pointee.methodOffset()..<object.pointee.methodCount() {
                let method = object.pointee.method(index)
                add(method.returnMetaType())
                for parameter in 0..<method.parameterCount() {
                    add(method.parameterMetaType(parameter))
                }
            }
        }
    }

    func render(exports: [String: Export]) throws -> String {
        var result = "import QtQuick.tooling 1.2\n\nModule {\n"
        for name in objects.keys.sorted() {
            guard let object = objects[name] else { continue }
            result += try component(object, name: name, export: exports[name])
        }
        return result + "}\n"
    }

    private func component(_ object: UnsafePointer<QMetaObject>, name: String, export: Export?) throws -> String {
        var result = "    Component {\n        name: \(quoted(name))\n        accessSemantics: \"reference\"\n"
        if let superclass = object.pointee.superClass() {
            result += "        prototype: \(quoted(String(cString: superclass.pointee.className())))\n"
        }
        for (key, field) in [("DefaultProperty", "defaultProperty"), ("ParentProperty", "parentProperty")] {
            let index = key.withCString { object.pointee.indexOfClassInfo($0) }
            if index >= 0 {
                let value = String(cString: object.pointee.classInfo(index).value())
                result += "        \(field): \(quoted(value))\n"
            }
        }
        if let export {
            // QtBridge's SwiftQmlElementBuilder registers every element at version 1.0.
            result += "        exports: [\(quoted("\(export.uri)/\(export.name) 1.0"))]\n"
            result += "        exportMetaObjectRevisions: [\(pd_qmltypes_export_revision())]\n"
            if !export.creatable {
                result += "        isCreatable: false\n"
            }
        } else {
            result += "        isCreatable: false\n"
        }
        var properties: [(String, String)] = []
        for index in object.pointee.propertyOffset()..<object.pointee.propertyCount() {
            let property = object.pointee.property(index)
            let propertyName = String(cString: property.name())
            let runtimeName = try typeName(property.metaType(), context: "\(name).\(propertyName)")
            var text = "        Property {\n            name: \(quoted(propertyName))\n"
            text += ToolingType(runtimeName).fields(indent: "            ")
            if !property.isWritable() {
                text += "            isReadonly: true\n"
            }
            if property.isConstant() {
                text += "            isPropertyConstant: true\n"
            }
            if property.isFinal() {
                text += "            isFinal: true\n"
            }
            if property.isRequired() {
                text += "            isRequired: true\n"
            }
            if property.hasNotifySignal() {
                let notify = property.notifySignal().name()
                text += "            notify: \(quoted(String(notify.toStdString())))\n"
            }
            text += "        }\n"
            properties.append((propertyName, text))
        }
        for property in properties.sorted(by: { $0.0 < $1.0 }) {
            result += property.1
        }
        // Manifest order is load-bearing: qmlcachegen bakes relative method indices
        // from it for plugin-less modules, so this must match runtime registration
        // order exactly. NEVER sort.
        for index in object.pointee.methodOffset()..<object.pointee.methodCount() {
            let method = object.pointee.method(index)
            let methodType = method.methodType().rawValue
            let isSignal = methodType == qtMethodTypeSignal
            guard
                isSignal
                    || (method.access().rawValue == qtMethodAccessPublic
                        && (methodType == qtMethodTypeMethod || methodType == qtMethodTypeSlot))
            else { continue }
            let methodNameBytes = method.name()
            let methodName = String(methodNameBytes.toStdString())
            var text = "        \(isSignal ? "Signal" : "Method") {\n            name: \(quoted(methodName))\n"
            let returnName = try typeName(method.returnMetaType(), context: "\(name).\(methodName) return")
            if returnName != "void" {
                text += ToolingType(returnName).fields(indent: "            ")
            }
            if method.isConst() {
                text += "            isMethodConstant: true\n"
            }
            let parameterNames = method.parameterNames()
            for parameter in 0..<method.parameterCount() {
                let parameterName = try typeName(
                    method.parameterMetaType(parameter), context: "\(name).\(methodName) parameter \(parameter)")
                let parameterNameBytes = parameterNames[numericCast(parameter)]
                let runtimeParameterName = String(parameterNameBytes.toStdString())
                text += "            Parameter {\n"
                if !runtimeParameterName.isEmpty {
                    text += "                name: \(quoted(runtimeParameterName))\n"
                }
                text += ToolingType(parameterName).fields(indent: "                ")
                text += "            }\n"
            }
            text += "        }\n"
            result += text
        }
        return result + "    }\n"
    }
}

@main
private struct PorydawQmlTypesCommand {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fail("Usage: porydaw_qmltypes <outdir>")
        }
        do {
            guard let application = pd_qmltypes_application_create(CommandLine.argc, CommandLine.unsafeArgv) else {
                throw QmlTypesError.invalidMetadata("Could not create QCoreApplication")
            }
            defer { pd_qmltypes_application_destroy(application) }
            try generate(in: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
        } catch {
            fail("porydaw_qmltypes: \(error)")
        }
    }

    @MainActor
    private static func generate(in directory: URL) throws {
        var exports: [String: Export] = [:]
        for type in PorydawQmlTypes.instantiable {
            type.registerQmlElement()
            try addExport(type, creatable: true, to: &exports)
        }
        for type in PorydawQmlTypes.uncreatable {
            type.registerUncreatableQmlElement()
            try addExport(type, creatable: false, to: &exports)
        }
        var walk = MetaObjectWalk()
        for name in exports.keys.sorted() {
            let type = runtimeType(named: name + "*")
            guard type.isValid(), let object = type.metaObject() else {
                throw QmlTypesError.invalidMetadata("No registered metaobject for \(name)")
            }
            walk.add(object)
        }
        walk.collect()
        let qmltypes = try walk.render(exports: exports)
        let module = directory.appendingPathComponent("PorydawApp", isDirectory: true)
        try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
        try writeIfChanged(qmltypes, to: module.appendingPathComponent("PorydawApp.qmltypes"))
        // QColor/QFont value types (QmlColor/QmlFont properties) are declared by QtQuick.
        try writeIfChanged(
            "module PorydawApp\ntypeinfo PorydawApp.qmltypes\ndepends QtQuick\n",
            to: module.appendingPathComponent("qmldir"))
    }

    /// Leaves an identical file untouched so the restat build edge stops here
    /// instead of recompiling every QML cache unit after unrelated Swift edits.
    private static func writeIfChanged(_ contents: String, to url: URL) throws {
        let data = Data(contents.utf8)
        if (try? Data(contentsOf: url)) == data { return }
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    private static func addExport(
        _ type: QObjectBuildable.Type, creatable: Bool, to exports: inout [String: Export]
    ) throws {
        let name = String(describing: type)
        let uri = "PorydawApp"
        guard exports[name] == nil else {
            throw QmlTypesError.invalidMetadata("Duplicate registration: \(uri)/\(name)")
        }
        exports[name] = Export(name: name, uri: uri, creatable: creatable)
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(EXIT_FAILURE)
    }
}
