// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Foundation

public struct QtBridgeableMacro {
    static let moduleName = "QtBridge"

    static let conformanceName = "QObjectBuildable"
    static var qualifiedConformanceName: String {
        return "\(moduleName).\(conformanceName)"
    }

    static var qtBridgeableConformanceType: TypeSyntax {
        "\(raw: qualifiedConformanceName)"
    }

    static let instantiableName = "QmlInstantiable"
    static var qualifiedInstantiableName: String {
        return "\(moduleName).\(instantiableName)"
    }

    static var instantiableConformanceType: TypeSyntax {
        "\(raw: qualifiedInstantiableName)"
    }

    static let trackedMacroName = "QtTracked"
    static let ignoredMacroName = "QtIgnored"
    static let signalMacroName = "QtSignal"

    static let paramsListName = "QMetaParamsList"

    static let holderTypeName = "QObjectHolder"
    static var qualifiedHolderTypeName: String {
        return "\(moduleName).\(holderTypeName)"
    }
    static let privateHolderVariableName = "_objectHolder"
    static let holderVariableName = "objectHolder"
    static var privateHolderVariable : DeclSyntax {
        return
          """
          private var \(raw: privateHolderVariableName): \(raw: qualifiedHolderTypeName)?
          """
    }
    static var holderVariable : DeclSyntax {
        return
          """
          public lazy var \(raw: holderVariableName): \(raw: qualifiedHolderTypeName) = {
              if let object = \(raw: privateHolderVariableName) { return object }
              return \(raw: qualifiedHolderTypeName)(owner: self)
          }()
          """
    }

    static let builderTypeName = "QMetaObjectBuilder"
    static var qualifiedBuilderTypeName: String {
        return "\(moduleName).\(builderTypeName)"
    }
    static let builderVariableName = "metaObjectBuilder"

    static func builderVariable(className: String) -> DeclSyntax {
        let modifiers = DeclModifierListSyntax {
            DeclModifierSyntax(name: .identifier("static"))
            DeclModifierSyntax(name: .identifier("public"))
        }

        let typeAnn = TypeAnnotationSyntax(
            colon: .colonToken(),
            type: IdentifierTypeSyntax(name: .identifier(qualifiedBuilderTypeName))
        )

        let closureLiteral: ExprSyntax = """
        {
            return \(raw: qualifiedBuilderTypeName).create(from: \(raw: className).self)
        }()
        """

        let binding = PatternBindingSyntax(
            pattern: IdentifierPatternSyntax(identifier: .identifier(builderVariableName)),
            typeAnnotation: typeAnn,
            initializer: InitializerClauseSyntax(equal: .equalToken(), value: closureLiteral)
        )

        let varDecl = VariableDeclSyntax(
            attributes: [],
            modifiers: modifiers,
            bindingSpecifier: .keyword(.let),
            bindings: PatternBindingListSyntax([binding])
        )

        return DeclSyntax(varDecl)
    }

    static func registerMethodsAndPropertiesFunction(registrations : [String]) -> DeclSyntax {
        return """
        public static func registerMethodsAndProperties(for builder: \(raw: qualifiedBuilderTypeName)) {
            builder.startRegistration(for: self)
            \(raw: registrations.joined(separator: "\n\n"))
        }
        """
    }

    static func registerMetaTypeInterfaceFunction(typeName: String) -> DeclSyntax {
        return """
        public static func registerMetaTypeInterface(for builder: \(raw: qualifiedBuilderTypeName)) {
            builder.registerCreateFn(objectHolderPath: \\\(raw: typeName)._objectHolder)
        }
        """
    }

    static func didSetAccessor(propertyName: String) -> AccessorDeclSyntax {
        return """
        didSet {
            self.emitSignal(for: "\(raw: propertyName)")
        }
        """
    }

    private static func buildArgTypes(params: FunctionParameterListSyntax,
                                      arrayName: String) -> (arrayInit: String, pushCalls: [String])?
    {
        var pushCalls: [String] = []

        for param in params {
            guard param.type.isSupportedSettableType else { return nil }
            pushCalls.append("\(arrayName).append(\(param.type.trimmed.description).self)")
        }

        let arrayVar = pushCalls.isEmpty ? "let" : "var"
        let arrayInit = "\(arrayVar) \(arrayName) : [QVariantGettable.Type] = []"
        return (arrayInit, pushCalls)
    }

    private static func processSignalDeclaration(functionDecl: FunctionDeclSyntax,
                                                 into registrationsArr: inout [String],
                                                 signalCounter: inout Int)
    {
        guard functionDecl.isValidForRegistration else {
            return
        }

        if functionDecl.hasAttribute(QtBridgeableMacro.ignoredMacroName) {
            return
        }

        let signalName = functionDecl.name.text
        let params = functionDecl.signature.parameterClause.parameters
        let arrayName = "signalArgTypes\(signalCounter)"

        guard let (arrayInit, pushCalls) = buildArgTypes(params: params, arrayName: arrayName) else {
            return
        }

        registrationsArr.append(
        """
        \(arrayInit)
        \(pushCalls.joined(separator: "\n"))
        builder.registerSignal(signalName: "\(signalName)", argTypes: \(arrayName))
        """)
        signalCounter += 1
    }

