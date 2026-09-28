.import "EditorDrawerLayoutSupport.js" as LayoutSupport
.import "EditorDrawerPageSupport.js" as PageSupport

    // ---- the production Voice Changes page ----------------------------------

    function voicePageItem(testCase) { return testCase.pageItem(testCase.voiceChangesKind) }

    function voicePlot(testCase) { return testCase.findChild(voicePageItem(testCase), "voicePlot") }

    function voicePlotInput(testCase) { return testCase.findChild(voicePageItem(testCase), "voicePlotInput") }

    function voiceModel(testCase) { return testCase.surface.applicationSession.voiceChangesPage() }

    /// The drawn marker rules of the hosted page, in tree order.
    function voiceMarkerLines(testCase) {
        return PageSupport.collectByName(testCase, voicePlot(testCase), "voiceChangeMarkerLine", [])
    }

    function mountProductionVoice(testCase, location, values) {
        testCase.verify(testCase.bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the production Voice Changes page attaches to its slot")
        testCase.resetChrome(location, values)
        testCase.tryVerify(function() {
            var toggle = testCase.toggle(testCase.voiceChangesKind)
            return toggle !== null && toggle.width > 0
        }, 2000, "the published voice-changes toggle is drawn for the attached page")
        if (!testCase.section(testCase.voiceChangesKind).visible)
            LayoutSupport.clickToggle(testCase, testCase.voiceChangesKind)
        testCase.tryVerify(function() { return testCase.section(testCase.voiceChangesKind).visible }, 2000,
                  "the voice-changes section is visible")
        testCase.tryVerify(function() { return voicePageItem(testCase) !== null }, 2000,
                  "the drawer hosts the production Voice Changes page item")
        testCase.tryVerify(function() {
            var page = voicePageItem(testCase)
            return page !== null && page.width > 0 && page.height > 0
        }, 2000, "the hosted production page took its drawn body size")
        testCase.tryVerify(function() {
            return testCase.findChild(voicePageItem(testCase), "voiceReadout") !== null
        }, 2000, "the hosted production page composed its readout")
        return voicePageItem(testCase)
    }

    /// The drawn picker rows of the hosted page.
    function voicePickerRowItems(testCase) {
        return PageSupport.collectByPrefix(testCase, testCase.findChild(testCase.surface, "voicePicker"), "voicePickerRow_", [])
    }

    function insertVoiceChange(testCase, startColumn) {
        var model = voiceModel(testCase)
        var drawnBefore = voiceMarkerLines(testCase).length
        var column = startColumn ? startColumn : 24
        for (var attempt = 0; attempt < 6; ++attempt) {
            var candidate = freeVoiceColumn(testCase, column)
            if (candidate < 0)
                return null
            doubleClickPlot(testCase, candidate)
            testCase.tryVerify(function() { return model.pickerOpen }, 1000,
                      "the double-click on the empty lane opened the picker")
            if (testCase.bootstrap.voiceMarkerTicks().split(",")
                    .indexOf(String(testCase.bootstrap.voicePickerTargetTick())) >= 0) {
                model.cancelPicker()
                column = candidate + 24
                continue
            }
            awaitVoiceModal(testCase, "voicePicker", true)
            awaitVoicePickerFocus(testCase)
            var index = model.pickerIndex
            testCase.keyClick(Qt.Key_Down)
            var list = testCase.findChild(testCase.surface, "voicePickerList")
            testCase.tryVerify(function() { return list && list.activeFocus }, 1000,
                      "Down transfers search focus to the matched voice list")
            testCase.compare(model.pickerIndex, index, "focus transfer preserves the current match")
            testCase.keyClick(Qt.Key_Down)
            testCase.tryVerify(function() { return model.pickerIndex === index + 1 }, 1000,
                      "the picker moved onto another slot than the captured one")
            testCase.keyClick(Qt.Key_Return)
            testCase.tryVerify(function() { return !model.pickerOpen }, 1000, "Enter accepted the picker")
            testCase.tryVerify(function() {
                return voiceMarkerLines(testCase).length === drawnBefore + 1
            }, 1000, "the accepted picker inserted exactly one voice change")
            var drawn = voiceMarkerLines(testCase)
            var input = voicePlotInput(testCase)
            for (var i = 0; i < drawn.length; ++i) {
                if (Math.abs(drawn[i].mapToItem(input, 0, 0).x - candidate) < 14)
                    return drawn[i]
            }
            return null
        }
        return null
    }

    function freeVoiceColumn(testCase, start) {
        var lines = voiceMarkerLines(testCase)
        var input = voicePlotInput(testCase)
        var reach = 14
        for (var x = start; x < input.width - 4; x += 24) {
            var free = true
            for (var i = 0; i < lines.length; ++i) {
                if (Math.abs(lines[i].mapToItem(input, 0, 0).x - x) < reach) {
                    free = false
                    break
                }
            }
            if (free)
                return x
        }
        return -1
    }

    /// One real double-click in the page's own plot coordinates.
    function doubleClickPlot(testCase, x) {
        var input = voicePlotInput(testCase)
        testCase.mouseDoubleClickSequence(input, x, input.height / 2, Qt.LeftButton)
    }

    function awaitVoiceModal(testCase, name, expected) {
        // A kind that hosts no page, or a hosted page that composes no such modal
        // (the container cases host their own test pages), is already settled.
        testCase.tryVerify(function() {
            var item = testCase.findChild(testCase.surface, name)
            return expected ? (item !== null && item.visible === true)
                            : (item === null || item.visible === false)
        }, 1000, name + " visibility is " + expected)
        if (expected && name === "voiceChangeMenu") {
            testCase.tryVerify(function() {
                var panel = testCase.findChild(testCase.surface, "voiceMenuPanel")
                if (!panel || panel.rowCount === 0) return false
                for (var i = 0; i < panel.rowCount; ++i) {
                    var row = panel.rowItem(i)
                    if (!row || !row.visible || row.width <= 0 || row.height <= 0) return false
                }
                return true
            }, 1000, "the shared voice menu realizes its drawn rows")
        }
    }

    /// The picker's search field takes active focus one event-loop pass after it
    /// opens; a key case waits for the focus the key will be delivered to.
    function awaitVoicePickerFocus(testCase) {
        testCase.tryVerify(function() {
            var field = testCase.findChild(testCase.surface, "voicePickerSearch")
            return field !== null && field.activeFocus
        }, 1000, "the picker took focus in its search field")
    }

    /// Types one zero-padded program number into the picker's focused search
    /// field, one real key at a time.
    function typeProgram(testCase, value) {
        var text = ("000" + value).slice(-3)
        for (var i = 0; i < text.length; ++i)
            testCase.keyClick(Qt.Key_0 + parseInt(text.charAt(i), 10))
        testCase.wait(0)
    }
