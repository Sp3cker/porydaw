import QtBridge

@MainActor
@QtBridgeable
public final class LayoutSpaces {
    public var zero: Int
    public var half: Int
    public var one: Int
    public var two: Int
    public var three: Int
    public var four: Int
    public var six: Int
    public var eight: Int

    public init(typography: Typography = Typography(baseFontPx: 13)) {
        zero = typography.space(.zero)
        half = typography.space(.half)
        one = typography.space(.one)
        two = typography.space(.two)
        three = typography.space(.three)
        four = typography.space(.four)
        six = typography.space(.six)
        eight = typography.space(.eight)
    }

    @QtIgnored
    public func update(typography: Typography) {
        setPublished(zero, typography.space(.zero)) { zero = $0 }
        setPublished(half, typography.space(.half)) { half = $0 }
        setPublished(one, typography.space(.one)) { one = $0 }
        setPublished(two, typography.space(.two)) { two = $0 }
        setPublished(three, typography.space(.three)) { three = $0 }
        setPublished(four, typography.space(.four)) { four = $0 }
        setPublished(six, typography.space(.six)) { six = $0 }
        setPublished(eight, typography.space(.eight)) { eight = $0 }
    }
}
