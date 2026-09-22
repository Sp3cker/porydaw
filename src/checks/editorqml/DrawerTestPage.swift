@testable import PorydawApp

/// The lane's real `EditorDrawerPage`: a test-only page with a settled kind, a
/// resolved content URL and a deterministic body policy, so the container's
/// host seam is exercised exactly the way a production page will use it.
///
/// Main-actor isolated like the seam it implements: the container cancels a
/// page synchronously from its main-actor path, and the compiler enforces that
/// this page is only ever touched from there.
@MainActor
final class DrawerTestPage: EditorDrawerPage {
    let sectionKind: DrawerSectionKind
    let contentUrl: String
    private(set) var bodyPolicy: EditorDrawerBodyPolicy

    /// The lane's own interaction state, exactly as a production page reports
    /// the gesture it owns; `cancelSectionInteraction` clears it, so the
    /// playhead's follow suspension can be driven and released through the real
    /// container seam.
    private(set) var interactionActive = false

    /// Counted by `EditorQmlBootstrap`; every cancellation the container
    /// performs, including the one a detach performs, lands here once.
    private let onCancel: @MainActor () -> Void

    init(
        sectionKind: DrawerSectionKind,
        contentUrl: String,
        maximumBodyHeight: Int?,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.sectionKind = sectionKind
        self.contentUrl = contentUrl
        self.bodyPolicy = EditorDrawerBodyPolicy(
            maximumBodyHeight: maximumBodyHeight,
            preferredBodyHeight: { hostHeight, metrics in
                Self.preferredBodyHeight(for: sectionKind, hostHeight: hostHeight, metrics: metrics)
            }
        )
        self.onCancel = onCancel
    }

    /// The voice-changes spill case declares a maximum after attaching; the
    /// container re-reads the policy on every layout pass.
    func setMaximumBodyHeight(_ maximum: Int?) {
        bodyPolicy.maximumBodyHeight = maximum
    }

    /// The lane's interruption control: the page owns an interaction, exactly as
    /// a production page does while its gesture is live.
    func setInteractionActive(_ active: Bool) {
        interactionActive = active
    }

    func cancelSectionInteraction() {
        interactionActive = false
        onCancel()
    }

    /// Host-relative defaults only: a case's expectations come from the
    /// rectangles the presenter publishes, never from a copied pixel constant.
    /// `nonisolated` because the `@Sendable` policy closure the container calls
    /// is synchronous and not actor-isolated; it reads only Sendable values.
    private nonisolated static func preferredBodyHeight(
        for kind: DrawerSectionKind,
        hostHeight: Int,
        metrics: EditorDrawerMetrics
    ) -> Int {
        switch kind {
        case .automation, .voiceChanges:
            // Production's automation default, bounded by the roll reserve.
            return min(
                max(hostHeight / 5, metrics.minimumBody),
                metrics.maximumDefaultBodyHeight(hostHeight: hostHeight)
            )
        case .velocity:
            // Production's velocity default keeps a smaller font-relative band.
            return min(max(hostHeight / 6, metrics.minimumBody * 2), metrics.minimumBody * 4)
        }
    }
}
