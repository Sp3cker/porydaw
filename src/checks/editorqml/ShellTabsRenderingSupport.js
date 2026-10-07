    function pointFor(testCase, tabId, tick, pitch) {
        var grid = testCase.gridOf(tabId)
        var surface = testCase.surfaceOf(tabId)
        var plot = testCase.findChild(surface, "timelineQuickRollPlot")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var x = tick * pixelsPerTick - grid.cameraScrollX
        var y = (127.0 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        return plot.mapToItem(testCase.findChild(surface, "swiftRollInput"), x, y)
    }

    function drawNote(testCase, tabId) {
        var grid = testCase.gridOf(tabId)
        var input = testCase.findChild(testCase.surfaceOf(tabId), "swiftRollInput")
        var plot = testCase.findChild(testCase.surfaceOf(tabId), "timelineQuickRollPlot")
        var before = JSON.parse(testCase.summaryOf(tabId))
        var snap = grid.snapTicks
        testCase.verify(snap > 0, "tab " + tabId + " publishes its snap resolution")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var firstTick = Math.ceil(((grid.cameraScrollX + 24.0) / pixelsPerTick) / snap) * snap
        var lastTick = Math.floor(((grid.cameraScrollX + plot.width - 24.0) / pixelsPerTick) / snap) * snap
        var firstRow = Math.max(0, Math.min(127,
            Math.ceil(grid.cameraScrollY / grid.rowHeight - 0.5)))
        var lastRow = Math.max(0, Math.min(127,
            Math.floor((grid.cameraScrollY + plot.height) / grid.rowHeight - 0.5)))
        var tick = -1
        var pitch = -1
        for (var row = firstRow; row <= lastRow && tick < 0; ++row) {
            var candidatePitch = 127 - row
            for (var candidate = Math.max(0, firstTick);
                 candidate + 2 * snap <= lastTick && tick < 0; candidate += snap) {
                var end = candidate + 2 * snap
                var occupied = before.some(function(note) {
                    return note.pitch === candidatePitch
                        && note.tick < end + snap
                        && note.tick + note.duration > candidate - snap
                })
                if (!occupied) {
                    tick = candidate
                    pitch = candidatePitch
                }
            }
        }
        testCase.verify(tick >= 0, "tab " + tabId + " has a visible empty lane to draw in"
               + " (plot=" + plot.width + "x" + plot.height
               + ", snap=" + snap + ", beatWidth=" + grid.beatWidth
               + ", ticks=" + firstTick + ".." + lastTick
               + ", rows=" + firstRow + ".." + lastRow + ")")
        var inset = Math.max(1, snap / 4)
        var start = pointFor(testCase, tabId, tick + inset, pitch)
        var finish = pointFor(testCase, tabId, tick + 2 * snap - inset, pitch)
        testCase.mouseMove(input, start.x, start.y)
        testCase.mousePress(input, start.x, start.y, Qt.LeftButton)
        testCase.mouseMove(input, finish.x, finish.y, 20, Qt.LeftButton)
        testCase.mouseRelease(input, finish.x, finish.y, Qt.LeftButton)
        var drawn = null
        testCase.verify(testCase.waitForNative(function() {
            var after = JSON.parse(testCase.summaryOf(tabId))
            return after.length === before.length + 1
        }, 5000), "a real pointer drag added one note to tab " + tabId)
        var after = JSON.parse(testCase.summaryOf(tabId))
        for (var i = 0; i < after.length; ++i) {
            if (!before.some(function(note) { return note.id === after[i].id }))
                drawn = after[i]
        }
        testCase.verify(drawn, "the drawn note has a new document identity")
        return drawn
    }


    // TestCase.grabImage crops the window grab at the anchor's parent-relative
    // x/y, so a region is the control's window rect shifted by that offset.
    function regionOf(testCase, image, anchor, control) {
        var win = control.mapToItem(null, 0, 0)
        var x = win.x - anchor.x
        var y = win.y - anchor.y
        var scaleX = anchor.width > 0 ? image.width / anchor.width : 1
        var scaleY = anchor.height > 0 ? image.height / anchor.height : 1
        return { x0: Math.max(0, Math.round(x * scaleX)),
                 y0: Math.max(0, Math.round(y * scaleY)),
                 x1: Math.min(image.width - 1, Math.round((x + control.width) * scaleX) - 1),
                 y1: Math.min(image.height - 1, Math.round((y + control.height) * scaleY) - 1) }
    }

    function collectAll(testCase, prefix) {
        var collected = []
        var roots = [testCase.shell.contentItem]
        for (var i = 0; i < testCase.shell.data.length; ++i)
            roots.push(testCase.shell.data[i])
        for (var r = 0; r < roots.length; ++r)
            testCase.collectByPrefix(roots[r], prefix, collected)
        return collected
    }
    function channelsOf(testCase, color) {
        return [Math.round(color.r * 255),
                Math.round(color.g * 255),
                Math.round(color.b * 255)]
    }

    function pixelDistance(testCase, image, x, y, target) {
        return Math.max(Math.abs(image.red(x, y) - target[0]),
                        Math.abs(image.green(x, y) - target[1]),
                        Math.abs(image.blue(x, y) - target[2]))
    }

    function changedPixels(testCase, before, after, region, limit) {
        var changed = 0
        var cap = limit || 1000000
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (imagePixelDiffers(testCase, before, after, x, y)) {
                    if (++changed > cap)
                        return changed
                }
            }
        }
        return changed
    }

    function imagePixelDiffers(testCase, before, after, x, y) {
        return before.pixel(x, y) !== after.pixel(x, y)
    }

    function matchingColorCount(testCase, image, region, target, tolerance) {
        var count = 0
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (pixelDistance(testCase, image, x, y, target) <= tolerance)
                    ++count
            }
        }
        return count
    }
    function grabRegionStable(testCase, item, region) {
        var previous = testCase.grabImage(item)
        for (var i = 0; i < 20; ++i) {
            testCase.wait(100)
            var next = testCase.grabImage(item)
            if (changedPixels(testCase, previous, next, region, 0) === 0)
                return next
            previous = next
        }
        return previous
    }

    function grabUntilDifferent(testCase, item, reference, region) {
        var frame = testCase.grabImage(item)
        for (var i = 0; i < 30 && changedPixels(testCase, reference, frame, region, 16) <= 16; ++i) {
            testCase.wait(100)
            frame = testCase.grabImage(item)
        }
        return frame
    }
    function volumeAxisLabels(testCase, tabId) {
        var plot = testCase.findChild(testCase.pageOf(tabId), "automationPlot")
        if (!plot)
            return []
        var labels = []
        for (var i = 0; i < plot.children.length; ++i) {
            var item = plot.children[i]
            if (typeof item.text === "string" && item.width > 0
                    && item.x >= 0 && item.x < plot.width / 3)
                labels.push(item.text)
        }
        return labels
    }
