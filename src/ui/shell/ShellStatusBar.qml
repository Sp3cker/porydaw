pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp

Rectangle {
    id: statusBar
    required property var root
    required property var shell
    required property var bodyMetrics
    required property var captionMetrics
        readonly property int statusTopInset: 3
        readonly property int statusBottomInset: 2
        readonly property int statusGripHeight: 13 + 4
        readonly property bool showingFailure: statusBar.shell.session.lastSaveError.length > 0
                                                && statusBar.shell.statusText === statusBar.shell.session.lastSaveError
        implicitHeight: Math.max(statusBar.captionMetrics.height, statusBar.bodyMetrics.height, statusGripHeight)
                        + statusTopInset + statusBottomInset
        color: statusBar.shell.session.palette.windowBackground
        Text {
            objectName: "shellStatusText"
            id: shellStatus
            anchors.left: parent.left
            width: Math.max(0, Math.min(implicitWidth, statusBar.showingFailure
                ? statusBar.width - (polyMeter.visible ? polyMeter.width : 0)
                  - statusBar.root.chromeSpacing.two * 3
                : statusBar.width / 4 - statusBar.root.chromeSpacing.two))
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: statusBar.statusTopInset
            anchors.bottomMargin: statusBar.statusBottomInset
            anchors.leftMargin: statusBar.root.chromeSpacing.two
            text: statusBar.shell.sceneActive ? statusBar.shell.statusText : qsTr("Closing…")
            font: Qt.font(statusBar.root.chromeTypography.caption)
            color: statusBar.root.colors.windowText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Text {
            objectName: "shellMouseHintText"
            visible: !statusBar.showingFailure
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
            font: Qt.font(statusBar.root.chromeTypography.caption)
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
            readonly property TransportBarPresenter presenter: statusBar.shell.session.transportBarPresenter()
            Text {
                objectName: "shellPolyPcmCaption"
                text: qsTr("PCM")
                font: Qt.font(statusBar.root.chromeTypography.body)
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
                    font: Qt.font(statusBar.root.chromeTypography.bodyMono)
                    color: statusBar.root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                text: "·"
                color: statusBar.root.colors.windowText
                font: Qt.font(statusBar.root.chromeTypography.body)
            }
            Text {
                objectName: "shellPolyCgbCaption"
                text: qsTr("CGB")
                color: statusBar.root.colors.windowText
                font: Qt.font(statusBar.root.chromeTypography.body)
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
                    font: Qt.font(statusBar.root.chromeTypography.bodyMono)
                    color: statusBar.root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: "·"
                color: statusBar.root.colors.windowText
                font: Qt.font(statusBar.root.chromeTypography.body)
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
                    font: Qt.font(statusBar.root.chromeTypography.body)
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: qsTr("notes lost")
                font: Qt.font(statusBar.root.chromeTypography.body)
                color: statusBar.root.colors.windowText
            }
        }
}
