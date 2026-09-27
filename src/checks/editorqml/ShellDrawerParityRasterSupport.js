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

    function checkAutomationParameter(testCase, parameter) {
        var page = testCase.automationPageItem()
        var input = testCase.automationPlotInput()
        var model = testCase.automationModel()
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
        testCase.verify(idle.width > 0, "the idle plot composited into an image")

        var insertion = { x: input.width * 0.55, y: input.height * 0.5 }
        testCase.mouseMove(input, insertion.x, insertion.y)
        testCase.verify(testCase.waitForNative(function() { return model.hoverVisible }, 3000),
               parameter + " publishes its insertion hover")
        var hovered = grabUntilDifferent(testCase, capture, idle, idleRegion)
        var inputRegion = regionOf(testCase, hovered, capture, input)
        testCase.verify(changedPixels(testCase, idle, hovered, inputRegion, 0) > 0,
               parameter + ": the insertion hover paints")
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
            if (!fill.visible)
                continue
            var center = fill.mapToItem(input, fill.width / 2, fill.height / 2)
            if (center.x > 12 && center.y > 12
                    && center.x < input.width - 12 && center.y < input.height - 12)
                node = { item: fill, at: center }
        }
        testCase.verify(node, "the fixture exposes a written node away from plot edges")
        var ring = testCase.findChild(node.item.parent, "automationNodeHover")
        testCase.verify(ring, "the node carries its hover ring")
        var ringRegion = regionOf(testCase, idle, capture, ring)
        testCase.mouseMove(input, node.at.x, node.at.y)
        testCase.verify(testCase.waitForNative(function() {
            var rings = testCase.collectByName(testCase.automationPageItem(), "automationNodeHover", [])
            return rings.some(function(item) { return item.visible })
        }, 3000), parameter + ": the node hover ring draws")
        testCase.waitForRendering(testCase.tabsRoot())
        var ringFrame = grabUntilDifferent(testCase, capture, idle, ringRegion)
        testCase.verify(changedPixels(testCase, idle, ringFrame, ringRegion, 0) > 0,
               parameter + ": the ring paints")
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
