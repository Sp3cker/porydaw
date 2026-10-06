import PorydawDocument

/// Qt pointer buttons as QML carries them (`mouse.button`).
public enum DrawerQtButton {
    public static let left = 1
    public static let right = 2
    public static let middle = 4
}

enum DrawerPan {
    static let dragDistanceSeed: Double = 10

    @MainActor
    static func moved(x: Double, previousX: inout Double, viewport: DocumentViewport?) {
        let delta = x - previousX
        previousX = x
        if delta != 0 {
            viewport?.mutateCamera { $0.scrollByPx(-delta) }
        }
    }
}

func manhattanExceeds(press: (x: Double, y: Double), x: Double, y: Double, threshold: Double) -> Bool {
    abs(x - press.x) + abs(y - press.y) >= threshold
}
