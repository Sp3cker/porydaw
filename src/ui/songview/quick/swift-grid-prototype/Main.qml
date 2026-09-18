import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
    id: root

    required property QtObject gridModel

    signal pitchEditorRequested
    property var pitchBridge: null
    onPitchEditorRequested: {
        if (!root.gridModel.hasEditableSelection())
            return;
        noteMenu.close();
        pitchBridge = root.gridModel.makePitchEditor(Math.round(popupTitleMetrics.height), Math.round(popupCaptionMetrics.height), bodyFace.font.family, monoFace.font.family);
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

    Shortcut {
        sequence: "Space"
        enabled: !noteMenu.opened && !pitchHost.visible
        onActivated: root.audio.togglePlayback()
    }
    Shortcut {
        sequences: ["Delete", "Backspace"]
        enabled: !noteMenu.opened && !pitchHost.visible
        onActivated: root.gridModel.deleteSelection()
    }
    Shortcut {
        sequence: "G"
        enabled: !noteMenu.opened && !pitchHost.visible
        onActivated: root.pitchEditorRequested()
    }

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
            }
            onLoaded: item.focusPitch()
        }
        onAboutToHide: root.gridModel.commitPitchCurves()
        onClosed: {
            root.pitchBridge = null;
            root.gridModel.closePitchEditor();
            root.contextualHint = "";
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

    FontLoader {
        id: bodyFace
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-Regular.ttf"
    }
    FontLoader {
        id: semiboldFace
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"
    }
    FontLoader {
        id: monoFace
        source: "qrc:/fonts/AtkinsonHyperlegibleMono-Regular.ttf"
    }
    readonly property real baseFontPx: appFontInfo.pixelSize
    readonly property real bodyScale: 1.125
    readonly property real bodyPx: Math.max(1, Math.round(baseFontPx * bodyScale))

    FontInfo {
        id: appFontInfo
        font: Qt.application.font
    }

    font.family: bodyFace.font.family
    font.pixelSize: root.bodyPx

    readonly property QtObject gridPalette: root.gridModel.palette
    readonly property QtObject scene: root.gridModel.scene

    visible: true
    width: 1280
    height: 800
    title: "Porydaw — Swift Grid Prototype"
    color: root.gridPalette.windowBackground

    function configureViewport() {
        root.gridModel.configureViewport(root.baseFontPx, Screen.devicePixelRatio, rollPlot.width, rollPlot.height);
    }

    function resetDemo() {
        root.gridModel.resetDemo();
        flick.contentX = 0;
        flick.contentY = root.gridModel.initialScrollY;
    }

    Component.onCompleted: {
        root.configureViewport();
        flick.contentY = root.gridModel.initialScrollY;
        console.log("SWIFT_GRID_READY");
    }
    // Production ItemVisibleHasChanged entry: window hide() is Hidden
    // (reason 2), matching the grid surface wire below. WindowDeactivate
    // arrives only through the native window eventFilter (reason 3):
    // isActive is app bookkeeping and is not synthesizable via sendEvent,
    // so there is deliberately no onActiveChanged wire. Popup-owned
    // surfaces keep their own input (spec deferral §8 — no popup teardown).
    onVisibleChanged: {
        if (!visible)
            root.gridModel.cancelPointer(2);
    }

    component ChromeButton: Rectangle {
        id: button
        required property string text
        signal clicked
        implicitWidth: caption.implicitWidth + Math.round(root.baseFontPx)
        implicitHeight: Math.round(root.baseFontPx * 2)
        activeFocusOnTab: true
        opacity: enabled ? 1 : 0.5
        color: pointer.pressed ? "#F5B61C" : pointer.containsMouse ? "#E7E2DC" : root.gridPalette.windowBackground
        border.width: 1 / Screen.devicePixelRatio
        border.color: root.gridPalette.outline
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: clicked()
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Text {
            id: caption
            anchors.centerIn: parent
            text: button.text
            font: root.font
            color: root.gridPalette.windowText
            renderType: Text.NativeRendering
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                button.forceActiveFocus(Qt.MouseFocusReason);
                button.clicked();
            }
        }
    }

    header: ToolBar {
        background: Rectangle {
            color: root.gridPalette.chromeBackground
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.gridPalette.separator
            }
        }
        contentItem: RowLayout {
            spacing: Math.round(root.baseFontPx * 0.5)

            Text {
                text: "Piano grid prototype — mus_route101 fixture"
                color: root.gridPalette.windowText
                font.pixelSize: root.bodyPx
                Layout.leftMargin: Math.round(root.baseFontPx * 0.5)
            }
            Text {
                text: root.contextualHint.length > 0 ? root.contextualHint : root.gridModel.statusText
                color: root.gridPalette.secondaryText
                font.pixelSize: root.bodyPx
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            ChromeButton {
                objectName: "transportPlayPause"
                text: root.audio.playing ? "Pause" : "Play"
                enabled: root.audio.ready
                onClicked: root.audio.togglePlayback()
            }
            ChromeButton {
                objectName: "transportStop"
                text: "Stop"
                enabled: root.audio.ready
                onClicked: root.audio.stop()
            }
            Text {
                objectName: "audioBackendStatus"
                text: root.audio.errorText.length > 0 ? "Audio unavailable: " + root.audio.errorText : root.audio.backendName + (root.audio.usingNullBackend ? " (null)" : "")
                color: root.audio.errorText.length > 0 ? root.gridPalette.playhead : root.gridPalette.secondaryText
                font.pixelSize: root.bodyPx
                elide: Text.ElideRight
            }
            ChromeButton {
                text: "Reset"
                onClicked: root.resetDemo()
                Layout.rightMargin: Math.round(root.baseFontPx * 0.5)
            }
        }
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
                    boundsBehavior: Flickable.StopAtBounds

                    contentWidth: pianoGridSurface.width
                    contentHeight: pianoGridSurface.height
                    onContentYChanged: root.gridModel.setViewportScroll(contentY)

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
                                root.gridModel.cancelPointer(2);
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
            noteMenu.openAt(pianoGridSurface.mapToItem(root.contentItem, x, y));
        }
    }

    NoteMenu {
        id: noteMenu
        objectName: "noteContextMenu"
        anchors.fill: parent
        baseFontPx: root.baseFontPx
        menuFont: root.font
        onChosen: function (command) {
            if (command === "delete")
                root.gridModel.deleteSelection();
            else if (command === "pitch")
                root.pitchEditorRequested();
        }
    }
}
