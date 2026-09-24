import QtQuick
import Porydaw.Ui

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    required property QtObject applicationSession
    property font applicationFont: Application.font
    property var shellRouter: null
    signal contextMenuAt(real x, real y)
    property url drawerPreferenceLocation: ""
    readonly property int cancelReasonPointerUngrabbed: 1
    readonly property int cancelReasonHidden: 2
    readonly property var gridModel: applicationSession.gridPresenter()
    readonly property var headersModel: applicationSession.trackHeadersPresenter()
    readonly property var drawerPresenter: applicationSession.drawerPresenter()
    readonly property var pitchBendPresenter: applicationSession.pitchBendPresenter()
    readonly property var hintService: applicationSession.mouseHintsPresenter()
    readonly property bool hintWindowActive: visible && Window.window !== null
                                            && Window.window.visible && Window.window.active
    onHintWindowActiveChanged: hintService.setWindowActive(hintWindowActive)
    readonly property real timelineSplitX: headersModel.trackHeaderWidth + gridModel.keyboardWidth
    readonly property real scrollbarBreadth: headersModel.scrollbarWidth
    readonly property int noteCount: gridModel.renderedNoteCount
    readonly property var timeSigHost: applicationSession.timeSigHost
    property point timeSigMenuPosition: Qt.point(0, 0)
    property point gridMenuPosition: Qt.point(0, 0)
    property point headerMenuPosition: Qt.point(0, 0)
    readonly property var rulerMenu: applicationSession.rulerMenuPresenter()
    property point timeSelectionMenuPosition: Qt.point(0, 0)
    property bool timeMenuFocus: false
    property bool insertPromptHadFocus: false

    function hoverRow(panel, row) { panel.highlightedRow = row }
    function activateRow(panel, row) {
        const item = panel.rowItem(row)
        if (!item || !item.active)
            return
        const actionId = item.itemData.actionId
        if (panel.rowObjectNamePrefix === "headerMenuRow_") {
            headersModel.activateHeaderMenuAction(actionId)
        } else if (panel.rowObjectNamePrefix === "gridMenuRow_") {
            gridModel.activateGridMenuRow(actionId)
        } else if (panel.rowObjectNamePrefix === "rulerMenuRow_") {
            const targetTick = rulerMenu.targetTick()
            const openPrompt = rulerMenu.activate(actionId)
            timeSigHost.closeTimeSigMenu()
            if (openPrompt)
                timeSigHost.openTimeSigPrompt(targetTick)
        }
    }

    Connections {
        target: root.applicationSession
        function onTimeSigPromptOpenChanged() {
            if (!root.applicationSession.timeSigPromptOpen)
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
        function onTimeSigMenuOpenChanged() {
            if (!root.applicationSession.timeSigMenuOpen
                && !root.applicationSession.timeSigPromptOpen
                && (!root.rulerMenu || !root.rulerMenu.insertTimePromptOpen))
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: root.rulerMenu
        function onInsertTimePromptOpenChanged() {
            if (root.rulerMenu.insertTimePromptOpen) {
                root.insertPromptHadFocus = true
            } else if (root.insertPromptHadFocus) {
                root.insertPromptHadFocus = false
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
            }
        }
    }
    Connections {
        target: root.rulerMenu
        function onIsOpenChanged() {
            if (!root.rulerMenu.isOpen && root.timeMenuFocus
                && !root.applicationSession.timeSigPromptOpen) {
                root.timeMenuFocus = false
                rollInput.forceActiveFocus(Qt.OtherFocusReason)
            }
        }
    }
    Connections {
        target: root.gridModel
        function onGridMenuKindChanged() {
            if (root.gridModel.gridMenuKind === 0
                && !root.applicationSession.timeSigPromptOpen)
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    readonly property string appliedRevisionText: gridModel.appliedRevisionText

    // The drawer's bar row is measured in the application font, as production's
    // chromeRowHeight() measures its dock and tab rows.
    FontMetrics {
        id: applicationFontMetrics
        font: root.applicationFont
    }

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()
    onVisibleChanged: {
        // Cancellation goes through the session, which fans out to the grid,
        // headers and drawer; document-scoped presenters may already be released
        // while the surface is still being hidden.
        if (!visible && root.applicationSession)
            root.applicationSession.cancelGridInput(root.cancelReasonHidden)
    }

    Connections {
        target: root.gridModel
        function onContextMenuRequested(x, y) {
            root.applicationSession.requestGridContextMenu(x, y)
            if (root.shellRouter) {
                const position = rollInput.mapToItem(null, x, y)
                root.contextMenuAt(position.x, position.y)
            }
        }
    }

    Connections {
        target: root.headersModel
        function onContextMenuRequested(x, y) {
            root.headerMenuPosition = trackHeaders.mapToItem(root, x, y)
        }
    }

    Rectangle {
        objectName: "swiftRollBackground"
        anchors.fill: parent
        color: root.gridModel.palette.rollBackground
        z: -1
    }

    // The drawer holds the bottom of the surface, so the roll band keeps only
    // the height the drawer leaves it.
    Item {
        id: rollBandContent
        objectName: "swiftRollBand"
        width: root.width
        height: Math.max(root.height - editorDrawer.height - hintStatus.height
                         - root.scrollbarBreadth, 0)
        z: 1

        TrackHeaderBand {
            id: trackHeaders
            x: 0
            y: root.gridModel.rulerHeight
            width: root.headersModel.trackHeaderWidth
            height: Math.max(parent.height - y, 0)
            bandRect: Qt.rect(0, 0, width, height)
            bandVisible: rollBandContent.visible
            model: root.headersModel
            controlFont: Qt.font(root.headersModel.controlFont)
        }

        // The roll owns a keyboard-local coordinate space beside the headers.
        Item {
            id: rollStack
            x: root.headersModel.trackHeaderWidth
            width: Math.max(parent.width - x - root.scrollbarBreadth, 0)
            height: parent.height
            clip: true

            // The same GridScene ruler chrome, marks and chip labels as the
            // timeline canvas. Its input occupies its own top band rather
            // than letting roll gestures intercept signature-chip clicks.
            Item {
                id: rulerBand
                objectName: "timelineQuickRuler"
                width: parent.width
                height: root.gridModel.rulerHeight
                clip: true

                TimelineQuickItem {
                    objectName: "timelineQuickRulerGutterChrome"
                    width: root.gridModel.keyboardWidth
                    height: parent.height
                    rects: root.gridModel.scene.rulerGutterChrome
                }
                Item {
                    objectName: "timelineRulerDivisionControl"
                    width: root.gridModel.keyboardWidth
                    height: parent.height / 2
                    Text {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.gridModel.gridDivisionControlText
                        color: root.gridModel.palette.primaryText
                        font: Qt.font({ family: root.applicationFont.family,
                                        pixelSize: Math.round(root.gridModel.baseFontPx * 0.8),
                                        hintingPreference: Font.PreferNoHinting })
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.gridMenuPosition = mapToItem(root, width / 2, height)
                            root.gridModel.openGridMenu(1)
                        }
                    }
                }

                Item {
                    objectName: "timelineRulerFeelControl"
                    y: parent.height / 2
                    width: root.gridModel.keyboardWidth
                    height: parent.height - y
                    Text {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.gridModel.gridFeelControlText
                        color: root.gridModel.palette.primaryText
                        font: Qt.font({ family: root.applicationFont.family,
                                        pixelSize: Math.round(root.gridModel.baseFontPx * 0.8),
                                        hintingPreference: Font.PreferNoHinting })
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.gridMenuPosition = mapToItem(root, width / 2, height)
                            root.gridModel.openGridMenu(2)
                        }
                    }
                }

                Item {
                    x: root.gridModel.keyboardWidth
                    width: Math.max(parent.width - x, 0)
                    height: parent.height
                    clip: true

                    TimelineQuickItem {
                        anchors.fill: parent
                        objectName: "timelineQuickRulerChrome"
                        rects: root.gridModel.scene.rulerChrome
                    }
                    TimelineQuickItem {
                        anchors.fill: parent
                        objectName: "timelineQuickRulerMarks"
                        rects: root.gridModel.scene.rulerMarks
                    }
                    Repeater {
                        model: root.gridModel.scene.rulerTextModel
                        delegate: Text {
                            required property var labelRect
                            required property string labelText
                            required property string labelColor
                            required property var labelFont
                            x: labelRect.x
                            y: labelRect.y
                            width: labelRect.width
                            height: labelRect.height
                            color: labelColor
                            text: labelText
                            font: Qt.font(labelFont)
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                        }
                    }
                    MouseArea {
                        id: rulerInput
                        objectName: "timelineRulerInput"
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        activeFocusOnTab: true
                        onDoubleClicked: (mouse) => {
                            if (mouse.button !== Qt.LeftButton)
                                return
                            const tick = root.timeSigHost.timeSigChipTick(mouse.x)
                            if (tick >= 0)
                                root.timeSigHost.openTimeSigPrompt(tick)
                        }
                        onPressed: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                root.rulerMenu.beginSweep(mouse.x)
                            } else if (mouse.button === Qt.RightButton) {
                                root.timeSigMenuPosition = mapToItem(root, mouse.x, mouse.y)
                                root.timeMenuFocus = false
                                root.timeSigHost.openTimeSigMenu(mouse.x)
                            }
                        }
                        onPositionChanged: (mouse) => {
                            if (mouse.buttons & Qt.LeftButton)
                                root.rulerMenu.updateSweep(mouse.x)
                        }
                        onReleased: (mouse) => {
                            if (mouse.button === Qt.LeftButton)
                                root.rulerMenu.endSweep(mouse.x)
                        }
                        onCanceled: root.rulerMenu.cancelSweep()
                    }
                }
            }


            Item {
                id: rollGutterSide
                objectName: "timelineQuickRollGutter"
                y: root.gridModel.rulerHeight
                width: root.gridModel.keyboardWidth
                height: Math.max(parent.height - y, 0)
                clip: true

                MouseArea {
                    id: gutterInput
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    onPressed: function(mouse) {
                        root.gridModel.beginKeyboardPointer(mouse.y)
                        mouse.accepted = true
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            root.gridModel.updateKeyboardPointer(mouse.y)
                        else
                            root.gridModel.updateHover(mouse.x, mouse.y)
                    }
                    onReleased: function(mouse) {
                        root.gridModel.endKeyboardPointer()
                        mouse.accepted = true
                    }
                    onCanceled: root.gridModel.endKeyboardPointer()
                    onExited: {
                        if (!pressed)
                            root.gridModel.clearKeyboardHover()
                    }
                    z: 10
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        root.deliverWheel(event, true)
                    }
                }
            }

            Item {
                id: rollPlot
                objectName: "timelineQuickRollPlot"
                x: root.gridModel.keyboardWidth
                y: root.gridModel.rulerHeight
                width: Math.max(parent.width - x, 0)
                // The band carries only the height the drawer leaves, so the plot
                // and the viewport push follow the band rather than the surface.
                height: Math.max(parent.height - y, 0)
                clip: true

                onWidthChanged: root.configureViewport()
                onHeightChanged: root.configureViewport()

                Item {
                    id: pianoGridSurface
                    objectName: "pianoGridSurface"
                    anchors.fill: parent

                    PianoRollCanvas {
                        bandSide: rollContentBand
                        gutterSide: rollGutterSide
                        plotSide: pianoGridSurface
                        timelineScene: root.gridModel.scene
                    }

                    MouseArea {
                        id: rollInput
                        objectName: "swiftRollInput"
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        preventStealing: true
                        hoverEnabled: true
                        // The drawer returns focus here when no section stays visible.
                        activeFocusOnTab: true
                        property bool timeMenuPressHandled: false

                        cursorShape: {
                            switch (root.gridModel.cursorKind) {
                            case 4: return Qt.ClosedHandCursor
                            case 1: return Qt.OpenHandCursor
                            case 2:
                            case 3: return Qt.SizeHorCursor
                            default: return Qt.ArrowCursor
                            }
                        }

                        onPressed: function(mouse) {
                            if (mouse.button === Qt.MiddleButton)
                                root.gridModel.beginPan(mouse.x, mouse.y)
                            else if (mouse.button === Qt.RightButton) {
                                root.timeSelectionMenuPosition = mapToItem(root, mouse.x, mouse.y)
                                root.rulerMenu.openTimeSelection(mouse.x)
                                timeMenuPressHandled = root.rulerMenu.menuKind === 2
                                root.timeMenuFocus = timeMenuPressHandled
                                if (!timeMenuPressHandled)
                                    root.gridModel.beginRightPointer(mouse.x, mouse.y)
                            } else
                                root.gridModel.beginPointer(mouse.x, mouse.y, mouse.modifiers)
                            mouse.accepted = true
                        }
                        onDoubleClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton)
                                root.gridModel.doublePointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            if (mouse.buttons & Qt.MiddleButton)
                                root.gridModel.updatePan(mouse.x, mouse.y)
                            else if (mouse.buttons & Qt.RightButton) {
                                if (!timeMenuPressHandled)
                                    root.gridModel.updateRightPointer(mouse.x, mouse.y)
                            }
                            else if (mouse.buttons & Qt.LeftButton)
                                root.gridModel.updatePointer(mouse.x, mouse.y)
                            else {
                                root.gridModel.updateHover(mouse.x, mouse.y)
                                root.applicationSession.playheadGuidesPresenter().updateHover(mouse.x)
                            }
                        }
                        onReleased: function(mouse) {
                            if (mouse.button === Qt.MiddleButton)
                                root.gridModel.endPan()
                            else if (mouse.button === Qt.RightButton) {
                                if (!timeMenuPressHandled)
                                    root.gridModel.endRightPointer(mouse.x, mouse.y)
                                timeMenuPressHandled = false
                            }
                            else
                                root.gridModel.endPointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onCanceled: {
                            timeMenuPressHandled = false
                            root.gridModel.inputCancelled(root.cancelReasonPointerUngrabbed)
                        }
                        onExited: {
                            if (pressedButtons === Qt.NoButton) {
                                root.gridModel.clearKeyboardHover()
                                root.applicationSession.playheadGuidesPresenter().clearHover()
                            }
                        }
                    }
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        root.deliverWheel(event, false)
                    }
                }
            }
            // Keyboard labels and hover chips are band-local in GridScene.
            // Move their shared parent with the plot, not just the gutter,
            // so adding the ruler does not displace these overlays.
            Item {
                id: rollContentBand
                y: root.gridModel.rulerHeight
                width: parent.width
                height: Math.max(parent.height - y, 0)
                z: 3
            }
        }
    }

    // Keep the timeline row below the drawer; its value is owned by the Swift
    // camera and the control only requests a new scroll position.
    TimelineScrollbar {
        id: horizontalScrollBar
        objectName: "timelineHorizontalScrollBar"
        z: 2
        x: root.timelineSplitX
        y: root.height - hintStatus.height - height
        width: Math.max(root.width - x, 0)
        height: root.scrollbarBreadth
        orientation: Qt.Horizontal
        minimum: root.gridModel.cameraMinHScroll
        maximum: root.gridModel.cameraMaxHScroll
        value: root.gridModel.cameraScrollX
        pageStep: rollPlot.width
        singleStep: 1
        minimumThumbLength: root.headersModel.scrollbarMinimumThumbHeight
        accessibleName: qsTr("Timeline")
        handleColor: root.headersModel.appearance.scrollbarHandle
        handleHoverColor: root.headersModel.appearance.scrollbarHandleHover
        visibleWhenNotScrollable: true
        thumbObjectName: "timelineHorizontalScrollThumb"

        onValueRequested: (value) => root.gridModel.setCameraHScroll(value)
        onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) =>
                              root.gridModel.scrollHorizontalByWheel(
                                  pixelX, pixelY, angleX, angleY,
                                  Qt.styleHints.wheelScrollLines)
    }

    TimelineScrollbar {
        id: rollScrollBar
        objectName: "timelineRollScrollBar"
        z: 2
        x: rollStack.x + rollStack.width
        y: rollPlot.y
        width: root.scrollbarBreadth
        height: rollPlot.height
        orientation: Qt.Vertical
        minimum: 0
        maximum: root.gridModel.cameraMaxVScroll
        value: root.gridModel.cameraScrollY
        pageStep: rollPlot.height
        singleStep: 1
        minimumThumbLength: root.headersModel.scrollbarMinimumThumbHeight
        accessibleName: qsTr("Piano roll")
        handleColor: root.headersModel.appearance.scrollbarHandle
        handleHoverColor: root.headersModel.appearance.scrollbarHandleHover
        visibleWhenNotScrollable: true
        thumbObjectName: "timelineRollScrollThumb"

        onValueRequested: (value) => root.gridModel.setCameraVScroll(value)
        onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) =>
                              root.gridModel.scrollVerticalByWheel(
                                  pixelX, pixelY, angleX, angleY,
                                  Qt.styleHints.wheelScrollLines)
    }

    Loader {
        id: headerMenuLoader
        anchors.fill: parent
        z: 10
        active: root.headersModel.menuOpen
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    root.headersModel.dismissHeaderMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.headersModel.dismissHeaderMenu()
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: root
                    menuModel: root.headersModel.menuItems
                    rootLevel: true
                    rowObjectNamePrefix: "headerMenuRow_"
                    appearance: ({
                        background: root.gridModel.palette.chromeBackground,
                        outline: root.gridModel.palette.separator,
                        text: root.gridModel.palette.primaryText,
                        hoverBackground: root.gridModel.palette.hoverChipFill,
                        hoverText: root.gridModel.palette.primaryText,
                        disabledText: root.gridModel.palette.secondaryText,
                        font: Application.font
                    })
                    rowHeight: Math.round(root.gridModel.baseFontPx * 1.8)
                    textX: Math.round(root.gridModel.baseFontPx * 0.9)
                    textRight: menuWidth - textX
                    menuWidth: Math.min(parent.width, Math.round(root.gridModel.baseFontPx * 18))
                    menuHeight: Math.min(parent.height, rowCount * rowHeight + 2)
                    menuOrigin: Qt.point(
                        Math.max(0, Math.min(root.headerMenuPosition.x, width - menuWidth)),
                        Math.max(0, Math.min(root.headerMenuPosition.y, height - menuHeight)))
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: gridMenuLoader
        anchors.fill: parent
        z: 10
        active: root.gridModel.gridMenuKind !== 0
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    root.gridModel.dismissGridMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: root.gridModel.dismissGridMenu()
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: root
                    menuModel: root.gridModel.gridMenuRows
                    rootLevel: true
                    rowObjectNamePrefix: "gridMenuRow_"
                    appearance: ({
                        background: root.gridModel.palette.chromeBackground,
                        outline: root.gridModel.palette.separator,
                        text: root.gridModel.palette.primaryText,
                        hoverBackground: root.gridModel.palette.hoverChipFill,
                        hoverText: root.gridModel.palette.primaryText,
                        disabledText: root.gridModel.palette.secondaryText,
                        font: root.applicationFont
                    })
                    rowHeight: Math.round(root.gridModel.baseFontPx * 1.8)
                    checkX: Math.round(root.gridModel.baseFontPx * 0.4)
                    checkWidth: Math.round(root.gridModel.baseFontPx * 0.8)
                    textX: Math.round(root.gridModel.baseFontPx * 1.5)
                    textRight: menuWidth - Math.round(root.gridModel.baseFontPx * 0.5)
                    menuWidth: Math.min(parent.width, Math.round(root.gridModel.baseFontPx * 16))
                    menuHeight: Math.min(parent.height, rowCount * rowHeight + 2)
                    menuOrigin: Qt.point(
                        Math.max(0, Math.min(root.gridMenuPosition.x, width - menuWidth)),
                        Math.max(0, Math.min(root.gridMenuPosition.y, height - menuHeight)))
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: timeSigMenuLoader
        anchors.fill: parent
        z: 10
        active: root.rulerMenu.isOpen
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    root.timeSigHost.closeTimeSigMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.timeSigHost.closeTimeSigMenu()
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: root
                    menuModel: root.rulerMenu.rows
                    rootLevel: true
                    rowObjectNamePrefix: "rulerMenuRow_"
                    appearance: ({
                        background: root.gridModel.palette.chromeBackground,
                        outline: root.gridModel.palette.separator,
                        text: root.gridModel.palette.primaryText,
                        hoverBackground: root.gridModel.palette.hoverChipFill,
                        hoverText: root.gridModel.palette.primaryText,
                        disabledText: root.gridModel.palette.secondaryText,
                        font: Application.font
                    })
                    rowHeight: Math.round(root.gridModel.baseFontPx * 1.8)
                    separatorHeight: 1
                    textX: Math.round(root.gridModel.baseFontPx * 0.9)
                    textRight: menuWidth - Math.round(root.gridModel.baseFontPx * 0.5)
                    menuWidth: Math.min(parent.width, Math.round(root.gridModel.baseFontPx * 18))
                    menuHeight: Math.min(parent.height, rowCount * rowHeight + 2)
                    menuOrigin: Qt.point(
                        Math.max(0, Math.min(root.rulerMenu.menuKind === 2
                                             ? root.timeSelectionMenuPosition.x : root.timeSigMenuPosition.x,
                                             width - menuWidth)),
                        Math.max(0, Math.min(root.rulerMenu.menuKind === 2
                                             ? root.timeSelectionMenuPosition.y : root.timeSigMenuPosition.y,
                                             height - menuHeight)))
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: timeSigPromptLoader
        anchors.fill: parent
        z: 11
        active: root.applicationSession.timeSigPromptOpen
        sourceComponent: Component {
            Item {
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.timeSigHost.cancelTimeSigPrompt()
                }
                TimeSignaturePrompt {
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    bridge: root.timeSigHost
                }
            }
        }
    }
    Loader {
        id: insertTimePromptLoader
        anchors.fill: parent
        z: 11
        active: root.rulerMenu && root.rulerMenu.insertTimePromptOpen
        sourceComponent: Component {
            Item {
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.rulerMenu.cancelInsertTimePrompt()
                }
                InsertTimePrompt {
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    bridge: root.rulerMenu
                }
            }
        }
    }
    Loader {
        id: pitchBendPopupLoader
        anchors.fill: parent
        z: 12
        active: root.pitchBendPresenter.isOpen
        visible: active
        enabled: active
        sourceComponent: Component {
            Item {
                focus: true
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: root.pitchBendPresenter.cancelAndClose()
                    onWheel: (wheel) => wheel.accepted = true
                }
                PitchBendPopup {
                    id: pitchBendPopup
                    bridge: root.pitchBendPresenter
                    fallbackFont: root.applicationFont
                    width: implicitWidth
                    height: implicitHeight
                    x: Math.max(0, Math.min(
                        root.timelineSplitX + root.pitchBendPresenter.anchorX
                            + root.pitchBendPresenter.anchorWidth / 2 - width / 2,
                        parent.width - width))
                    y: {
                        const below = root.gridModel.rulerHeight
                            + root.pitchBendPresenter.anchorY
                            + root.pitchBendPresenter.anchorHeight
                            + applicationFontMetrics.height / 3
                        const above = root.gridModel.rulerHeight
                            + root.pitchBendPresenter.anchorY - height
                            - applicationFontMetrics.height / 3
                        return Math.max(0, Math.min(
                            below + height <= editorDrawer.y ? below : above,
                            parent.height - height))
                    }
                    Component.onCompleted: {
                        root.pitchBendPresenter.configure(
                            Math.max(root.applicationFont.pixelSize,
                                     root.gridModel.baseFontPx),
                            applicationFontMetrics.lineSpacing,
                            root.gridModel.devicePixelRatio)
                        pitchBendPopup.focusInitialGraph()
                    }
                    onFallbackFontChanged: root.pitchBendPresenter.configure(
                        Math.max(root.applicationFont.pixelSize,
                                 root.gridModel.baseFontPx),
                        applicationFontMetrics.lineSpacing,
                        root.gridModel.devicePixelRatio)
                }
                Keys.onEscapePressed: (event) => {
                    root.pitchBendPresenter.cancelAndClose()
                    event.accepted = true
                }
            }
        }
    }


    // The container owns its chrome and publishes drawer-local rectangles; the
    // composition places it at the bottom and the container sizes its own height
    // from the presenter. The container names itself.
    EditorDrawer {
        id: editorDrawer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: horizontalScrollBar.top
        z: 2

        applicationSession: root.applicationSession
        hintService: root.hintService
        presenter: root.drawerPresenter
        drawerPalette: root.gridModel.palette
        preferenceLocation: root.drawerPreferenceLocation
    }

    MouseHintStatus {
        id: hintStatus
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: implicitHeight
        applicationFont: root.applicationFont
        presenter: root.hintService
        statusPalette: root.gridModel.palette
        onHeightChanged: root.configureViewport()
    }

    // One shared playhead over the whole surface: the roll plot column and every
    // visible drawer body. It renders the presenter's published position only,
    // takes no input, and sits above the drawer so its body segments are drawn
    // over the page content they cross.
    SharedPlayhead {
        id: sharedPlayhead
        anchors.fill: parent
        z: 3

        presenter: root.applicationSession.playheadPresenter()
        guides: root.applicationSession.playheadGuidesPresenter()
        hoverGuideColor: root.gridModel.palette.secondaryText
        editGuideColor: root.gridModel.palette.editCursor
        playheadColor: root.gridModel.palette.playhead
        rollPlotRect: Qt.rect(rollStack.x + rollPlot.x, rollPlot.y,
                              rollPlot.width, rollPlot.height)
        drawerRect: Qt.rect(editorDrawer.x, editorDrawer.y,
                            editorDrawer.width, editorDrawer.height)
        velocitySection: root.drawerPresenter.velocitySection
        voiceChangesSection: root.drawerPresenter.voiceChangesSection
        automationSection: root.drawerPresenter.automationSection
    }

    function configureViewport() {
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
        root.gridModel.configureViewport(Math.max(rollPlot.width, 1.0),
                                         Math.max(rollPlot.height, 1.0),
                                         root.gridModel.baseFontPx, dpr)
        root.headersModel.configureViewport(trackHeaders.width, trackHeaders.height,
                                            root.gridModel.baseFontPx, dpr)
        // Drawer plots share the roll viewport, not the scrollbar strips;
        // the container still spans the full surface behind that chrome.
        root.drawerPresenter.configureLayout(Math.max(0, root.width - root.scrollbarBreadth),
                                             Math.max(0, root.height - hintStatus.height
                                                      - root.scrollbarBreadth),
                                             root.timelineSplitX,
                                             root.gridModel.baseFontPx,
                                             applicationFontMetrics.lineSpacing)
    }

    function deliverWheel(event, overGutter) {
        root.gridModel.handleWheel(event.angleDelta.x, event.angleDelta.y,
                                   event.pixelDelta.x, event.pixelDelta.y,
                                   event.modifiers, event.phase, overGutter,
                                   event.x, event.y)
        event.accepted = true
    }

    Component.onCompleted: {
        hintService.setWindowActive(hintWindowActive)
        configureViewport()
    }
    Component.onDestruction: hintService.setWindowActive(false)
}
