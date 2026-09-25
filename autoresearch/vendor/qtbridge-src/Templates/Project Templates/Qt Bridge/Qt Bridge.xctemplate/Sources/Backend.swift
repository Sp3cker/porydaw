import Foundation
import QtBridge

@QtBridgeable
public class ___VARIABLE_modelName:identifier___ {
    public var name: String = ""
    public var greeting: String = "Hello, World!"

    public init() {}

    public func greet() {
        greeting = name.isEmpty ? "Hello, World!" : "Hello, \(name)!"
    }
}
