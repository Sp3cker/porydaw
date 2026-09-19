import QtQuick
import SwiftGrid 1.0

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    property bool centeredOnNotes: false
    // Mirrors TimelineInputCancelReason::Hidden (timelineinput.h). The host
    // names cancel reasons; QML cannot import the C++ enum.
    readonly property int cancelReasonHidden: 2

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()

    required property string documentToken
    required property int selectedTrack
    // Writable-seam bindings (spec §1–3): the band target id minted by the
    // host key router and the session feed id, both canonical decimal tokens
    // like documentToken. Empty = unbound: the Wave-3 read-only mount
    // contract holds until both arrive and gridModel.bindEditing runs, which
    // flips editingBound and clears readOnly.
    property string bandTarget: ""
    property string sessionToken: ""
    property bool editingBound: false

    readonly property QtObject gridModel: swiftGridModel
    readonly property int noteCount: swiftGridModel.renderedNoteCount
    readonly property string appliedRevisionText: swiftGridModel.appliedRevisionText

    PianoGrid {
        id: swiftGridModel
        objectName: "swiftGridModel"
        readOnly: !root.editingBound
        documentToken: root.documentToken
        documentTrack: root.selectedTrack
        onDocumentBoundChanged: root.bindEditingIfReady()
    }

    // Host recentering and scrollbar input can change the camera after the
    // initial bind. Render from those same coordinates used by band hit tests.
    // This signal also covers non-scrollbar camera changes: camera.cpp routes
    // pan/reveal/setters through sync*Camera, and time/key zoom through
    // updateScrollbars, which unconditionally notifies via both scroll setters.
    // songview.cpp's viewport/DPR changes, song rebind and state restore, plus
    // viewstate.cpp's projection recenter, use that same updateScrollbars tail.
    Connections {
        target: root.editingBound ? timelineQuickView : null
        function onScrollbarStateChanged() {
            flick.contentX = timelineQuickView.horizontalScrollValue + swiftGridModel.leadPadWidth;
            flick.contentY = timelineQuickView.verticalScrollValue;
        }
    }

    Rectangle {
        objectName: "swiftRollBackground"
        anchors.fill: parent
        color: swiftGridModel.palette.rollBackground
        z: -1
    }

    Item {
        id: rollBandContent
        y: -flick.contentY
        width: root.width
        height: Math.max(swiftGridModel.gridHeight, 1)
        z: 1

        Item {
            id: rollGutterSide
            objectName: "timelineQuickRollGutter"
            width: swiftGridModel.keyboardWidth
            height: parent.height
            clip: true
        }

        MouseArea {
            width: rollGutterSide.width
            height: parent.height
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: function (mouse) {
                swiftGridModel.hoverKeyboard(mouse.y);
            }
            onExited: function () {
                swiftGridModel.clearKeyboardHover();
            }
            z: 10
        }
    }

    Item {
        id: rollPlot
        objectName: "timelineQuickRollPlot"
        x: swiftGridModel.keyboardWidth
        width: Math.max(root.width - swiftGridModel.keyboardWidth, 0)
        height: root.height
        clip: true

        onWidthChanged: root.configureViewport()
        onHeightChanged: root.configureViewport()

        Flickable {
            id: flick
            objectName: "swiftRollViewport"
            anchors.fill: parent
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds

            contentWidth: pianoGridSurface.width
            contentHeight: pianoGridSurface.height
            onContentXChanged: {
                swiftGridModel.setViewportScrollX(contentX)
                // The band maps pointer facts through the host camera, so the
                // overlay's scroll must drive it: contentX 0 rests at the
                // camera's -leadPad floor, matching the C++ roll's home.
                if (root.editingBound)
                    timelineQuickView.setHorizontalScroll(contentX - swiftGridModel.leadPadWidth)
            }
            onContentYChanged: {
                swiftGridModel.setViewportScroll(contentY)
                if (root.editingBound)
                    timelineQuickView.setVerticalScroll(contentY)
            }

            // Unified viewing scroll: WheelHandler captures wheel/pan over the
            // visible viewport; rollInput.onWheel forwards content-area wheel events.
            WheelHandler {
                id: viewportWheel
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    var dx = event.angleDelta.x !== 0 ? event.angleDelta.x : event.pixelDelta.x;
                    var dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
                    root.scrollBy(dx, dy);
                    event.accepted = true;
                }
            }
            Item {
                id: pianoGridSurface
                objectName: "pianoGridSurface"
                width: Math.max(swiftGridModel.gridWidth, 1)
                height: Math.max(swiftGridModel.gridHeight, 1)

                onVisibleChanged: {
                    if (!visible)
                        swiftGridModel.inputCancelled(root.cancelReasonHidden);
                }

                PianoRollCanvas {
                    bandSide: rollBandContent
                    gutterSide: rollGutterSide
                    plotSide: pianoGridSurface
                    timelineScene: swiftGridModel.scene
                }

                MouseArea {
                    id: rollInput
                    objectName: "swiftRollInput"
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    preventStealing: true
                    hoverEnabled: true

                    cursorShape: {
                        switch (swiftGridModel.cursorKind) {
                        case 1:
                            return Qt.OpenHandCursor;
                        case 2:
                        case 3:
                            return Qt.SizeHorCursor;
                        default:
                            return Qt.ArrowCursor;
                        }
                    }

                    onPressed: function (mouse) {
                        mouse.accepted = true;
                    }
                    onDoubleClicked: function (mouse) {
                        mouse.accepted = true;
                    }
                    onPositionChanged: function (mouse) {
                        swiftGridModel.hoverPointer(mouse.x, mouse.y);
                    }
                    onReleased: function (mouse) {
                        mouse.accepted = true;
                    }
                    onCanceled: function () {
                    }
                    onWheel: function (e) {
                        var dx = e.angleDelta.x !== 0 ? e.angleDelta.x : e.pixelDelta.x;
                        var dy = e.angleDelta.y !== 0 ? e.angleDelta.y : e.pixelDelta.y;
                        root.scrollBy(dx, dy);
                        e.accepted = true;
                    }
                }
            }
        }
    }

    function configureViewport() {
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0;
        swiftGridModel.configureViewport(swiftGridModel.baseFontPx, dpr, Math.max(rollPlot.width, 1.0), Math.max(rollPlot.height, 1.0));
        if (rollPlot.height > 1 && !root.centeredOnNotes) {
            flick.contentY = swiftGridModel.initialScrollY;
            root.centeredOnNotes = true;
        }
    }
    function scrollBy(dx, dy) {
        var maxX = Math.max(0, flick.contentWidth - flick.width);
        var maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - dx));
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy));
    }


    // Binds the writable seams once both host ids are present (initial
    // properties or late sets): the sgs_ session receiver and the sgb_ band
    // surface through gridModel.bindEditing, then clears readOnly via
    // editingBound. Idempotent; bindEditing traps on malformed tokens, so
    // the flag flips only after a successful bind.
    function bindEditingIfReady() {
        if (root.editingBound || root.bandTarget === "" || root.sessionToken === ""
            || !swiftGridModel.documentBound) {
            return;
        }
        swiftGridModel.bindEditing(root.bandTarget, root.sessionToken);
        root.editingBound = true;
        // The band maps pointer facts through the host camera, so the overlay's
        // scroll must drive it. The initial centering ran before the bind, so
        // push the resting scroll once here; live pushes ride the flickable's
        // contentX/contentY handlers.
        timelineQuickView.setHorizontalScroll(flick.contentX - swiftGridModel.leadPadWidth)
        timelineQuickView.setVerticalScroll(flick.contentY)
    }
    onBandTargetChanged: bindEditingIfReady()
    onSessionTokenChanged: bindEditingIfReady()

    Component.onCompleted: {
        configureViewport();
        bindEditingIfReady();
    }
}
