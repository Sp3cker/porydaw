    function regionOf(testCase, image, anchor, control) {
        var origin = control.mapToItem(anchor, 0, 0)
        var scaleX = anchor.width > 0 ? image.width / anchor.width : 1
        var scaleY = anchor.height > 0 ? image.height / anchor.height : 1
        return { x0: Math.max(0, Math.round(origin.x * scaleX)),
                 y0: Math.max(0, Math.round(origin.y * scaleY)),
                 x1: Math.min(image.width - 1,
                              Math.round((origin.x + control.width) * scaleX) - 1),
                 y1: Math.min(image.height - 1,
                              Math.round((origin.y + control.height) * scaleY) - 1) }
    }

    function pixelDistance(testCase, image, x, y, target) {
        return Math.max(Math.abs(image.red(x, y) - target[0]),
                        Math.abs(image.green(x, y) - target[1]),
                        Math.abs(image.blue(x, y) - target[2]))
    }

    function colorChannels(testCase, color) {
        var hex = String(color).replace("#", "")
        if (hex.length === 8)
            hex = hex.slice(2)
        return [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16),
                parseInt(hex.slice(4, 6), 16)]
    }

    function paintedColor(testCase, image, capture, item, color) {
        var region = regionOf(testCase, image, capture, item)
        var expected = colorChannels(testCase, color)
        for (var y = region.y0; y <= region.y1; ++y) {
            for (var x = region.x0; x <= region.x1; ++x) {
                if (pixelDistance(testCase, image, x, y, expected) <= 3)
                    return true
            }
        }
        return false
    }

    function nearestPaintedColor(testCase, image, capture, item, color) {
        var region = regionOf(testCase, image, capture, item)
        var expected = colorChannels(testCase, color)
        var nearest = 255
        for (var y = region.y0; y <= region.y1; ++y) {
            for (var x = region.x0; x <= region.x1; ++x)
                nearest = Math.min(nearest, pixelDistance(testCase, image, x, y, expected))
        }
        return nearest
    }

    function compositedColor(testCase, base, overlay) {
        var color = String(overlay).replace("#", "")
        var alpha = color.length === 8 ? parseInt(color.slice(0, 2), 16) / 255 : 1
        var ink = colorChannels(testCase, overlay)
        return base.map(function(channel, index) {
            return Math.round(channel * (1 - alpha) + ink[index] * alpha)
        })
    }

    function forkStemShade(testCase, trackFill) {
        var rgb = colorChannels(testCase, trackFill).map(function(value) {
            var channel = value / 255
            return channel <= 0.04045 ? channel / 12.92
                                      : Math.pow((channel + 0.055) / 1.055, 2.4)
        })
        var l = Math.pow(0.4122214708 * rgb[0] + 0.5363325363 * rgb[1]
                         + 0.0514459929 * rgb[2], 1 / 3)
        var m = Math.pow(0.2119034982 * rgb[0] + 0.6806995451 * rgb[1]
                         + 0.1073969566 * rgb[2], 1 / 3)
        var s = Math.pow(0.0883024619 * rgb[0] + 0.2817188376 * rgb[1]
                         + 0.6299787005 * rgb[2], 1 / 3)
        var light = (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s) * 2 / 3
        var a = (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s) * 2 / 3
        var b = (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s) * 2 / 3
        var ll = light + 0.3963377774 * a + 0.2158037573 * b
        var mm = light - 0.1055613458 * a - 0.0638541728 * b
        var ss = light - 0.0894841775 * a - 1.2914855480 * b
        function gamma(value) {
            var channel = value <= 0.0031308 ? 12.92 * value
                           : 1.055 * Math.pow(Math.max(0, value), 1 / 2.4) - 0.055
            return Math.round(Math.max(0, Math.min(255, channel * 255)))
        }
        return "#" + [
            gamma(4.0767416621 * ll * ll * ll - 3.3077115913 * mm * mm * mm
                  + 0.2309699292 * ss * ss * ss),
            gamma(-1.2684380046 * ll * ll * ll + 2.6097574011 * mm * mm * mm
                  - 0.3413193965 * ss * ss * ss),
            gamma(-0.0041960863 * ll * ll * ll - 0.7034186147 * mm * mm * mm
                  + 1.7076147010 * ss * ss * ss)
        ].map(function(value) { return ("0" + value.toString(16)).slice(-2) }).join("")
    }

    function pixelsDiffer(testCase, before, after, x, y) {
        return before.red(x, y) !== after.red(x, y)
            || before.green(x, y) !== after.green(x, y)
            || before.blue(x, y) !== after.blue(x, y)
    }

    function changedPixels(testCase, before, after, region, limit) {
        var changed = 0
        var cap = limit || 1000000
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (pixelsDiffer(testCase, before, after, x, y)) {
                    if (++changed > cap)
                        return changed
                }
            }
        }
        return changed
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
        for (var i = 0; i < 30 && changedPixels(testCase, reference, frame, region, 0) <= 0; ++i) {
            testCase.wait(100)
            frame = testCase.grabImage(item)
        }
        return frame
    }

    function nodeCenter(testCase, input, tick, value, parameter) {
        var grid = testCase.gridModel()
        var font = testCase.automationModel().baseFontPx
        var radius = Math.max(font * 3 / 16 + font / 12,
                              font * 9 / 32 + font / 10)
        var padding = Math.round(radius)
        var maximum = parameter === "Tempo" ? 255 : 127
        var minimum = parameter === "Tempo" ? 20 : 0
        var x = Math.round((tick * grid.beatWidth / grid.ticksPerBeat
                            - grid.cameraScrollX) * input.Screen.devicePixelRatio)
                / input.Screen.devicePixelRatio
        var y = input.height - padding
                - (value - minimum) * (input.height - 2 * padding)
                  / (maximum - minimum)
        return { x: x, y: y, ringRadius: font * 9 / 32,
                 ringWidth: Math.max(1, font / 12) }
    }
    // Route 101's copied MIDI fixture: held CC10=48 after tick 144 and held
    // Tempo=120 BPM until the written 132 BPM event at tick 192.
    function route101Automation(parameter) {
        return parameter === "Pan"
            ? { nodeTick: 144, nodeValue: 48, heldValueAt168: 48 }
            : { nodeTick: 192, nodeValue: 132, heldValueAt168: 120 }
    }

    function physicalPoint(testCase, capture, image, input, point) {
        var scene = input.mapToItem(capture, point.x, point.y)
        return { x: Math.round(scene.x * image.width / capture.width),
                 y: Math.round(scene.y * image.height / capture.height) }
    }

    function pixelIs(testCase, image, x, y, color, tolerance) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height)
            return false
        return pixelDistance(testCase, image, x, y, colorChannels(testCase, color)) <= (tolerance || 3)
    }

    function ringQuadrants(testCase, image, capture, input, center, color) {
        var position = physicalPoint(testCase, capture, image, input, center)
        var scale = image.width / capture.width
        var radius = center.ringRadius * scale
        var width = center.ringWidth * scale
        var bits = 0
        for (var dy = -Math.ceil(radius + width); dy <= Math.ceil(radius + width); ++dy) {
            for (var dx = -Math.ceil(radius + width); dx <= Math.ceil(radius + width); ++dx) {
                var distance = Math.sqrt(dx * dx + dy * dy)
                if (distance < radius - width / 2 - 0.75
                        || distance > radius + width / 2 + 0.75)
                    continue
                if (pixelIs(testCase, image, position.x + dx, position.y + dy, color, 12))
                    bits |= 1 << ((dx >= 0 ? 1 : 0) | (dy >= 0 ? 2 : 0))
            }
        }
        return bits
    }

    function checkAutomationParameter(testCase, parameter) {
        var page = testCase.automationPageItem()
        var input = testCase.automationPlotInput()
        var model = testCase.automationModel()
        var expected = route101Automation(parameter)
        testCase.verify(page && input && model, "the automation page is mounted")
        var tab = null
        for (var i = 0; i < model.tabCount; ++i) {
            var candidate = testCase.findChild(page, "automationParameterTab" + i)
            if (candidate && candidate.text === parameter)
                tab = candidate
        }
        testCase.verify(tab, "missing parameter tab: " + parameter)
        tab.forceActiveFocus(Qt.TabFocusReason)
        testCase.mouseClick(tab, tab.width * 0.2, tab.height / 2)
        testCase.verify(testCase.waitForNative(function() { return tab.checked }, 3000),
               parameter + " activates by pointer")
        var roll = testCase.rollInput()
        testCase.mouseMove(roll, 20, 20)
        testCase.verify(testCase.waitForNative(function() { return !model.hoverVisible }, 3000),
               "no hover is published away from the plot")
        var before = testCase.revision()
        testCase.verify(before.length > 0, "the document publishes its revision")
        var capture = testCase.shell.contentItem
        var idleRegion = regionOf(testCase, testCase.grabImage(capture), capture, input)
        var idle = grabRegionStable(testCase, capture, idleRegion)

        var held = nodeCenter(testCase, input, 168, expected.heldValueAt168, parameter)
        var insertion = { x: held.x, y: input.height * 0.5 }
        testCase.mouseMove(input, insertion.x, insertion.y)
        testCase.verify(testCase.waitForNative(function() { return model.hoverVisible }, 3000),
               parameter + " publishes its insertion hover")
        var hovered = grabUntilDifferent(testCase, capture, idle, idleRegion)
        var inputRegion = regionOf(testCase, hovered, capture, input)
        testCase.verify(changedPixels(testCase, idle, hovered, inputRegion, 0) > 0,
               parameter + ": the insertion hover paints")
        var hover = testCase.findChild(page, "automationHoverGhost")
        var hoverPoint = physicalPoint(testCase, capture, hovered, input, held)
        testCase.verify(hover && hover.visible
                        && pixelIs(testCase, hovered, hoverPoint.x, hoverPoint.y, "#302c29"),
                        "the insertion ghost center paints palette primary ink")
        testCase.compare(testCase.revision(), before, parameter + ": hovering writes nothing")
        testCase.mouseMove(input, insertion.x, insertion.y)
        var repeated = grabRegionStable(testCase, capture, inputRegion)
        testCase.compare(changedPixels(testCase, hovered, repeated, inputRegion, 0), 0,
                parameter + ": the repeated hover is pixel-stable")

        testCase.mouseMove(roll, 20, 20)
        testCase.verify(testCase.waitForNative(function() { return !model.hoverVisible }, 3000),
               parameter + ": leaving the plot clears the hover")
        testCase.waitForRendering(testCase.tabsRoot())
        var cleared = grabRegionStable(testCase, capture, inputRegion)
        testCase.compare(changedPixels(testCase, idle, cleared, inputRegion, 0), 0,
                parameter + ": the cleared plot matches idle")
        testCase.compare(testCase.revision(), before, parameter + ": the hover round trip writes nothing")

        var fills = testCase.collectByName(page, "automationNodeFill", [])
        testCase.verify(fills.length > 0, parameter + ": the lane draws written nodes")
        var node = null
        for (var f = 0; f < fills.length && !node; ++f) {
            var fill = fills[f]
            if (fill.visible && fill.parent.model.tick === expected.nodeTick
                    && fill.parent.model.value === expected.nodeValue)
                node = { item: fill, at: fill.mapToItem(input, fill.width / 2, fill.height / 2) }
        }
        testCase.verify(node, "the Route 101 lane exposes its literal written node")
        var projected = nodeCenter(testCase, input, expected.nodeTick,
                                   expected.nodeValue, parameter)
        testCase.verify(Math.abs(projected.x - node.at.x) <= 1
                        && Math.abs(projected.y - node.at.y) <= 1,
                        "the written node center follows the independent tick and value projection")
        var fillPoint = physicalPoint(testCase, capture, idle, input, projected)
        testCase.verify(pixelIs(testCase, idle, fillPoint.x, fillPoint.y, "#302c29"),
                        "the written node center paints the palette primary fill")
        var ring = testCase.findChild(node.item.parent, "automationNodeHover")
        testCase.verify(ring, "the Route 101 node carries its hover ring")
        testCase.mouseMove(input, projected.x, projected.y)
        testCase.verify(testCase.waitForNative(function() {
            var rings = testCase.collectByName(testCase.automationPageItem(), "automationNodeHover", [])
            return rings.some(function(item) { return item.visible })
        }, 3000), parameter + ": the node hover ring draws")
        testCase.waitForRendering(testCase.tabsRoot())
        var ringFrame = grabUntilDifferent(testCase, capture, idle, inputRegion)
        testCase.verify(changedPixels(testCase, idle, ringFrame, inputRegion, 0) > 0,
               parameter + ": the ring paints")
        testCase.compare(ringQuadrants(testCase, ringFrame, capture, input,
                                       projected, "#b9e8ee"), 15,
                         "the written node hover paints selection-ink annulus in four quadrants")
        testCase.compare(testCase.revision(), before, parameter + ": node hovering writes nothing")
        testCase.mouseMove(roll, 20, 20)
        testCase.verify(testCase.waitForNative(function() {
            var rings = testCase.collectByName(testCase.automationPageItem(), "automationNodeHover", [])
            return !rings.some(function(item) { return item.visible })
        }, 3000), parameter + ": leaving the node clears the ring")
        testCase.waitForRendering(testCase.tabsRoot())
        var ringCleared = grabRegionStable(testCase, capture, inputRegion)
        testCase.compare(changedPixels(testCase, idle, ringCleared, inputRegion, 0), 0,
                parameter + ": the plot returns to idle")
        testCase.compare(testCase.revision(), before, parameter + ": the ring round trip writes nothing")
    }
