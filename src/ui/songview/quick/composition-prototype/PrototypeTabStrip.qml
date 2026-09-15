pragma ComponentBehavior: Bound
// THROWAWAY composition prototype — NOT production code, NOT a migration.
// Real tab strip: stock TabBar/TabButton only. The controller owns the model
// and selection identity; this strip only emits requests.
//
// Ownership split:
//   Qt-owned:      tab layout, horizontal overflow scrolling, currentIndex
//                  mechanics, focus traversal between tabs, press visuals.
//   App-owned:     which song is selected (selectedId/selectedIndex come in
//                  as bindings; we never store independent selection state),
//                  model mutations (we emit *Requested signals only).
import QtQuick
import QtQuick.Controls

TabBar {
    id: root

    // ---- fixed contract -------------------------------------------------
    required property var pageModel        // ListModel: roles songId, ready
    required property string selectedId    // authoritative selection identity
    property int selectedIndex: -1         // controller projection of selectedId

    signal selectRequested(string songId)
    signal moveRequested(int from, int to)
    signal closeRequested(string songId)

    // Controller-facing lookup: returns the TabButton for a model index.
    // The shell's explicit keyboard entry (F6) forceActiveFocus()es this.
    function tabAt(index) { return tabRepeater.itemAt(index); }

    // Pure projection of the app-owned selection. No onCurrentIndexChanged
    // feedback: model insert/remove/move churns currentIndex internally and
    // must never be converted into selection requests. Only real user input
    // (pointer, Enter/Return, accessibility press, Left/Right) requests.
    currentIndex: root.selectedIndex

    // Stock TabBar contentItem is a horizontally scrollable ListView —
    // overflow and "selected tab reachable" are Qt-owned behavior.
    contentItem: ListView {
        model: root.contentModel
        currentIndex: root.currentIndex
        spacing: root.spacing
        orientation: ListView.Horizontal
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickIfNeeded
        snapMode: ListView.SnapToItem
        highlightMoveDuration: 0
        clip: true
        // Keep the selected tab visible when it changes or on narrow widths.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        onWidthChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    }

    Repeater {
        id: tabRepeater
        model: root.pageModel

        delegate: Component {
            TabButton {
            id: tab
            required property string songId
            required property bool ready
            required property int index

            objectName: "tab_" + songId
            text: songId + (ready ? "" : " (off)")
            // Font-relative width; stock strip scrolls when they don't fit.
            implicitWidth: Math.max(tabFm.averageCharacterWidth * 12,
                                    tabContent.advanceWidth + closeBtn.width + tab.padding * 3)
            // Explicit width keeps intrinsic size: TabBar's default equal-width
            // sizing would compress tabs instead of letting the strip scroll.
            width: implicitWidth
            Accessible.name: "Tab " + songId

            // Checked is a pure projection of app-owned selectedId — no
            // independent selection state lives here.
            checked: songId === root.selectedId

            // Permit Tab/Backtab focus so Enter/Return and accessibility
            // press have a real target. Space is deliberately NOT claimed:
            // global transport must outrank incidental chrome focus.
            focusPolicy: Qt.TabFocus
            // Native explicit navigation: Left/Right move focus to the
            // neighbor tab AND request that neighbor's selection — one
            // semantic request per key press, no synthetic forwarding.
            KeyNavigation.left: tabRepeater.itemAt(index - 1)
            KeyNavigation.right: tabRepeater.itemAt(index + 1)
            Keys.onLeftPressed: function(event) {
                if (index > 0)
                    root.selectRequested(root.pageModel.get(index - 1).songId);
                event.accepted = false;   // let KeyNavigation move focus too
            }
            Keys.onRightPressed: function(event) {
                if (index < root.pageModel.count - 1)
                    root.selectRequested(root.pageModel.get(index + 1).songId);
                event.accepted = false;
            }

            FontMetrics { id: tabFm }
            TextMetrics { id: tabContent; text: tab.text; font: tab.font }

            onClicked: root.selectRequested(songId)          // pointer select
            Keys.onReturnPressed: root.selectRequested(songId)
            Keys.onEnterPressed: root.selectRequested(songId)
            Accessible.onPressAction: root.selectRequested(songId)

            // Nested close control. It eats its own press so clicking it
            // never selects the tab.
            ToolButton {
                id: closeBtn
                objectName: "close_" + tab.songId
                anchors.right: parent.right
                anchors.rightMargin: tab.padding / 2
                anchors.verticalCenter: parent.verticalCenter
                text: "×"
                focusPolicy: Qt.NoFocus
                implicitWidth: tabFm.averageCharacterWidth * 3
                implicitHeight: tabFm.height * 1.2
                Accessible.name: "Close " + tab.songId
                onClicked: root.closeRequested(tab.songId)
            }

            // Drag-to-reorder: Qt owns grab/threshold; we interpret the drop.
            // The destination is resolved ONLY at release: the release point
            // (scene coordinates) is mapped into the strip's ListView and
            // indexAt answers which real variable-width tab sits under it.
            // grabChanged discriminates the outcomes: GrabExclusive arms the
            // drag, CancelGrabExclusive aborts with no move, UngrabExclusive
            // means the grab was relinquished — a commit additionally
            // requires a physical release (EventPoint.Released) on an enabled
            // strip, inside the visible viewport, on a real tab. No stale
            // per-move dropIndex is kept, so an outside release or a grab
            // stolen by another handler can never reorder.
            DragHandler {
                id: drag
                target: null                    // we track, we don't move the tab
                yAxis.enabled: false
                property int startIndex: -1
                onGrabChanged: function(transition, eventPoint) {
                    var view = root.contentItem;
                    if (transition === PointerDevice.GrabExclusive) {
                        startIndex = tab.index;
                        return;
                    }
                    if (transition === PointerDevice.CancelGrabExclusive) {
                        startIndex = -1;        // grab stolen/lost: abort
                        return;
                    }
                    if (transition !== PointerDevice.UngrabExclusive)
                        return;                 // unrelated passive transitions
                    var from = startIndex;
                    startIndex = -1;
                    // Ungrab is not necessarily a release: disabling the
                    // strip mid-drag relinquishes the grab too. Commit only
                    // on a real Released point while the strip is enabled.
                    if (from < 0 || !root.enabled
                            || eventPoint.state !== EventPoint.Released)
                        return;
                    var vp = view.mapFromItem(null,
                                              eventPoint.scenePosition.x,
                                              eventPoint.scenePosition.y);
                    // Release must land inside the visible viewport — an
                    // offscreen model tab under the coordinate does not count.
                    if (vp.x < 0 || vp.y < 0 || vp.x >= view.width || vp.y >= view.height)
                        return;
                    var hit = view.indexAt(vp.x + view.contentX, vp.y);
                    if (hit >= 0 && hit !== from)
                        root.moveRequested(from, hit);
                }
            }
            }
        }
    }
}
