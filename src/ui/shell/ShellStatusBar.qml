import QtQuick

Rectangle {
    required property var root
    required property var shell
    required property var bodyMetrics
    required property var captionMetrics
        readonly property int statusTopInset: 3
        readonly property int statusBottomInset: 2
        readonly property int statusGripHeight: 13 + 4
        readonly property bool showingFailure: shell.session.lastSaveError.length > 0
                                                && shell.statusText === shell.session.lastSaveError
        implicitHeight: Math.max(captionMetrics.height, bodyMetrics.height, statusGripHeight)
                        + statusTopInset + statusBottomInset
        color: shell.session.palette.windowBackground
        Text {
            objectName: "shellStatusText"
            id: shellStatus
            anchors.left: parent.left
            width: Math.max(0, Math.min(implicitWidth, parent.showingFailure
                ? parent.width - (polyMeter.visible ? polyMeter.width : 0)
                  - root.chromeSpacing.two * 3
                : parent.width / 4 - root.chromeSpacing.two))
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: parent.statusTopInset
            anchors.bottomMargin: parent.statusBottomInset
            anchors.leftMargin: root.chromeSpacing.two
            text: shell.sceneActive ? shell.statusText : qsTr("Closing…")
            font: Qt.font(root.chromeTypography.caption)
            color: root.colors.windowText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Text {
            objectName: "shellMouseHintText"
            visible: !parent.showingFailure
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: parent.statusTopInset
            anchors.bottomMargin: parent.statusBottomInset
            width: Math.max(0, parent.width - 2 * Math.max(
                shellStatus.width + root.chromeSpacing.two * 2,
                polyMeter.visible ? polyMeter.width + root.chromeSpacing.two * 2 : 0))
            text: shell.mouseHints.text
            textFormat: Text.PlainText
            font: Qt.font(root.chromeTypography.caption)
            color: root.colors.windowText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Row {
            id: polyMeter
            objectName: "shellPolyMeter"
            anchors.right: parent.right
            anchors.rightMargin: root.chromeSpacing.two
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: (parent.statusTopInset - parent.statusBottomInset) / 2
            spacing: bodyMetrics.advanceWidth(" ") / 2
            visible: presenter.polyMeterVisible
            readonly property var presenter: shell.session.transportBarPresenter()
            Text {
                objectName: "shellPolyPcmCaption"
                text: qsTr("PCM")
                font: Qt.font(root.chromeTypography.body)
                color: root.colors.windowText
            }
            Rectangle {
                implicitWidth: pcmValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: bodyMetrics.height
                color: root.colors.polyphonyValueBackground
                Text {
                    id: pcmValue
                    objectName: "shellPolyPcmValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.pcmText
                    font: Qt.font(root.chromeTypography.bodyMono)
                    color: root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                text: "·"
                color: root.colors.windowText
                font: Qt.font(root.chromeTypography.body)
            }
            Text {
                objectName: "shellPolyCgbCaption"
                text: qsTr("CGB")
                color: root.colors.windowText
                font: Qt.font(root.chromeTypography.body)
            }
            Rectangle {
                implicitWidth: cgbValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: bodyMetrics.height
                color: root.colors.polyphonyValueBackground
                Text {
                    id: cgbValue
                    objectName: "shellPolyCgbValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.cgbText
                    font: Qt.font(root.chromeTypography.bodyMono)
                    color: root.colors.polyphonyValueText
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: "·"
                color: root.colors.windowText
                font: Qt.font(root.chromeTypography.body)
            }
            Rectangle {
                visible: polyMeter.presenter.lostVisible
                implicitWidth: lostValue.implicitWidth + polyMeter.spacing * 2
                implicitHeight: bodyMetrics.height
                color: root.colors.polyphonyValueBackground
                Text {
                    id: lostValue
                    objectName: "shellPolyLostValue"
                    anchors.fill: parent
                    anchors.leftMargin: polyMeter.spacing
                    anchors.rightMargin: polyMeter.spacing
                    text: polyMeter.presenter.lostText
                    color: root.colors.polyphonyValueText
                    font: Qt.font(root.chromeTypography.body)
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Text {
                visible: polyMeter.presenter.lostVisible
                text: qsTr("notes lost")
                font: Qt.font(root.chromeTypography.body)
                color: root.colors.windowText
            }
        }
}
