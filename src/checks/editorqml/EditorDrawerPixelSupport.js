.import "EditorDrawerLayoutSupport.js" as LayoutSupport

    // ---- rendered theme ----------------------------------------------------

    function channelsOf(testCase, color) {
        var value = parseInt(String(color).slice(-6), 16)
        return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]
    }

    // 0 = the button's own background, 1 = the pure keyboard-label tint, read
    // from the channel the two colours differ in most.
    function tintFraction(testCase, pixel, background, tint, channel) {
        return (background[channel] - pixel[channel]) / (background[channel] - tint[channel])
    }

    function widestChannel(testCase, background, tint) {
        var channel = 0
        for (var c = 1; c < 3; ++c) {
            if (Math.abs(background[c] - tint[c]) > Math.abs(background[channel] - tint[channel]))
                channel = c
        }
        return channel
    }

    function regionOf(testCase, image, anchor, control) {
        var origin = control.mapToItem(anchor, 0, 0)
        var scaleX = anchor.width > 0 ? image.width / anchor.width : 1
        var scaleY = anchor.height > 0 ? image.height / anchor.height : 1
        return { x0: Math.round(origin.x * scaleX), y0: Math.round(origin.y * scaleY),
                 x1: Math.round((origin.x + control.width) * scaleX) - 1,
                 y1: Math.round((origin.y + control.height) * scaleY) - 1 }
    }

    function interiorOf(testCase, region, control) {
        var scaleX = (control && control.width > 0)
                ? (region.x1 - region.x0 + 1) / control.width : 1
        var scaleY = (control && control.height > 0)
                ? (region.y1 - region.y0 + 1) / control.height : 1
        var ringX = Math.max(1, Math.ceil(2 * scaleX))
        var ringY = Math.max(1, Math.ceil(2 * scaleY))
        return { ringX: ringX, ringY: ringY,
                 x0: region.x0 + ringX, y0: region.y0 + ringY,
                 x1: region.x1 - ringX, y1: region.y1 - ringY,
                 usable: region.x1 - ringX >= region.x0 + ringX
                         && region.y1 - ringY >= region.y0 + ringY }
    }

    function isInterior(testCase, image, x, y, bounds) {
        return bounds.usable && x >= bounds.x0 && x <= bounds.x1
                && y >= bounds.y0 && y <= bounds.y1 && image.alpha(x, y) === 255
    }

    function nearestPixel(testCase, image, region, target) {
        var best = null
        var bestAt = "(none)"
        var bestDistance = 256
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (image.alpha(x, y) !== 255)
                    continue
                var pixel = [image.red(x, y), image.green(x, y), image.blue(x, y)]
                var distance = Math.max(Math.abs(pixel[0] - target[0]),
                                        Math.abs(pixel[1] - target[1]),
                                        Math.abs(pixel[2] - target[2]))
                if (distance < bestDistance) {
                    bestDistance = distance
                    best = pixel
                    bestAt = "(" + x + "," + y + ")"
                }
            }
        }
        return { pixel: best ? best : [0, 0, 0], at: bestAt, distance: bestDistance }
    }
    // Nearest channel distance to the target ink inside the node disc, ignoring
    // the vertical/horizontal step lines through the center and the disc edge.
    function isolatedNodeInkDistance(testCase, image, anchor, plot, x, y, radius, target) {
        var origin = plot.mapToItem(anchor, x, y)
        var sx = image.width / anchor.width
        var sy = image.height / anchor.height
        var cx = origin.x * sx
        var cy = origin.y * sy
        var outer = (radius + 1) * (sx + sy) / 2
        var line = 1.5 * (sx + sy) / 2
        var best = 256
        for (var px = Math.floor(cx - outer); px <= Math.ceil(cx + outer); ++px) {
            for (var py = Math.floor(cy - outer); py <= Math.ceil(cy + outer); ++py) {
                if (px < 0 || py < 0 || px >= image.width || py >= image.height)
                    continue
                if (image.alpha(px, py) !== 255)
                    continue
                if (Math.abs(px - cx) <= line || Math.abs(py - cy) <= line)
                    continue
                var dx = px - cx, dy = py - cy
                if (dx * dx + dy * dy > outer * outer)
                    continue
                var distance = Math.max(Math.abs(image.red(px, py) - target[0]),
                                        Math.abs(image.green(px, py) - target[1]),
                                        Math.abs(image.blue(px, py) - target[2]))
                if (distance < best)
                    best = distance
            }
        }
        return best
    }

    function renderDiagnostics(testCase, image, control, region, fill, tintMatch, background, tint) {
        if (!image || !region || !fill || !tintMatch)
            return " (no grab)"
        var bounds = interiorOf(testCase, region, control)
        return " (control " + (control ? control.width + "x" + control.height : "?")
                + ", grab " + image.width + "x" + image.height
                + ", region " + region.x0 + "," + region.y0 + " " 
                + (region.x1 - region.x0 + 1) + "x" + (region.y1 - region.y0 + 1)
                + ", blend ring " + bounds.ringX + "x" + bounds.ringY
                + ", nearest-fill " + fill.pixel.join("/") + " d=" + fill.distance + " " + fill.at
                + ", nearest-tint " + tintMatch.pixel.join("/") + " d=" + tintMatch.distance
                + " " + tintMatch.at
                + ", expected fill " + background.join("/")
                + ", expected tint " + tint.join("/") + ")"
    }

    function verifyToggleRendering(testCase, kind, background, ink, message, maxTintDistance) {
        var tintLimit = maxTintDistance === undefined ? 24 : maxTintDistance
        var control = testCase.toggle(kind)
        var anchor = testCase.surface
        var tint = channelsOf(testCase, ink)
        var base = channelsOf(testCase, background)
        var channel = widestChannel(testCase, base, tint)
        testCase.verify(Math.abs(base[channel] - tint[channel]) > 2,
               message + ": the button background and the tint must differ")
        var image = null
        var region = null
        var fill = null
        var tintMatch = null
        var waited = 0
        while (waited < 5000) {
            image = testCase.grabImage(anchor)
            region = regionOf(testCase, image, anchor, control)
            fill = nearestPixel(testCase, image, region, base)
            tintMatch = nearestPixel(testCase, image, region, tint)
            if (fill.distance <= 8 && tintMatch.distance <= tintLimit)
                break
            testCase.wait(50)
            waited += 50
        }
        testCase.verify(fill.distance <= 8 && tintMatch.distance <= tintLimit,
               message + ": the themed control rendered"
               + renderDiagnostics(testCase, image, control, region, fill, tintMatch, base, tint))
        for (var c = 0; c < 3; ++c) {
            testCase.fuzzyCompare(fill.pixel[c], base[c], 2,
                         message + ": button background channel " + c
                         + renderDiagnostics(testCase, image, control, region, fill, tintMatch,
                                                      base, tint))
            testCase.fuzzyCompare(tintMatch.pixel[c], tint[c], tintLimit,
                         message + ": glyph tint channel " + c
                         + renderDiagnostics(testCase, image, control, region, fill, tintMatch,
                                                      base, tint))
        }

        var bounds = interiorOf(testCase, region, control)
        for (var x = bounds.x0; x <= bounds.x1; ++x) {
            for (var y = bounds.y0; y <= bounds.y1; ++y) {
                if (!isInterior(testCase, image, x, y, bounds))
                    continue
                var pixel = [image.red(x, y), image.green(x, y), image.blue(x, y)]
                var fraction = tintFraction(testCase, pixel, base, tint, channel)
                testCase.verify(fraction > -0.2 && fraction < 1.2,
                       message + ": pixel " + x + "," + y + " is not a tint blend of the button"
                       + renderDiagnostics(testCase, image, control, region, fill, tintMatch,
                                                    base, tint))
                var clamped = Math.max(0, Math.min(1, fraction))
                for (var k = 0; k < 3; ++k) {
                    var blended = base[k] + (tint[k] - base[k]) * clamped
                    testCase.verify(Math.abs(blended - pixel[k]) <= 6,
                           message + ": pixel " + x + "," + y + " channel " + k + " is not a tint blend")
                }
            }
        }
    }

    function exclusionOf(testCase, image, anchor, item) {
        var region = regionOf(testCase, image, anchor, item)
        var scaleX = item.width > 0 ? (region.x1 - region.x0 + 1) / item.width : 1
        var scaleY = item.height > 0 ? (region.y1 - region.y0 + 1) / item.height : 1
        var padX = Math.max(1, Math.ceil(2 * scaleX))
        var padY = Math.max(1, Math.ceil(2 * scaleY))
        return { x0: region.x0 - padX, y0: region.y0 - padY,
                 x1: region.x1 + padX, y1: region.y1 + padY }
    }

    function barExclusions(testCase, image, anchor) {
        var exclusions = []
        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        for (var i = 0; i < kinds.length; ++i) {
            var toggle = testCase.toggle(kinds[i])
            if (!toggle || !toggle.visible || toggle.width <= 0 || toggle.height <= 0)
                continue
            exclusions.push(exclusionOf(testCase, image, anchor, toggle))
        }
        return exclusions
    }

    function nearestBarPixel(testCase, image, bounds, exclusions, target) {
        var best = [0, 0, 0]
        var bestAt = "(none)"
        var bestDistance = 256
        for (var x = bounds.x0; x <= bounds.x1; ++x) {
            for (var y = bounds.y0; y <= bounds.y1; ++y) {
                if (image.alpha(x, y) !== 255)
                    continue
                var excluded = false
                for (var e = 0; e < exclusions.length; ++e) {
                    var r = exclusions[e]
                    if (x >= r.x0 && x <= r.x1 && y >= r.y0 && y <= r.y1) {
                        excluded = true
                        break
                    }
                }
                if (excluded)
                    continue
                var pixel = [image.red(x, y), image.green(x, y), image.blue(x, y)]
                var distance = Math.max(Math.abs(pixel[0] - target[0]),
                                        Math.abs(pixel[1] - target[1]),
                                        Math.abs(pixel[2] - target[2]))
                if (distance < bestDistance) {
                    bestDistance = distance
                    best = pixel
                    bestAt = "(" + x + "," + y + ")"
                }
            }
        }
        return { pixel: best, at: bestAt, distance: bestDistance }
    }

    function verifyBarRendering(testCase, message) {
        var control = testCase.bar()
        var anchor = testCase.surface
        var fill = channelsOf(testCase, testCase.drawerPalette().chromeBackground)
        var edge = channelsOf(testCase, testCase.drawerPalette().outline)
        var separation = Math.max(Math.abs(fill[0] - edge[0]), Math.abs(fill[1] - edge[1]),
                                  Math.abs(fill[2] - edge[2]))
        testCase.verify(separation > 2, message + ": the chrome fill and the outline must differ")
        var barBox = LayoutSupport.renderedRect(testCase, control)
        var kinds = [testCase.velocityKind, testCase.voiceChangesKind, testCase.automationKind]
        for (var k = 0; k < kinds.length; ++k) {
            var grip = testCase.grip(kinds[k])
            if (grip.visible)
                testCase.verify(LayoutSupport.renderedRect(testCase, grip).y + grip.height <= barBox.y + 0.01,
                       message + ": no grip paints inside the bar")
        }
        var detent = testCase.findChild(testCase.drawer(), "drawerDetent")
        if (detent && detent.visible) {
            var detentBox = LayoutSupport.renderedRect(testCase, detent)
            testCase.verify(detentBox.y + detentBox.height <= barBox.y + 0.01
                   || detentBox.y >= barBox.y + barBox.height - 0.01,
                   message + ": the detent paints outside the bar")
        }
        var image = null
        var region = null
        var fillMatch = null
        var topMatch = null
        var bottomMatch = null
        var waited = 0
        while (waited < 5000) {
            image = testCase.grabImage(anchor)
            region = regionOf(testCase, image, anchor, control)
            var bounds = interiorOf(testCase, region, control)
            var exclusions = barExclusions(testCase, image, anchor)
            fillMatch = nearestBarPixel(testCase, image, bounds, exclusions, fill)
            topMatch = nearestBarPixel(testCase, 
                image, { x0: region.x0, y0: region.y0, x1: region.x1, y1: region.y0 + 2 },
                exclusions, edge)
            bottomMatch = nearestBarPixel(testCase, 
                image, { x0: region.x0, y0: region.y1 - 2, x1: region.x1, y1: region.y1 },
                exclusions, edge)
            if (fillMatch.distance <= 2 && topMatch.distance <= 2 && bottomMatch.distance <= 2)
                break
            testCase.wait(50)
            waited += 50
        }
        testCase.verify(fillMatch.distance <= 2,
               message + ": the bar renders its opaque chrome fill (nearest "
               + fillMatch.pixel.join("/") + " d=" + fillMatch.distance + " " + fillMatch.at
               + ", expected " + fill.join("/") + ")")
        testCase.verify(topMatch.distance <= 2,
               message + ": the bar renders its opaque outline top rim (nearest "
               + topMatch.pixel.join("/") + " d=" + topMatch.distance + " " + topMatch.at
               + ", expected " + edge.join("/") + ")")
        testCase.verify(bottomMatch.distance <= 2,
               message + ": the bar renders its opaque outline bottom rim (nearest "
               + bottomMatch.pixel.join("/") + " d=" + bottomMatch.distance + " " + bottomMatch.at
               + ", expected " + edge.join("/") + ")")
    }
