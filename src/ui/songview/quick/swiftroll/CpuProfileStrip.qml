pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp as App

Item {
    id: strip
    required property EditorSurface root
    objectName: "cpuProfileStrip"
    readonly property App.CpuMeterPresenter meter: root.shellRouter ? root.shellRouter.cpuMeter : null
    readonly property App.PianoGrid grid: root.gridModel
    readonly property bool selected: root.shellRouter !== null
        && root.shellRouter.session.songTabs.selectedId === root.applicationSession.tabId
    readonly property bool rendering: visible && selected && meter !== null
    readonly property real gutter: grid.keyboardWidth
    readonly property App.CpuGraphScene scene: App.CpuGraphScene {
        meter: strip.meter
        palette: strip.grid.palette
        onMeterChanged: strip.refresh()
        onPaletteChanged: strip.refresh()
    }

    function refresh(): void {
        if (strip.rendering && heat) {
            strip.scene.updateProfile(heat.width, heat.height,
                                      strip.grid.cameraScrollX, strip.grid.beatWidth,
                                      strip.grid.ticksPerBeat, strip.grid.devicePixelRatio)
        }
    }

    onRenderingChanged: refresh()
    Component.onCompleted: strip.refresh()
    Connections {
        target: strip.rendering ? strip.grid : null
        function onCameraScrollXChanged(): void { strip.refresh() }
        function onBeatWidthChanged(): void { strip.refresh() }
        function onTicksPerBeatChanged(): void { strip.refresh() }
        function onDevicePixelRatioChanged(): void { strip.refresh() }
    }
    Connections {
        target: strip.rendering ? strip.grid.palette : null
        function onPolyphonyActiveFillChanged(): void { strip.refresh() }
        function onWarningTextChanged(): void { strip.refresh() }
        function onErrorTextChanged(): void { strip.refresh() }
    }
    Connections {
        target: strip.rendering ? strip.meter : null
        function onProfileDataRevisionChanged(): void { strip.refresh() }
        function onBudgetChanged(): void { strip.refresh() }
    }

    Rectangle { anchors.fill: parent; color: strip.grid.palette.chromeBackground }
    Text {
        x: 0; width: strip.gutter - strip.root.baseFontPx * 0.3; height: parent.height
        text: strip.meter && strip.meter.profileStatus === "Profiling…" ? qsTr("CPU…") : qsTr("CPU")
        color: strip.grid.palette.secondaryText
        font: strip.root.captionFont
        horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
    }
    Item {
        id: heat
        objectName: "cpuProfileHeat"
        x: strip.gutter; width: Math.max(0, parent.width - x); height: parent.height
        clip: true
        onWidthChanged: strip.refresh()
        onHeightChanged: strip.refresh()
        DisplayList {
            anchors.fill: parent
            source: strip.rendering ? strip.scene : null
            list: 0
            revision: strip.scene.displayRevision
        }
        MouseArea {
            id: hover
            objectName: "cpuProfileHover"
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.RightButton
            onClicked: menu.popup()
            property int cycles: -1
            function refreshCycles(): void {
                cycles = strip.rendering ? strip.scene.cyclesAt(mouseX) : -1
            }
            onMouseXChanged: hover.refreshCycles()
            Component.onCompleted: hover.refreshCycles()
            Connections {
                target: strip.rendering ? strip.scene : null
                function onDisplayRevisionChanged(): void { hover.refreshCycles() }
            }
            Connections {
                target: strip
                function onRenderingChanged(): void { hover.refreshCycles() }
            }
            ToolTip.visible: containsMouse && (cycles >= 0 || (strip.meter && strip.meter.profileStatus.length > 0))
            ToolTip.text: cycles >= 0
                ? qsTr("Estimated GBA sound cost: %1 cycles (%2% of VBlank). Right-click to hide.")
                    .arg(cycles).arg(Math.round(cycles * 100 / 83776))
                : strip.meter ? strip.meter.profileStatus : ""
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom; width: parent.width
        height: 1 / strip.grid.devicePixelRatio; color: strip.grid.palette.separator
    }
    Menu {
        id: menu
        MenuItem {
            text: qsTr("Hide CPU Profile")
            onTriggered: strip.root.shellRouter.activate("view.cpu_profile")
        }
    }
}