    private static func processFunctionDeclaration(className : String,
                                                   functionDecl: FunctionDeclSyntax,
                                                   into registrationsArr: inout [String],
                                                   methodCounter : inout Int) -> Void
    {
        guard functionDecl.isValidForRegistration else {
            return
        }

        if functionDecl.hasAttribute(QtBridgeableMacro.ignoredMacroName)
            || functionDecl.hasAttribute(QtBridgeableMacro.signalMacroName) {
            return
        }

        let methodName = functionDecl.name.text
        let params = functionDecl.signature.parameterClause.parameters

        let arrayName = "argTypes\(methodCounter)"

        guard let (arrayInit, pushCalls) = buildArgTypes(params: params, arrayName: arrayName) else {
            return
        }

        var paramExtraction: [String] = []
        var args: [String] = []

        for (index, param) in params.enumerated() {
            let paramName = param.firstName.text
            let paramType = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)

            let extractor = "let \(paramName) : \(paramType) = args.get(\(index))"
            paramExtraction.append(extractor)
            args.append("\(paramName): \(paramName)")
        }

        let call = args.isEmpty
            ? "self.\(methodName)()"
            : "self.\(methodName)(\(args.joined(separator: ", ")))"

        let returnClauseType = functionDecl.signature.returnClause?.type
        let isSupportedReturnType = returnClauseType?.isSupportedReturnType ?? true
        if (!isSupportedReturnType) {
            return
        }

        let returnsVoid = returnClauseType?.isVoid ?? true
        let returnTypeString = returnClauseType?.trimmed.description ?? ""
        let returnType: String = returnsVoid ? "nil" : "\(returnTypeString).self"
        let returnBody: String = {
            if returnsVoid {
                return """
                \(call)
                    return QVariant()
                """
            } else {
                return "return QVariant(value: \(call))"
            }
        }()

        let registration =
        """
        \(arrayInit)
        \(pushCalls.joined(separator: "\n"))
        builder.registerSlot(
            name: "\(methodName)",
            returnType: \(returnType),
            argTypes: \(arrayName),
            method: { (owner: Any, args: \(paramsListName)) in
            guard let self = owner as? \(className) else {
                return QVariant()
            }
            \(paramExtraction.joined(separator: "\n    "))
            \(returnBody)
        })
        """

        methodCounter += 1
        registrationsArr.append(registration)
    }

    private static func processVariableDeclaration(className : String,
                                                   variableDecl: VariableDeclSyntax,
                                                   into registrationsArr: inout [String]) -> Void
    {
        guard variableDecl.isValidForRegistration else {
            return
        }

        if variableDecl.hasAttribute(QtBridgeableMacro.ignoredMacroName) {
            return
        }

        guard variableDecl.isSupportedGettableType
                || variableDecl.hasAttribute(QtBridgeableMacro.trackedMacroName) else {
            return
        }

        let propertyName = variableDecl.identifier!.text
        let registrationCode =
        """
        builder.registerProperty(
            name: \"\(propertyName)\",
            keyPath: \\\(className).\(propertyName)
        )
        """

        registrationsArr.append(registrationCode)
    }
}

struct BridgeableDiagnostic: DiagnosticMessage {
    enum ID: String {
        case invalidApplication = "invalid type"
    }

    var message: String
    var diagnosticID: MessageID
    var severity: DiagnosticSeverity

    init(message: String, diagnosticID: SwiftDiagnostics.MessageID,
         severity: SwiftDiagnostics.DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = diagnosticID
        self.severity = severity
    }

    init(message: String, domain: String, id: ID,
         severity: SwiftDiagnostics.DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: domain, id: id.rawValue)
        self.severity = severity
    }
}

extension DiagnosticsError {
    init<S: SyntaxProtocol>(syntax: S,
                          message: String,
                          domain: String = "QtBridge",
                          id: BridgeableDiagnostic.ID,
                          severity: SwiftDiagnostics.DiagnosticSeverity = .error) {
        self.init(diagnostics: [
            Diagnostic(node: Syntax(syntax),
                       message: BridgeableDiagnostic(message: message,
                                                     domain: domain,
                                                     id: id,
                                                     severity: severity))
        ])
    }
}

