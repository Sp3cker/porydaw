import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport

// Same-frame production check: records are PD_DL_ID_NONE, so the stem is
// checked against the carrier-derived viewX oracle plus fetched==published.
EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    property var samples: []
    property var pendingFrame: null
    property int missedFrames: 0
    property var stemItem: null
    property var gridItem: null
    property var pageModel: null
    property var plotItem: null
    property double handleTick: 0

    function stemX() { return testCase.stemItem.mapToItem(testCase.plotItem, 0, 0).x }
    Connections {
        id: frameObserver
        target: null
        function onAfterAnimating() {
            if (testCase.pageModel === null || testCase.gridItem === null)
                return
            if (testCase.pageModel.displayRevision === testCase.gridItem.fetchedRevision)
                return
            if (testCase.pendingFrame !== null)
                testCase.missedFrames++
            testCase.pendingFrame = { x: testCase.stemX(),
                                      published: testCase.pageModel.displayRevision }
        }
    }

    Connections {
        id: fetchObserver
        target: null
        function onFetchedRevisionChanged() {
            if (testCase.pendingFrame === null)
                return
            testCase.samples.push({ x: testCase.pendingFrame.x,
                                    published: testCase.pendingFrame.published,
                                    fetched: testCase.gridItem.fetchedRevision,
                                    faceWidth: testCase.gridItem.face(0).width })
            testCase.pendingFrame = null
        }
    }

    function test_velocityHandlesTrackFreshGridEveryFrame() {
        if (testCase.containerPhase) skip("production composition only")
        var page = VelocitySupport.mountProductionVelocity(testCase, "velocity-same-frame")
        var plot = VelocitySupport.velocityPlot(testCase)
        var input = VelocitySupport.velocityPlotInput(testCase)
        var model = VelocitySupport.velocityModel(testCase)
        var gridModel = testCase.surface.gridModel
        var grid = testCase.findChild(plot, "velocityGridLines")
        verify(plot && input && grid, "the mounted velocity plot exposes its grid list")
        verify(grid.visible, "the grid list remains mounted")
        waitForRendering(testCase.surface)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the staged song exposes a node before the scroll")
        var stems = PageSupport.collectByName(testCase, plot, "velocityNodeStem", [])
        verify(stems.length === nodes.length, "every drawn node owns its stem")
        testCase.stemItem = stems[0]
        testCase.gridItem = grid
        testCase.pageModel = model
        testCase.plotItem = plot
        testCase.handleTick = nodes[0].parent.model.tick
        function expectedX() {
            var dpr = model.devicePixelRatio > 0 ? model.devicePixelRatio : 1
            var ppt = gridModel.beatWidth / gridModel.ticksPerBeat
            var stable = Math.round(testCase.handleTick * ppt * dpr) / dpr
            var scroll = Math.round(gridModel.cameraScrollX * dpr) / dpr
            return stable - scroll
        }

        frameObserver.target = grid.Window.window
        fetchObserver.target = grid
        gridModel.setCameraHScroll(0)
        waitForRendering(testCase.surface)
        testCase.samples = []
        testCase.pendingFrame = null
        testCase.missedFrames = 0
        var scroll0 = gridModel.cameraScrollX
        var range = Math.min(gridModel.beatWidth, gridModel.cameraMaxHScroll - scroll0)
        if (!(range >= 20))
            skip("the staged song fits without horizontal scroll")
        var stepPx = Math.max(1, Math.floor(range / 10))
        var observedX = testCase.stemX()
        var rev0 = model.displayRevision
        for (var frame = 1; frame <= 10; ++frame) {
            var before = testCase.samples.length
            var scrollBefore = gridModel.cameraScrollX
            testCase.mouseWheel(input, input.width / 2, input.height / 2,
                                0, -stepPx, Qt.NoButton, Qt.ShiftModifier)
            tryVerify(function() { return gridModel.cameraScrollX !== scrollBefore },
                      2000, "the wheel step scrolls the shared camera at step " + frame)
            waitForRendering(testCase.surface)
            compare(testCase.missedFrames, 0)
            verify(testCase.samples.length > before,
                   "frame observed at step " + frame + " scroll " + scroll0
                   + "->" + gridModel.cameraScrollX + " rev " + rev0
                   + "->" + model.displayRevision + " fetched " + grid.fetchedRevision)
            for (var index = before; index < testCase.samples.length; ++index) {
                var sample = testCase.samples[index]
                compare(sample.fetched, sample.published)
                fuzzyCompare(sample.x, expectedX(), 0.01,
                             "the stem tracks the fresh grid projection at step " + frame)
                verify(sample.faceWidth > 0, "the grid list decodes and paints at step " + frame)
            }
            verify(Math.abs(testCase.stemX() - observedX) > 0
                   || gridModel.cameraScrollX === gridModel.cameraMaxHScroll
                   || gridModel.cameraScrollX === 0,
                   "the wheel step moves the mounted handle or reaches the scroll end")
            observedX = testCase.stemX()
        }
        compare(grid.fetchedRevision, model.displayRevision)
        gridModel.setCameraHScroll(scroll0)
    }
}
