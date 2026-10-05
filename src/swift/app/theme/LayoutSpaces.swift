import QtBridge

@MainActor
@QtBridgeable
public final class LayoutSpaces {
    public var zero: Int = 0
    public var half: Int = 0
    public var one: Int = 0
    public var two: Int = 0
    public var three: Int = 0
    public var four: Int = 0
    public var six: Int = 0
    public var eight: Int = 0

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        update(typography: typography)
    }

    @QtIgnored
    public func update(typography: Typography) {
        publish(\.zero, typography.space(.zero))
        publish(\.half, typography.space(.half))
        publish(\.one, typography.space(.one))
        publish(\.two, typography.space(.two))
        publish(\.three, typography.space(.three))
        publish(\.four, typography.space(.four))
        publish(\.six, typography.space(.six))
        publish(\.eight, typography.space(.eight))
    }
}
