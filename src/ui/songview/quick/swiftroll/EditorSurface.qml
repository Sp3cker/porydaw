import QtQuick
import QtQml.Models
import Porydaw.Ui

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    required property QtObject applicationSession
    readonly property int baseFontPx: applicationSession.timeSigHost
                                      ? applicationSession.timeSigHost.baseFontPx
                                      : applicationSession.baseFontPx
    readonly property font bodyFont: Qt.font(applicationSession.timeSigHost.typographyFonts.body)
    readonly property font captionFont: Qt.font(applicationSession.timeSigHost.typographyFonts.caption)
    property var shellRouter: null
    signal contextMenuAt(real x, real y)
    readonly property int cancelReasonPointerUngrabbed: 1
    readonly property int cancelReasonHidden: 2
    readonly property var gridModel: applicationSession.gridPresenter()
    readonly property var headersModel: applicationSession.trackHeadersPresenter()
    readonly property var drawerPresenter: applicationSession.drawerPresenter()
    readonly property var velocityModel: applicationSession.velocityPage()
    property bool velocityPromptRetainingRelease: false
    readonly property var otherEventsPresenter: applicationSession.otherEventsBand()
    readonly property var pitchBendPresenter: applicationSession.pitchBendPresenter()
    readonly property var eventListPresenter: applicationSession.eventListPresenter()
    readonly property bool showEvents: applicationSession.showsEvents
    onShowEventsChanged: {
        if (!root.showEvents)
            eventPage.active = false
        if (root.eventListPresenter)
            root.eventListPresenter.setVisible(root.showEvents)
        eventListHost.visible = root.showEvents
        if (root.showEvents)
            eventPage.active = true
        else
            rollInput.forceActiveFocus(Qt.OtherFocusReason)
    }
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
    property bool menuDismissReturnsFocus: false
    property bool menuHostHeldFocus: false
    property bool insertPromptHadFocus: false
    readonly property int menuHorizontalPadding: applicationSession.timeSigHost.layoutSpaces.two
    readonly property int menuVerticalPadding: applicationSession.timeSigHost.layoutSpaces.half
    readonly property int menuGap: applicationSession.timeSigHost.layoutSpaces.one
    function retargetNoteMenu(x, y) {
        const point = rollInput.mapFromItem(null, x, y)
        return rollPlot.visible && point.x >= 0 && point.y >= 0
            && point.x < rollInput.width && point.y < rollInput.height
            && gridModel.retargetNoteMenu(point.x, point.y)
    }

    component MenuMeasure: Item {
        required property var items
        readonly property real widestText: {
            let width = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i)
                if (row && !row.separator)
                    width = Math.max(width, row.advance)
            }
            return Math.ceil(width)
        }
        readonly property real widestShortcut: {
            let width = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i)
                if (row && !row.separator && row.shortcutText)
                    width = Math.max(width, bodyFontMetrics.advanceWidth(row.shortcutText))
            }
            return Math.ceil(width)
        }
        readonly property int separatorCount: {
            let count = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i)
                if (row && row.separator)
                    ++count
            }
            return count
        }
        Instantiator {
            id: entries
            model: items
            delegate: QtObject {
                required property var model
                readonly property var itemData: model.modelData ?? model
                readonly property bool separator: itemData.separator ?? false
                readonly property string shortcutText: itemData.shortcutText ?? ""
                readonly property real advance: bodyFontMetrics.advanceWidth(itemData.text ?? "")
            }
        }
    }

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
            const wasTimeMenu = rulerMenu.menuKind === 2
            root.menuDismissReturnsFocus = true
            const openPrompt = rulerMenu.activate(actionId)
            timeSigHost.closeTimeSigMenu()
            if (openPrompt)
                timeSigHost.openTimeSigPrompt(targetTick)
            else if (wasTimeMenu && !rulerMenu.insertTimePromptOpen)
                rollInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }

    Connections {
        target: root.applicationSession
        function onTimeSigPromptOpenChanged() {
            if (!root.applicationSession.timeSigPromptOpen)
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
            if (root.rulerMenu.isOpen) {
                root.menuDismissReturnsFocus = false
                root.menuHostHeldFocus = !!(timeSigMenuLoader.item
                                             && timeSigMenuLoader.item.activeFocus)
                return
            }
            const returnFocus = root.menuDismissReturnsFocus || root.menuHostHeldFocus
            root.menuDismissReturnsFocus = false
            root.menuHostHeldFocus = false
            if (root.timeSigHost && root.timeSigHost.timeSigMenuOpen)
                root.timeSigHost.closeTimeSigMenu()
            if (root.timeMenuFocus) {
                root.timeMenuFocus = false
                if (returnFocus && !root.applicationSession.timeSigPromptOpen
                    && !root.rulerMenu.insertTimePromptOpen)
                    rollInput.forceActiveFocus(Qt.OtherFocusReason)
            } else if (returnFocus && !root.applicationSession.timeSigPromptOpen
                       && !root.rulerMenu.insertTimePromptOpen) {
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
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

    FontMetrics {
        id: bodyFontMetrics
        font: root.bodyFont
    }

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()
    onVisibleChanged: {
        // Cancellation goes through the session, which fans out to the grid,
        // headers and drawer; document-scoped presenters may already be released
        // while the surface is still being hidden.
        if (!visible && root.applicationSession)
            root.applicationSession.cancelGridInput(root.cancelReasonHidden)
        if (visible && root.showEvents && eventPage.item)
            Qt.callLater(function() {
                if (root.visible && root.showEvents && eventPage.item)
                    eventPage.item.forceActiveFocus(Qt.OtherFocusReason)
            })
    }

    Connections {
        target: root.gridModel
        function onContextMenuRequested(x, y) {
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
        height: Math.max(root.height - editorDrawer.height - otherEventsBand.height
                         - hintStatus.height - root.scrollbarBreadth, 0)
        z: 1

        TrackHeaderBand {
            id: trackHeaders
            x: 0
            y: root.gridModel.rulerHeight
            width: root.headersModel.trackHeaderWidth
            height: Math.max(parent.height - y, 0)
            onWidthChanged: root.configureViewport()
            onHeightChanged: root.configureViewport()
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
                            rulerMoves.flush()
                            if (mouse.button !== Qt.LeftButton)
                                return
                            const tick = root.timeSigHost.timeSigChipTick(mouse.x, mouse.y)
                            if (tick >= 0)
                                root.timeSigHost.openTimeSigPrompt(tick)
                        }
                        onPressed: (mouse) => {
                            rulerMoves.flush()
                            if (mouse.button === Qt.LeftButton) {
                                root.rulerMenu.beginSweep(mouse.x, mouse.y, mouse.modifiers)
                            } else if (mouse.button === Qt.RightButton) {
                                root.timeMenuFocus = false
                                root.timeSigHost.captureTimeSigMenuPress(mouse.x, mouse.y)
                            }
                        }
                        onPositionChanged: (mouse) => {
                            if (mouse.buttons & Qt.LeftButton)
                                rulerMoves.enqueue(mouse.x, mouse.y,
                                                   mouse.buttons, mouse.modifiers)
                        }
                        onReleased: (mouse) => {
                            rulerMoves.flush()
                            if (mouse.button === Qt.LeftButton) {
                                root.rulerMenu.endSweep(mouse.x, mouse.y)
                            } else if (mouse.button === Qt.RightButton) {
                                root.timeSigMenuPosition = mapToItem(root, mouse.x, mouse.y)
                                root.timeSigHost.openTimeSigMenu()
                            }
                        }
                        onCanceled: {
                            rulerMoves.flush()
                            root.rulerMenu.cancelSweep()
                        }
                        MoveCoalescer {
                            id: rulerMoves
                            dispatch: (x, y, buttons, modifiers) => {
                                root.rulerMenu.updateSweep(x, y)
                            }
                        }
                    }
                }
            }

            Item {
                id: rollGutterSide
                objectName: "timelineQuickRollGutter"
                visible: !root.showEvents
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
                visible: !root.showEvents
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
                        property bool rightSweepActive: false

                        Component.onCompleted:
                            root.gridModel.dragDistance = Qt.styleHints.startDragDistance
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
                            rollMoves.flush()
                            if (mouse.button === Qt.MiddleButton)
                                root.gridModel.beginPan(mouse.x, mouse.y)
                            else if (mouse.button === Qt.RightButton) {
                                rightSweepActive = (mouse.modifiers & Qt.ShiftModifier) !== 0
                                if (rightSweepActive) {
                                    root.rulerMenu.beginSweep(mouse.x, mouse.y, mouse.modifiers)
                                } else {
                                    root.timeSelectionMenuPosition = mapToItem(root, mouse.x, mouse.y)
                                    root.rulerMenu.openTimeSelection(mouse.x)
                                    timeMenuPressHandled = root.rulerMenu.menuKind === 2
                                    root.timeMenuFocus = timeMenuPressHandled
                                    if (!timeMenuPressHandled)
                                        root.gridModel.beginRightPointer(mouse.x, mouse.y)
                                }
                            }
                            else
                                root.gridModel.beginPointer(mouse.x, mouse.y, mouse.modifiers)
                            mouse.accepted = true
                        }
                        onDoubleClicked: function(mouse) {
                            rollMoves.flush()
                            if (mouse.button === Qt.LeftButton)
                                root.gridModel.doublePointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            rollMoves.enqueue(mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
                        }
                        onReleased: function(mouse) {
                            rollMoves.flush()
                            if (mouse.button === Qt.MiddleButton)
                                root.gridModel.endPan()
                            else if (mouse.button === Qt.RightButton) {
                                if (rightSweepActive)
                                    root.rulerMenu.endSweep(mouse.x, mouse.y)
                                else if (!timeMenuPressHandled)
                                    root.gridModel.endRightPointer(mouse.x, mouse.y)
                                rightSweepActive = false
                                timeMenuPressHandled = false
                            }
                            else
                                root.gridModel.endPointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onCanceled: {
                            rollMoves.flush()
                            timeMenuPressHandled = false
                            if (rightSweepActive)
                                root.rulerMenu.cancelSweep()
                            rightSweepActive = false
                            root.gridModel.inputCancelled(root.cancelReasonPointerUngrabbed)
                        }
                        onExited: {
                            rollMoves.flush()
                            if (pressedButtons === Qt.NoButton)
                                root.gridModel.clearKeyboardHover()
                        }
                        MoveCoalescer {
                            id: rollMoves
                            dispatch: (x, y, buttons, modifiers) => {
                                if (buttons & Qt.MiddleButton)
                                    root.gridModel.updatePan(x, y)
                                else if (buttons & Qt.RightButton) {
                                    if (rollInput.rightSweepActive)
                                        root.rulerMenu.updateSweep(x, y)
                                    else if (!rollInput.timeMenuPressHandled)
                                        root.gridModel.updateRightPointer(x, y)
                                }
                                else if (buttons & Qt.LeftButton)
                                    root.gridModel.updatePointer(x, y, modifiers)
                                else
                                    root.gridModel.updateHover(x, y)
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
                objectName: "rollContentBand"
                visible: !root.showEvents
                y: root.gridModel.rulerHeight
                width: parent.width
                height: Math.max(parent.height - y, 0)
                z: 3
            }
        }

        Item {
            id: eventListHost
            x: root.headersModel.trackHeaderWidth
            y: root.gridModel.rulerHeight
            width: Math.max(parent.width - x, 0)
            height: Math.max(parent.height - y, 0)
            z: 4
            visible: false

            Loader {
                id: eventPage
                anchors.fill: parent
                active: false
                onLoaded: {
                    if (root.eventListPresenter) {
                        root.eventListPresenter.setVisible(root.showEvents)
                    }
                    if (root.showEvents && root.visible)
                        Qt.callLater(function() {
                            if (root.showEvents && eventPage.item)
                                eventPage.item.forceActiveFocus(Qt.OtherFocusReason)
                        })
                }
                sourceComponent: Component {
                    EventListPage {
                        objectName: "eventListPage"
                        presenter: root.eventListPresenter
                    }
                }
            }
        }

        Item {
            id: rulerControls
            objectName: "timelineRulerControls"
            width: root.headersModel.trackHeaderWidth
                + root.gridModel.keyboardWidth
            height: root.gridModel.rulerHeight
            clip: true
            readonly property real controlsInset: 8
            readonly property real controlsGap: 4
            readonly property real controlsStroke:
                1 / (root.gridModel.devicePixelRatio > 0
                     ? root.gridModel.devicePixelRatio : 1)
            readonly property font controlsFont: root.bodyFont
            readonly property real gridLabelWidth:
                Math.min(gridLabel.implicitWidth,
                         Math.max(0, width - controlsInset))
            readonly property real controlWidth:
                Math.max(0, (Math.max(0, width - controlsInset
                                      - gridLabelWidth - controlsGap)
                             - controlsGap) / 2)

            component GridRowControl: Item {
                id: gridControl
                required property string controlText
                required property int menuKind
                readonly property bool controlPressed: gridArea.pressed
                activeFocusOnTab: true
                Keys.onReturnPressed: openMenu()
                Keys.onEnterPressed: openMenu()

                function openMenu() {
                    root.gridMenuPosition = mapToItem(root, width / 2, height)
                    root.gridModel.openGridMenu(menuKind)
                    Qt.callLater(function() {
                        if (gridMenuLoader.item)
                            gridMenuLoader.item.forceActiveFocus(Qt.PopupFocusReason)
                    })
                }

                Rectangle {
                    id: gridControlBackground
                    objectName: "gridControlBackground"
                    anchors.fill: parent
                    color: gridControl.controlPressed
                        ? root.gridModel.palette.buttonPressedBackground
                        : root.gridModel.palette.buttonHoverBackground
                    border.width: rulerControls.controlsStroke
                    border.color: root.gridModel.palette.outline
                }
                Text {
                    id: gridControlLabel
                    objectName: "gridControlLabel"
                    anchors.left: parent.left
                    anchors.leftMargin: rulerControls.controlsGap
                    anchors.right: gridControlArrow.left
                    anchors.rightMargin: rulerControls.controlsGap / 2
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: root.gridModel.palette.buttonText
                    font: rulerControls.controlsFont
                    text: gridControl.controlText
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    id: gridControlArrow
                    objectName: "gridControlArrow"
                    anchors.right: parent.right
                    anchors.rightMargin: rulerControls.controlsGap
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.gridModel.palette.buttonText
                    font: rulerControls.controlsFont
                    text: "▾"
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    id: gridArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: gridControl.openMenu()
                }
            }

            Text {
                id: gridLabel
                objectName: "timelineRulerGridLabel"
                x: rulerControls.controlsInset
                width: rulerControls.gridLabelWidth
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: root.gridModel.palette.primaryText
                font: rulerControls.controlsFont
                text: qsTr("Grid")
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            GridRowControl {
                objectName: "timelineRulerDivisionControl"
                x: rulerControls.controlsInset + rulerControls.gridLabelWidth
                    + rulerControls.controlsGap
                y: Math.max(0, (parent.height - height) / 2)
                width: rulerControls.controlWidth
                height: Math.min(parent.height,
                    gridLabel.implicitHeight + rulerControls.controlsInset)
                controlText: root.gridModel.gridDivisionControlText
                menuKind: 1
            }
            GridRowControl {
                objectName: "timelineRulerFeelControl"
                x: rulerControls.controlsInset + rulerControls.gridLabelWidth
                    + rulerControls.controlsGap + rulerControls.controlWidth
                    + rulerControls.controlsGap
                y: Math.max(0, (parent.height - height) / 2)
                width: rulerControls.controlWidth
                height: Math.min(parent.height,
                    gridLabel.implicitHeight + rulerControls.controlsInset)
                controlText: root.gridModel.gridFeelControlText
                menuKind: 2
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
        externalVisible: !root.showEvents
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
        Connections {
            target: root.headersModel
            function onMenuOpenChanged() {
                if (!root.headersModel.menuOpen)
                    Qt.callLater(function() {
                        if (!root.headersModel.menuOpen && root.headersModel.renamingTrack < 0
                            && trackHeaders.bandVisible)
                            trackHeaders.restoreHeaderFocus()
                    })
            }
        }
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
                MenuMeasure {
                    id: headerMeasure
                    items: root.headersModel.menuItems
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
                        hoverText: root.gridModel.palette.hoverChipText,
                        disabledText: root.gridModel.palette.disabledText,
                        font: root.bodyFont
                    })
                    rowHeight: Math.round(bodyFontMetrics.height) + 2 * root.menuVerticalPadding
                    textX: root.menuHorizontalPadding
                    textRight: menuWidth - 1 - root.menuHorizontalPadding
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + headerMeasure.widestText + root.menuHorizontalPadding)
                    menuHeight: Math.min(parent.height, 2 + rowCount * rowHeight)
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
                MenuMeasure {
                    id: gridMeasure
                    items: root.gridModel.gridMenuRows
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
                        hoverText: root.gridModel.palette.hoverChipText,
                        disabledText: root.gridModel.palette.disabledText,
                        font: root.bodyFont
                    })
                    rowHeight: Math.round(bodyFontMetrics.height) + 2 * root.menuVerticalPadding
                    checkX: root.menuHorizontalPadding
                    checkWidth: Math.floor(rowHeight / 2)
                    textX: root.menuHorizontalPadding + checkWidth + root.menuGap
                    textRight: menuWidth - 1 - root.menuHorizontalPadding
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + gridMeasure.widestText + root.menuHorizontalPadding)
                    menuHeight: Math.min(parent.height, 2 + rowCount * rowHeight)
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
                onActiveFocusChanged: {
                    if (activeFocus)
                        root.menuHostHeldFocus = true
                    else if (root.rulerMenu.isOpen)
                        root.menuHostHeldFocus = false
                }
                Keys.onEscapePressed: (event) => {
                    root.menuDismissReturnsFocus = true
                    root.timeSigHost.closeTimeSigMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        root.menuDismissReturnsFocus = true
                        root.timeSigHost.closeTimeSigMenu()
                    }
                }
                MenuMeasure {
                    id: rulerMeasure
                    items: root.rulerMenu.rows
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
                        hoverText: root.gridModel.palette.hoverChipText,
                        disabledText: root.gridModel.palette.disabledText,
                        font: root.bodyFont
                    })
                    rowHeight: Math.round(bodyFontMetrics.height) + 2 * root.menuVerticalPadding
                    separatorHeight: 1
                    textX: root.menuHorizontalPadding
                    textRight: rulerMeasure.widestShortcut > 0
                               ? menuWidth - rulerMeasure.widestShortcut
                                 - root.menuHorizontalPadding * 2
                               : menuWidth - 1 - root.menuHorizontalPadding
                    shortcutRight: rulerMeasure.widestShortcut > 0
                                   ? menuWidth - root.menuHorizontalPadding : -1
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + rulerMeasure.widestText + root.menuHorizontalPadding
                                        + (rulerMeasure.widestShortcut > 0
                                           ? rulerMeasure.widestShortcut
                                             + root.menuHorizontalPadding * 2 : 0))
                    menuHeight: Math.min(parent.height, 2
                                         + (rowCount - rulerMeasure.separatorCount) * rowHeight
                                         + rulerMeasure.separatorCount)
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
                    promptPalette: root.gridModel.palette
                }
            }
        }
    }
    Loader {
        id: velocityPromptLoader
        anchors.fill: parent
        z: 13
        active: root.velocityModel && (root.velocityModel.promptOpen
                                       || root.velocityPromptRetainingRelease)
        sourceComponent: Component {
            VelocityPrompt {
                anchors.fill: parent
                model: root.velocityModel
                promptPalette: root.gridModel.palette
                focusOrigin: rollInput
                hintService: root.hintService
                onConsumingOutsidePressChanged: {
                    root.velocityPromptRetainingRelease = consumingOutsidePress
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
                    onPressed: (mouse) => {
                        const rollPoint = rollInput.mapFromItem(root, mouse.x, mouse.y)
                        const overRoll = rollPlot.visible && rollPoint.x >= 0 && rollPoint.y >= 0
                            && rollPoint.x < rollInput.width && rollPoint.y < rollInput.height
                        const hit = overRoll && mouse.button === Qt.LeftButton
                            && root.gridModel.focusNoteUnderCursor(rollPoint.x, rollPoint.y)
                        root.pitchBendPresenter.cancelAndClose()
                        mouse.accepted = hit
                        if (hit)
                            rollInput.forceActiveFocus(Qt.MouseFocusReason)
                    }
                    onWheel: (wheel) => wheel.accepted = true
                }
                PitchBendPopup {
                    id: pitchBendPopup
                    bridge: root.pitchBendPresenter
                    fallbackFont: root.bodyFont
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
                            + bodyFontMetrics.height / 3
                        const above = root.gridModel.rulerHeight
                            + root.pitchBendPresenter.anchorY - height
                            - bodyFontMetrics.height / 3
                        return Math.max(0, Math.min(
                            below + height <= editorDrawer.y ? below : above,
                            parent.height - height))
                    }
                    Component.onCompleted: {
                        root.pitchBendPresenter.configure(
                            root.baseFontPx,
                            bodyFontMetrics.lineSpacing,
                            root.gridModel.devicePixelRatio)
                        pitchBendPopup.focusInitialGraph()
                    }
                    onFallbackFontChanged: root.pitchBendPresenter.configure(
                        root.baseFontPx,
                        bodyFontMetrics.lineSpacing,
                        root.gridModel.devicePixelRatio)
                }
                Keys.onEscapePressed: (event) => {
                    root.pitchBendPresenter.cancelAndClose()
                    rollInput.forceActiveFocus(Qt.OtherFocusReason)
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
        anchors.bottom: otherEventsBand.top
        z: 2

        applicationSession: root.applicationSession
        hintService: root.hintService
        presenter: root.drawerPresenter
        drawerPalette: root.gridModel.palette
    }
    OtherEventsBand {
        id: otherEventsBand
        objectName: "timelineOtherEventsBand"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: horizontalScrollBar.top
        z: 2
        presenter: root.otherEventsPresenter
        colors: root.gridModel.palette
        gridModel: root.gridModel
        overlayRoot: root
        timelineSplitX: root.timelineSplitX
        plotWidth: rollPlot.width
        applicationFont: root.bodyFont
        onHeightChanged: root.configureViewport()
    }


    MouseHintStatus {
        id: hintStatus
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: implicitHeight
        captionFont: root.captionFont
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
        rollBodyVisible: !root.showEvents
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
                                         root.baseFontPx, dpr)
        root.headersModel.configureViewport(
            Math.max(0, trackHeaders.width - root.headersModel.scrollbarWidth),
            trackHeaders.height, root.baseFontPx, dpr)
        // Drawer plots share the roll viewport, not the scrollbar strips;
        // the container still spans the full surface behind that chrome.
        root.drawerPresenter.configureLayout(Math.max(0, root.width - root.scrollbarBreadth),
                                             Math.max(0, root.height - hintStatus.height
                                                      - root.scrollbarBreadth - otherEventsBand.height),
                                             root.timelineSplitX,
                                             root.baseFontPx,
                                             bodyFontMetrics.lineSpacing)
        root.otherEventsPresenter.configureViewport(
            Math.max(0, rollPlot.width), root.baseFontPx,
            bodyFontMetrics.lineSpacing)
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
        if (root.eventListPresenter)
            root.eventListPresenter.setVisible(root.showEvents)
        eventListHost.visible = root.showEvents
        eventPage.active = root.showEvents
        configureViewport()
    }
    Component.onDestruction: hintService.setWindowActive(false)
}
