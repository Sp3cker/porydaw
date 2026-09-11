pragma ComponentBehavior: Bound
// PROTOTYPE — THROWAWAY. Do not ship, do not add to CMakeLists QML_FILES.
// Question: which arrangement lets a user edit + view automation while keeping
// all nine parameters reachable, now that scrolling is allowed?
// Run:  qml src/ui/songview/quick/AutomationTabsPrototype.qml
//
// Deliberately standalone: no Porydaw.Ui import, no C++ canvas. `mock` below
// mimics the AutomationCanvas surface the real AutomationTabs.qml binds to
// (parameterLabels / activeParameter / selectedParameters / activateParameter
// / parameterAppearance), so a settled layout ports back by swapping `mock`
// for `canvas`. Colors approximate the real theme roles.
import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts

Window {
    id: win

    property string variant: "D"
    property string clickMode: "activate" // activate | selection

    width: 1180
    height: 820
    visible: true
    color: "#14161a"
    title: "Automation tabs prototype — A/B/C/D x three drawer heights"

    // ---------------------------------------------------------------- mock
    QtObject {
        id: mock
        property int activeParameter: 1
        property var selectedParameters: [1, 2]
        property bool showPips: true
        property bool showLegend: true

        // Catalog order mirrors CCLanes::supportedControllers() + Tempo.
        property var labels: [
            { "text": "Modulation", "data": false },
            { "text": "Volume", "data": true },
            { "text": "Pan", "data": true },
            { "text": "Bend range", "data": false },
            { "text": "LFO speed", "data": false },
            { "text": "Echo volume", "data": true },
            { "text": "Echo length", "data": false },
            { "text": "Pitch bend", "data": false },
            { "text": "Tempo", "data": true }
        ]
        property var ranges: ["0–127", "0–127", "0–127", "0–127", "0–127",
                              "0–127", "0–127", "-24–24", "BPM"]

        // Approximations of parameterAppearance(): base font ~12px,
        // minimumPixelSize = layout::fontPx(2/3), cell floor = fontPxF(4/3).
        readonly property int labelPx: 12
        readonly property int minPx: 8
        readonly property real minCell: 17.3
        readonly property int inset: 4
        readonly property int stroke: 1
        property color tabBg: "#262a31"
        property color tabHover: "#2e343d"
        property color tabSel: "#2f6feb"
        property color tabText: "#c3c9d2"
        property color tabOutline: "#363c46"
        property color pip: "#7fd18a"
        property color focusRing: "#8ab4ff"
        property color selEdge: "#f0b23c"

        function activate(index) { activeParameter = index; }
        function toggleSelection(index) {
            var next = selectedParameters.slice();
            var at = next.indexOf(index);
            if (at === -1) next.push(index); else next.splice(at, 1);
            selectedParameters = next;
        }
        // One concept, two surfaces: a parameter in the shared selection gets
        // the yellow tab rule AND a dashed curve in the plot. Plain click
        // activates; Cmd/Ctrl+click toggles inclusion; an armed clickMode makes
        // it reachable without a modifier.
        function applyClick(index, modifiers) {
            if (win.clickMode === "selection")
                toggleSelection(index);
            else if (modifiers & (Qt.ControlModifier | Qt.MetaModifier))
                toggleSelection(index);
            else if (modifiers & Qt.AltModifier)
                toggleSelection(index);
            else
                activate(index);
        }
        // The plot ghosts every selected lane except the active one.
        function ghostCount() {
            var n = 0;
            for (var i = 0; i < selectedParameters.length; ++i)
                if (selectedParameters[i] !== activeParameter) ++n;
            return n;
        }
        function cycle(delta) {
            var n = labels.length;
            activeParameter = (activeParameter + delta + n) % n;
        }
        function reset() {
            activeParameter = 1;
            selectedParameters = [1, 2];
        }
    }

    // ------------------------------------------------------- tab delegate
    component ParamTab: Controls.TabButton {
        id: tab

        required property int index
        required property string label
        required property bool hasData
        required property bool tempo

        font.pixelSize: mock.labelPx
        padding: mock.inset
        focusPolicy: Qt.StrongFocus
        hoverEnabled: true
        checkable: false
        // Display-only: the MouseArea below owns activation, so neither a
        // click, Space, nor an exclusivity group may write `checked`.
        checked: mock.activeParameter === tab.index

        contentItem: RowLayout {
            spacing: 4

            Rectangle {
                width: 6
                height: 6
                radius: 3
                color: mock.pip
                visible: mock.showPips && tab.hasData
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: tab.label
                font: tab.font
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: mock.minPx
                wrapMode: Text.NoWrap
                elide: Text.ElideNone
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true
                color: mock.tabText
                Accessible.ignored: true
            }
        }

        background: Rectangle {
            color: tab.checked ? mock.tabSel : tab.hovered ? mock.tabHover : mock.tabBg
            border.width: mock.stroke
            border.color: mock.tabOutline

            // Shared-selection inclusion: bottom rule, never a full outline,
            // and never on the tab being edited — that one is the blue fill.
            Rectangle {
                visible: mock.selectedParameters.indexOf(tab.index) !== -1
                        && mock.activeParameter !== tab.index
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: mock.stroke
                height: mock.stroke
                color: mock.selEdge
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: mock.stroke
                color: "transparent"
                border.width: mock.stroke
                border.color: tab.visualFocus ? mock.focusRing : "transparent"
            }
        }

        // Plain click activates; a modified click toggles shared-selection
        // inclusion, which shows as the yellow rule here and a dashed curve
        // in the plot.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: (mouse) => {
                tab.forceActiveFocus();
                mock.applyClick(tab.index, mouse.modifiers);
            }
        }
    }

    // ---------------------------------------------------------- plot mock
    component PlotMock: Rectangle {
        id: plot

        color: "#171a1f"
        border.width: 1
        border.color: "#2a2f37"

        // Prototype-only repaint trigger; the real canvas repaints from C++.
        property int paintTick: 0
        onPaintTickChanged: canvas.requestPaint()

        Connections {
            target: mock
            function onSelectedParametersChanged() { plot.paintTick++; }
            function onActiveParameterChanged() { plot.paintTick++; }
        }

        Canvas {
            id: canvas

            anchors.fill: parent

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.clearRect(0, 0, width, height);

                ctx.strokeStyle = "#232830";
                ctx.lineWidth = 1;
                for (var gx = 0; gx < width; gx += 48) {
                    ctx.beginPath();
                    ctx.moveTo(gx + 0.5, 0);
                    ctx.lineTo(gx + 0.5, height);
                    ctx.stroke();
                }

                function valueAt(index, t) {
                    var phase = index * 1.1;
                    return 0.5 + 0.32 * Math.sin(t * 7.0 + phase)
                            + 0.10 * Math.sin(t * 19.0 + phase * 2.0);
                }
                function curve(index, color, dashed, wide) {
                    ctx.strokeStyle = color;
                    ctx.lineWidth = wide ? 2 : 1;
                    ctx.setLineDash(dashed ? [4, 3] : []);
                    ctx.beginPath();
                    for (var px = 0; px <= width; px += 4) {
                        var t = px / Math.max(1, width);
                        var y = height - valueAt(index, t) * (height - 10) - 5;
                        if (px === 0) ctx.moveTo(px, y); else ctx.lineTo(px, y);
                    }
                    ctx.stroke();
                    ctx.setLineDash([]);
                }
                function nodes(index, color) {
                    ctx.fillStyle = color;
                    for (var n = 0; n < 8; ++n) {
                        var t = (n + 0.5) / 8;
                        var y = height - valueAt(index, t) * (height - 10) - 5;
                        ctx.fillRect(t * width - 2.5, y - 2.5, 5, 5);
                    }
                }

                for (var g = 0; g < mock.selectedParameters.length; ++g)
                    if (mock.selectedParameters[g] !== mock.activeParameter)
                        curve(mock.selectedParameters[g], "#5d6773", true, false);
                curve(mock.activeParameter, "#4c9ffe", false, true);
                nodes(mock.activeParameter, "#dce3ec");
            }
        }

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 6
            visible: mock.showLegend
            text: mock.labels[mock.activeParameter].text + "  ·  "
                  + mock.ranges[mock.activeParameter]
                  + (mock.ghostCount() ? "   +" + mock.ghostCount() + " in selection" : "")
            font.pixelSize: 11
            color: "#8f98a6"
        }
    }

    // ----------------------------------- gutter variants: A (1 col), B/D (2 col)
    component GutterColumn: Item {
        id: gutter

        property int columns: 2
        Component.onCompleted: Qt.callLater(() => console.log(
            "gutter", width, "x", height, "cols", columns, "gridH", grid.implicitHeight))

        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: grid.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            GridLayout {
                id: grid

                width: parent.width
                columns: gutter.columns
                rowSpacing: 0
                columnSpacing: 0

                Repeater {
                    model: mock.labels

                    ParamTab {
                        required property var modelData

                        label: modelData.text
                        hasData: modelData.data
                        tempo: index === mock.labels.length - 1
                        Layout.columnSpan: (gutter.columns > 1 && tempo) ? 2 : 1
                    }
                }
            }
        }
    }

    // --------------------------------------- variant C: strip above the plot
    component StripAbove: Item {
        id: above

        property int columns: 1 // unused; keeps the strip uniform

        Flickable {
            anchors.fill: parent
            clip: true
            contentWidth: stripRow.implicitWidth
            contentHeight: stripRow.implicitHeight
            interactive: contentWidth > width
            boundsBehavior: Flickable.StopAtBounds

            RowLayout {
                id: stripRow

                height: parent.height
                width: Math.max(parent.width, stripRow.implicitWidth)
                spacing: 2
                Repeater {
                    model: mock.labels

                    ParamTab {
                        required property var modelData

                        label: modelData.text
                        hasData: modelData.data
                        tempo: index === mock.labels.length - 1
                        Layout.minimumWidth: 74
                    }
                }
            }
        }
    }

    // ------------------------------------------- one drawer strip (gutter+plot)
    component Strip: Column {
        id: strip

        required property int bodyHeight
        required property string variant
        property int gutterWidth: 284 // SongView::timelineSplitX = fontPx(17.5 + 13/3) at 13px
        property int columns: 2
        readonly property bool above: strip.variant === "C"

        width: parent.width
        height: bodyHeight
        spacing: 0

        // Variant C: one label row across the full strip, plot underneath.
        StripAbove {
            id: band

            width: parent.width
            height: strip.above ? Math.min(26, Math.max(18, strip.height / 4)) : 0
            visible: strip.above
        }

        Row {
            width: parent.width
            height: strip.height - band.height

            Rectangle {
                width: strip.gutterWidth
                height: parent.height
                color: "#1e2128"
                border.width: 1
                border.color: "#2a2f37"
                visible: !strip.above

                GutterColumn {
                    anchors.fill: parent
                    columns: strip.columns
                }
            }

            PlotMock {
                width: parent.width - (strip.above ? 0 : strip.gutterWidth)
                height: parent.height
            }
        }
    }

    // ---------------------------------------------------------------- chrome
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
            text: "PROTOTYPE — automation parameter selector: arrangement x drawer height"
            font.pixelSize: 13
            color: "#e6e9ee"
        }

        Repeater {
            model: [
                { "h": 44, "tag": "floor ~3.4em (layout::fontPx(17/5))" },
                { "h": 96, "tag": "typical resized drawer" },
                { "h": 170, "tag": "tall drawer" }
            ]

            Column {
                required property var modelData
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: modelData.tag + "  (" + modelData.h + "px)"
                    font.pixelSize: 10
                    color: "#7d8695"
                }

                Strip {
                    bodyHeight: modelData.h
                    variant: win.variant
                    columns: win.variant === "A" ? 1 : 2
                    width: parent.width
                }
            }
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            height: 76
            color: "#1e2128"
            border.width: 1
            border.color: "#2a2f37"
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    spacing: 6

                    Repeater {
                        model: [
                            { "k": "A", "d": "1 column (spec today)" },
                            { "k": "B", "d": "2 columns (HEAD)" },
                            { "k": "C", "d": "strip above plot" },
                            { "k": "D", "d": "2 col + pips/legend" }
                        ]

                        Controls.Button {
                            required property var modelData
                            text: modelData.k + "  " + modelData.d
                            font.pixelSize: 11
                            checked: win.variant === modelData.k
                            onClicked: win.variant = modelData.k
                        }
                    }
                    Repeater {
                        model: [
                            { "k": "activate", "d": "click: activate" },
                            { "k": "selection", "d": "click: +sel" },
                        ]

                        Controls.Button {
                            required property var modelData
                            text: modelData.d
                            font.pixelSize: 11
                            checked: win.clickMode === modelData.k
                            onClicked: win.clickMode = modelData.k
                        }
                    }

                    Controls.Button {
                        text: "pips"
                        font.pixelSize: 11
                        checkable: true
                        checked: mock.showPips
                        onToggled: mock.showPips = checked
                    }
                    Controls.Button {
                        text: "legend"
                        font.pixelSize: 11
                        checkable: true
                        checked: mock.showLegend
                        onToggled: mock.showLegend = checked
                    }
                    Controls.Button {
                        text: mock.selectedParameters.length ? "clear selection" : "no selection"
                        font.pixelSize: 11
                        onClicked: mock.selectedParameters = []
                    }
                    Controls.Button {
                        text: "reset"
                        font.pixelSize: 11
                        onClicked: mock.reset()
                    }
                }

                Text {
                    text: "active: " + mock.labels[mock.activeParameter].text
                          + "   selection: " + mock.selectedParameters
                          + "   |  1-4 = variant, Cmd/Ctrl/Alt+click = selection (yellow + dashed curve), Ctrl+Alt+Up/Down = cycle"
                    font.pixelSize: 11
                    color: "#9aa3b2"
                }
            }
        }
    }
    // Throwaway self-test: proves the gesture router without synthetic input.
    Component.onCompleted: {
        mock.reset();
        mock.applyClick(0, Qt.MetaModifier);
        mock.applyClick(3, Qt.ControlModifier);
        mock.applyClick(5, Qt.AltModifier);
        mock.applyClick(7, 0);
        console.log("SELFTEST selection=" + mock.selectedParameters + " active=" + mock.activeParameter
                    + " ghostsInPlot=" + mock.ghostCount());
        mock.reset();
    }

    Shortcut { sequence: "Ctrl+Alt+Up"; onActivated: mock.cycle(-1) }
    Shortcut { sequence: "Ctrl+Alt+Down"; onActivated: mock.cycle(1) }
    Shortcut { sequence: "1"; onActivated: win.variant = "A" }
    Shortcut { sequence: "2"; onActivated: win.variant = "B" }
    Shortcut { sequence: "3"; onActivated: win.variant = "C" }
    Shortcut { sequence: "4"; onActivated: win.variant = "D" }
    Shortcut { sequence: "Ctrl+Alt+Left"; onActivated: win.variant = "A" }
    Shortcut { sequence: "Ctrl+Alt+Right"; onActivated: win.variant = "D" }
}
