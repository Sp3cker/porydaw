import Foundation
import PorydawCore

// MARK: - Projection geometry

/// The page's font-relative geometry, derived exactly as
/// `VelocityArea::Geometry::resolve` derives it from `layout::fontPx` and the
/// `layout::space` tokens the ruler and transient use.
public struct VelocityNodeGeometry: Equatable, Sendable {
    public var hitRadius: Double = 0
    public var durationLineVerticalRadius: Double = 0
    public var durationLineHorizontalSlop: Double = 0
    public var dragActivationDistance: Double = 0
    public var nodePaintRadius: Double = 0
    public var nodeOutlineDipWidth: Double = 0
    public var selectedNodeRingRadius: Double = 0
    public var selectedNodeRingDipWidth: Double = 0
    public var stemDipWidth: Double = 0
    public var selectedStemDipWidth: Double = 0
    public var densityD1: Double = 0
    public var densityD2: Double = 0
    public var densityD3: Double = 0
    public var densityD4: Double = 0
    public var verticalInset: Double = 0
    public var labelSideInset: Double = 0
    public var labelColumnGap: Double = 0
    public var tickLabelLength: Double = 0
    public var tickShortLength: Double = 0
    public var markerLength: Double = 0
    public var gridLineStroke: Double = 0
    public var pixel: Double = 1

    public init() {}

    public init(baseFontPx: Double, devicePixelRatio: Double) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let dpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        func px(_ multiplier: Double) -> Double { fontPx(base, multiplier) }
        densityD1 = px(6)
        densityD2 = px(25.0 / 3.0)
        densityD3 = px(12)
        densityD4 = px(24)
        hitRadius = px(0.5)
        durationLineVerticalRadius = px(1.0 / 3.0)
        durationLineHorizontalSlop = px(1.0 / 6.0)
        dragActivationDistance = px(1.0 / 12.0)
        nodePaintRadius = px(7.0 / 26.0)
        nodeOutlineDipWidth = px(1.0 / 12.0)
        selectedNodeRingRadius = px(3.0 / 8.0)
        selectedNodeRingDipWidth = px(1.0 / 6.0)
        stemDipWidth = px(1.0 / 6.0)
        selectedStemDipWidth = px(1.0 / 4.0)
        verticalInset = px(0.75)
        labelSideInset = px(0.5)
        labelColumnGap = px(0.25)
        tickLabelLength = 3 * px(0.125)
        tickShortLength = px(0.25)
        markerLength = px(0.5)
        gridLineStroke = gridLineThickness(baseFontPx: base, devicePixelRatio: dpr)
        pixel = physicalPixel(dpr)
    }
}

// MARK: - Value axis

/// Font-relative ruler geometry: one value per `VelocityAxisGeometry` field.
public struct VelocityAxisGeometry: Equatable, Sendable {
    public var height: Double = 0
    public var verticalInset: Double = 0
    public var labelWidth: Double = 0
    public var labelSideInset: Double = 0
    public var labelColumnGap: Double = 0
    public var labelHeight: Double = 0
    public var continuousDensityD1: Double = 0
    public var continuousDensityD2: Double = 0
    public var continuousDensityD3: Double = 0
    public var continuousDensityD4: Double = 0

    public init() {}
}

public struct VelocityAxisTick: Equatable, Sendable {
    public var velocity: Int = 1
    public var y: Double = 0

    public init(velocity: Int = 1, y: Double = 0) {
        self.velocity = velocity
        self.y = y
    }
}

public struct VelocityAxisLabel: Equatable, Sendable {
    public var velocity: Int = 1
    public var y: Double = 0
    public var text: String = ""

    public init(velocity: Int = 1, y: Double = 0, text: String = "") {
        self.velocity = velocity
        self.y = y
        self.text = text
    }
}

/// One intrinsic (PSG level) graduation. `labelVisible` is the density decision
/// and `emphasized` the active-and-single-selection one; both come from
/// `rebuildQuickAxis`, so QML renders two booleans instead of a rule.
public struct VelocityAxisGraduation: Equatable, Sendable {
    public var level: Int = 0
    public var velocity: Int = 1
    public var y: Double = 0
    public var audible: Bool = false
    public var active: Bool = false
    public var labelVisible: Bool = true
    public var emphasized: Bool = false
    public var text: String = ""

    public init() {}
}

public struct VelocityAxisMarker: Equatable, Sendable {
    public var velocity: Int = 1
    public var y: Double = 0

    public init(velocity: Int = 1, y: Double = 0) {
        self.velocity = velocity
        self.y = y
    }
}

