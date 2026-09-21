import PorydawCore

// The velocity band's plot-relative projection. The page's own hit tests and
// the scene's handle and band rows read the same x/y maths from this one value,
// so a pointer lands on exactly what the renderer drew.
//
// Ownership: a context-holding value constructed per rebuild from the shared
// camera, the font-relative geometry, the device pixel ratio and the published
// value axis. It retains no session and no page state; `hitTest` takes the
// handle set explicitly, so the caller decides which rows it tests against.

/// Plot-relative x/y projection and note hit testing for the velocity band.
struct VelocityProjection: Sendable {
    /// The shared camera at the page's DPR, or `nil` while the page has no
    /// session: the same "no projection yet" state x reads as zero in.
    var camera: EditorCamera?
    var geometry: VelocityNodeGeometry
    var devicePixelRatio: Double
    var axis: VelocityAxisModel

    init(camera: EditorCamera?, geometry: VelocityNodeGeometry, devicePixelRatio: Double,
         axis: VelocityAxisModel) {
        self.camera = camera
        self.geometry = geometry
        self.devicePixelRatio = devicePixelRatio
        self.axis = axis
    }

    /// The shared camera's own projection at the page's device pixel ratio.
    func xForDisplayTick(_ tick: Double) -> Double {
        guard let camera else { return 0 }
        return camera.displayX(tick: tick, origin: 0, dpr: devicePixelRatio)
    }

    /// One displayed value's y: the continuous ladder while the detent set is
    /// unlocked, else the note's own map's level center.
    func yForNote(map: VelocityMap, velocity: Int, detentUnlock: Bool) -> Double {
        if detentUnlock { return axis.velocityToY(velocity) }
        guard let level = map.level(of: velocity) else { return axis.velocityToY(velocity) }
        return axis.levelToY(level, map: map)
    }

    /// The note under the pointer: a centered circle hit beats a stem hit, a
    /// selected handle beats an unselected one, then the nearer hit, then the
    /// later row of the passed set.
    @MainActor
    func hitTest(x: Double, y: Double, includeStems: Bool,
                 handles: [VelocityHandle]) -> NoteID? {
        let radius = geometry.hitRadius
        var best: NoteID?
        var bestCircle = false
        var bestSelected = false
        var bestDistance = 0.0
        var bestOrder = 0
        var order = 0
        for handle in handles {
            let dx = handle.x - x
            let dy = handle.y - y
            let distance = dx * dx + dy * dy
            let circleHit = distance <= radius * radius
            let stemHit = includeStems
                && x >= handle.x - geometry.durationLineHorizontalSlop
                && x <= handle.endX + geometry.durationLineHorizontalSlop
                && abs(y - handle.y) <= geometry.durationLineVerticalRadius
            if circleHit || stemHit {
                let better = best == nil
                    || (circleHit && !bestCircle)
                    || (circleHit == bestCircle && handle.selected && !bestSelected)
                    || (circleHit == bestCircle && handle.selected == bestSelected
                        && (distance < bestDistance
                            || (distance == bestDistance && order > bestOrder)))
                if better {
                    best = handle.noteID
                    bestCircle = circleHit
                    bestSelected = handle.selected
                    bestDistance = distance
                    bestOrder = order
                }
            }
            order += 1
        }
        return best
    }
}
