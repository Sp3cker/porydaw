// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

import SwiftSyntax
import SwiftSyntaxMacros

extension VariableDeclSyntax {
    var identifier: TokenSyntax? {
        bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier
    }

    var type: String? {
       return bindings.first?.typeAnnotation?.type.trimmed.description
    }

    var isSupportedSettableType: Bool {
        return bindings.first?.typeAnnotation?.type.isSupportedSettableType ?? false
    }

    var isSupportedGettableType: Bool {
        return bindings.first?.typeAnnotation?.type.isSupportedGettableType ?? false
    }

    var isImmutable: Bool {
        bindingSpecifier.tokenKind == .keyword(.let)
    }

    var isInstance: Bool {
        !modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) ||
            mod.name.tokenKind == .keyword(.class)
        }
    }

    var isPrivate: Bool {
        modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.private)
        }
    }

    var isValidForRegistration: Bool {
       !isPrivate && !isComputed && !hasDidSet && isInstance && identifier != nil
    }

    var hasPublished : Bool {
        return !isImmutable && hasAttribute("Published")
    }

    func hasAttribute(_ attributeName: String) -> Bool {
        attributes.contains(where: { attr in
            attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == attributeName
        })
    }

    func accessorsMatching(_ predicate: (TokenKind) -> Bool) -> [AccessorDeclSyntax] {
        let accessors: [AccessorDeclListSyntax.Element] = bindings.compactMap { patternBinding in
          switch patternBinding.accessorBlock?.accessors {
          case .accessors(let accessors):
            return accessors
          default:
            return nil
          }
        }.flatMap { $0 }
        return accessors.compactMap { accessor in
          if predicate(accessor.accessorSpecifier.tokenKind) {
            return accessor
          } else {
            return nil
          }
        }
      }

    var hasDidSet: Bool {
        return accessorsMatching({ $0 == .keyword(.didSet) }).count > 0
    }

    var isComputed: Bool {
        if accessorsMatching({ $0 == .keyword(.get) }).count > 0 {
            return true
        } else {
            return bindings.contains { binding in
                if case .getter = binding.accessorBlock?.accessors {
                    return true
                } else {
                    return false
                }
            }
        }
    }
}

extension FunctionDeclSyntax {
    var isInstance: Bool {
        !modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) ||
            mod.name.tokenKind == .keyword(.class)
        }
    }

    var isPrivate: Bool {
        modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.private)
        }
    }

    var isValidForRegistration: Bool {
       !isPrivate && isInstance
    }

    func hasAttribute(_ attributeName: String) -> Bool {
        attributes.contains(where: { attr in
            attr.as(AttributeSyntax.self)?.attributeName.trimmedDescription == attributeName
        })
    }
}

extension TypeSyntax {
    var isSupportedSettableType: Bool {
        return isSupportedBasicType || isVariantMapType || isStringListType
    }

    var isSupportedGettableType: Bool {
        return isSupportedSettableType || isListModelType || isTableModelType
    }

    var isSupportedReturnType: Bool {
        return isSupportedSettableType || isVoid || self.is(IdentifierTypeSyntax.self)
    }

    var isVoid: Bool {
        if let definedReturn = self.as(IdentifierTypeSyntax.self),
           definedReturn.name.text == "Void" {
            return true
        }

        if let tuple = self.as(TupleTypeSyntax.self), tuple.elements.isEmpty {
            return true
        }

        return false
    }

    private static let supportedBasicTypes: Set<String> = [
        "Int", "UInt", "Double", "Float", "String", "Bool"
    ]

    private var isSupportedBasicType: Bool {
        return Self.supportedBasicTypes.contains(trimmed.description)
    }

    private var isListModelType: Bool {
        let t = trimmed.description.replacingOccurrences(of: " ", with: "")
        return t.hasPrefix("QListModel<") && t.hasSuffix(">")
    }

    private var isTableModelType: Bool {
        let t = trimmed.description.replacingOccurrences(of: " ", with: "")
        return t.hasPrefix("QTableModel<") && t.hasSuffix(">")
    }

    private var isVariantMapType: Bool {
        // [String: QVariantSettable]
        if let dictType = self.as(DictionaryTypeSyntax.self) {
            let keyIsString = dictType.key.trimmed.description == "String"
            let valueIsQVariant = dictType.value.trimmed.description == "QVariantSettable"
            return keyIsString && valueIsQVariant
        }

        // Dictionary<String, QVariantSettable>
        if let identType = self.as(IdentifierTypeSyntax.self),
           identType.name.text == "Dictionary",
           let args = identType.genericArgumentClause?.arguments,
           args.count == 2
        {
            let keyIsString   = args[args.startIndex].argument.trimmed.description == "String"
            let valueIsQVariant = args[args.index(after: args.startIndex)].argument.trimmed.description == "QVariantSettable"
            return keyIsString && valueIsQVariant
        }

        return false
    }

    private var isStringListType: Bool {
        // [String]
        if let arrayType = self.as(ArrayTypeSyntax.self) {
            return arrayType.element.trimmed.description == "String"
        }

        // Array<String>
        if let identType = self.as(IdentifierTypeSyntax.self),
           identType.name.text == "Array",
           let args = identType.genericArgumentClause?.arguments,
           args.count == 1
        {
            return args[args.startIndex].argument.trimmed.description == "String"
        }

        return false
    }
}
