enum DrawerPan {
    static let dragDistanceSeed: Double = 10

    @MainActor
    static func moved(x: Double, previousX: inout Double, session: DocumentSession?) {
        let delta = x - previousX
        previousX = x
        if delta != 0 {
            session?.mutateCamera { $0.scrollByPx(-delta) }
        }
    }
}

func manhattanExceeds(press: (x: Double, y: Double), x: Double, y: Double, threshold: Double) -> Bool {
    abs(x - press.x) + abs(y - press.y) >= threshold
}
