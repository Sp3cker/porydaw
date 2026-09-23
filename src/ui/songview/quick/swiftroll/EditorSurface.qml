import QtQuick
import ".." as Original
import "../drawer"

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
    readonly property var hintService: applicationSession.mouseHintsPresenter()
    readonly property bool hintWindowActive: visible && Window.window !== null
                                            && Window.window.visible && Window.window.active
    onHintWindowActiveChanged: hintService.setWindowActive(hintWindowActive)
    readonly property real timelineSplitX: headersModel.trackHeaderWidth + gridModel.keyboardWidth
    readonly property int noteCount: gridModel.renderedNoteCount
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
        height: Math.max(root.height - editorDrawer.height - hintStatus.height, 0)
        z: 1

        Original.TrackHeaderBand {
            id: trackHeaders
            x: 0
            width: root.headersModel.trackHeaderWidth
            height: parent.height
            bandRect: Qt.rect(0, 0, width, height)
            bandVisible: rollBandContent.visible
            model: root.headersModel
            controlFont: Qt.font(root.headersModel.controlFont)
        }

        // The roll owns a keyboard-local coordinate space beside the headers.
        Item {
            id: rollStack
            x: root.headersModel.trackHeaderWidth
            width: Math.max(parent.width - x, 0)
            height: parent.height
            clip: true

            Item {
                id: rollGutterSide
                objectName: "timelineQuickRollGutter"
                x: 0
                width: root.gridModel.keyboardWidth
                height: parent.height
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
                width: Math.max(parent.width - x, 0)
                // The band carries only the height the drawer leaves, so the plot
                // and the viewport push follow the band rather than the surface.
                height: parent.height
                clip: true

                onWidthChanged: root.configureViewport()
                onHeightChanged: root.configureViewport()

                Item {
                    id: pianoGridSurface
                    objectName: "pianoGridSurface"
                    anchors.fill: parent

                    Original.PianoRollCanvas {
                        bandSide: rollStack
                        gutterSide: rollGutterSide
                        plotSide: pianoGridSurface
                        timelineScene: root.gridModel.scene
                    }

                    MouseArea {
                        id: rollInput
                        objectName: "swiftRollInput"
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        preventStealing: true
                        hoverEnabled: true
                        // The drawer returns focus here when no section stays visible.
                        activeFocusOnTab: true

                        cursorShape: {
                            switch (root.gridModel.cursorKind) {
                            case 1: return Qt.OpenHandCursor
                            case 2:
                            case 3: return Qt.SizeHorCursor
                            default: return Qt.ArrowCursor
                            }
                        }

                        onPressed: function(mouse) {
                            if (mouse.button === Qt.RightButton)
                                root.gridModel.beginRightPointer(mouse.x, mouse.y)
                            else
                                root.gridModel.beginPointer(mouse.x, mouse.y, mouse.modifiers)
                            mouse.accepted = true
                        }
                        onDoubleClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton)
                                root.gridModel.doublePointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            if (mouse.buttons & Qt.RightButton)
                                root.gridModel.updateRightPointer(mouse.x, mouse.y)
                            else if (mouse.buttons & Qt.LeftButton)
                                root.gridModel.updatePointer(mouse.x, mouse.y)
                            else
                                root.gridModel.updateHover(mouse.x, mouse.y)
                        }
                        onReleased: function(mouse) {
                            if (mouse.button === Qt.RightButton)
                                root.gridModel.endRightPointer(mouse.x, mouse.y)
                            else
                                root.gridModel.endPointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onCanceled: root.gridModel.inputCancelled(root.cancelReasonPointerUngrabbed)
                        onExited: {
                            if (pressedButtons === Qt.NoButton)
                                root.gridModel.clearKeyboardHover()
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
        }
    }

    // The container owns its chrome and publishes drawer-local rectangles; the
    // composition places it at the bottom and the container sizes its own height
    // from the presenter. The container names itself.
    EditorDrawer {
        id: editorDrawer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hintStatus.top
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
        // Every drawer plot shares the roll's timeline split, leaving the full
        // header-plus-keyboard gutter for the automation parameter labels.
        root.drawerPresenter.configureLayout(root.width, Math.max(0, root.height - hintStatus.height),
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
