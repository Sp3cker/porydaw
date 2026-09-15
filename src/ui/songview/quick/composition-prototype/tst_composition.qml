// THROWAWAY experiment driver — ephemeral, NOT registered project coverage.
// Mounts the real CompositionPrototype and exercises native focus/selection
// behavior with real mouse/key delivery. Observes outcomes; does not
// simulate or route focus itself.
// Run:  qmltestrunner -input src/ui/songview/quick/composition-prototype/tst_composition.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest

TestCase {
    id: tc
    name: "CompositionPrototype"
    when: windowShown
    width: 700; height: 500
    visible: true

    Component { id: shellComp; CompositionPrototype {} }
    property var shell: null

    function init() {
        shell = createTemporaryObject(shellComp, tc);
        verify(shell);
        verify(shell.tabStrip, "shell must expose tabStrip");
        waitForRendering(shell);
    }
    function cleanup() { shell = null; }

    // ---- helpers --------------------------------------------------------

    function focusItem() {
        var w = shell.Window.window;
        return w ? w.activeFocusItem : null;
    }
    function isDescendant(item, ancestor) {
        for (var p = item; p; p = p.parent)
            if (p === ancestor) return true;
        return false;
    }
    function findByName(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        var kids = root.children || [];
        for (var i = 0; i < kids.length; ++i) {
            var hit = findByName(kids[i], name);
            if (hit) return hit;
        }
        return findByName(root.contentItem, name);
    }
    function indexOf(id) {
        for (var i = 0; i < shell.pageModel.count; ++i)
            if (shell.pageModel.get(i).songId === id) return i;
        return -1;
    }
    function tabFor(id) {
        var i = indexOf(id);
        return i < 0 ? null : shell.tabStrip.tabAt(i);
    }
    function closeButtonFor(id) {
        var t = tabFor(id);
        return t ? findByName(t, "close_" + id) : null;
    }
    function labelFor(item) {
        if (!item) return "none";
        for (var i = 0; i < shell.pageModel.count; ++i) {
            var p = shell.pageFor(shell.pageModel.get(i).songId);
            if (!p) continue;
            if (item === p) return p.songId + ":page";
            if (item === p.editorA) return p.songId + ":editorA";
            if (item === p.editorB) return p.songId + ":editorB";
            if (item === p.canvas) return p.songId + ":canvas";
            if (item === p.popupEditor) return p.songId + ":popupEditor";
        }
        return item.objectName || String(item);
    }
    function diag(tag) {
        console.log("[diag]", tag,
                    "| focus=" + labelFor(focusItem()),
                    "| sel=" + shell.selectedId + "@" + shell.selectedIndex,
                    "| created=" + shell.createdCount,
                    "destroyed=" + shell.destroyedCount);
    }
    function clickTab(id) {
        var t = tabFor(id);
        verify(t, "tab " + id);
        mouseClick(t);
        waitForRendering(shell);
    }
    function clickClose(id) {
        var c = closeButtonFor(id);
        verify(c, "close button for " + id);
        mouseClick(c);
        waitForRendering(shell);
    }
    function typeInto(field, text) {
        mouseClick(field);
        waitForRendering(shell);
        for (var i = 0; i < text.length; ++i) keyClick(text[i]);
        waitForRendering(shell);
    }
    // Type with NO mouse refocus; assert the text landed in a descendant of
    // `page` and return which field received it.
    function typeNow(page, text) {
        for (var i = 0; i < text.length; ++i) keyClick(text[i]);
        waitForRendering(shell);
        var f = focusItem();
        verify(isDescendant(f, page),
               "focus must be inside " + page.songId + ", got " + labelFor(f));
        return f;
    }
    function assertFocusIn(page, tag) {
        var f = focusItem();
        verify(isDescendant(f, page),
               tag + ": focus must be inside " + page.songId +
               ", got " + labelFor(f));
        return f;
    }
    // 0) Initial state: the ready selected page must hold a live focused
    //    editor immediately after construction — no click, no refocus.
    //    Catches a missing editorArea focus default (focus falls to root).
    function test_00_initial_ready_page_typing() {
        var a = shell.pageFor("A");
        verify(a);
        var f = typeNow(a, "i");
        verify(f === a.editorA || f === a.editorB,
               "initial focus must be a real editor, got " + labelFor(f));
        compare(f.text, "i", "ready page accepts keys with zero setup");
    }


    // ---- tests ----------------------------------------------------------

    // 1) Real pointer tab click + typing into both fields; K on canvas must
    //    not leak into text fields; native undo must restore text.
    function test_01_tabs_typing_canvas_undo() {
        var a = shell.pageFor("A");
        typeInto(a.editorA, "hi");
        typeInto(a.editorB, "yo");
        compare(a.editorA.text, "hi");
        compare(a.editorB.text, "yo");
        keyClick(Qt.Key_Z, Qt.ControlModifier);   // native undo in editorB
        compare(a.editorB.text, "", "native undo must revert typed text");
        keyClick(Qt.Key_Z, Qt.ControlModifier);
        compare(a.editorB.text, "", "second undo is a no-op");
        mouseClick(a.canvas);
        keyClick(Qt.Key_K);
        compare(a.editCount, 1);
        compare(a.editorA.text, "hi", "K must not leak into editorA");
        diag("tabs/typing/canvas/undo");
    }

    // 2) Switch A->B->A preserves each page's focused descendant AND the
    //    restored descendant accepts key input with no mouse refocus.
    function test_02_switch_restores_live_focus() {
        var a = shell.pageFor("A"), b = shell.pageFor("B");
        mouseClick(a.editorB);
        clickTab("B");
        compare(shell.selectedId, "B");
        mouseClick(b.editorA);
        clickTab("A");
        diag("after A->B->A");
        compare(focusItem(), a.editorB,
                "A's focused descendant should be restored, got " + labelFor(focusItem()));
        var f = typeNow(a, "x");                  // no refocus click
        compare(f, a.editorB, "typed text must land in restored editorB");
        compare(a.editorB.text, "x");
        clickTab("B");
        compare(focusItem(), b.editorA,
                "B's focused descendant should be restored, got " + labelFor(focusItem()));
        f = typeNow(b, "y");
        compare(f, b.editorA);
        compare(b.editorA.text, "y");
    }

    // 3) Readiness: background unready doesn't block A; selected-unready
    //    cannot edit; recovery restores a live focused descendant that
    //    accepts keys immediately.
    function test_03_readiness_gating_and_recovery() {
        var a = shell.pageFor("A"), b = shell.pageFor("B");
        shell.setReady("B", false);
        typeInto(a.editorA, "ok");
        compare(a.editorA.text, "ok", "A editable while B unready");
        shell.setReady("A", false);
        waitForRendering(shell);
        diag("A unready");
        mouseClick(a.editorA);
        keyClick("x");
        compare(a.editorA.text, "ok", "unready selected page must not accept edits");
        shell.setReady("A", true);
        waitForRendering(shell);
        var f = typeNow(a, "!");
        compare(f, a.editorA, "recovery must restore the previously focused editorA");
        compare(a.editorA.text, "ok!", "recovered page accepts edits without refocus");
        shell.setReady("B", true);
    }

    // 4) Close the focused page via its real close button; the survivor's
    //    focused descendant must accept keys immediately (no stranded focus).
    function test_04_close_selected_survivor_typing() {
        var a = shell.pageFor("A"), b = shell.pageFor("B");
        mouseClick(a.editorB);
        var before = shell.destroyedCount;
        clickClose("A");
        diag("closed A");
        compare(shell.destroyedCount, before + 1);
        verify(!shell.pageFor("A"));
        compare(shell.selectedId, "B", "successor selection");
        compare(shell.pageFor("B"), b, "survivor must be the same QObject");
        var f = typeNow(b, "s");
        verify(f === b.editorA || f === b.editorB,
               "typed text must reach a B editor, got " + labelFor(f));
        compare(f.text, "s", "survivor accepts edits after close");
        compare(b.editCount, 0, "no stale page edit");
    }

    // 5) Close a popup-owning selected page via its REAL close button while
    //    the popup is open: the pointer press must reach the strip (popup is
    //    non-modal), the popup dies with the page, and the survivor accepts
    //    keys immediately — no refocus click anywhere.
    function test_05_close_popup_owner() {
        var a = shell.pageFor("A"), b = shell.pageFor("B");
        a.popup.open();
        waitForRendering(shell);
        verify(a.popup.visible);
        typeInto(a.popupEditor, "pop");
        compare(a.popupEditor.text, "pop");
        clickClose("A");                     // real click with popup open
        diag("closed popup owner A");
        verify(!shell.pageFor("A"));
        verify(!findByName(shell, "popupEditor_A"),
               "popup editor must be destroyed with its owner page");
        compare(shell.selectedId, "B");
        var f = typeNow(b, "z");
        verify(f === b.editorA || f === b.editorB,
               "text must land in survivor B, got " + labelFor(f));
        compare(f.text, "z");
    }
    // 5b) Popup cancellation by SELECTION LOSS: switching pages must close
    //     the popup and the survivor must accept keys immediately — no
    //     manual focus restoration anywhere.
    function test_05b_popup_cancel_on_switch() {
        var a = shell.pageFor("A"), b = shell.pageFor("B");
        a.popup.open();
        waitForRendering(shell);
        verify(a.popup.visible);
        typeInto(a.popupEditor, "pop");
        compare(a.popupEditor.text, "pop");
        clickTab("B");                          // real tab input cancels it
        waitForRendering(shell);
        diag("switched away from popup owner");
        verify(!a.popup.visible, "popup must close on selection loss");
        compare(shell.selectedId, "B");
        var f = typeNow(b, "w");
        verify(f === b.editorA || f === b.editorB,
               "survivor must accept keys after popup cancel, got " + labelFor(f));
        compare(f.text, "w");
        compare(a.popupEditor.text, "pop", "cancelled popup keeps its text");
    }

    // 5c) Popup cancellation by READINESS LOSS: unready closes the popup;
    //     recovery must restore a live focused descendant that types
    //     immediately — again with no refocus click.
    function test_05c_popup_cancel_on_unready() {
        var a = shell.pageFor("A");
        a.popup.open();
        waitForRendering(shell);
        typeInto(a.popupEditor, "pop");
        compare(a.popupEditor.text, "pop");
        shell.setReady("A", false);
        waitForRendering(shell);
        diag("readiness lost with popup open");
        verify(!a.popup.visible, "popup must close on readiness loss");
        shell.setReady("A", true);
        waitForRendering(shell);
        var f = typeNow(a, "r");
        verify(f === a.editorA || f === a.editorB,
               "recovered page must accept keys, got " + labelFor(f));
        compare(f.text, "r");
    }


    // 6) Real close button on a NON-selected page: selection, focus and the
    //    selected page's identity/text must be untouched.
    function test_06_close_nonselected() {
        var a = shell.pageFor("A");
        typeInto(a.editorA, "keep");
        mouseClick(a.editorB);
        var createdBefore = shell.createdCount;
        clickClose("C");
        diag("closed nonselected C");
        verify(!shell.pageFor("C"));
        compare(shell.selectedId, "A", "selection unchanged by nonselected close");
        compare(shell.pageFor("A"), a, "selected page identity preserved");
        compare(a.editorA.text, "keep");
        compare(shell.createdCount, createdBefore, "close must not recreate pages");
        var f = typeNow(a, "!");
        compare(f, a.editorB, "focus must still be A's editorB");
        compare(a.editorB.text, "!");
    }

    // 7) Close the last page, then addPage() must reopen a fresh usable page.
    function test_07_close_all_then_add() {
        while (shell.pageModel.count > 0)
            shell.closePage(shell.pageModel.get(0).songId);
        waitForRendering(shell);
        compare(shell.pageModel.count, 0);
        compare(shell.selectedId, "");
        var id = shell.addPage();
        waitForRendering(shell);
        verify(id && id.length > 0, "addPage must return a new songId");
        compare(shell.selectedId, id, "new page becomes selected");
        var p = shell.pageFor(id);
        verify(p);
        var f = typeNow(p, "n");
        verify(f === p.editorA || f === p.editorB,
               "fresh page must accept keys, got " + labelFor(f));
        compare(f.text, "n");
    }

    // 8) Reorder through a real pointer drag on the tab strip: the live page
    //    object, its text/counter and the selection must survive.
    function test_08_drag_reorder_preserves_page() {
        var a = shell.pageFor("A");
        typeInto(a.editorA, "keep");
        mouseClick(a.canvas); keyClick(Qt.Key_K);
        compare(a.editCount, 1);
        var createdBefore = shell.createdCount;
        var t = tabFor("A");
        verify(t);
        var p0 = t.mapToItem(shell.tabStrip, 0, 0);
        var dropX = p0.x + t.width * 2.2;         // drag two slots right
        mouseDrag(t, t.width / 2, t.height / 2,
                  dropX - p0.x, 0, Qt.LeftButton, Qt.NoModifier, 300);
        waitForRendering(shell);
        diag("after drag");
        verify(indexOf("A") !== 0, "drag must reorder A off index 0");
        compare(shell.selectedId, "A", "selected identity survives drag");
        compare(shell.pageFor("A"), a, "same QObject after drag");
        compare(a.editorA.text, "keep");
        compare(a.editCount, 1);
        compare(shell.createdCount, createdBefore, "reorder must not recreate pages");
    }

    // 8b) Drag cancellation: a real drag released OUTSIDE the visible strip
    //     viewport must not reorder, and a grab cancelled mid-drag (strip
    //     disabled while held — normal Qt input cancellation, no direct
    //     handler calls) must not reorder either. Selection, page identity
    //     and page state stay untouched throughout.
    function test_08b_drag_cancel_no_reorder() {
        var a = shell.pageFor("A");
        typeInto(a.editorA, "keep");
        var createdBefore = shell.createdCount;

        // -- outside release: drag A across B, then release below the strip.
        var t = tabFor("A");
        verify(t);
        var p0 = t.mapToItem(shell.tabStrip, 0, 0);
        var midX = p0.x + t.width * 2.2;        // held over B's slot
        var dropY = shell.tabStrip.height + 20; // below the strip viewport
        mousePress(t, t.width / 2, t.height / 2);
        waitForRendering(shell);
        mouseMove(t, midX - p0.x, t.height / 2, 300, Qt.LeftButton);
        waitForRendering(shell);
        mouseMove(t, midX - p0.x, dropY - p0.y, 300, Qt.LeftButton);
        waitForRendering(shell);
        mouseRelease(t, midX - p0.x, dropY - p0.y);
        waitForRendering(shell);
        diag("after outside-release drag");
        compare(indexOf("A"), 0,
                "release outside the strip viewport must not reorder");
        compare(shell.selectedId, "A");
        compare(shell.pageFor("A"), a, "same QObject after cancelled drop");
        compare(a.editorA.text, "keep");

        // -- grab loss: hold a drag, disable the strip mid-drag (Qt cancels
        //    the grab), release, re-enable. No move may be committed.
        t = tabFor("A");
        p0 = t.mapToItem(shell.tabStrip, 0, 0);
        mousePress(t, t.width / 2, t.height / 2);
        waitForRendering(shell);
        mouseMove(t, t.width * 2.2, t.height / 2, 300, Qt.LeftButton);
        waitForRendering(shell);
        shell.tabStrip.enabled = false;         // native grab cancellation
        waitForRendering(shell);
        mouseRelease(t, t.width * 2.2, t.height / 2);
        waitForRendering(shell);
        shell.tabStrip.enabled = true;
        waitForRendering(shell);
        diag("after grab-cancelled drag");
        compare(indexOf("A"), 0,
                "cancelled grab must not commit a move");
        compare(shell.selectedId, "A");
        compare(shell.pageFor("A"), a);
        compare(a.editorA.text, "keep");
        compare(shell.createdCount, createdBefore,
                "cancelled drags must not recreate pages");

        // -- control: a real in-strip drag still moves exactly once.
        t = tabFor("A");
        p0 = t.mapToItem(shell.tabStrip, 0, 0);
        mouseDrag(t, t.width / 2, t.height / 2,
                  t.width * 2.2, 0, Qt.LeftButton, Qt.NoModifier, 300);
        waitForRendering(shell);
        verify(indexOf("A") !== 0, "in-strip drag must still reorder A");
        compare(shell.selectedId, "A");
        compare(shell.pageFor("A"), a);
        compare(a.editorA.text, "keep");
    }

    // 9) Model movePage keeps identity too (distinct path: no pointer input).
    function test_09_model_move_preserves_identity() {
        var a = shell.pageFor("A");
        typeInto(a.editorA, "keep");
        var createdBefore = shell.createdCount;
        shell.movePage(0, 2);
        waitForRendering(shell);
        compare(shell.selectedId, "A");
        compare(shell.pageFor("A"), a, "same QObject after move");
        compare(a.editorA.text, "keep");
        compare(shell.createdCount, createdBefore);
        compare(shell.selectedIndex, 2);
    }

    // 10) Overflow: seed pages, select A via the ordinary controller path
    //     (the strip scrolls it into view), then narrow so the last tab is
    //     offscreen. A real wheel scrolls it back and a real click must
    //     produce an observable A->last selection transition (not an
    //     already-selected no-op).
    function test_10_overflow_scroll_select() {
        var ids = [];
        for (var i = 0; i < 8; ++i) ids.push(shell.addPage());
        waitForRendering(shell);
        var last = ids[ids.length - 1];
        var page = shell.pageFor(last);
        verify(page);
        // Controller setup: selecting A scrolls its tab into view and
        // guarantees the last tab is NOT already selected.
        shell.selectPage("A");
        waitForRendering(shell);
        compare(shell.selectedId, "A", "precondition: A selected, last is not");
        shell.width = 320;                        // force overflow
        waitForRendering(shell);
        var t = tabFor(last);
        var lv = shell.tabStrip.contentItem;   // stock horizontal ListView
        verify(lv, "strip contentItem must be the scrollable ListView");
        // Real horizontal wheel/trackpad deltas aimed at the ListView's
        // center: negative xDelta scrolls content rightward (toward the
        // last tab). Require observable contentX movement, not just spins.
        var startX = lv.contentX;
        for (var spin = 0; spin < 40; ++spin) {
            t = tabFor(last);
            if (t) {
                var pos = t.mapToItem(shell.tabStrip, 0, 0);
                if (pos.x >= 0 && pos.x + t.width <= shell.tabStrip.width)
                    break;
            }
            mouseWheel(lv, lv.width / 2, lv.height / 2,
                       -120, 0, Qt.NoButton, Qt.NoModifier);
            waitForRendering(shell);
        }
        verify(lv.contentX > startX,
               "horizontal wheel must move contentX, " + startX + "->" + lv.contentX);
        verify(t, "last tab must be reachable after wheel scrolling");
        // Native wheel scrolling animates; wait (bounded) for the ListView
        // to settle AND the tab to be fully onscreen before clicking.
        var settled = false;
        tryVerify(function() {
            var p = t.mapToItem(shell.tabStrip, 0, 0);
            settled = !lv.moving && !lv.flicking
                   && p.x >= 0 && p.x + t.width <= shell.tabStrip.width;
            return settled;
        });
        verify(settled,
               "last tab must settle fully onscreen: contentX=" + lv.contentX
               + " contentWidth=" + lv.contentWidth + " width=" + lv.width
               + " tabX=" + t.mapToItem(shell.tabStrip, 0, 0).x
               + " tabWidth=" + t.width
               + " moving=" + lv.moving + " flicking=" + lv.flicking);
        mouseClick(t);
        waitForRendering(shell);
        compare(shell.selectedId, last,
                "offscreen tab click must transition selection A->" + last);
        compare(shell.pageFor(last), page, "scrolled-to page identity preserved");
        var f = typeNow(page, "e");
        verify(f === page.editorA || f === page.editorB);
        compare(f.text, "e");
    }

    // 11) Keyboard: F6 is the shell-advertised explicit entry into the tab
    //     strip (a user command, not focus repair). Once a tab holds focus,
    //     Left/Right navigate with selection following the focused tab,
    //     Enter activates, and Space on a focused tab drives transport.
    //     Plain Tab inside a text field is reported, not asserted: macOS
    //     tabFocusBehavior is platform-derived and read-only in QML.
    function test_11_keyboard_nav_and_transport() {
        var a = shell.pageFor("A"), b = shell.pageFor("B");
        mouseClick(a.editorA);
        waitForRendering(shell);

        // F6: advertised focus-tab-strip entry; must land on selected tab.
        keyClick(Qt.Key_F6);
        waitForRendering(shell);
        var fTab = focusItem();
        verify(isDescendant(fTab, shell.tabStrip),
               "F6 must focus the tab strip, got " + labelFor(fTab));
        compare(fTab, tabFor("A"),
                "F6 must focus the selected tab, got " + labelFor(fTab));

        // Space on the FOCUSED TAB: transport fires exactly once, selection
        // and strip focus are unchanged. Must run before canvas checks.
        var tc0 = shell.transportCount;
        keyClick(Qt.Key_Space);
        waitForRendering(shell);
        compare(shell.transportCount, tc0 + 1,
                "Space on focused tab must trigger transport exactly once");
        compare(shell.selectedId, "A", "Space must not change selection");
        verify(isDescendant(focusItem(), shell.tabStrip),
               "Space must not eject strip focus, got " + labelFor(focusItem()));

        // Right: selection follows the focused tab; focus stays in strip.
        keyClick(Qt.Key_Right);
        waitForRendering(shell);
        compare(shell.selectedId, "B", "Right must move selection to next tab");
        compare(focusItem(), tabFor("B"),
                "focus must ride to the newly selected tab, got "
                + labelFor(focusItem()));
        // Left back to A; Enter re-activates the focused tab explicitly.
        keyClick(Qt.Key_Left);
        waitForRendering(shell);
        compare(shell.selectedId, "A");
        compare(focusItem(), tabFor("A"));
        keyClick(Qt.Key_Enter);
        waitForRendering(shell);
        compare(shell.selectedId, "A", "Enter on selected tab is a no-op");
        verify(isDescendant(focusItem(), shell.tabStrip),
               "Enter must not strand focus outside the strip, got "
               + labelFor(focusItem()));

        // Re-select A through real tab input before touching A's canvas:
        // navigate Right to B then Left back to A, all inside the strip.
        keyClick(Qt.Key_Right);
        waitForRendering(shell);
        compare(shell.selectedId, "B");
        keyClick(Qt.Key_Left);
        waitForRendering(shell);
        compare(shell.selectedId, "A", "A re-selected via real tab input");

        // Space transport on canvas (standalone shell Shortcut).
        mouseClick(a.canvas);
        waitForRendering(shell);
        tc0 = shell.transportCount;
        keyClick(Qt.Key_Space);
        compare(shell.transportCount, tc0 + 1,
                "Space on canvas must trigger standalone transport");

        // Literal Space inside a text field must edit text, not transport.
        mouseClick(a.editorA);
        keyClick(Qt.Key_Space);
        compare(a.editorA.text, " ", "Space must insert a literal space");
        compare(shell.transportCount, tc0 + 1,
                "Space in text must not trigger transport");

        // Ordinary Tab inside a text field: platform-derived behavior on
        // macOS (tabFocusBehavior is read-only in QML). Report honestly —
        // assert only that the field did not eat it as a literal tab char.
        keyClick(Qt.Key_Tab);
        waitForRendering(shell);
        console.log("[tab] Tab inside editorA: focus=" + labelFor(focusItem()),
                    "editorA.text=" + JSON.stringify(a.editorA.text));
        compare(a.editorA.text, " ",
                "Tab must not insert a literal tab into the text field");

        // Ctrl+Tab cycles selection; scoped descendant focus is preserved.
        mouseClick(a.editorB);
        keyClick(Qt.Key_Tab, Qt.ControlModifier);
        waitForRendering(shell);
        compare(shell.selectedId, "B", "Ctrl+Tab must advance selection");
        keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.ShiftModifier);
        waitForRendering(shell);
        compare(shell.selectedId, "A", "Ctrl+Shift+Tab must cycle back");
        compare(focusItem(), a.editorB,
                "A's scoped descendant must be restored, got " + labelFor(focusItem()));
    }

    // 12) Negative control: does plain StackLayout visibility alone remove
    //     keyboard focus? Isolated shell, observational — type after hiding
    //     and REPORT which field actually receives the input.
    Component {
        id: negComp
        FocusScope {
            width: 300; height: 200; focus: true
            property alias sl: sl
            property alias tfA: tfA
            property alias tfB: tfB
            StackLayout {
                id: sl; anchors.fill: parent
                TextField { id: tfA; objectName: "negA" }
                TextField { id: tfB; objectName: "negB" }
            }
        }
    }
    function test_12_negative_visibility_focus() {
        var neg = createTemporaryObject(negComp, tc);
        verify(neg);
        waitForRendering(neg);
        mouseClick(neg.tfA);
        waitForRendering(neg);
        verify(neg.tfA.activeFocus, "precondition: tfA focused");
        neg.sl.currentIndex = 1;              // hide tfA via StackLayout only
        waitForRendering(neg);
        verify(!neg.tfA.visible, "StackLayout should hide non-current item");
        keyClick("q");                        // where does the key land?
        waitForRendering(neg);
        var w = neg.Window.window;
        var f = w ? w.activeFocusItem : null;
        console.log("[neg] after hiding tfA: tfA.activeFocus=" + neg.tfA.activeFocus,
                    "tfA.text=" + neg.tfA.text,
                    "tfB.text=" + neg.tfB.text,
                    "windowFocus=" + (f ? (f.objectName || String(f)) : "none"));
        // Observed on Qt 6.11 (macOS): StackLayout visibility alone does NOT
        // drop keyboard focus — the hidden tfA keeps activeFocus and receives
        // the key; tfB stays empty. This is a deliberately expected NATIVE
        // limitation recorded by this throwaway experiment, not the desired
        // application behavior (the shell's FocusScope gating is what makes
        // real page switches safe).
        verify(neg.tfA.activeFocus,
               "native limitation: hidden tfA keeps activeFocus");
        compare(f, neg.tfA, "window focus stays on the hidden field");
        compare(neg.tfA.text, "q", "hidden tfA still receives input");
        compare(neg.tfB.text, "", "tfB receives nothing");
        console.log("[neg] verdict: hidden tfA STILL received input (expected native limitation)");
    }
}
