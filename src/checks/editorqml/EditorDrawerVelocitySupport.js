.import "EditorDrawerLayoutSupport.js" as LayoutSupport
.import "EditorDrawerPageSupport.js" as PageSupport

    function velocityPageItem(testCase) { return testCase.pageItem(testCase.velocityKind) }

    function velocityPlot(testCase) { return testCase.findChild(velocityPageItem(testCase), "velocityPlot") }

    function velocityPlotInput(testCase) { return testCase.findChild(velocityPageItem(testCase), "velocityPlotInput") }

    function velocityRuler(testCase) { return testCase.findChild(velocityPageItem(testCase), "velocityRuler") }

    function velocityModel(testCase) { return testCase.surface.applicationSession.velocityPage() }

    function velocityPromptChild(testCase, name) {
        var item = null
        testCase.tryVerify(function() {
            item = testCase.findChild(testCase.surface, name)
            return item !== null
        }, 3000, "the mounted velocity prompt contains " + name)
        return item
    }

    /// The drawn node fills of the hosted page, in tree order.
    function velocityNodes(testCase) {
        return PageSupport.collectByName(testCase, velocityPlot(testCase), "velocityNodeFill", [])
    }

    /// The notes the production grid publishes, parsed from its own summary.
    function gridNotes(testCase) {
        return JSON.parse(testCase.surface.gridModel.noteSummary)
    }

    function primaryGridNotes(testCase) {
        return gridNotes(testCase).filter(function(note) {
            return !note.ghost && note.track === testCase.surface.gridModel.trackIndex
        })
    }

    function selectedNoteId(testCase) {
        var ids = testCase.bootstrap.velocitySelectedNoteIds()
        if (ids.length === 0 || ids.indexOf(",") >= 0)
            return -1
        return parseInt(ids, 10)
    }

    function noteVelocity(testCase, noteId) {
        var notes = primaryGridNotes(testCase)
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].id === noteId)
                return notes[i].velocity
        }
        return -1
    }

    /// A real left press/release on one drawn node, which is the page's own
    /// selection path.
    function clickNode(testCase, node) {
        var input = velocityPlotInput(testCase)
        var center = node.mapToItem(input, node.width / 2, node.height / 2)
        testCase.mouseClick(input, center.x, center.y, Qt.LeftButton)
    }

    function mountProductionVelocity(testCase, location, values) {
        testCase.verify(testCase.bootstrap.attachProductionSection(testCase.velocityKind),
               "the production Velocity page attaches to its slot")
        testCase.resetChrome(location, values)
        testCase.tryVerify(function() {
            var toggle = testCase.toggle(testCase.velocityKind)
            return toggle !== null && toggle.width > 0
        }, 2000, "the published velocity toggle is drawn for the attached page (grid "
                  + (testCase.surface.gridModel !== null)
                  + ", presenterLayout=" + testCase.presenter().barHeight
                  + ", gutter=" + testCase.presenter().plotOrigin + ")")
        if (!testCase.section(testCase.velocityKind).visible)
            LayoutSupport.clickToggle(testCase, testCase.velocityKind)
        testCase.tryVerify(function() { return testCase.section(testCase.velocityKind).visible }, 2000,
                  "the velocity section is visible")
        testCase.tryVerify(function() { return velocityPageItem(testCase) !== null }, 2000,
                  "the drawer hosts the production page item")
        testCase.tryVerify(function() {
            var page = velocityPageItem(testCase)
            return page !== null && page.width > 0 && page.height > 0
        }, 2000, "the hosted production page took its drawn body size")
        testCase.tryVerify(function() { return velocityNodes(testCase).length > 0 }, 2000,
                  "the hosted production page drew a node per published handle ("
                  + velocityNodes(testCase).length + " drawn, selected "
                  + velocityModel(testCase).selectedCount + ")")
        return velocityPageItem(testCase)
    }
