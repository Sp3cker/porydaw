pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import PorydawApp

Rectangle {
    id: statusBar
    required final property ShellWindow root
    required final property ShellPresenter shell
    required final property FontMetrics bodyMetrics
    required final property FontMetrics captionMetrics
        readonly property int statusTopInset: 3
        readonly property int statusBottomInset: 2
        readonly property int statusGripHeight: 13 + 4
        readonly property bool showingFailure: statusBar.shell.session.lastSaveError.length > 0
                                                && statusBar.shell.statusText === statusBar.shell.session.lastSaveError
        readonly property string openingText: {
            switch (statusBar.shell.session.projectOpeningStage) {
            case 1: return qsTr("Reading project… (1/3)")
            case 2: return qsTr("Opening songs… (2/3)")
            case 3: return qsTr("Indexing instruments… (3/3)")
            default: return ""
            }
        }
        readonly property bool showingProgress: openingText.length > 0 && !showingFailure
        implicitHeight: Math.max(statusBar.captionMetrics.height, statusBar.bodyMetrics.height, statusGripHeight)
                        + statusTopInset + statusBottomInset
        Connections {
            target: statusBar.shell.settingsStore
            function onCpuBudgetCyclesChanged(): void { statusBar.shell.cpuMeter.poll() }
        }
        color: statusBar.shell.session.palette.windowBackground
        Text {
            objectName: "shellStatusText"
            id: shellStatus
            anchors.left: parent.left
            width: Math.max(0, Math.min(implicitWidth, statusBar.showingFailure || statusBar.showingProgress
                ? statusBar.width - (polyMeter.visible ? polyMeter.width : 0)
                  - statusBar.root.chromeSpacing.two * 3
                : statusBar.width / 4 - statusBar.root.chromeSpacing.two))
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: statusBar.statusTopInset
            anchors.bottomMargin: statusBar.statusBottomInset
            anchors.leftMargin: statusBar.root.chromeSpacing.two
            text: !statusBar.shell.sceneActive ? qsTr("Closing…")
                  : statusBar.showingProgress ? statusBar.openingText : statusBar.shell.statusText
            font: statusBar.root.chromeTypography.caption
            color: statusBar.root.colors.windowText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Text {
            objectName: "shellMouseHintText"
            visible: !statusBar.showingFailure && !statusBar.showingProgress
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: statusBar.statusTopInset
            anchors.bottomMargin: statusBar.statusBottomInset
            width: Math.max(0, parent.width - 2 * Math.max(
                shellStatus.width + statusBar.root.chromeSpacing.two * 2,
                polyMeter.visible ? polyMeter.width + statusBar.root.chromeSpacing.two * 2 : 0))
            text: statusBar.shell.mouseHints.text
            textFormat: Text.PlainText
            font: statusBar.root.chromeTypography.caption
            color: statusBar.root.colors.windowText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Row {
            id: polyMeter
            objectName: "shellPolyMeter"
            anchors.right: parent.right
            anchors.rightMargin: statusBar.root.chromeSpacing.two
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (statusBar.statusTopInset - statusBar.statusBottomInset) / 2
            spacing: statusBar.bodyMetrics.advanceWidth(" ") / 2
            visible: polyMeter.presenter.polyMeterVisible
            final readonly property TransportBarPresenter presenter: statusBar.shell.session.transportBarPresenter()
            Text {
                id: cpuValue
                objectName: "shellCpuValue"
                readonly property CpuMeterPresenter cpu: statusBar.shell.cpuMeter
                text: cpu.valid ? qsTr("CPU %1%").arg(cpu.percent) : qsTr("CPU --")
                color: !cpu.valid ? statusBar.root.colors.windowText
                     : cpu.level === 2 ? statusBar.root.colors.errorText
                     : cpu.level === 1 ? statusBar.root.colors.warningText : statusBar.root.colors.windowText
                font: statusBar.root.chromeTypography.body
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Open GBA CPU meter")
                Accessible.onPressAction: statusBar.shell.activate("view.cpu_meter")
                Keys.onReturnPressed: statusBar.shell.activate("view.cpu_meter")
                Keys.onEnterPressed: statusBar.shell.activate("view.cpu_meter")
                ToolTip.visible: cpuHover.containsMouse
                ToolTip.text: cpu.valid
                    ? qsTr("Estimated m4aSoundMain: %1 cycles (%2% of VBlank)\nSequencer: %3 cycles (estimated)\nCGB: %4 cycles\nMixer: %5 cycles\nBudget: %6 cycles · VBlank: 83,776 · whole frame: 280,896\nClick to open CPU panel")
                        .arg(cpu.total).arg(cpu.percent).arg(cpu.sequencer).arg(cpu.cgb).arg(cpu.mixer).arg(cpu.budget)
                    : qsTr("Estimated GBA sound-driver cost, not host CPU. Click to open CPU panel.")
                MouseArea {
                    id: cpuHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: statusBar.shell.activate("view.cpu_meter")
                }
            }
            Text {
                text: "·"
                color: statusBar.root.colors.windowText
                font: statusBar.root.chromeTypography.body
            }
            Text {
                objectName: "shellPolyPcmCaption"
                text: qsTr("PCM")
                font: statusBar.root.chromeTypography.body
                color: statusBar.root.colors.windowText
            }
            Rectangle {
                implicitWidth: pcmValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: statusBar.bodyMetrics.height
                color: statusBar.root.colors.polyphonyValueBackground
                Text {
                    id: pcmValue
                    objectName: "shellPolyPcmValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.pcmText
                    font: statusBar.root.chromeTypography.bodyMono
                    color: statusBar.root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                text: "·"
                color: statusBar.root.colors.windowText
                font: statusBar.root.chromeTypography.body
            }
            Text {
                objectName: "shellPolyCgbCaption"
                text: qsTr("CGB")
                color: statusBar.root.colors.windowText
                font: statusBar.root.chromeTypography.body
            }
            Rectangle {
                implicitWidth: cgbValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: statusBar.bodyMetrics.height
                color: statusBar.root.colors.polyphonyValueBackground
                Text {
                    id: cgbValue
                    objectName: "shellPolyCgbValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.cgbText
                    font: statusBar.root.chromeTypography.bodyMono
                    color: statusBar.root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: "·"
                color: statusBar.root.colors.windowText
                font: statusBar.root.chromeTypography.body
            }
            Rectangle {
                visible: polyMeter.presenter.lostVisible
                implicitWidth: lostValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: statusBar.bodyMetrics.height
                color: statusBar.root.colors.polyphonyValueBackground
                Text {
                    id: lostValue
                    objectName: "shellPolyLostValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.lostText
                    color: statusBar.root.colors.polyphonyValueText
                    font: statusBar.root.chromeTypography.body
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: qsTr("notes lost")
                font: statusBar.root.chromeTypography.body
                color: statusBar.root.colors.windowText
            }
        }
}
