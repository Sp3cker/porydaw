.import "EditorDrawerLayoutSupport.js" as LayoutSupport
.import "EditorDrawerPixelSupport.js" as PixelSupport

    // ---- the shared playhead ------------------------------------------------

    // The one production presenter the session owns; the composition's playhead
    // mounts on this same object.
    function playheadPresenter(testCase) { return testCase.session.playheadPresenter() }

    function playheadClip(testCase, name) { return testCase.findChild(testCase.surface, name) }

    function playheadLine(testCase, name) {
        var clip = playheadClip(testCase, name)
        return clip ? testCase.findChild(clip, "sharedPlayheadLine") : null
    }

    function playheadSurfaceX(testCase, name) {
        var line = playheadLine(testCase, name)
        return line ? line.mapToItem(testCase.surface, line.width / 2, 0).x : -1
    }

    function playheadMatchesProjection(testCase, name, projectedX) {
        var line = playheadLine(testCase, name)
        if (!line)
            return false
        var dpr = testCase.devicePixelRatio
        var left = line.mapToItem(testCase.surface, 0, 0).x * dpr
        return Math.abs(line.width * dpr - 1) < 0.000001
            && Math.abs(left - Math.round(left)) < 0.000001
            && Math.abs(playheadSurfaceX(testCase, name) - projectedX) <= 0.5 / dpr + 0.000001
    }

    function verifyPlayheadPixels(testCase, name) {
        var line = playheadLine(testCase, name)
        testCase.verify(line && line.visible && line.width > 0 && line.height > 0)
        testCase.waitForRendering(line)
        var image = testCase.grabImage(testCase.surface)
        var region = PixelSupport.regionOf(testCase, image, testCase.surface, line)
        testCase.compare(PixelSupport.nearestPixel(testCase, image, region, PixelSupport.channelsOf(testCase, line.color)).distance,
                0, name + " draws the playhead colour at its projected position")
    }

    // Production toggle activation until the kind's body is visible.
    function showSection(testCase, kind) {
        LayoutSupport.awaitRenderedLayout(testCase)
        if (!testCase.section(kind).visible)
            LayoutSupport.clickToggle(testCase, kind)
        LayoutSupport.awaitRenderedLayout(testCase)
    }

    // One authoritative observation through the production presenter, with the
    // drawn composition given a pass to catch up.
    function presentPlayhead(testCase, sample, transport) {
        var changed = testCase.bootstrap.presentPlayheadObservation(sample, transport)
        testCase.wait(0)
        return changed
    }

    // A drawn segment's visibility follows the published one on the next pass,
    // the same lag every other drawn binding in this suite accounts for.
    function awaitPlayheadVisibility(testCase, name, expected) {
        testCase.tryVerify(function() {
            var clip = playheadClip(testCase, name)
            return clip !== null && clip.visible === expected
        }, 2000, "the " + name + " segment visibility is " + expected)
    }

    // ---- the production Velocity page ---------------------------------------

    // Every named descendant, in tree order: the page publishes one node group
    // per note, so a case never assumes document order from a single lookup.
    function collectByName(testCase, item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            collectByName(testCase, item.children[i], name, collected)
        return collected
    }

    // ---- visible text contract ------------------------------------------

    function isEffectivelyVisible(testCase, item) {
        for (var current = item; current; current = current.parent) {
            if (!current.visible)
                return false
        }
        return true
    }

    function collectVisibleTexts(testCase, item, found) {
        var collected = found || []
        if (!item || !item.children)
            return collected
        if (item.text !== undefined && item.color !== undefined && item.font !== undefined
                && item.length === undefined && isEffectivelyVisible(testCase, item))
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            collectVisibleTexts(testCase, item.children[i], collected)
        return collected
    }

    function collectAllTexts(testCase, item, found) {
        var collected = found || []
        if (!item || !item.children)
            return collected
        if (item.text !== undefined && item.color !== undefined && item.font !== undefined
                && item.length === undefined)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            collectAllTexts(testCase, item.children[i], collected)
        return collected
    }

    function auditVisibleTextInk(testCase, root, what) {
        var texts = collectVisibleTexts(testCase, root, [])
        testCase.verify(texts.length > 0, what + ": the mounted composition drew text at all")
        for (var i = 0; i < texts.length; ++i) {
            testCase.verify(texts[i].color.a > 0,
                   what + ": opaque ink for '" + texts[i].objectName + "' ('"
                   + texts[i].text + "')")
        }
        return texts
    }

    function collectByNames(testCase, item, names, found) {
        var collected = found || []
        if (!item)
            return collected
        if (names.indexOf(String(item.objectName)) >= 0)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            collectByNames(testCase, item.children[i], names, collected)
        return collected
    }

    function collectByPrefix(testCase, item, prefix, found) {
        var collected = found || []
        if (!item)
            return collected
        if (String(item.objectName).indexOf(prefix) === 0)
            collected.push(item)
        for (var i = 0; i < item.children.length; ++i)
            collectByPrefix(testCase, item.children[i], prefix, collected)
        return collected
    }
