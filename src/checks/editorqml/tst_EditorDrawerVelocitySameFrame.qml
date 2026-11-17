import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerVelocitySupport.js" as VelocitySupport

// Same-frame production check: the fetched stem is compared with the live camera oracle.
EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    property var samples: []
    property var pendingFrame: null
    property int missedFrames: 0
    property double handleID: 0
    property var gridItem: null
    property var pageModel: null
    property double handleTick: 0

    function stemX() { return testCase.gridItem.face(testCase.handleID).x }
    function expectedX() {
        var grid = testCase.surface.gridModel
        var dpr = testCase.pageModel.devicePixelRatio
        var stable = Math.round(testCase.handleTick * grid.beatWidth / grid.ticksPerBeat * dpr) / dpr
        return stable - Math.round(grid.cameraScrollX * dpr) / dpr
    }
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
            testCase.pendingFrame = { x: testCase.expectedX(),
                                      published: testCase.pageModel.displayRevision }
        }
    }

    Connections {
        id: fetchObserver
        target: null
        function onFetchedRevisionChanged() {
            if (testCase.pendingFrame === null)
                return
            testCase.samples.push({ x: testCase.stemX(), expectedX: testCase.pendingFrame.x,
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
        gridModel.setCameraHScroll(0)
        waitForRendering(testCase.surface)
        var scroll0 = gridModel.cameraScrollX
        var range = Math.min(gridModel.beatWidth, gridModel.cameraMaxHScroll - scroll0)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the staged song exposes a node before the scroll")
        var drawing = JSON.parse(bootstrap.velocityDrawing())
        var dpr = model.devicePixelRatio
        var scroll = Math.round(gridModel.cameraScrollX * dpr) / dpr
        var stemNodes = drawing.handles.filter(function(node) {
            var left = Math.min(node.x, node.endX) - scroll
            var width = Math.max(1, Math.abs(node.endX - node.x))
            var height = Math.max(1, Math.round(model.baseFontPx * (node.selected ? 1 / 4 : 1 / 6))) / dpr
            return left < plot.width && left + width > 0
                && node.y - height / 2 < plot.height && node.y + height / 2 > 0
        })
        verify(stemNodes.length > 0 && stemNodes.every(function(node) {
            return drawing.records.some(function(record) {
                return record.id === node.noteIdText && (record.flags & 2) === 0
                    && record.w > 0 && record.h > 0
            })
        }), "every paintable node owns its actual decoded duration stem")
        if (!(range >= 20))
            skip("the staged song fits without horizontal scroll")
        var stepPx = Math.max(1, Math.floor(range / 10))
        var scrollEnd = Math.round((scroll0 + 10 * stepPx) * dpr) / dpr
        var margin = Math.max(model.baseFontPx, 1 / dpr)
        var trackedNode = stemNodes.find(function(node) {
            return node.x - scrollEnd >= margin && node.x - scroll <= plot.width - margin
        })
        verify(trackedNode !== undefined,
               "the staged song exposes a stem throughout the complete tested pan")
        testCase.handleID = Number(trackedNode.noteIdText)
        testCase.gridItem = grid
        testCase.pageModel = model
        testCase.handleTick = trackedNode.tick

        frameObserver.target = grid.Window.window
        fetchObserver.target = grid
        testCase.samples = []
        testCase.pendingFrame = null
        testCase.missedFrames = 0
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
                fuzzyCompare(sample.x, sample.expectedX, 0.01,
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