extension QtBridgeableMacro : MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let identified = declaration.asProtocol(NamedDeclSyntax.self) else {
            return []
        }

        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
          throw DiagnosticsError(syntax: node,
                                 message: "'@QtBridgeable' can only be applied to class type",
                                 id: .invalidApplication)
        }

        let typeName = identified.name.trimmed.text

        var declarations: [DeclSyntax] = []
        declarations.append(QtBridgeableMacro.privateHolderVariable)
        declarations.append(QtBridgeableMacro.holderVariable)
        declarations.append(QtBridgeableMacro.builderVariable(className: typeName))

        var registrations: [String] = []
        var nSignals = 1
        var nSlots = 1
        // Signals must be registered first
        for member in classDecl.memberBlock.members {
            guard let functionDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            if functionDecl.hasAttribute(QtBridgeableMacro.signalMacroName) {
                processSignalDeclaration(functionDecl: functionDecl, into: &registrations, signalCounter: &nSignals)
            }
        }

        for member in classDecl.memberBlock.members {
            if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                processFunctionDeclaration(className: typeName, functionDecl: functionDecl,
                                           into: &registrations, methodCounter: &nSlots)
            } else if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
                processVariableDeclaration(className: typeName, variableDecl: variableDecl,
                                           into: &registrations)
            } else {
               continue
            }
        }

        declarations.append(registerMethodsAndPropertiesFunction(registrations: registrations))
        declarations.append(registerMetaTypeInterfaceFunction(typeName: typeName))
        return declarations
    }
}

extension QtBridgeableMacro : ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        if protocols.isEmpty {
          return []
        }

        return [
            try ExtensionDeclSyntax(
                "extension \(raw: type.trimmedDescription): \(raw: qualifiedConformanceName) {}")
        ]
    }
}

extension QtBridgeableMacro: MemberAttributeMacro {
    public static func expansion<
        Declaration: DeclGroupSyntax,
        MemberDeclaration: DeclSyntaxProtocol,
        Context: MacroExpansionContext
    >(
        of node: AttributeSyntax,
        attachedTo declaration: Declaration,
        providingAttributesFor member: MemberDeclaration,
        in context: Context
    ) throws -> [AttributeSyntax] {
        guard let property = member.as(VariableDeclSyntax.self),
                  property.isValidForRegistration && property.type != nil else  {
            return []
        }

        if property.hasAttribute(QtBridgeableMacro.trackedMacroName) ||
            property.hasAttribute(QtBridgeableMacro.ignoredMacroName) {
            return []
        }

        guard property.isSupportedGettableType else { return [] }

        return [
            AttributeSyntax(
                attributeName: IdentifierTypeSyntax(name: .identifier(QtBridgeableMacro.trackedMacroName)))
        ]
    }
}

public struct QtTrackedMacro: AccessorMacro {
    public static func expansion<
      Context: MacroExpansionContext,
      Declaration: DeclSyntaxProtocol
    >(
      of node: AttributeSyntax,
      providingAccessorsOf declaration: Declaration,
      in context: Context
    ) throws -> [AccessorDeclSyntax] {
        guard let property = declaration.as(VariableDeclSyntax.self),
                  property.isValidForRegistration,
                  !property.isImmutable else {
          return []
        }

        let propertyName = property.identifier!.text
        return [ QtBridgeableMacro.didSetAccessor(propertyName: propertyName) ]
    }
}

public struct QtIgnoredMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        return []
    }
}

public struct QtSignalMacro: BodyMacro {
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        providingBodyFor declaration: some SwiftSyntax.DeclSyntaxProtocol
        & SwiftSyntax.WithOptionalCodeBlockSyntax,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.CodeBlockItemSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw DiagnosticsError(syntax: node,
                                   message: "'@QtSignal' can only be applied to functions",
                                   id: .invalidApplication)
        }

        if funcDecl.body != nil {
            throw DiagnosticsError(syntax: node,
                                   message: "'@QtSignal' functions must not have a body",
                                   id: .invalidApplication)
        }

        guard funcDecl.isValidForRegistration else {
            throw DiagnosticsError(syntax: node,
                                   message: "'@QtSignal' functions must not be private or static",
                                   id: .invalidApplication)
        }

        let name = funcDecl.name.text
        let params = funcDecl.signature.parameterClause.parameters

        var argType: [String] = []
        for param in params {
            guard param.type.isSupportedSettableType else {
                throw DiagnosticsError(syntax: node,
                                       message: "Unsupported parameter type: \(param.type.trimmed.description)",
                                       id: .invalidApplication)
            }
            let paramName = param.firstName.text
            argType.append("\(paramName).toVariant()")
        }

        let argsArray = argType.isEmpty ? "[]" : "[\(argType.joined(separator: ", "))]"

        return [
            """
            emitSignal(signalName: "\(raw: name)", args: \(raw: argsArray))
            """
        ]
    }
}


@main
struct QtBridgePackagePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        QtBridgeableMacro.self,
        QtTrackedMacro.self,
        QtIgnoredMacro.self,
        QtSignalMacro.self
    ]
}
