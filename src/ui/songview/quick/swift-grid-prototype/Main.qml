import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root

    required property QtObject gridModel

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
    color: gridPalette ? gridPalette.windowBackground : "#C9C1BB"
    property int servedMetricsVersion: 0

    function metricFont(spec) {
        var f = { family: spec.family, pixelSize: Math.max(1, spec.pixelSize) }
        if (spec.weight !== undefined)
            f.weight = spec.weight
        if (spec.letterSpacing !== undefined)
            f.letterSpacing = spec.letterSpacing
        return Qt.font(f)
    }

    function serveMetrics() {
        var request = root.gridModel.metricsRequest
        if (!request || request.length === 0)
            return
        var fonts = root.gridModel.measurementFonts
        var lines = request.split("\n")
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i]
            if (line.length === 0)
                continue
            var tab = line.indexOf("\t")
            var key = tab < 0 ? line : line.slice(0, tab)
            var text = tab < 0 ? "" : line.slice(tab + 1)
            var dot = key.indexOf(".")
            var fontName = dot < 0 ? key : key.slice(0, dot)
            var what = dot < 0 ? "" : key.slice(dot + 1)
            var spec = fonts ? fonts[fontName] : undefined
            if (spec === undefined)
                continue
            if (what === "fit") {
                var fitted = 1
                for (var px = Math.max(1, spec.pixelSize); px > 0; --px) {
                    metricMeter.font = Qt.font({
                        family: spec.family, pixelSize: px,
                        weight: spec.weight !== undefined ? spec.weight : Font.Normal,
                        letterSpacing: spec.letterSpacing !== undefined ? spec.letterSpacing : 0
                    })
                    if (metricMeter.ascent + metricMeter.descent <= root.gridModel.rowHeight) {
                        fitted = px
                        break
                    }
                }
                root.gridModel.provideMetric(key, fitted)
                continue
            }
            metricMeter.font = root.metricFont(spec)
            if (what === "ascent")
                root.gridModel.provideMetric(key, metricMeter.ascent)
            else if (what === "height")
                root.gridModel.provideMetric(key, metricMeter.height)
            else if (what.indexOf("advance.") === 0)
                root.gridModel.provideMetric(key, metricMeter.advanceWidth(text))
        }
        root.gridModel.metricsSubmitted()
    }

    FontMetrics {
        id: metricMeter
    }

    Connections {
        target: root.gridModel
        function onMetricsVersionChanged() {
            if (root.gridModel.metricsVersion !== root.servedMetricsVersion) {
                root.servedMetricsVersion = root.gridModel.metricsVersion
                root.serveMetrics()
            }
        }
    }

    function configureViewport() {
        root.gridModel.configureViewport(root.baseFontPx, Screen.devicePixelRatio,
                                         rollPlot.width, rollPlot.height)
    }

    function resetDemo() {
        root.gridModel.resetDemo()
        flick.contentX = 0
        flick.contentY = root.gridModel.initialScrollY
    }

    Component.onCompleted: {
        root.configureViewport()
        flick.contentY = root.gridModel.initialScrollY
        console.log("SWIFT_GRID_READY")
    }

    header: ToolBar {
        background: Rectangle {
            color: root.gridPalette ? root.gridPalette.chromeBackground : "#BDB5AF"
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.gridPalette ? root.gridPalette.separator : "#5B5652"
            }
        }
        contentItem: RowLayout {
            spacing: 8

            Text {
                text: "Piano grid prototype — mus_route101 fixture"
                color: root.gridPalette ? root.gridPalette.windowText : "#302C29"
                font.pixelSize: root.bodyPx
                Layout.leftMargin: 8
            }
            Text {
                text: root.gridModel.statusText
                color: root.gridPalette ? root.gridPalette.secondaryText : "#57514C"
                font.pixelSize: root.bodyPx
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Button {
                text: "Reset"
                onClicked: root.resetDemo()
                Layout.rightMargin: 8
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
                    scene: root.scene
                    sceneLayer: TimelineQuickItem.RulerGutterChrome
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
                        scene: root.scene
                        sceneLayer: TimelineQuickItem.RulerChrome
                        z: 0
                    }
                    TimelineQuickItem {
                        objectName: "timelineQuickRulerMarks"
                        anchors.fill: parent
                        scene: root.scene
                        sceneLayer: TimelineQuickItem.RulerMarks
                        z: 1
                    }
                    Item {
                        anchors.fill: parent
                        z: 2

                        Repeater {
                            model: root.scene ? root.scene.rulerTextModel : null
                            delegate: Text {
                                required property var labelRect
                                required property string labelText
                                required property string labelColor
                                required property var labelFont
                                required property int labelHorizontalAlignment
                                required property int labelVerticalAlignment

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
                        root.gridModel.hoverKeyboard(mouse.y)
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

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    Item {
                        id: pianoGridSurface
                        objectName: "pianoGridSurface"
                        width: Math.max(root.gridModel.gridWidth, 1)
                        height: Math.max(root.gridModel.gridHeight, 1)

                        PianoRollCanvas {
                            bandSide: rollBandContent
                            gutterSide: rollGutterSide
                            plotSide: pianoGridSurface
                            timelineScene: root.scene
                        }

                        MouseArea {
                            id: inputArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            hoverEnabled: true
                            z: 10

                            cursorShape: {
                                switch (root.gridModel.cursorKind) {
                                case 1: return Qt.OpenHandCursor
                                case 2:
                                case 3: return Qt.SizeHorCursor
                                default: return Qt.ArrowCursor
                                }
                            }

                            onPressed: function (mouse) {
                                if (mouse.wasHeld)
                                    return
                                root.gridModel.beginPointer(mouse.x, mouse.y)
                            }
                            onDoubleClicked: function (mouse) {
                                root.gridModel.cancelPointer()
                                root.gridModel.doublePointer(mouse.x, mouse.y)
                            }
                            onPositionChanged: function (mouse) {
                                if (pressed)
                                    root.gridModel.updatePointer(mouse.x, mouse.y)
                                else
                                    root.gridModel.hoverPointer(mouse.x, mouse.y)
                            }
                            onReleased: function (mouse) {
                                root.gridModel.updatePointer(mouse.x, mouse.y)
                                root.gridModel.endPointer()
                            }
                            onCanceled: function () {
                                root.gridModel.cancelPointer()
                            }
                            onWheel: function (e) {
                                flick.contentX = Math.max(
                                    0, Math.min(flick.contentWidth - flick.width,
                                                flick.contentX - e.angleDelta.x))
                                flick.contentY = Math.max(
                                    0, Math.min(flick.contentHeight - flick.height,
                                                flick.contentY - e.angleDelta.y))
                                e.accepted = true
                            }
                        }
                    }
                }
            }
        }
    }
}
