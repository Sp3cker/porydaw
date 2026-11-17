.import "EditorDrawerLayoutSupport.js" as LayoutSupport

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

    /// Plain decoded records and interaction values; no QML delegate stand-ins.
    function decodeDrawing(json) {
        var drawing = JSON.parse(json)
        return (drawing.handles || []).map(function(handle) {
            var records = (drawing.records || []).filter(function(record) {
                return record.id === handle.noteIdText
            })
            var fillIndex = records.findIndex(function(record) {
                return (record.flags & 2) !== 0 && record.strokeWidth === 0
            })
            if (fillIndex < 0)
                return null
            handle.stem = records.find(function(record) { return (record.flags & 2) === 0 })
            handle.fill = records[fillIndex]
            handle.ring = records.slice(0, fillIndex).find(function(record) {
                return (record.flags & 2) !== 0 && record.strokeWidth > 0
            }) || null
            handle.outline = handle.selected || !handle.dimmed ? records[fillIndex + 1] : null
            handle.hover = handle.hovered && !handle.selected ? records[records.length - 1] : null
            return handle
        }).filter(function(handle) { return handle !== null })
    }

    function velocityNodes(testCase) {
        return decodeDrawing(testCase.bootstrap.velocityDrawing())
    }

    function center(handle) {
        return { x: handle.fill.x + handle.fill.w / 2, y: handle.fill.y + handle.fill.h / 2 }
    }

    function rectPoint(rect, xFraction, yFraction) {
        return { x: rect.x + rect.w * xFraction, y: rect.y + rect.h * yFraction }
    }

    function color(record) {
        return Qt.rgba((record.argb >>> 16 & 255) / 255, (record.argb >>> 8 & 255) / 255,
                       (record.argb & 255) / 255, (record.argb >>> 24) / 255)
    }

    function nearestRecordInk(testCase, image, capture, plot, record, ink) {
        var origin = plot.mapToItem(capture, record.x, record.y)
        var sx = image.width / capture.width
        var sy = image.height / capture.height
        var expected = typeof ink === "string" ? Qt.color(ink) : ink
        var nearest = 255
        for (var y = Math.max(0, Math.floor(origin.y * sy));
             y < Math.min(image.height, Math.ceil((origin.y + record.h) * sy)); ++y) {
            for (var x = Math.max(0, Math.floor(origin.x * sx));
                 x < Math.min(image.width, Math.ceil((origin.x + record.w) * sx)); ++x) {
                nearest = Math.min(nearest, Math.max(Math.abs(image.red(x, y) - expected.r * 255),
                    Math.abs(image.green(x, y) - expected.g * 255), Math.abs(image.blue(x, y) - expected.b * 255)))
            }
        }
        return nearest
    }

    /// The notes the production grid publishes, parsed from its own summary.
    function gridNotes(testCase) {
        return JSON.parse(testCase.surface.gridModel.fetchNoteSummary())
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
        var point = center(node)
        testCase.mouseClick(input, point.x, point.y, Qt.LeftButton)
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
                  "the hosted production page decoded bulk note geometry ("
                  + velocityNodes(testCase).length + " drawn, selected "
                  + velocityModel(testCase).selectedCount + ")")
        return velocityPageItem(testCase)
    }