/// The ruler as pure values: `VelocityAxis` from `velocityaxis.cpp`, including
/// the density ladder, the intrinsic row centers and boundaries, the displayed
/// value markers and the ruler hit rules.
public struct VelocityAxisModel: Sendable {
    public enum Mode: Int, Sendable {
        case continuous = 0
        case intrinsic = 1
    }

    public static let maximumContinuousTicks = 32
    public static let maximumContinuousLabels = 17
    public static let maximumIntrinsicGraduations = 16
    public static let maximumMarkers = 2
    public static let minimumVelocity = 1
    public static let maximumVelocity = 127

    public private(set) var map = VelocityMap(voiceKind: .unresolved)
    public var geometry = VelocityAxisGeometry()
    public private(set) var top: Double = 0
    public private(set) var bottom: Double = 0
    public private(set) var ticks: [VelocityAxisTick] = []
    public private(set) var labels: [VelocityAxisLabel] = []
    public private(set) var graduations: [VelocityAxisGraduation] = []
    public private(set) var markers: [VelocityAxisMarker] = []
    public private(set) var accessibleDescription = "Velocity"

    private var levelCenters: [Double] = []
    private var levelBoundaries: [Double] = []

    public init() {
        rebuild()
    }

    public init(map: VelocityMap, geometry: VelocityAxisGeometry, activeValues: [UInt8] = []) {
        self.map = map
        self.geometry = geometry
        rebuild(activeValues: activeValues)
    }

    public var mode: Mode { map.levelCount == 0 ? .continuous : .intrinsic }

    public var drawableSpan: Double { bottom - top }

    public func velocityToY(_ velocity: Int) -> Double {
        let clamped = min(max(velocity, Self.minimumVelocity), Self.maximumVelocity)
        guard drawableSpan != 0 else { return bottom }
        return bottom - Double(clamped - Self.minimumVelocity) * drawableSpan
            / Double(Self.maximumVelocity - Self.minimumVelocity)
    }

    public func yToVelocity(_ y: Double) -> Int {
        guard drawableSpan != 0 else { return Self.minimumVelocity }
        let clampedY = min(max(y, top), bottom)
        let scaled = (bottom - clampedY) * Double(Self.maximumVelocity - Self.minimumVelocity)
            / drawableSpan
        return min(max(Self.minimumVelocity + Int(scaled.rounded()), Self.minimumVelocity),
                   Self.maximumVelocity)
    }

    public func levelToY(_ level: Int) -> Double {
        guard !levelCenters.isEmpty else { return bottom }
        return levelCenters[min(max(level, 0), levelCenters.count - 1)]
    }

    public func yToLevel(_ y: Double) -> Int {
        let highest = max(0, map.levelCount - 1)
        var level = 0
        while level < highest, level < levelBoundaries.count, y <= levelBoundaries[level] {
            level += 1
        }
        return level
    }

    public func levelBoundaryToY(_ lowerLevel: Int) -> Double {
        guard !levelBoundaries.isEmpty else { return bottom }
        return levelBoundaries[min(max(lowerLevel, 0), levelBoundaries.count - 1)]
    }

    /// Pure intrinsic geometry, shared by per-note centers and section bands.
    public func levelBoundaryToY(_ lowerLevel: Int, map: VelocityMap) -> Double {
        (velocityToY(Int(map.levelRange(lowerLevel).last))
            + velocityToY(Int(map.levelRange(lowerLevel + 1).first))) / 2
    }

    public func levelToY(_ level: Int, map: VelocityMap) -> Double {
        let lower = level == 0 ? bottom : levelBoundaryToY(level - 1, map: map)
        let upper = level + 1 == map.levelCount ? top : levelBoundaryToY(level, map: map)
        return (lower + upper) / 2
    }

    public func hasLabel(_ velocity: Int) -> Bool {
        labels.contains { $0.velocity == velocity }
    }

    /// `VelocityAxis::inRuler`: the ruler owns `[0, rulerWidth)`.
    public func inRuler(x: Double, rulerWidth: Double) -> Bool {
        x >= 0 && x < rulerWidth
    }

    /// `VelocityAxis::rulerVelocityAt`: a level representative in intrinsic
    /// mode, else the label whose text row covers `y`, else `-1`.
    public func rulerVelocityAt(y: Double, labelHeight: Double) -> Int {
        if mode == .intrinsic { return Int(map.representative(yToLevel(y))) }
        let textRadius = labelHeight / 2
        for label in labels where abs(y - label.y) <= textRadius {
            return label.velocity
        }
        return -1
    }

    // MARK: Construction

