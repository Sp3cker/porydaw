import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import Porydaw.Ui

Item {
    id: panel
    objectName: "polyphonyPanel"
    required property var presenter
    required property var colors
    required property font applicationFont
    readonly property font boldFont: Qt.font({
        family: applicationFont.family, pixelSize: applicationFont.pixelSize, weight: Font.Bold
    })
    readonly property font headerFont: Qt.font({
        family: applicationFont.family, pixelSize: applicationFont.pixelSize, weight: Font.DemiBold
    })
    readonly property real em: Math.max(1, applicationFont.pixelSize)
    readonly property real gap: Math.round(em / 2)
    readonly property bool wideLayout: width >= em * 50
    readonly property real margin: Math.round(em * 8 / 12)
    readonly property real contentWidth: width - 2 * margin
    readonly property real headingHeight: Math.round(em * 1.5)

    Rectangle { anchors.fill: parent; color: panel.colors.windowBackground }

    Flickable {
        id: scroll
        objectName: "polyphonyScroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.height + 2 * panel.margin
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: Basic.ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: content
            x: panel.margin
            y: panel.margin
            width: panel.contentWidth
            height: Math.max(scroll.height - 2 * panel.margin, log.y + log.height)

            Basic.CheckBox {
                id: invert
                objectName: "polyphonyInvert"
                x: 0
                y: 0
                width: parent.width
                height: panel.headingHeight
                text: qsTr("Solo overflow (invert audio)")
                checked: panel.presenter.invertChecked
                font: panel.applicationFont
                palette.windowText: panel.colors.windowText
                ToolTip.text: qsTr("Mutes normal playback and makes ONLY the sounds lost to the polyphony limit audible.")
                ToolTip.visible: hovered
                onClicked: panel.presenter.setInvertChecked(checked)
            }

            Item {
                id: sections
                y: invert.y + invert.height + panel.gap
                width: parent.width
                height: panel.wideLayout ? Math.max(usage.height, overflow.height)
                    : usage.height + panel.gap + overflow.height

                Item {
                    id: usage
                    objectName: "polyphonyUsageSection"
                    width: panel.wideLayout ? sections.width - overflow.width - panel.gap : sections.width
                    height: usageLabel.height + panel.gap + grid.height
                    Text {
                        id: usageLabel
                        objectName: "polyphonyUsageHeading"
                        text: qsTr("Channel usage")
                        width: parent.width
                        height: panel.headingHeight
                        font: panel.boldFont
                        color: panel.colors.windowText
                    }
                    Column {
                        id: grid
                        y: usageLabel.height + panel.gap
                        width: parent.width
                        spacing: 0
                        PolyphonyChannelGroup {
                            width: parent.width
                            caption: qsTr("PCM")
                            channels: panel.presenter.pcm
                            colors: panel.colors
                            em: panel.em
                        }
                        PolyphonyChannelGroup {
                            width: parent.width
                            caption: qsTr("CGB")
                            channels: panel.presenter.cgb
                            colors: panel.colors
                            em: panel.em
                        }
                        Text {
                            width: parent.width
                            height: panel.headingHeight
                            visible: panel.presenter.showingShadow
                            text: qsTr("Lost sounds currently playing (solo overflow):")
                            color: panel.colors.secondaryText
                            font: panel.applicationFont
                        }
                        PolyphonyChannelGroup {
                            width: parent.width
                            visible: panel.presenter.showingShadow
                            caption: qsTr("PCM")
                            channels: panel.presenter.shadowPcm
                            colors: panel.colors
                            em: panel.em
                        }
                        PolyphonyChannelGroup {
                            width: parent.width
                            visible: panel.presenter.showingShadow
                            caption: qsTr("CGB")
                            channels: panel.presenter.shadowCgb
                            colors: panel.colors
                            em: panel.em
                        }
                    }
                }

                Item {
                    id: overflow
                    objectName: "polyphonyOverflowSection"
                    x: panel.wideLayout ? sections.width - width : 0
                    y: panel.wideLayout ? 0 : usage.height + panel.gap
                    width: panel.wideLayout ? Math.round(panel.em * 320 / 12) : sections.width
                    height: table.y + table.height
                    Text {
                        id: overflowLabel
                        objectName: "polyphonyOverflowHeading"
                        width: Math.min(implicitWidth + panel.em,
                                        parent.width - resetButton.width - panel.gap)
                        height: panel.headingHeight
                        text: qsTr("Overflow by track")
                        font: panel.boldFont
                        color: panel.colors.windowText
                    }
                    Basic.Button {
                        id: resetButton
                        objectName: "polyphonyReset"
                        anchors.right: parent.right
                        height: panel.headingHeight
                        text: qsTr("Reset")
                        font: panel.applicationFont
                        leftPadding: panel.gap
                        rightPadding: panel.gap
                        topPadding: 0
                        bottomPadding: 0
                        onClicked: panel.presenter.reset()
                    }
                    Rectangle {
                        id: table
                        objectName: "polyphonyOverflowTable"
                        y: overflowLabel.height + panel.gap
                        width: parent.width
                        height: panel.wideLayout ? Math.max(panel.em * 90 / 12, usage.height - y)
                            : Math.max(Math.round(panel.em * 90 / 12),
                                       header.height + rows.height + panel.em / 2)
                        color: panel.colors.buttonBackground
                        border.color: panel.colors.outline
                        border.width: 1
                        // The widget stretches Track after three numeric ResizeToContents sections.
                        readonly property real trackWidth: Math.max(panel.em * 6,
                            width - Math.round(panel.em * 187 / 12))
                        Rectangle {
                            id: header
                            x: 1; y: 1
                            width: parent.width - 2
                            height: Math.round(panel.em * 22 / 12)
                            color: panel.colors.menuBackground
                            Row {
                                anchors.fill: parent
                                Repeater {
                                    model: [qsTr("Track"), qsTr("Dropped"), qsTr("Cut Off"), qsTr("Tail Cut")]
                                    delegate: Text {
                                        required property string modelData
                                        required property int index
                                        width: index === 0 ? table.trackWidth : (header.width - table.trackWidth) / 3
                                        height: header.height
                                        text: modelData
                                        font: panel.headerFont
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        color: panel.colors.windowText
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        Column {
                            id: rows
                            y: header.y + header.height
                            width: parent.width - 2
                            Repeater {
                                model: panel.presenter.counters
                                delegate: Rectangle {
                                    id: counterRow
                                    required property int index
                                    required property string name
                                    required property int dropped
                                    required property int cutOff
                                    required property int tailCut
                                    required property bool flash
                                    width: rows.width
                                    height: Math.round(panel.em * 30 / 12)
                                    color: flash ? panel.colors.polyphonyFlashBackground : panel.colors.buttonBackground
                                    border.color: panel.colors.outline
                                    border.width: 0.5
                                    Row {
                                        anchors.fill: parent
                                        Repeater {
                                            model: [name, String(dropped), String(cutOff), String(tailCut)]
                                            delegate: Rectangle {
                                                required property string modelData
                                                required property int index
                                                objectName: index === 0
                                                    ? "polyphonyOverflowRow_" + counterRow.index : ""
                                                width: index === 0 ? table.trackWidth : (rows.width - table.trackWidth) / 3
                                                height: parent.height
                                                color: "transparent"
                                                border.color: panel.colors.outline
                                                border.width: 0.5
                                                Text {
                                                    anchors.fill: parent
                                                    leftPadding: panel.em / 4
                                                    text: parent.modelData
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                    color: counterRow.flash ? panel.colors.polyphonyFlashText : panel.colors.windowText
                                                    font: panel.applicationFont
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        objectName: "polyphonyEmpty"
                        anchors.centerIn: table
                        visible: panel.presenter.counterCount === 0
                        text: qsTr("No overflow recorded")
                        font: panel.applicationFont
                        color: panel.colors.secondaryText
                    }
                }
            }

            Text {
                id: logHeading
                objectName: "polyphonyLogHeading"
                y: sections.y + sections.height + panel.gap
                width: parent.width
                height: panel.headingHeight
                text: qsTr("Recent events")
                font: panel.boldFont
                color: panel.colors.windowText
            }
            Rectangle {
                id: log
                objectName: "polyphonyEventLog"
                y: logHeading.y + logHeading.height + panel.gap / 2
                width: parent.width
                height: Math.max(panel.em * 4, scroll.height - panel.margin - y)
                color: panel.colors.buttonBackground
                border.color: panel.colors.outline
                border.width: 1
                ListView {
                    id: list
                    objectName: "polyphonyEventRows"
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    model: panel.presenter.events
                    delegate: Item {
                        id: eventRow
                        required property string text
                        required property int kind
                        required property int index
                        objectName: "polyphonyEventRow_" + index
                        width: list.width
                        height: panel.em * 14 / 12
                        Text {
                            anchors.fill: parent
                            text: eventRow.text
                            font: panel.applicationFont
                            color: eventRow.kind === 0 ? panel.colors.errorText
                                : eventRow.kind === 1 ? panel.colors.warningText : panel.colors.secondaryText
                            elide: Text.ElideRight
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: panel.presenter.activateEvent(eventRow.index, panel.Screen.devicePixelRatio)
                        }
                    }
                }
            }
        }
    }
}
