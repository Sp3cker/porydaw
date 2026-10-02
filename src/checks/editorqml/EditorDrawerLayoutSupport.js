
    function keyName(testCase, kind) {
        switch (kind) {
        case testCase.automationKind: return "automation"
        case testCase.velocityKind: return "velocity"
        case testCase.voiceChangesKind: return "voiceChanges"
        }
        return ""
    }

    function attachPage(testCase, kind) {
        return testCase.bootstrap.attachTestSection(kind, String(testCase.testPageUrl))
    }

    function observePageDestruction(testCase, item) {
        item.pageDestroyed.connect(function() { testCase.pageDestructions += 1 })
    }

    // ---- the historical store ---------------------------------------------

    function seedStore(testCase, location, values) {
        var store = testCase.bootstrap.preferences
        for (var key in values) {
            var name = "editorDrawer." + key
            if (key === "activePage")
                store.setString(name, values[key])
            else if (key.indexOf("Visible") >= 0)
                store.setBool(name, values[key])
            else
                store.setInt(name, values[key])
        }
        store.synchronize()
    }

    function snapshotStore(testCase, location) {
        var store = testCase.bootstrap.preferences
        var snapshot = {}
        for (var i = 0; i < testCase.drawerKeys.length; ++i) {
            var key = testCase.drawerKeys[i]
            var name = "editorDrawer." + key
            if (!store.hasValue(name))
                snapshot[key] = "absent"
            else if (key === "activePage")
                snapshot[key] = "string:" + store.string(name, "")
            else if (key.indexOf("Visible") >= 0)
                snapshot[key] = "boolean:" + store.bool(name, false)
            else
                snapshot[key] = "number:" + store.int(name, -1)
        }
        return snapshot
    }

    function compareSnapshots(testCase, actual, expected, message) {
        for (var i = 0; i < testCase.drawerKeys.length; ++i) {
            var key = testCase.drawerKeys[i]
            testCase.compare(actual[key], expected[key], message + " [" + key + "]")
        }
    }

    function awaitStoreKey(testCase, location, key, expected) {
        testCase.tryVerify(function() { return snapshotStore(testCase, location)[key] === expected }, 2000,
                  "the store records " + key + "=" + expected)
    }

    // ---- input -------------------------------------------------------------

    function clickToggle(testCase, kind) {
        awaitRenderedLayout(testCase)
        var control = testCase.toggle(kind)
        testCase.mouseClick(control, control.width / 2, control.height / 2, Qt.LeftButton)
    }

    function focusControl(testCase, control) {
        control.forceActiveFocus(Qt.TabFocusReason)
        testCase.tryCompare(control, "activeFocus", true, 1000, "the control holds focus")
    }

    function pressGrip(testCase, kind) {
        awaitRenderedLayout(testCase)
        var control = testCase.grip(kind)
        testCase.pressSceneY = control.mapToItem(null, 0, control.height / 2).y
        testCase.dragSceneY = testCase.pressSceneY
        testCase.mousePress(control, control.width / 2, control.height / 2, Qt.LeftButton)
    }

    function dragGripTo(testCase, kind, sceneY) {
        var control = testCase.grip(kind)
        testCase.dragSceneY = sceneY
        var local = control.mapFromItem(null, 0, sceneY)
        testCase.mouseMove(control, local.x, local.y, -1, Qt.LeftButton)
    }

    function releaseGrip(testCase, kind) {
        var control = testCase.grip(kind)
        var local = control.mapFromItem(null, 0, testCase.dragSceneY)
        testCase.mouseRelease(control, local.x, local.y, Qt.LeftButton)
    }

    function focusIsIn(testCase, item) {
        if (!item)
            return false
        var window = item.Window.window
        var focused = window ? window.activeFocusItem : null
        for (var current = focused; current; current = current.parent) {
            if (current === item)
                return true
        }
        return false
    }

    // ---- drawn rectangles --------------------------------------------------

    function awaitRenderedLayout(testCase) {
        testCase.tryVerify(function() {
            var presenter = testCase.presenter()
            var container = testCase.drawer()
            var band = testCase.rollBand()
            var bar = testCase.bar()
            var timeline = testCase.findChild(testCase.surface, "timelineHorizontalScrollBar")
            var other = testCase.findChild(testCase.surface, "timelineOtherEventsBand")
            if (!presenter || !container || !band || !bar || !timeline || !other)
                return false
            if (container.height !== presenter.height)
                return false
            var rollOrigin = band.mapToItem(testCase.surface, 0, 0)
            var drawerOrigin = container.mapToItem(testCase.surface, 0, 0)
            var timelineOrigin = timeline.mapToItem(testCase.surface, 0, 0)
            var otherOrigin = other.mapToItem(testCase.surface, 0, 0)
            if (rollOrigin.x !== 0 || rollOrigin.y !== 0
                || drawerOrigin.x !== 0
                || band.width !== testCase.surface.width
                || container.width !== testCase.surface.width
                || band.height !== drawerOrigin.y
                || drawerOrigin.y + container.height !== otherOrigin.y
                || otherOrigin.y + other.height !== timelineOrigin.y
                || other.height !== testCase.surface.otherEventsPresenter.bandHeight
                || !timeline.visible || timeline.width <= 0
                || timeline.height !== testCase.surface.headersModel.scrollbarWidth
                || timelineOrigin.y + timeline.height !== testCase.surface.height)
                return false
            if (bar.visible !== presenter.barVisible)
                return false
            return !bar.visible || (bar.x === presenter.barX && bar.y === presenter.barY
                                    && bar.width === presenter.barWidth
                                    && bar.height === presenter.barHeight)
        }, 2000, "the drawn composition catches up with the presenter")
    }

    // A drawn control sits exactly where the presenter published it, measured in
    // the container's own coordinate system.
    function verifyRect(testCase, item, x, y, width, height, what) {
        var origin = item.mapToItem(testCase.drawer(), 0, 0)
        testCase.fuzzyCompare(origin.x, x, 0.01, what + ": x")
        testCase.fuzzyCompare(origin.y, y, 0.01, what + ": y")
        testCase.fuzzyCompare(item.width, width, 0.01, what + ": width")
        testCase.fuzzyCompare(item.height, height, 0.01, what + ": height")
    }

    function renderedRect(testCase, item) {
        var origin = item.mapToItem(testCase.drawer(), 0, 0)
        return { x: origin.x, y: origin.y, width: item.width, height: item.height }
    }

    function verifySurfaceRect(testCase, item, x, y, width, height, what) {
        var origin = item.mapToItem(testCase.surface, 0, 0)
        testCase.fuzzyCompare(origin.x, x, 0.01, what + ": x")
        testCase.fuzzyCompare(origin.y, y, 0.01, what + ": y")
        testCase.fuzzyCompare(item.width, width, 0.01, what + ": width")
        testCase.fuzzyCompare(item.height, height, 0.01, what + ": height")
    }

    function bodyInsideContainer(testCase, kind) {
        var state = testCase.section(kind)
        var presenter = testCase.presenter()
        return state.bodyY + state.bodyHeight <= presenter.height - presenter.barHeight + 0.01
    }

