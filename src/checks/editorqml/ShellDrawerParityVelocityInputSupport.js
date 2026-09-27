    function mountedRawVelocityGesture(testCase, input, grid, notes) {
        var ruler = testCase.findChild(testCase.velocityPageItem(), "velocityRulerInput")
        var roll = testCase.rollInput()
        var inset = grid.baseFontPx * 0.75
        var yFor = function(value) {
            return inset + (ruler.height - 2 * inset) * (127 - value) / 126
        }
        var laterPoint = testCase.gridPointFor(notes[1].tick + notes[1].duration / 2,
                                      notes[1].pitch)
        testCase.mouseClick(roll, laterPoint.x, laterPoint.y, Qt.LeftButton,
                   Qt.ControlModifier)
        for (var index = 0; index < 2; ++index) {
            var note = notes[index]
            var point = testCase.gridPointFor(note.tick + note.duration / 2, note.pitch)
            testCase.mouseClick(roll, point.x, point.y, Qt.LeftButton)
            var value = index === 0 ? 33 : 87
            testCase.mousePress(ruler, ruler.width / 2, yFor(value), Qt.LeftButton, Qt.ControlModifier)
            testCase.mouseRelease(ruler, ruler.width / 2, yFor(value), Qt.LeftButton)
        }
        var firstPoint = testCase.gridPointFor(notes[0].tick + notes[0].duration / 2, notes[0].pitch)
        testCase.mouseClick(roll, firstPoint.x, firstPoint.y, Qt.LeftButton, Qt.ControlModifier)
        var staged = JSON.parse(grid.noteSummary)
        testCase.compare(staged.find(function(note) { return note.id === notes[0].id }).velocity, 33,
                "the mounted raw drag begins with a quiet velocity of 33")
        testCase.compare(staged.find(function(note) { return note.id === notes[1].id }).velocity, 87,
                "the mounted raw drag begins with a later velocity of 87")
        var first = testCase.velocityHandleFor(notes[0].id)
        var later = testCase.velocityHandleFor(notes[1].id)
        testCase.verify(first.selected && later.selected && first.x > 0 && first.x < input.width,
               "the mounted raw drag captures both visible note columns")
        var baseline = grid.noteSummary
        var before = Number(testCase.revision())
        var rawAtPress = Math.round(1 + (ruler.height - inset - first.y) * 126
                                    / (ruler.height - 2 * inset))
        var endY = yFor(rawAtPress + 7)
        testCase.mousePress(input, first.x, first.y, Qt.LeftButton, Qt.ControlModifier)
        testCase.mouseMove(input, first.x, endY, -1, Qt.LeftButton, Qt.NoModifier)
        testCase.verify(testCase.waitForNative(function() {
            var quiet = testCase.velocityHandleFor(notes[0].id)
            var companion = testCase.velocityHandleFor(notes[1].id)
            return quiet && companion && quiet.preview && companion.preview
        }, 3000), "the mounted raw plot routes the modifier-held press into two previews")
        testCase.compare(testCase.velocityHandleFor(notes[0].id).value, 40,
                "the mounted raw gesture previews quiet literal 40")
        testCase.compare(testCase.velocityHandleFor(notes[1].id).value, 94,
                "the mounted raw gesture previews later literal 94")
        testCase.compare(grid.noteSummary, baseline,
                "the mounted raw gesture keeps both stored velocities while held")
        testCase.compare(Number(testCase.revision()), before,
                "the mounted raw gesture stages no document revision")
        testCase.mouseRelease(input, first.x, endY, Qt.LeftButton)
        testCase.verify(testCase.waitForNative(function() {
            var current = JSON.parse(grid.noteSummary)
            return current.some(function(note) { return note.id === notes[0].id && note.velocity === 40 })
                && current.some(function(note) { return note.id === notes[1].id && note.velocity === 94 })
        }, 5000), "the mounted raw release commits exactly 40 and 94")
        testCase.compare(Number(testCase.revision()), before + 1,
                "the mounted raw release advances exactly one revision")
        testCase.compare(testCase.velocityHandleFor(notes[2].id).preview, false,
                "the mounted raw release leaves the outsider without a preview")
    }

    function mountedRawVelocityRamp(testCase, input, grid, notes) {
        var ruler = testCase.findChild(testCase.velocityPageItem(), "velocityRulerInput")
        var roll = testCase.rollInput()
        var inset = grid.baseFontPx * 0.75
        var yFor = function(value) {
            return inset + (ruler.height - 2 * inset) * (127 - value) / 126
        }
        var firstPosition = testCase.gridPointFor(notes[0].tick + notes[0].duration / 2,
                                         notes[0].pitch)
        var laterPosition = testCase.gridPointFor(notes[1].tick + notes[1].duration / 2,
                                         notes[1].pitch)
        testCase.mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        testCase.mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        var originalScroll = grid.cameraScrollY
        grid.setCameraVScroll((127 - notes[2].pitch + 0.5) * grid.rowHeight
                              - roll.height / 2)
        var midpoint = testCase.gridPointFor(notes[2].tick + notes[2].duration / 2,
                                    notes[2].pitch)
        testCase.verify(midpoint.x > 0 && midpoint.x < roll.width
               && midpoint.y > 0 && midpoint.y < roll.height,
               "the middle note is visible after the mounted roll scroll")
        testCase.mouseClick(roll, midpoint.x, midpoint.y, Qt.LeftButton)
        testCase.mousePress(ruler, ruler.width / 2, yFor(56), Qt.LeftButton, Qt.ControlModifier)
        testCase.mouseRelease(ruler, ruler.width / 2, yFor(56), Qt.LeftButton)
        grid.setCameraVScroll(originalScroll)
        testCase.mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        testCase.mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        var first = testCase.velocityHandleFor(notes[0].id)
        var middle = testCase.velocityHandleFor(notes[2].id)
        var later = testCase.velocityHandleFor(notes[1].id)
        var pressX = 2 * middle.x - later.x
        testCase.verify(first.selected && middle.selected && later.selected
               && first.x < middle.x && middle.x < later.x
               && pressX > 0 && pressX < middle.x
               && Math.abs(pressX - first.x) <= first.hitRadius,
               "the mounted raw ramp brackets the selected midpoint in distinct columns")
        var original = grid.noteSummary
        var before = Number(testCase.revision())
        testCase.mousePress(input, pressX, yFor(37), Qt.LeftButton,
                   Qt.ControlModifier | Qt.ShiftModifier)
        testCase.mouseMove(input, later.x, yFor(93), -1, Qt.LeftButton, Qt.NoModifier)
        testCase.verify(testCase.waitForNative(function() {
            var a = testCase.velocityHandleFor(notes[0].id)
            var b = testCase.velocityHandleFor(notes[2].id)
            var c = testCase.velocityHandleFor(notes[1].id)
            return a && b && c && a.preview && b.preview && c.preview
                && a.value === 37 && b.value === 65 && c.value === 93
        }, 3000), "the mounted unlocked ramp previews literal 37, 65 and 93")
        testCase.compare(grid.noteSummary, original,
                "the mounted raw ramp keeps the committed roll unchanged while held")
        testCase.compare(Number(testCase.revision()), before,
                "the mounted raw ramp defers its revision until release")
        testCase.mouseRelease(input, later.x, yFor(93), Qt.LeftButton)
        testCase.verify(testCase.waitForNative(function() {
            var current = JSON.parse(grid.noteSummary)
            return current.some(function(note) { return note.id === notes[0].id && note.velocity === 37 })
                && current.some(function(note) { return note.id === notes[2].id && note.velocity === 65 })
                && current.some(function(note) { return note.id === notes[1].id && note.velocity === 93 })
        }, 5000), "the mounted raw ramp commits literal 37, 65 and 93")
        testCase.compare(Number(testCase.revision()), before + 1,
                "the mounted raw ramp release advances one revision")
        testCase.mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        testCase.mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        grid.setCameraVScroll((127 - notes[2].pitch + 0.5) * grid.rowHeight
                              - roll.height / 2)
        midpoint = testCase.gridPointFor(notes[2].tick + notes[2].duration / 2, notes[2].pitch)
        testCase.mousePress(ruler, ruler.width / 2, yFor(104), Qt.LeftButton,
                   Qt.ControlModifier)
        testCase.mouseRelease(ruler, ruler.width / 2, yFor(104), Qt.LeftButton)
        testCase.mouseClick(roll, midpoint.x, midpoint.y, Qt.LeftButton,
                   Qt.ControlModifier)
        grid.setCameraVScroll(originalScroll)
        testCase.mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton)
        testCase.mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
    }

    function mountedVelocityRulerAndPaint(testCase, model, detent, input, grid, notes, expectedSnap) {
        var first = testCase.velocityHandleFor(notes[0].id)
        var later = testCase.velocityHandleFor(notes[1].id)
        var ruler = testCase.findChild(testCase.velocityPageItem(), "velocityRulerInput")
        testCase.verify(ruler && ruler.visible, "the mounted velocity ruler receives pointer input")
        var inset = grid.baseFontPx * 0.75
        var yFor = function(value) {
            return inset + (ruler.height - 2 * inset) * (127 - value) / 126
        }
        var rawY = yFor(73)
        testCase.verify(rawY > 0 && rawY < ruler.height,
               "raw 73 lies inside the mounted ruler")
        testCase.verify(detent.visible && detent.enabled && model.detentsAvailable,
               "every family mounts an available and enabled ruler detent control")
        testCase.compare(testCase.accessibleChecked(detent), true,
                "every family's ruler control starts checked before modifier unlock")
        var before = Number(testCase.revision())
        testCase.mousePress(ruler, ruler.width / 2, rawY, Qt.LeftButton, Qt.ControlModifier)
        testCase.tryCompare(grid, "appliedRevisionText", String(before + 1))
        var current = JSON.parse(grid.noteSummary)
        testCase.compare(current.find(function(note) { return note.id === notes[0].id }).velocity, 73,
                "the modifier-unlocked ruler writes the first selected roll note on press")
        testCase.compare(current.find(function(note) { return note.id === notes[1].id }).velocity, 73,
                "the modifier-unlocked ruler writes the later selected roll note on press")
        testCase.compare(testCase.accessibleChecked(detent), true,
                "the held unlock never unchecks the rendered detent control")
        testCase.mouseRelease(ruler, ruler.width / 2, rawY, Qt.LeftButton)
        testCase.compare(Number(testCase.revision()), before + 1,
                "the mounted ruler release writes no second revision")
        for (var locked of [true, false]) {
            first = testCase.velocityHandleFor(notes[0].id)
            later = testCase.velocityHandleFor(notes[1].id)
            if (locked) {
                testCase.verify(detent.visible, "each locked family paints with a visible detent control")
                testCase.verify(detent.enabled, "each locked family paints with an enabled detent control")
                testCase.compare(testCase.accessibleChecked(detent), true,
                        "each locked family paints with the rendered checkbox checked")
            } else {
                testCase.verify(detent.visible, "each unlocked family paints with a visible detent control")
                testCase.verify(detent.enabled, "each unlocked family paints with an enabled detent control")
                testCase.compare(testCase.accessibleChecked(detent), true,
                        "each unlocked family paints with the rendered checkbox checked")
            }
            var startY = yFor(locked ? 73 : 37)
            var endY = yFor(locked ? 73 : 91)
            var pressX = first.x - first.hitRadius * 2
            var pressY = startY + (endY - startY) * (pressX - first.x) / (later.x - first.x)
            var snapshot = grid.noteSummary
            before = Number(testCase.revision())
            testCase.mousePress(input, pressX, pressY, Qt.LeftButton,
                       locked ? Qt.NoModifier : Qt.ControlModifier)
            testCase.mouseMove(input, first.x, startY, -1, Qt.LeftButton, Qt.NoModifier)
            testCase.mouseMove(input, later.x, endY, -1, Qt.LeftButton, Qt.NoModifier)
            var expectedFirst = locked ? expectedSnap : 37
            var expectedLast = locked ? expectedSnap : 91
            testCase.verify(testCase.waitForNative(function() {
                var a = testCase.velocityHandleFor(notes[0].id)
                var b = testCase.velocityHandleFor(notes[1].id)
                return a && b && a.preview && b.preview
                    && a.value === expectedFirst && b.value === expectedLast
            }, 3000), "the mounted paint sweep previews the press-latched detent policy: "
                 + JSON.stringify({ locked: locked, press: [pressX, pressY], start: [first.x, startY],
                                    selected: model.selectedCount, size: [input.width, input.height],
                                    firstHandle: [first.y, first.hitRadius, first.selected],
                                    laterHandle: [later.y, later.selected],
                                    end: [later.x, endY], current: [
                                        testCase.velocityHandleFor(notes[0].id)
                                            ? [testCase.velocityHandleFor(notes[0].id).value,
                                               testCase.velocityHandleFor(notes[0].id).preview] : null,
                                        testCase.velocityHandleFor(notes[1].id)
                                            ? [testCase.velocityHandleFor(notes[1].id).value,
                                               testCase.velocityHandleFor(notes[1].id).preview] : null
                                    ], active: model.interactionActive }))
            testCase.compare(grid.noteSummary, snapshot,
                    "the mounted paint sweep keeps the committed roll unchanged")
            testCase.compare(Number(testCase.revision()), before,
                    "the mounted paint sweep defers its revision until release")
            testCase.mouseRelease(input, later.x, endY, Qt.LeftButton)
            testCase.verify(testCase.waitForNative(function() {
                var values = JSON.parse(grid.noteSummary)
                return values.some(function(note) {
                    return note.id === notes[0].id && note.velocity === expectedFirst
                }) && values.some(function(note) {
                    return note.id === notes[1].id && note.velocity === expectedLast
                })
            }, 5000), "the mounted paint release commits both selected values")
            testCase.compare(Number(testCase.revision()), before + 1,
                    "the mounted paint release commits one revision")
            testCase.compare(testCase.velocityHandleFor(notes[0].id).preview, false,
                    "the mounted paint release clears its first visible preview")
            testCase.compare(testCase.velocityHandleFor(notes[2].id).value, 104,
                    "the mounted paint release retains the outside note")
            testCase.compare(testCase.accessibleChecked(detent), true,
                    "the paint unlock never changes the rendered detent control")
            if (locked) {
                testCase.mouseClick(detent, detent.width / 2, detent.height / 2)
                testCase.tryVerify(function() { return !testCase.accessibleChecked(detent) })
                before = Number(testCase.revision())
                testCase.mousePress(ruler, ruler.width / 2, rawY, Qt.LeftButton)
                testCase.tryCompare(grid, "appliedRevisionText", String(before + 1))
                current = JSON.parse(grid.noteSummary)
                testCase.compare(current.find(function(note) { return note.id === notes[0].id }).velocity, 73,
                        "the disabled-detent ruler writes the first selected roll note on press")
                testCase.compare(current.find(function(note) { return note.id === notes[1].id }).velocity, 73,
                        "the disabled-detent ruler writes the later selected roll note on press")
                testCase.compare(current.find(function(note) { return note.id === notes[2].id }).velocity, 104,
                        "the disabled-detent ruler preserves the outside roll note")
                testCase.compare(testCase.accessibleChecked(detent), false,
                        "the detents-disabled ruler leaves the rendered checkbox unchecked")
                testCase.mouseRelease(ruler, ruler.width / 2, rawY, Qt.LeftButton)
                testCase.compare(Number(testCase.revision()), before + 1,
                        "the disabled-detent ruler also commits only on press")
                testCase.mouseClick(detent, detent.width / 2, detent.height / 2)
                testCase.tryVerify(function() { return testCase.accessibleChecked(detent) === true })
            }
        }
    }
