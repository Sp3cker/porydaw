pragma ComponentBehavior: Bound
// Each logical hover group has one publisher; Swift owns application scope.
// This component owns source lifetime and retains hints across the owner's grab.
import QtQuick
import QtQml
import Porydaw.Ui
import PorydawApp
HoverHandler {
    id: hint
    // A token identifies this physical source without retaining its QObject
    // in Swift. Visibility and destruction below release its ownership.
    required property Item source
    property MouseHints hintService: null
    property bool scopeAllowed: true
    property MouseHints _service: null
    property int _sourceToken: 0
    property int profile: HintProfiles.Empty
    // Retain the originating profile while the bound drag owner holds its grab,
    // even if Qt drops hover membership.
    property bool gestureOwning: false
    // Actual release containment overrides frozen hover membership.
    property bool releaseInside: true

    onHintServiceChanged: {
        if (_service && _sourceToken)
            _service.clear(_sourceToken)
        _service = hintService
        _sourceToken = _service ? _service.allocateSourceToken() : 0
        _owned = false
        _gestureProfile = HintProfiles.Empty
        sync()
    }
    onScopeAllowedChanged: sync()
    property QtObject sourceLifetime: Connections {
        target: hint.source
        function onVisibleChanged(): void { hint.sync() }
        function onWindowChanged(): void { hint.sync() }
        function onParentChanged(): void { hint.sync() }
    }
    property QtObject refresh: Connections {
        target: hint._hints()

        function onScopeRefresh(): void {
            hint.sync()
        }
    }

    property bool _owned: false
    // The originating profile retained across the group's grab.
    property int _gestureProfile: HintProfiles.Empty

    function _hints(): MouseHints {
        return _service
    }

    // Only the existing owner's grab retains a claimed group.
    onHoveredChanged: {
        // A real re-entry ends the previous outside-release suppression.
        if (hovered)
            releaseInside = true
        sync()
    }
    // An implicit grab can leave hovered true across an outside release.
    // Only a newly delivered inside position rearms that suppressed source.
    onPointChanged: {
        if (!releaseInside && !gestureOwning && hovered)
            settleRelease(point.scenePosition)
    }
    onGestureOwningChanged: {
        if (gestureOwning) {
            if (hovered)
                _gestureProfile = profile
        } else {
            // On completion the actual release position decides; a frozen
            // membership no longer resumes the grabbed profile.
            _gestureProfile = HintProfiles.Empty
        }
        sync()
    }
    // Child hover changes profiles without a new hover event; retained grabs
    // keep their originating profile until release.
    onProfileChanged: if (!gestureOwning) sync()
    onSourceChanged: {
        if (_service && _sourceToken)
            _superseded(_service)
        sync()
    }
    Component.onCompleted: sync()
    // A source-check clear, not a claim: the service releases only
    // this source's ownership.
    Component.onDestruction: {
        if (_service && _sourceToken)
            _service.clear(_sourceToken)
    }

    // Settle actual release containment before bookkeeping so outside releases
    // clear ownership even when Qt froze hover.
    function settleRelease(scenePosition: point): void {
        if (!source)
            return
        const localPosition = source.mapFromItem(null, scenePosition.x, scenePosition.y)
        releaseInside = source.contains(localPosition)
        sync()
    }

    // A grabbed neighbor delivers its real release coordinate here when
    // Qt has not yet synthesized new hover membership for this source.
    function receiveRelease(scenePosition: point): void {
        if (!source || !_service || !_sourceToken || !_sourceVisible()
                || !scopeAllowed || gestureOwning)
            return
        const localPosition = source.mapFromItem(null, scenePosition.x, scenePosition.y)
        if (!source.contains(localPosition))
            return
        releaseInside = true
        _service.claim(_sourceToken, profile)
        _owned = true
    }

    // Normal hover and lifecycle events claim here; receiveRelease() claims
    // from a grabbed neighbor's real coordinates before Qt updates hover.
    function sync(): void {
        const hints = _hints()
        if (!hints || !_sourceToken)
            return
        if (!source) {
            _superseded(hints)
            return
        }
        // Scope loss clears even a gesture-retained empty profile.
        if (!scopeAllowed) {
            _superseded(hints)
            return
        }
        // Effective lifetime: a hidden or windowless source owns nothing,
        // even mid-gesture.
        if (!_sourceVisible()) {
            _superseded(hints)
            return
        }
        if (gestureOwning) {
            if (_owned) {
                // Retain the originating profile for the whole grab.
                hints.claim(_sourceToken, _gestureProfile)
            } else if (hovered && releaseInside) {
                _gestureProfile = profile
                hints.claim(_sourceToken, profile)
                _owned = true
            }
            return
        }
        if (!hovered || !releaseInside) {
            // Clear this source's ownership; never reclaim with an empty profile.
            _superseded(hints)
            return
        }
        hints.claim(_sourceToken, profile)
        _owned = true
    }

    function _superseded(hints: MouseHints): void {
        _owned = false
        _gestureProfile = HintProfiles.Empty
        hints.clear(_sourceToken)
    }

    function _sourceVisible(): bool {
        const win = source.Window.window
        // A detached (unparented or differently fresh) item has no window;
        // a closed or hidden window has no hover to claim.
        return win !== null && win.visible
                && source.visible && source.parent !== null
    }
}
