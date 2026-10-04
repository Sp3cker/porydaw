import QtBridge

@MainActor
@QtBridgeable
public final class BridgeValueTypeProbe: QmlInstantiableStatus {
    public var sampleColor: QmlColor = QmlColor(red8: 51, green8: 102, blue8: 153, alpha8: 204)
    public var sampleFont: QmlFont = QmlFont(
        family: "Atkinson Hyperlegible Next", pixelSize: 19, weight: 600,
        italic: true, letterSpacing: 1.5, features: ["tnum": 1])
    @QtTracked public var child: BridgeValueTypeProbe? = nil

    public init() {}
    public func componentComplete() {}

    public func echoColor(value: QmlColor) -> QmlColor { value }
    public func echoFont(value: QmlFont) -> QmlFont { value }
    public func selfObject() -> BridgeValueTypeProbe { self }
    public func optionalObject() -> Optional<BridgeValueTypeProbe> { child }

    public func echoMap(value: [String: QVariantSettable]) -> [String: QVariantSettable] { value }

    public func writesReachedSwift() -> Bool {
        let expectedColor = QmlColor(red: 1, green: 0, blue: 1, alpha: 1)
        let expectedFont = QmlFont(
            family: "Atkinson Hyperlegible Next", pixelSize: 23, weight: 700,
            italic: false, letterSpacing: -0.5, hintingPreference: .preferVerticalHinting)
        return sampleColor == expectedColor && sampleFont == expectedFont
    }

    public func restoreValues() {
        child = nil
        sampleColor = QmlColor(red8: 51, green8: 102, blue8: 153, alpha8: 204)
        sampleFont = QmlFont(
            family: "Atkinson Hyperlegible Next", pixelSize: 19, weight: 600,
            italic: true, letterSpacing: 1.5, features: ["tnum": 1])
    }
}
