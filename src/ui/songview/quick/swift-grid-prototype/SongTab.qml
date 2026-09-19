import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

FocusScope {
    id: root

    required property QtObject gridModel
    required property font font
    required property real baseFontPx
    required property string monoFamily
    readonly property real bodyPx: font.pixelSize
    readonly property bool noteMenuOpen: noteMenu.opened
    readonly property bool pitchEditorOpen: pitchHost.visible

    onVisibleChanged: {
        if (!visible) {
            root.gridModel.inputCancelled(2);
            if (pitchHost.visible)
                root.gridModel.cancelPitchCurves();
            noteMenu.close();
            pitchHost.close();
        }
    }

    signal pitchEditorRequested
    property var pitchBridge: null
    onPitchEditorRequested: {
        if (!root.gridModel.hasEditableSelection())
            return;
        noteMenu.close();
        pitchBridge = root.gridModel.makePitchEditor(Math.round(popupTitleMetrics.height), Math.round(popupCaptionMetrics.height), root.font.family, root.monoFamily);
        pitchHost.open();
    }

    property string contextualHint: ""
    readonly property QtObject audio: root.gridModel.audio

    // Playhead metrics mirror ui/playheadoverlay.cpp: font-scaled radius and
    // triangle, single-pixel core, asymmetric bloom while playing.
    readonly property real playheadX: {
        const dpr = root.gridModel.devicePixelRatio;
        const x = root.gridModel.leadPadWidth + root.audio.playheadTick * root.gridModel.beatWidth / root.gridModel.ticksPerBeat;
        return Math.round(x * dpr) / dpr;
    }
    readonly property real playheadGlowRadius: Math.round(root.baseFontPx * 0.625)
    readonly property real playheadGlowLeft: root.audio.playing ? playheadGlowRadius - 1 : playheadGlowRadius
    readonly property real playheadGlowRight: root.audio.playing ? 0.5 : playheadGlowRadius
    readonly property real playheadPeakAlpha: root.audio.playing ? 0.13 : 0.06
    readonly property int playheadTriangleHalfWidth: Math.round(root.baseFontPx * 0.25)
    readonly property int playheadTriangleHeight: Math.round(root.baseFontPx * 0.5)
    Timer {
        interval: 30
        running: root.audio.playing
        repeat: true
        onTriggered: root.audio.refreshTransport()
    }

    FontMetrics {
        id: popupTitleMetrics
        font: Qt.font({
            family: root.font.family,
            pixelSize: root.bodyPx,
            weight: Font.DemiBold
        })
    }
    FontMetrics {
        id: popupCaptionMetrics
        font: Qt.font({
            family: root.font.family,
            pixelSize: Math.round(root.baseFontPx)
        })
    }

    Popup {
        id: pitchHost
        objectName: "pitchPopupHost"
        parent: Overlay.overlay
        modal: true
        dim: false
        focus: true
        padding: 0
        margins: 0
        background: null
        closePolicy: Popup.CloseOnPressOutside
        width: root.pitchBridge ? root.pitchBridge.metrics.popupWidth : 0
        height: root.pitchBridge ? root.pitchBridge.metrics.popupHeight : 0
        x: {
            if (!root.pitchBridge)
                return 0;
            const note = root.gridModel.pitchEditorAnchor();
            const anchor = pianoGridSurface.mapToItem(parent, note.x + note.width / 2, note.y);
            const margin = Math.round(root.baseFontPx * 0.25);
            return Math.max(margin, Math.min(anchor.x - width / 2, parent.width - width - margin));
        }
        y: {
            if (!root.pitchBridge)
                return 0;
            const note = root.gridModel.pitchEditorAnchor();
            const anchor = pianoGridSurface.mapToItem(parent, note.x, note.y);
            const margin = Math.round(root.baseFontPx * 0.25);
            let proposed = anchor.y + note.height + margin + 1;
            if (proposed + height > parent.height - margin)
                proposed = anchor.y - margin - height;
            return Math.max(margin, Math.min(proposed, parent.height - height - margin));
        }
        contentItem: Loader {
            active: pitchHost.visible
            sourceComponent: PitchBendPopup {
                bridge: root.pitchBridge
                onHintChanged: text => root.contextualHint = text
                onEscapePressed: root.escapePressed()
            }
            onLoaded: item.focusPitch()
        }
        onAboutToHide: root.gridModel.commitPitchCurves()
        onClosed: {
            root.pitchBridge = null;
            root.gridModel.closePitchEditor();
            root.contextualHint = "";
            if (root.visible)
                inputArea.forceActiveFocus();
        }
    }

    Connections {
        target: root.pitchBridge
        function onPreviewRequested() {
            root.gridModel.previewPitchCurves();
        }
        function onCommitRequested() {
            root.gridModel.commitPitchCurves();
        }
        function onCancelRequested() {
            root.gridModel.cancelPitchCurves();
            pitchHost.close();
        }
        function onAuditionRequested() {
            if (root.audio.playing)
                root.audio.stop();
            else
                root.audio.playFrom(root.pitchBridge.startTick);
        }
    }
    readonly property QtObject gridPalette: root.gridModel.palette
    readonly property QtObject scene: root.gridModel.scene
    function configureViewport() {
        root.gridModel.configureViewport(root.baseFontPx, Screen.devicePixelRatio, rollPlot.width, rollPlot.height);
    }

    function resetDemo() {
        root.gridModel.resetDemo();
        flick.contentX = 0;
        flick.contentY = root.gridModel.initialScrollY;
    }

    // The single Escape arbiter (spec §3.5): every surface forwards Escape
    // here; the model decides over the observed noteMenu.opened and returns
    // the action this host executes. Raw values mirror GridEscapeAction
    // (2 = closePitchEditor, 3 = closeNoteMenu); other actions need no QML
    // work — the model already tore the gesture down or cleared selection.
    function escapePressed() {
        const action = root.gridModel.escapePressed(noteMenu.opened);
        if (action === 2)
            pitchHost.close();
        else if (action === 3)
            noteMenu.close();
    }

    Component.onCompleted: {
        root.configureViewport();
        flick.contentY = root.gridModel.initialScrollY;
        console.log("SWIFT_GRID_READY");
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: rulerBand
            Layout.fillWidth: true
            Layout.preferredHeight: root.gridModel.rulerHeight
            clip: true

            Item {
                id: rulerGutter
                objectName: "timelineQuickRulerGutter"
                width: root.gridModel.keyboardWidth
                height: parent.height
                clip: true

                TimelineQuickItem {
                    objectName: "timelineQuickRulerGutterChrome"
                    anchors.fill: parent
                    rects: root.scene.rulerGutterChrome
                    z: 0
                }
            }

            Item {
                id: rulerPlot
                objectName: "timelineQuickRulerPlot"
                x: rulerGutter.width
                width: parent.width - rulerGutter.width
                height: parent.height
                clip: true

                Item {
                    id: rulerContent
                    x: -flick.contentX
                    width: Math.max(root.gridModel.gridWidth, 1)
                    height: parent.height

                    TimelineQuickItem {
                        objectName: "timelineQuickRulerChrome"
                        anchors.fill: parent
                        rects: root.scene.rulerChrome
                        z: 0
                    }
                    TimelineQuickItem {
                        objectName: "timelineQuickRulerMarks"
                        anchors.fill: parent
                        rects: root.scene.rulerMarks
                        z: 1
                    }
                    Item {
                        anchors.fill: parent
                        z: 2

                        Repeater {
                            model: root.scene.rulerTextModel
                            delegate: Text {
                                required property var labelRect
                                required property string labelText
                                required property string labelColor
                                required property var labelFont
                                required property int labelHorizontalAlignment
                                required property int labelVerticalAlignment

                                objectName: "rulerLabel_" + labelText
                                x: labelRect.x
                                y: labelRect.y
                                width: labelRect.width
                                height: labelRect.height
                                text: labelText
                                color: labelColor
                                font: Qt.font(labelFont)
                                horizontalAlignment: labelHorizontalAlignment
                                verticalAlignment: labelVerticalAlignment
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                elide: Text.ElideNone
                                maximumLineCount: 1
                                clip: contentWidth > width || contentHeight > height
                            }
                        }
                    }
                    Shape {
                        objectName: "rulerPlayheadTriangle"
                        visible: root.audio.ready
                        x: root.playheadX - root.playheadTriangleHalfWidth
                        y: rulerContent.height - root.playheadTriangleHeight
                        width: 2 * root.playheadTriangleHalfWidth
                        height: root.playheadTriangleHeight
                        z: 3

                        ShapePath {
                            fillColor: root.gridPalette.playhead
                            strokeColor: "transparent"
                            PathMove {
                                x: 0
                                y: 0
                            }
                            PathLine {
                                x: 2 * root.playheadTriangleHalfWidth
                                y: 0
                            }
                            PathLine {
                                x: root.playheadTriangleHalfWidth
                                y: root.playheadTriangleHeight
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: rollBand
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Item {
                id: rollBandContent
                y: -flick.contentY
                width: rollBand.width
                height: Math.max(root.gridModel.gridHeight, 1)
                z: 1

                Item {
                    id: rollGutterSide
                    objectName: "timelineQuickRollGutter"
                    width: root.gridModel.keyboardWidth
                    height: parent.height
                    clip: true
                }

                MouseArea {
                    width: rollGutterSide.width
                    height: parent.height
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onPositionChanged: function (mouse) {
                        root.gridModel.hoverKeyboard(mouse.y);
                    }
                    onExited: root.gridModel.clearKeyboardHover()
                    z: 10
                }
            }

            Item {
                id: rollPlot
                objectName: "timelineQuickRollPlot"
                x: rollGutterSide.width
                width: parent.width - rollGutterSide.width
                height: parent.height
                clip: true

                onWidthChanged: root.configureViewport()
                onHeightChanged: root.configureViewport()

                Flickable {
                    id: flick
                    objectName: "pianoGridViewport"
                    anchors.fill: parent
                    clip: true
                    interactive: false
                    pixelAligned: true
                    boundsBehavior: Flickable.StopAtBounds

                    contentWidth: pianoGridSurface.width
                    contentHeight: pianoGridSurface.height
                    onContentYChanged: root.gridModel.setViewportScroll(contentY)
                    onContentXChanged: root.gridModel.setViewportScrollX(contentX)

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }
                    ScrollBar.horizontal: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    Item {
                        id: pianoGridSurface
                        objectName: "pianoGridSurface"
                        width: Math.max(root.gridModel.gridWidth, 1)
                        height: Math.max(root.gridModel.gridHeight, 1)
                        // Production ItemVisibleHasChanged entry: per-surface
                        // hidden tears the grid gesture down (reason 2).
                        onVisibleChanged: {
                            if (!visible)
                                root.gridModel.inputCancelled(2);
                        }
                        PianoRollCanvas {
                            bandSide: rollBandContent
                            gutterSide: rollGutterSide
                            plotSide: pianoGridSurface
                            timelineScene: root.scene
                        }
                        Item {
                            objectName: "gridPlayhead"
                            visible: root.audio.ready
                            x: root.playheadX - root.playheadGlowLeft
                            width: root.playheadGlowLeft + root.playheadGlowRight
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            z: 5

                            Rectangle {
                                x: 0
                                width: root.playheadGlowLeft
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop {
                                        position: 0.0
                                        color: "transparent"
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: Qt.alpha(root.gridPalette.playhead, root.playheadPeakAlpha)
                                    }
                                }
                            }
                            Rectangle {
                                x: root.playheadGlowLeft
                                width: root.playheadGlowRight
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop {
                                        position: 0.0
                                        color: Qt.alpha(root.gridPalette.playhead, root.playheadPeakAlpha)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: "transparent"
                                    }
                                }
                            }
                            Rectangle {
                                x: root.playheadGlowLeft - 0.5
                                width: 1
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                color: root.gridPalette.playhead
                            }
                        }

                        MouseArea {
                            id: inputArea
                            objectName: "pianoGridInput"
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            preventStealing: true
                            // Focus home of the grid surface: press-driven
                            // gestures hold active focus so a focus steal is
                            // observable as production focusOutEvent (reason 0).
                            focus: true
                            hoverEnabled: true
                            // Window-tier Escape fallback (spec §3.5): the
                            // focused grid input surface forwards to the same
                            // arbiter as every popup surface. Keys.onEscapePressed
                            // only — Keys.onPressed intercepts G even when
                            // accepted is false and blocks the window Shortcut.
                            Keys.onEscapePressed: event => {
                                root.escapePressed();
                                event.accepted = true;
                            }
                            z: 10
                            property bool rightHeld: false
                            // Production focusOutEvent entry: focus loss while
                            // visible keeps a live gesture committable
                            // (reason 0 is survival — zero state change). The
                            // visible guard arbitrates the hidden case, which
                            // owns its teardown through reason 2 instead.
                            onActiveFocusChanged: {
                                if (!activeFocus && visible)
                                    root.gridModel.cancelPointer(0);
                            }

                            cursorShape: {
                                switch (root.gridModel.cursorKind) {
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
                                if (mouse.wasHeld)
                                    return;
                                inputArea.forceActiveFocus(Qt.MouseFocusReason);
                                if (mouse.button === Qt.RightButton) {
                                    rightHeld = true;
                                    root.gridModel.beginRightPointer(mouse.x, mouse.y, Qt.styleHints.startDragDistance);
                                } else {
                                    root.gridModel.beginPointer(mouse.x, mouse.y);
                                }
                            }
                            onDoubleClicked: function (mouse) {
                                if (mouse.button === Qt.RightButton)
                                    return;
                                root.gridModel.cancelPointer(1);
                                root.gridModel.doublePointer(mouse.x, mouse.y);
                            }
                            onPositionChanged: function (mouse) {
                                if (rightHeld)
                                    root.gridModel.updateRightPointer(mouse.x, mouse.y);
                                else if (pressed)
                                    root.gridModel.updatePointer(mouse.x, mouse.y);
                                else
                                    root.gridModel.hoverPointer(mouse.x, mouse.y);
                            }
                            onReleased: function (mouse) {
                                if (rightHeld) {
                                    rightHeld = false;
                                    root.gridModel.endRightPointer(mouse.x, mouse.y);
                                } else {
                                    root.gridModel.updatePointer(mouse.x, mouse.y);
                                    root.gridModel.endPointer();
                                }
                            }
                            onCanceled: function () {
                                if (rightHeld) {
                                    rightHeld = false;
                                    root.gridModel.cancelRightPointer(1);
                                } else {
                                    root.gridModel.cancelPointer(1);
                                }
                            }
                            onWheel: function (e) {
                                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - e.angleDelta.x));
                                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - e.angleDelta.y));
                                e.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: root.gridModel
        function onContextMenuRequested(x, y) {
            noteMenu.openAt(pianoGridSurface.mapToItem(noteMenu, x, y));
        }
    }

    NoteMenu {
        id: noteMenu
        objectName: "noteContextMenu"
        anchors.fill: parent
        baseFontPx: root.baseFontPx
        menuFont: root.font
        onEscapePressed: root.escapePressed()
        onChosen: function (command) {
            if (command === "delete")
                root.gridModel.deleteSelection();
            else if (command === "pitch")
                root.pitchEditorRequested();
        }
    }
}
