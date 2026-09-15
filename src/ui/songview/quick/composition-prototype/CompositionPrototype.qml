// THROWAWAY composition prototype — NOT production code, NOT a migration.
// Question under test: what do StackLayout, Repeater, ListModel.move and
// FocusScope give us for persistent song pages, text focus, readiness,
// close/reorder and popup cancellation WITHOUT custom focus management?
// Run standalone:  qml src/ui/songview/quick/composition-prototype/CompositionPrototype.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

FocusScope {
    id: root
    width: u * 44
    height: u * 32
    focus: true

    // ---- authoritative state -------------------------------------------
    // selectedId is the ONLY selection authority. selectedIndex is derived
    // and re-synced after every observable model mutation.
    property string selectedId: "A"
    property int selectedIndex: -1
    property int createdCount: 0
    property int destroyedCount: 0

    // ---- fixed contract aliases ----------------------------------------
    property alias pageModel: pageModel
    property alias pageStack: pageStack
    property alias tabStrip: tabStrip

    // ---- reserved for native-host integration (set by native host) ------
    property bool nativeHost: false
    property int transportCount: 0

    // Explicit user entry into the editor area FocusScope. Qt then restores
    // that scope's focused descendant chain (page scope -> editor). Never
    // invoked by selection changes; switching alone does not force focus.
    function enterEditor(reason) {
        editorArea.forceActiveFocus(reason === undefined ? Qt.OtherFocusReason : reason);
    }

    // Explicit user entry into the tab strip for keyboard-only use. F6 is
    // the advertised "focus the tab strip" command (Qt.ShortcutFocusReason);
    // it targets the selected TabButton so Left/Right and Enter work there.
    // This is a user command, not focus repair — selection changes never
    // call it.
    function enterTabStrip() {
        var t = tabStrip.tabAt(selectedIndex);
        if (t) t.forceActiveFocus(Qt.ShortcutFocusReason);
    }

    FontMetrics { id: fm }
    property int u: Math.max(8, fm.font.pixelSize)

    ListModel {
        id: pageModel
        ListElement { songId: "A"; ready: true }
        ListElement { songId: "B"; ready: true }
        ListElement { songId: "C"; ready: true }
    }

    function indexOf(id) {
        for (var i = 0; i < pageModel.count; ++i)
            if (pageModel.get(i).songId === id) return i;
        return -1;
    }
    function pageFor(id) {
        for (var i = 0; i < pageRepeater.count; ++i) {
            var p = pageRepeater.itemAt(i);
            if (p && p.songId === id) return p;
        }
        return null;
    }
    function focusLabel() {
        var w = Window.window;
        var f = w ? w.activeFocusItem : null;
        return f ? (f.objectName || String(f)) : "none";
    }
    function syncSelection(where) {
        selectedIndex = indexOf(selectedId);
        console.log("[proto]", where,
                    "| selectedId=" + selectedId,
                    "index=" + selectedIndex,
                    "| focus=" + focusLabel());
    }

    function selectPage(id) {
        if (indexOf(id) < 0) { console.log("[proto] selectPage: no page", id); return; }
        if (selectedId === id) return;   // same identity: no re-emission
        selectedId = id;
        syncSelection("selectPage(" + id + ")");
    }
    function setReady(id, r) {
        var i = indexOf(id);
        if (i < 0) return;
        pageModel.setProperty(i, "ready", r);
        syncSelection("setReady(" + id + "," + r + ")");
    }
    function movePage(from, to) {
        if (from < 0 || from >= pageModel.count || to < 0 || to >= pageModel.count) return;
        pageModel.move(from, to, 1);
        syncSelection("movePage(" + from + "->" + to + ")");
    }

    // Close transaction ordering (the observed bug was removing the row
    // while its popup still owned focus, leaving focus on QQuickRootItem):
    //   1. close the outgoing page's popup while the page is still alive and
    //      still selected, so Qt returns focus to that page's scope;
    //   2. publish the successor selection while the outgoing page still
    //      exists, so the incoming scope activates through a normal scope
    //      transfer (its remembered focused descendant gets focus);
    //   3. only then remove the row and let the page be destroyed.
    // No timers, no remembered-item state, no blanket forceActiveFocus.
    function closePage(id) {
        var i = indexOf(id);
        if (i < 0) return;
        var p = pageFor(id);
        if (p && p.popup.visible) p.popup.close();
        if (selectedId === id) {
            var next = pageModel.count > 1
                     ? pageModel.get(i + 1 < pageModel.count ? i + 1 : i - 1).songId
                     : "";
            selectedId = next;   // deselect also closes popup via page handler
        }
        pageModel.remove(i);
        syncSelection("closePage(" + id + ")");
    }

    // Monotonic id source: survives close/reopen without reuse.
    property int pageSeq: 0
    function addPage() {
        var id = "N" + (++pageSeq);
        pageModel.append({ songId: id, ready: true });
        selectedId = id;
        syncSelection("addPage(" + id + ")");
        return id;
    }

    // Ctrl+Tab cycling: selection-only, identity-preserving (songId, not
    // position). Plain Shortcut precedence is Qt-native: focused text/popup
    // editors keep their keys via shortcut override.
    function cyclePage(d) {
        if (pageModel.count === 0) return;
        var i = selectedIndex < 0 ? 0 : selectedIndex;
        selectPage(pageModel.get((i + d + pageModel.count) % pageModel.count).songId);
    }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: root.cyclePage(1) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: root.cyclePage(-1) }
    // F6: platform-independent explicit keyboard entry into the tab strip.
    // macOS's default tabFocusBehavior keeps Tab out of buttons, so this is
    // the honest keyboard path; ordinary Tab still traverses text fields.
    Shortcut { sequence: "F6"; onActivated: root.enterTabStrip() }

    // Standalone transport probe. Under the native host a real QAction owns
    // Space instead, so this Shortcut is disabled there. TextFields keep
    // native precedence: Space still types a space while editing.
    Shortcut {
        sequence: "Space"
        enabled: !root.nativeHost
        onActivated: {
            root.transportCount += 1;
            console.log("[proto] transport", root.transportCount);
        }
    }

    Component.onCompleted: syncSelection("init")

    ColumnLayout {
        anchors.fill: parent
        spacing: root.u / 2

        Label {
            text: "SONG PAGE COMPOSITION — PROTOTYPE (throwaway)"
            font.bold: true
            font.pixelSize: root.u
        }

        // Control strip: all pointer controls are Qt.NoFocus so clicks do not
        // steal active focus and Qt's scope transfer stays observable.
        Flow {
            Layout.fillWidth: true
            spacing: root.u / 2
            Repeater {
                model: [
                    { label: "Toggle ready", act: function() { var i = root.selectedIndex; if (i >= 0) root.setReady(root.selectedId, !pageModel.get(i).ready); } },
                    { label: "Move <",  act: function() { if (root.selectedIndex > 0) root.movePage(root.selectedIndex, root.selectedIndex - 1); } },
                    { label: "Move >",  act: function() { if (root.selectedIndex >= 0 && root.selectedIndex < pageModel.count - 1) root.movePage(root.selectedIndex, root.selectedIndex + 1); } },
                    { label: "Close",   act: function() { if (root.selectedId !== "") root.closePage(root.selectedId); } },
                    { label: "Popup",   act: function() { var p = root.pageFor(root.selectedId); if (p) p.popup.open(); } },
                    { label: "Add",     act: function() { root.addPage(); } },
                    // Populate enough tabs to exercise narrow-strip overflow.
                    { label: "Fill",    act: function() { for (var k = 0; k < 8; ++k) root.addPage(); } },
                    // Explicit editor entry seam (same path the native
                    // host's "Return to editor" button uses).
                    { label: "Editor",  act: function() { root.enterEditor(Qt.OtherFocusReason); } }
                ]
                delegate: Button {
                    text: modelData.label
                    font.pixelSize: root.u * 0.8
                    focusPolicy: Qt.NoFocus
                    onClicked: modelData.act()
                }
            }
        }

        // Native tab strip (frozen contract): inputs pageModel/selectedId/
        // selectedIndex; emits *Requested signals the shell answers through
        // the same model APIs the control strip uses. Strip navigation must
        // not force-focus an editor; selection stays authority-only here.
        PrototypeTabStrip {
            id: tabStrip
            Layout.fillWidth: true
            pageModel: pageModel
            selectedId: root.selectedId
            selectedIndex: root.selectedIndex
            onSelectRequested: function(id) { root.selectPage(id); }
            onMoveRequested: function(from, to) { root.movePage(from, to); }
            onCloseRequested: function(id) { root.closePage(id); }
        }

        // Editor area FocusScope: the single explicit-entry target. Pages
        // inside keep their own FocusScope; Qt restores the focused
        // descendant chain when this scope receives active focus.
        FocusScope {
            id: editorArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: true

            StackLayout {
                id: pageStack
                anchors.fill: parent
                currentIndex: root.selectedIndex

                Repeater {
                    id: pageRepeater
                    model: pageModel
                    delegate: PrototypePage {
                        selected: songId === root.selectedId
                        onLifecycle: function(kind, pageId) {
                            if (kind === "created") root.createdCount++;
                            else if (kind === "destroyed") root.destroyedCount++;
                            console.log("[proto] lifecycle", kind, pageId,
                                        "| created=" + root.createdCount,
                                        "destroyed=" + root.destroyedCount);
                        }
                    }
                }
            }

            // Empty-workspace re-entry: visible only when every page is
            // closed; keyboard- and screen-reader-reachable.
            Button {
                anchors.centerIn: parent
                visible: pageModel.count === 0
                text: "New song page"
                font.pixelSize: root.u
                Accessible.name: "Create a new song page"
                onClicked: root.addPage()
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: root.u * 0.8
            text: "focus=" + root.focusLabel()
                  + " | selected=" + root.selectedId + "@" + root.selectedIndex
                  + " | created=" + root.createdCount
                  + " destroyed=" + root.destroyedCount
                  + " | transport=" + root.transportCount
                  + (root.nativeHost ? " (native)" : "")
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: root.u * 0.8
            text: "Click tabs to switch; Ctrl+Tab cycles; F6 focuses the "
                  + "tab strip (Left/Right, Enter). Type in fields, "
                  + "click canvas + press K. Toggle ready / Move / Close act "
                  + "on the selected page. Popup opens the page's popup; "
                  + "switching or unready cancels it. Space = transport"
                  + (root.nativeHost ? " (native QAction)." : " (standalone).")
        }
    }
}
