import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_toggleRetainsStoredHeight() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "stored-height"
        verify(LayoutSupport.attachPage(testCase, testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "activePage": "automations" })

        var presenter = testCase.presenter()
        var kind = testCase.automationKind
        var barRow = presenter.barHeight
        var stored = testCase.section(kind).bodyHeight
        var openHeight = presenter.height
        verify(stored > 0 && openHeight > barRow, "the visible section has a body")
        tryVerify(function() { return testCase.pageItem(kind) !== null }, 2000,
                  "the visible section loads its page")
        var sectionPage = testCase.pageItem(kind)

        LayoutSupport.clickToggle(testCase, kind)
        compare(testCase.section(kind).visible, false, "the click hides the section")
        compare(presenter.height, barRow, "a hidden section releases its height")
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.rollInput().height, testCase.editorHeight() - barRow - testCase.surface.gridModel.rulerHeight,
                "the roll grows by the released height")
        compare(testCase.grip(kind).visible, false, "no handle while hidden")
        compare(testCase.body(kind).visible, false, "no body while hidden")
        verify(testCase.pageItem(kind) === sectionPage, "hiding keeps the same page instance")

        LayoutSupport.clickToggle(testCase, kind)
        compare(testCase.section(kind).visible, true, "the click shows the section")
        fuzzyCompare(testCase.section(kind).bodyHeight, stored, 0.01, "the stored body height returns")
        fuzzyCompare(presenter.height, openHeight, 0.01, "the container height returns")

        // The keyboard path hides through the same transition.
        LayoutSupport.focusControl(testCase, testCase.toggle(kind))
        keyClick(Qt.Key_Return)
        compare(testCase.section(kind).visible, false, "Return hides the section")
        LayoutSupport.awaitRenderedLayout(testCase)
        compare(testCase.bar().visible, true, "the bar stays for the last hidden section")
        compare(testCase.toggle(kind).visible, true, "the toggle stays too")
        compare(testCase.grip(kind).visible, false, "no handle for the last hidden section")
        compare(testCase.body(kind).visible, false, "no body for the last hidden section")
        compare(presenter.height, barRow, "the container is the bar row")

        LayoutSupport.clickToggle(testCase, kind)
        compare(testCase.section(kind).visible, true, "the section shows again")
        LayoutSupport.awaitRenderedLayout(testCase)
        fuzzyCompare(testCase.section(kind).bodyHeight, stored, 0.01,
                     "re-showing restores the same body height")
        compare(testCase.rollInput().height, testCase.editorHeight() - openHeight - testCase.surface.gridModel.rulerHeight,
                "the roll gives the height back")
    }

    function test_resizeClampAndCancellation() {
        // This phase's own process: the production page keeps its slot in the lane's own run.
        if (testCase.productionPhase) skip("the container cases run in the lane's container child")

        var location = "resize"
        verify(LayoutSupport.attachPage(testCase, testCase.automationKind), "the automation page attaches")
        testCase.resetChrome(location, { "automationVisible": true, "activePage": "automations" })

        var presenter = testCase.presenter()
        var kind = testCase.automationKind
        var host = testCase.surface.height
        var stored = testCase.section(kind).bodyHeight
        var openHeight = presenter.height

        LayoutSupport.pressGrip(testCase, kind)
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY - 40)
        fuzzyCompare(testCase.section(kind).bodyHeight, stored + 40, 1,
                     "the drag grows the body by its delta")
        fuzzyCompare(presenter.height, openHeight + 40, 1, "the container grows with the body")
        verify(presenter.height <= testCase.editorHeight(), "the container stays above the status strip")

        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY + 600)
        var floorHeight = testCase.section(kind).bodyHeight
        verify(floorHeight > 0 && floorHeight < stored, "dragging down clamps at a positive minimum")
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY + 400)
        fuzzyCompare(testCase.section(kind).bodyHeight, floorHeight, 0.01, "the minimum is stable")
        verify(LayoutSupport.bodyInsideContainer(testCase, kind), "the body stays inside the container")
        LayoutSupport.releaseGrip(testCase, kind)

        // The grip's keyboard path reaches the same floor and steps by the
        // resize step, while the cross-axis arrows are consumed no-ops.
        LayoutSupport.focusControl(testCase, testCase.grip(kind))
        for (var i = 0; i < 24; ++i)
            keyClick(Qt.Key_Down)
        fuzzyCompare(testCase.section(kind).bodyHeight, floorHeight, 0.01,
                     "the keyboard path shares the minimum body")
        var beforeStep = testCase.section(kind).bodyHeight
        LayoutSupport.focusControl(testCase, testCase.grip(kind))
        keyClick(Qt.Key_Up)
        var step = testCase.section(kind).bodyHeight - beforeStep
        verify(step > 0, "Up grows the body by the resize step")
        keyClick(Qt.Key_Up)
        fuzzyCompare(testCase.section(kind).bodyHeight, beforeStep + 2 * step, 0.01,
                     "each press adds one resize step")
        keyClick(Qt.Key_Down)
        fuzzyCompare(testCase.section(kind).bodyHeight, beforeStep + step, 0.01,
                     "Down takes one step back")
        testCase.leftPropagations = 0
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Right)
        compare(testCase.leftPropagations, 0, "the grip consumes the cross-axis arrows")
        fuzzyCompare(testCase.section(kind).bodyHeight, beforeStep + step, 0.01,
                     "the cross-axis arrows resize nothing")

        // Dragging far up fills the host and stops there.
        LayoutSupport.pressGrip(testCase, kind)
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY - 4000)
        fuzzyCompare(presenter.height, testCase.editorHeight(), 0.01,
                     "the container clamps above the status strip")
        var ceiling = testCase.section(kind).bodyHeight
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY - 200)
        fuzzyCompare(testCase.section(kind).bodyHeight, ceiling, 0.01,
                     "the available height is stable")
        verify(LayoutSupport.bodyInsideContainer(testCase, kind), "the clamped body stays inside the container")
        LayoutSupport.releaseGrip(testCase, kind)

        // A cancelled drag keeps the height it applied and leaves no session:
        // further movement with the button still down changes nothing.
        LayoutSupport.pressGrip(testCase, kind)
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY + 25)
        var applied = testCase.section(kind).bodyHeight
        fuzzyCompare(applied, ceiling - 25, 1, "the drag applied its delta")
        presenter.inputCancelled(1)
        LayoutSupport.dragGripTo(testCase, kind, testCase.dragSceneY + 120)
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "a cancelled drag has no session left")
        LayoutSupport.releaseGrip(testCase, kind)
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "releasing after a cancellation keeps the applied height")

        LayoutSupport.awaitRenderedLayout(testCase)
        var rightStart = testCase.section(kind).bodyHeight
        var rightGrip = testCase.grip(kind)
        mousePress(rightGrip, rightGrip.width / 2, rightGrip.height / 2, Qt.RightButton)
        var rightLocal = rightGrip.mapFromItem(null, 0, testCase.dragSceneY - 40)
        mouseMove(rightGrip, rightLocal.x, rightLocal.y, Qt.RightButton)
        mouseRelease(rightGrip, rightLocal.x, rightLocal.y, Qt.RightButton)
        fuzzyCompare(testCase.section(kind).bodyHeight, rightStart, 0.01,
                     "a right-button drag on the handle resizes nothing")

        // The host shrink re-clamps the drawn body and keeps the stored height.
        testCase.surface.height = host - 250
        verify(presenter.height <= testCase.editorHeight() + 0.01,
               "the container follows the host shrink")
        verify(testCase.section(kind).bodyHeight < applied, "the shrink re-clamps the drawn body")
        testCase.surface.height = host
        fuzzyCompare(testCase.section(kind).bodyHeight, applied, 0.01,
                     "the stored height survived the host shrink")
    }
}
