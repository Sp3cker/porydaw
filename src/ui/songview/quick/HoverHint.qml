// One reusable hover-scope group policy. A HoverHint owns exactly one logical
// target group and is that group's only publisher into the mouse-hints
// service. Child HoverHandlers may select the profile (by changing `profile`)
// but never publish independently, and no ancestor publisher may cover
// different-profile descendants: attach the publisher at the smallest item
// that sees the whole group's hover. A child or page-wide ancestor publisher
// over mixed profiles is a protocol violation.
//
// The Quick popup scope is enforced here. While the session is open, a source
// its overlay owns may keep claiming; every other source is suppressed and
// cannot claim even an empty profile (a suppressed group also clears existing
// ownership). Native popups and application inactivity are the service's own
// gates, not this component's.
import QtQuick
import QtQml
import Porydaw.Ui
HoverHandler {
    id: hint
    // The item whose physical surface this group describes. Ownership claims
    // and clears use this identity, so a source switch moves the claim and a
    // destroyed source is released by the service's source observation.
    required property Item source
    property int profile: HintProfiles.Empty
    // While the existing drag owner holds the group's grab (the caller binds
    // this to that owner's active flag), the originating profile stays
    // claimed even if Qt drops hover membership mid-gesture.
    property bool gestureOwning: false
    // Whether the drag owner's actual final position is inside `source`. A
    // drag group settles this from real release coordinates via
    // settleRelease()/settleReleaseFromGlobal(); a frozen hover membership
    // never keeps ownership after an outside release.
    property bool releaseInside: true

    // A HoverHandler is a QObject without an Item-style default property, so
    // each non-visual Connections is bound to a named property instead. The
    // target must resolve at creation: an unset Connections target falls back
    // to this handler, which owns neither signal; an explicitly assigned null
    // stays deliberately unconnected while the context object is unavailable.
    property QtObject links: Connections {
        target: hint._session()

        function onIsOpenChanged() {
            hint.sync()
        }
    }
    property QtObject refresh: Connections {
        target: hint._hints()

        function onScopeRefresh() {
            hint.sync()
        }
    }

    property bool _owned: false
    // The originating profile retained across the group's grab.
    property int _gestureProfile: HintProfiles.Empty

    function _hints() {
        return (typeof mouseHints !== "undefined") ? mouseHints : null
    }
    function _session() {
        return (typeof quickPopupSession !== "undefined") ? quickPopupSession : null
    }

    // Pointer scope changes reclaim or clear. Launching a grab is not
    // itself enough: a group only retains while its existing owner really
    // holds it, per the caller's gestureOwning binding.
    onHoveredChanged: sync()
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
    // A child hover may hand the group another profile without any hover
    // event of its own. During a retained grab the originating profile
    // stays claimed until the grab ends.
    onProfileChanged: if (!gestureOwning) sync()
    onSourceChanged: sync()
    Component.onCompleted: sync()
    // A source-check clear, not a claim: the service releases only
    // this source's ownership.
    Component.onDestruction: {
        const hints = (typeof mouseHints !== "undefined") ? mouseHints : null
        if (hints && source)
            hints.clear(source)
    }

    // Settles a completed group gesture from the drag owner's actual release
    // coordinates in the scene window. The containment check runs against
    // the source before any release bookkeeping, so an outside release
    // clears even when Qt froze hover membership.
    function settleRelease(scenePosition) {
        if (!source)
            return
        releaseInside = source.contains(
                    source.mapFromItem(null, scenePosition.x, scenePosition.y))
        sync()
    }
    function settleReleaseFromGlobal(globalPosition) {
        if (!source)
            return
        releaseInside = source.contains(source.mapFromGlobal(globalPosition))
        sync()
    }

    // The one claim path. Hover changes, profile changes, gesture
    // starts and completions, both session transitions and native scope
    // refreshes all funnel here; nothing outside this function decides
    // ownership, so a close with unchanged `hovered` and a refresh with
    // unchanged hover both still resync.
    function sync() {
        const hints = _hints()
        if (!hints || !source)
            return
        // Scope gate first: a suppressed group may not claim or keep even
        // an empty profile. This also overrides gesture retention — scope
        // loss ends a retained profile.
        const session = _session()
        if (session && session.isOpen && !session.owns(source)) {
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
                hints.claim(source, _gestureProfile)
            } else if (hovered && releaseInside) {
                _gestureProfile = profile
                hints.claim(source, profile)
                _owned = true
            }
            return
        }
        if (!hovered || !releaseInside) {
            // Unhovered, or the drag settled outside: a source-checked
            // clear, never an empty-profile reclaim by a no-longer-hovered
            // source.
            _superseded(hints)
            return
        }
        hints.claim(source, profile)
        _owned = true
    }

    function _superseded(hints) {
        _owned = false
        _gestureProfile = HintProfiles.Empty
        hints.clear(source)
    }

    function _sourceVisible() {
        const win = source.Window.window
        // A detached (unparented or differently fresh) item has no window;
        // a closed or hidden window has no hover to claim.
        return win !== null && win.visible
                && source.visible && source.parent !== null
    }
}
