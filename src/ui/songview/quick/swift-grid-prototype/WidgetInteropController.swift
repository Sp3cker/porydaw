import Foundation
import NativeWidgetInterop
import QtBridge

// Result kinds shared with native/widget_interop.h (sgw widget interop ABI).
private enum WidgetInteropResult: Int32 {
    case menuAction = 3
    case menuDismissed = 4
    case accepted = 5
    case cancelled = 6
}

// The native host keeps the controller as an unretained callback context; the
// result arrives on the GUI thread from the modal dialog/menu event loop.
private func deliverWidgetInteropResult(
    _ kind: Int32, _ detail: UnsafePointer<CChar>?, _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let controller = Unmanaged<WidgetInteropController>.fromOpaque(context).takeUnretainedValue()
    let detailText = detail.map { String(cString: $0) } ?? ""
    MainActor.assumeIsolated {
        controller.complete(kind: kind, detail: detailText)
    }
}

/// QML-facing launch state for retained QWidget fixtures and the native menu.
/// The host owns widget lifetime; outcomes stay available for logs and smoke
/// observations, not diagnostic chrome.
@MainActor
@QtBridgeable
public final class WidgetInteropController {
    /// Latest completed outcome, or an unavailability note when a launch
    /// could not start. Empty until the first launch.
    public var statusText: String = ""
    /// Append-only outcome log, one entry per line.
    public var historyText: String = ""
    /// True while a wizard/menu operation is open. The launch controls are
    /// disabled for exactly that window.
    public var busy: Bool = false

    @QtIgnored private var outcomes: [String] = []
    @QtIgnored private var installed: Bool = false

    public init() {}

    /// QML-callable bootstrap boundary: the root window invokes this from its
    /// Component.onCompleted, so the native host installs only once QApplication
    /// is fully constructed. Idempotent; host first, smoke second.
    public func initializeHost() {
        guard !installed else { return }
        installed = true
        sgw_installWidgetInteropHost()
        sgw_installWidgetInteropSmoke()
    }


    /// Opens a native QMenu at a QQuickWindow-local point in logical pixels
    /// (top-left origin), as mapped from the calling control by QML.
    public func openMenu(windowX: Double, windowY: Double) {
        start(failure: "Menu unavailable") {
            sgw_openWidgetMenu(
                windowX, windowY,
                deliverWidgetInteropResult, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    /// Opens a standalone window fixture by kind.
    public func openWindowFixture(kind: Int) {
        start(failure: "Fixture unavailable") {
            sgw_openWindowFixture(
                Int32(kind), deliverWidgetInteropResult,
                Unmanaged.passUnretained(self).toOpaque())
        }
    }

    public func openFixture(kind: Int) {
        openWindowFixture(kind: kind)
    }

    // The host accepts at most one operation at a time; `busy` mirrors that on
    // the QML side and keeps the launch controls disabled while one is open.
    // A zero return means the host could not start the operation at all.
    private func start(failure: String, _ open: () -> Int32) {
        guard !busy else { return }
        busy = true
        if open() == 0 {
            busy = false
            statusText = failure
        }
    }

    fileprivate func complete(kind: Int32, detail: String) {
        guard let result = WidgetInteropResult(rawValue: kind) else {
            // Not part of the shared ABI; never leave the launch controls
            // stuck on an unknown result.
            busy = false
            return
        }
        let outcome: String
        switch result {
        case .menuAction:
            outcome = "Menu action: \(detail)"
        case .menuDismissed:
            outcome = "Menu dismissed"
        case .accepted:
            outcome = detail.isEmpty ? "Accepted" : "Accepted: \(detail)"
        case .cancelled:
            outcome = detail.isEmpty ? "Cancelled" : "Cancelled: \(detail)"
        }
        busy = false
        statusText = outcome
        outcomes.append(outcome)
        historyText = outcomes.joined(separator: "\n")
        print("WIDGET_INTEROP \(outcome)")
    }
}
