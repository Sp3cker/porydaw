import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    SignalSpy { id: projectReadySpy; signalName: "projectRootChanged" }

    function test_aProjectSwitchThenWindowCloseKeepsSongBytes() {
        var root = bootstrap.projectRoot
        var route = fileProbe.songPath(root, "mus_route101")
        var little = fileProbe.songPath(root, "mus_littleroot_test")
        compare(fileProbe.fileFingerprint(route), "471:d31e7c4a0a32a53f")
        compare(fileProbe.fileFingerprint(little), "425:c27d69bdefcd9207")
        openShell(["mus_route101", "mus_littleroot_test"])
        var tree = fileProbe.projectTreeFingerprint(root)
        verify(tree.length > 0, "A162 the staged project tree fingerprints before the switch-and-close journey")
        projectReadySpy.target = session()
        session().openProject(root)
        verify(waitForNative(function() {
            return projectReadySpy.count === 1 && session().projectOpen
                && tabs().tabCount === 0 && session().lastSaveError === ""
        }, 30000), "the project switch finishes before reopening songs")
        session().openSong("mus_route101")
        verify(waitForNative(function() { return tabs().tabCount === 1 }, 30000), "the first song reopens")
        waitForPage(tabs().selectedId)
        session().openSong("mus_littleroot_test")
        verify(waitForNative(function() { return tabs().tabCount === 2 }, 30000), "the second song reopens")
        waitForPage(tabs().selectedId)
        verify(!session().documentDirty, "the two-song close starts clean")
        var dialog = findChild(shell, "songTabCloseDialog")
        verify(dialog !== null, "the close gate is mounted")
        var promptShown = false
        var cancelled = 0
        var onVisible = function() { if (dialog.visible) promptShown = true }
        var onCancelled = function() { ++cancelled }
        dialog.visibleChanged.connect(onVisible)
        session().closeCancelled.connect(onCancelled)
        shell.close()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && !shell.visible
        }, 30000), "A108 the real window close completes and hides the window within 30 s")
        verify(!promptShown && cancelled === 0 && !shell.visible,
               "A174/A106 the clean two-song window close is accepted with no prompt and no cancellation")
        compare(fileProbe.fileFingerprint(route), "471:d31e7c4a0a32a53f",
                "A176 the window close preserves the first song's pinned MIDI bytes")
        compare(fileProbe.fileFingerprint(little), "425:c27d69bdefcd9207",
                "A177 the window close preserves the second song's pinned MIDI bytes")
        compare(fileProbe.projectTreeFingerprint(root), tree,
                "the switch-and-close journey leaves every staged project file unchanged")
        if (dialog.visibleChanged !== undefined)
            dialog.visibleChanged.disconnect(onVisible)
        if (session().closeCancelled !== undefined)
            session().closeCancelled.disconnect(onCancelled)
        projectReadySpy.target = null
    }

    function test_bDirtyWindowCloseCancelKeepsWindowOpen() {
        var id = openShell(["mus_route101"])[0]
        var path = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var before = fileProbe.fileFingerprint(path)
        verify(before.length > 0, "the dirty-close song is readable")
        drawNote(id)
        verify(session().documentDirty, "the drawn note makes the song dirty")
        var cancelled = 0
        var onCancelled = function() { ++cancelled }
        session().closeCancelled.connect(onCancelled)
        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseId === id }, 5000),
               "the dirty window close raises the tab's gate")
        verify(awaitGateButtons(), "the dirty window close raises the tab's Save/Discard/Cancel prompt")
        var cancel = dialogButton("songTabCancel")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2)
        verify(waitForNative(function() { return cancelled === 1 }, 5000), "Cancel emits the close cancellation")
        verify(shell.visible && shell.shellPresenter.sceneActive && !shell.shellPresenter.closeReady
               && tabs().tabCount === 1 && session().documentDirty,
               "Cancel keeps the window and its dirty tab open")
        compare(fileProbe.fileFingerprint(path), before, "Cancel wrote no song bytes")
        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseId === id }, 5000),
               "the dirty window close raises the gate again")
        verify(awaitGateButtons(), "the Save/Discard/Cancel prompt returns")
        var discard = dialogButton("songTabDiscard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && !shell.visible
        }, 30000), "Discard lets the window close and hide")
        compare(fileProbe.fileFingerprint(path), before, "Discard wrote no song bytes")
        if (session().closeCancelled !== undefined)
            session().closeCancelled.disconnect(onCancelled)
    }

    function test_cWindowCloseRetiresPageBeforeDocument() {
        openShell(["mus_route101", "mus_littleroot_test"])
        var active = tabs().selectedId
        fileProbe.children.push(shell.shellPresenter)
        verify(fileProbe.watchSelectedDocument(), "the selected document is observed weakly")
        verify(!fileProbe.watchedDocumentReleased(), "the selected document starts open")
        var stack = pages()
        var repeater = null
        for (var i = 0; i < stack.children.length && !repeater; ++i) {
            if (stack.children[i].itemRemoved !== undefined)
                repeater = stack.children[i]
        }
        verify(repeater !== null, "the page stack exposes its page repeater")
        var order = []
        var onRemoved = function(index, item) {
            if (!item || item.objectName !== "songTab_" + active)
                return
            repeater.itemRemoved.disconnect(onRemoved)
            if (fileProbe.watchedDocumentReleased() && order.indexOf("document") < 0)
                order.push("document")
            order.push("page")
        }
        repeater.itemRemoved.connect(onRemoved)
        shell.close()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && !shell.visible
        }, 30000), "the teardown journey's window close completes")
        verify(waitForNative(function() { return fileProbe.watchedDocumentReleased() }, 5000),
               "the selected document is released")
        if (order.indexOf("document") < 0)
            order.push("document")
        compare(order[0], "page", "A183 the closing tab's page leaves the scene before its document is released")
        compare(order[1], "document", "A184 the closing tab's document is released after its page")
        compare(order.length, 2, "A185 the page-then-document teardown reports exactly two events")
    }
}
