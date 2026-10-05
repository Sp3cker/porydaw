import Foundation
import PorydawDocument
import QtBridge

/// The two guide kinds rendered over the shared timeline plot.
public enum PlayheadGuideKind: Int, Sendable {
    case hover = 0
    case edit = 1
}

/// The owner of the currently published hover guide. A later owner replaces an
/// earlier one, while clearing an owner that no longer owns the guide is a no-op.
public enum PlayheadGuideHoverOwner: Int, Sendable {
    case none = 0
    case automation = 1
    case voiceChanges = 2
}

/// One guide's QML-facing presentation. The kind is fixed for the lifetime of
/// the state object; content and visibility are replaced only when they change.
@MainActor
@QtBridgeable
public final class PlayheadGuideState {
    public var contentX: Double = 0
    @QtTracked public var visible = false
    public var kind: Int

    public init(kind: Int) {
        self.kind = kind
    }
}

/// Presents the hover and edit guides through the document viewport's camera.
/// QML receives only plot-local coordinates and draws the clipped segments;
/// pointer ownership, song-start clamping, arbitration and projection remain in
/// Swift.
@MainActor
@QtBridgeable
public final class PlayheadGuidesPresenter {
    @QtTracked public var hover = PlayheadGuideState(kind: PlayheadGuideKind.hover.rawValue)
    @QtTracked public var edit = PlayheadGuideState(kind: PlayheadGuideKind.edit.rawValue)
    @QtTracked public var timelineAttached = false

    /// Distinct guide publications, retained for deterministic presenter checks.
    public private(set) var presentationCount: UInt64 = 0

    private weak var viewport: DocumentViewport?
    private var hoverOwner: Int?
    private var hoverTick: Double?
    private var published: Presentation?

    private struct Presentation: Equatable {
        var timelineAttached: Bool
        var hoverContentX: Double
        var hoverVisible: Bool
        var editContentX: Double
        var editVisible: Bool
    }

    public init() {}

    // MARK: - Owner lifecycle

    /// Attaches one document generation and publishes its current edit cursor.
    /// The workspace remains the session's sole `onChange` subscriber and calls
    /// `sessionDidChange(_:)` for cursor-domain publications.
    @QtIgnored
    public func attach(viewport: DocumentViewport) {
        self.viewport = viewport
        hoverOwner = nil
        hoverTick = nil
        published = nil
        timelineAttached = true
        apply()
    }

    /// Detaches synchronously and hides both guides before the document retires.
    @QtIgnored
    public func detach() {
        viewport = nil
        hoverOwner = nil
        hoverTick = nil
        apply()
    }

    // MARK: - Session publications

    /// Routes the session's single change publication. Only cursor changes can
    /// alter the edit guide; document and selection changes leave its tick alone.
    @QtIgnored
    public func sessionDidChange(_ change: SessionChange) {
        guard change.domains.contains(.cursor) else { return }
        refreshEditCursor()
    }

    /// Reprojects both retained guide ticks through the current camera.
    @QtIgnored
    public func refreshProjection() {
        guard viewport != nil else { return }
        apply()
    }

    /// Refreshes the edit guide from the session's current edit cursor.
    @QtIgnored
    public func refreshEditCursor() {
        guard viewport != nil else { return }
        apply()
    }

    // MARK: - Hover ownership

    /// Publishes a hover for one owner. A before-song-start or invalid position
    /// clears only that owner, preserving a different owner's active hover.
    @QtIgnored
    public func updateHover(owner: Int, contentX: Double) {
        guard owner != PlayheadGuideHoverOwner.none.rawValue else { return }
        guard let viewport, contentX.isFinite else {
            clearHover(owner: owner)
            return
        }
        let tick = viewport.camera.tickAtContentX(contentX)
        guard tick.isFinite, tick >= 0 else {
            clearHover(owner: owner)
            return
        }
        hoverOwner = owner
        hoverTick = tick
        apply()
    }

    /// Clears an owner only when that owner currently owns the published hover.
    @QtIgnored
    public func clearHover(owner: Int) {
        guard hoverOwner == owner else { return }
        hoverOwner = nil
        hoverTick = nil
        apply()
    }

    // MARK: - Presentation

    private func projectedX(tick: Double) -> Double {
        guard let viewport else { return 0 }
        return viewport.camera.contentX(tick: tick)
    }

    private func isVisible(tick: Double, contentX: Double) -> Bool {
        guard timelineAttached, tick.isFinite, tick >= 0, contentX.isFinite,
            let viewport
        else { return false }
        let width = viewport.camera.snapshot.viewportWidth
        return contentX >= 0 && contentX < width
    }

    /// Publishes only a changed aggregate, preserving one bridge update per
    /// distinct projection and keeping edit hidden while hover is visible.
    @discardableResult
    private func apply() -> Bool {
        let hoverTick = self.hoverTick
        let hoverX = hoverTick.map(projectedX) ?? 0
        let hoverVisible = hoverTick.map { isVisible(tick: $0, contentX: hoverX) } ?? false
        let editTick = viewport.map { Double($0.session.editCursor) } ?? 0
        let editX = projectedX(tick: editTick)
        let editVisible = isVisible(tick: editTick, contentX: editX) && !hoverVisible
        let next = Presentation(
            timelineAttached: viewport != nil && timelineAttached,
            hoverContentX: hoverX, hoverVisible: hoverVisible,
            editContentX: editX, editVisible: editVisible)
        guard next != published else { return false }
        published = next
        presentationCount &+= 1
        if timelineAttached != next.timelineAttached { timelineAttached = next.timelineAttached }
        if hover.contentX != next.hoverContentX { hover.contentX = next.hoverContentX }
        if hover.visible != next.hoverVisible { hover.visible = next.hoverVisible }
        if edit.contentX != next.editContentX { edit.contentX = next.editContentX }
        if edit.visible != next.editVisible { edit.visible = next.editVisible }
        return true
    }
}