    private mutating func rebuild(activeValues: [UInt8] = []) {
        let height = max(0, geometry.height)
        let inset = max(0, geometry.verticalInset)
        top = min(inset, height / 2)
        bottom = max(top, height - inset)
        ticks = []
        labels = []
        graduations = []
        levelCenters = []
        levelBoundaries = []
        buildContinuousTicks()
        buildContinuousMarkers(activeValues: activeValues)
        if mode == .intrinsic { buildIntrinsicRows() }
        accessibleDescription = map.levelCount == 0
            ? "Velocity"
            : "Velocity. \(map.voiceName) has \(map.levelCount) volume levels."
    }

    private mutating func addTick(_ velocity: Int) {
        guard ticks.count < Self.maximumContinuousTicks else { return }
        ticks.append(VelocityAxisTick(velocity: velocity, y: velocityToY(velocity)))
    }

    private mutating func addLabel(_ velocity: Int) {
        guard labels.count < Self.maximumContinuousLabels else { return }
        labels.append(VelocityAxisLabel(velocity: velocity, y: velocityToY(velocity),
                                        text: String(velocity)))
    }

    /// `VelocityAxis::buildContinuousTicks`: the ruler thins out as the body
    /// shrinks, in the four exact density bands.
    private mutating func buildContinuousTicks() {
        let span = max(0, geometry.height)
        if span < geometry.continuousDensityD1 {
            for velocity in [127, 96, 64, 32, 1] { addTick(velocity) }
            for velocity in [127, 64, 1] { addLabel(velocity) }
            return
        }
        if span < geometry.continuousDensityD2 {
            addTick(127)
            for velocity in stride(from: 112, through: 16, by: -16) { addTick(velocity) }
            addTick(1)
            for velocity in [127, 64, 1] { addLabel(velocity) }
            return
        }
        if span < geometry.continuousDensityD3 {
            addTick(127)
            for velocity in stride(from: 112, through: 16, by: -16) { addTick(velocity) }
            addTick(1)
            for velocity in [127, 96, 64, 32, 1] { addLabel(velocity) }
            return
        }
        if span < geometry.continuousDensityD4 {
            addTick(127)
            for velocity in stride(from: 120, through: 8, by: -8) { addTick(velocity) }
            addTick(1)
            addLabel(127)
            for velocity in stride(from: 112, through: 16, by: -16) { addLabel(velocity) }
            addLabel(1)
            return
        }
        addTick(127)
        for velocity in stride(from: 123, through: 7, by: -4) { addTick(velocity) }
        addTick(1)
        addLabel(127)
        for velocity in stride(from: 120, through: 8, by: -8) { addLabel(velocity) }
        addLabel(1)
    }

    /// `VelocityAxis::buildContinuousMarkers`: the lowest and highest displayed
    /// value of the active set, one marker when they coincide.
    private mutating func buildContinuousMarkers(activeValues: [UInt8]) {
        guard let first = activeValues.first else { return }
        var minimum = Int(clampVelocity(Int(first)))
        var maximum = minimum
        for value in activeValues.dropFirst() {
            let velocity = Int(clampVelocity(Int(value)))
            minimum = min(minimum, velocity)
            maximum = max(maximum, velocity)
        }
        markers.append(VelocityAxisMarker(velocity: minimum, y: velocityToY(minimum)))
        if maximum != minimum {
            markers.append(VelocityAxisMarker(velocity: maximum, y: velocityToY(maximum)))
        }
    }

    /// `VelocityAxis::buildIntrinsicRows`: one row per PSG level, boundaries
    /// where the effective volume changes, labels thinned to the label height.
    private mutating func buildIntrinsicRows() {
        let levelCount = map.levelCount
        guard levelCount > 0 else { return }
        var labelStride = 1
        let levelHeight = drawableSpan / Double(levelCount)
        while labelStride <= levelCount,
              levelHeight * Double(labelStride) < max(0, geometry.labelHeight)
        {
            labelStride *= 2
        }
        for level in 0..<max(0, levelCount - 1) {
            levelBoundaries.append(levelBoundaryToY(level, map: map))
        }
        for level in 0..<levelCount where graduations.count < Self.maximumIntrinsicGraduations {
            let lowerBoundary = level == 0 ? bottom : levelBoundaries[level - 1]
            let upperBoundary = level + 1 == levelCount ? top : levelBoundaries[level]
            let center = (lowerBoundary + upperBoundary) / 2
            levelCenters.append(center)
            var graduation = VelocityAxisGraduation()
            graduation.level = level
            graduation.velocity = Int(map.representative(level))
            graduation.audible = level != 0
            graduation.labelVisible = (level + 1) % labelStride == 0
            graduation.y = center
            graduation.text = "Vol \(level + 1)"
            graduation.active = markers.contains { map.level(of: $0.velocity) == level }
            graduations.append(graduation)
        }
    }
}
