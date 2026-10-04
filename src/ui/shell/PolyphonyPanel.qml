pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp

Item {
    id: panel
    objectName: "polyphonyPanel"
    required property PolyphonyPanelPresenter presenter
    required property var colors
    required property var typography
    required property var layoutSpaces
    required property real baseFontPx
    readonly property real em: baseFontPx
    readonly property real gap: layoutSpaces.two
    readonly property bool wideLayout: width >= em * 50
    readonly property real margin: Math.round(em * 8 / 12)
    readonly property real contentWidth: width - 2 * margin
    readonly property real headingHeight: Math.round(em * 1.5)
    // Measured layout results; section rects share the sections item's coordinate space.
    readonly property rect usageSectionRect: Qt.rect(usage.x, usage.y, usage.width, usage.height)
    readonly property rect overflowSectionRect: Qt.rect(overflow.x, overflow.y,
                                                        overflow.width, overflow.height)
    readonly property bool gridFullyVisible: grid.width > 0
        && grid.height >= grid.implicitHeight
        && grid.y + grid.height <= usage.height
        && content.x + usage.x + grid.width <= scroll.width
        && content.y + sections.y + usage.y + usage.height <= scroll.contentHeight
    readonly property real vScrollRange: Math.max(0, scroll.contentHeight - scroll.height)

    Rectangle { anchors.fill: parent; color: panel.colors.windowBackground }

    Flickable {
        id: scroll
        objectName: "polyphonyScroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.height + 2 * panel.margin
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: content
            x: panel.margin
            y: panel.margin
            width: panel.contentWidth
            height: Math.max(scroll.height - 2 * panel.margin, log.y + log.height)

            CheckBox {
                id: invert
                objectName: "polyphonyInvert"
                x: 0
                y: 0
                width: content.width
                height: panel.headingHeight
                text: qsTr("Solo overflow (invert audio)")
                checked: panel.presenter.invertChecked
                font: Qt.font(panel.typography.body)
                palette.windowText: panel.colors.windowText
                ToolTip.text: qsTr("Mutes normal playback and makes ONLY the sounds lost to the polyphony limit audible.")
                ToolTip.visible: hovered
                onClicked: panel.presenter.setInvertChecked(checked)
            }

            Item {
                id: sections
                y: invert.y + invert.height + panel.gap
                width: content.width
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
                        width: usage.width
                        height: panel.headingHeight
                        font: Qt.font(panel.typography.bodyBold)
                        color: panel.colors.windowText
                    }
                    Column {
                        id: grid
                        y: usageLabel.height + panel.gap
                        width: usage.width
                        spacing: 0
                        PolyphonyChannelGroup {
                            width: grid.width
                            caption: qsTr("PCM")
                            channels: panel.presenter.pcm
                            colors: panel.colors
                            em: panel.em
                            typography: panel.typography
                        }
                        PolyphonyChannelGroup {
                            width: grid.width
                            caption: qsTr("CGB")
                            channels: panel.presenter.cgb
                            colors: panel.colors
                            em: panel.em
                            typography: panel.typography
                        }
                        Text {
                            objectName: "polyphonyShadowNotice"
                            width: grid.width
                            height: panel.headingHeight
                            visible: panel.presenter.showingShadow
                            text: qsTr("Lost sounds currently playing (solo overflow):")
                            color: panel.colors.secondaryText
                            font: Qt.font(panel.typography.body)
                        }
                        PolyphonyChannelGroup {
                            width: grid.width
                            visible: panel.presenter.showingShadow
                            caption: qsTr("PCM")
                            channels: panel.presenter.shadowPcm
                            colors: panel.colors
                            em: panel.em
                            typography: panel.typography
                        }
                        PolyphonyChannelGroup {
                            width: grid.width
                            visible: panel.presenter.showingShadow
                            caption: qsTr("CGB")
                            channels: panel.presenter.shadowCgb
                            colors: panel.colors
                            em: panel.em
                            typography: panel.typography
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
                                        overflow.width - resetButton.width - panel.gap)
                        height: panel.headingHeight
                        text: qsTr("Overflow by track")
                        font: Qt.font(panel.typography.bodyBold)
                        color: panel.colors.windowText
                    }
                    Button {
                        id: resetButton
                        objectName: "polyphonyReset"
                        anchors.right: parent.right
                        height: panel.headingHeight
                        text: qsTr("Reset")
                        font: Qt.font(panel.typography.body)
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
                        width: overflow.width
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
                            width: table.width - 2
                            height: Math.round(panel.em * 22 / 12)
                            color: panel.colors.menuBackground
                            Row {
                                anchors.fill: parent
                                Repeater {
                                    readonly property list<string> labels: [qsTr("Track"), qsTr("Dropped"), qsTr("Cut Off"), qsTr("Tail Cut")]
                                    model: labels
                                    delegate: Text {
                                        objectName: "polyphonyTableHeader"
                                        required property string modelData
                                        required property int index
                                        width: index === 0 ? table.trackWidth : (header.width - table.trackWidth) / 3
                                        height: header.height
                                        text: modelData
                                        font: Qt.font(panel.typography.body)
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
                            width: table.width - 2
                            Repeater {
                                model: panel.presenter.counters
                                delegate: Rectangle {
                                    id: counterRow
                                    required property int index
                                    required property string name
                                    required property int dropped
                                    required property int cutOff
                                    required property int tailCut
                                    required property real flashAlpha
                                    width: rows.width
                                    height: Math.round(panel.em * 30 / 12)
                                    color: panel.colors.buttonBackground
                                    border.color: panel.colors.outline
                                    border.width: 0.5
                                    Rectangle {
                                        objectName: "polyphonyFlashOverlay"
                                        anchors.fill: parent
                                        color: panel.colors.polyphonyFlashBackground
                                        opacity: counterRow.flashAlpha
                                    }
                                    Row {
                                        anchors.fill: parent
                                        Repeater {
                                            readonly property list<string> values: [counterRow.name, String(counterRow.dropped), String(counterRow.cutOff), String(counterRow.tailCut)]
                                            model: values
                                            delegate: Rectangle {
                                                id: counterCell
                                                required property string modelData
                                                required property int index
                                                objectName: index === 0
                                                    ? "polyphonyOverflowRow_" + counterRow.index : ""
                                                width: index === 0 ? table.trackWidth : (rows.width - table.trackWidth) / 3
                                                height: counterRow.height
                                                color: "transparent"
                                                border.color: panel.colors.outline
                                                border.width: 0.5
                                                Text {
                                                    objectName: "polyphonyCounterText"
                                                    anchors.fill: parent
                                                    leftPadding: panel.em / 4
                                                    text: counterCell.modelData
                                                    elide: Text.ElideRight
                                                    font: Qt.font(panel.typography.body)
                                                    verticalAlignment: Text.AlignVCenter
                                                    color: panel.colors.windowText
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
                        font: Qt.font(panel.typography.body)
                        color: panel.colors.secondaryText
                    }
                }
            }

            Text {
                id: logHeading
                objectName: "polyphonyLogHeading"
                y: sections.y + sections.height + panel.gap
                width: content.width
                height: panel.headingHeight
                text: qsTr("Recent events")
                font: Qt.font(panel.typography.bodyBold)
                color: panel.colors.windowText
            }
            Rectangle {
                id: log
                objectName: "polyphonyEventLog"
                y: logHeading.y + logHeading.height + panel.gap / 2
                width: content.width
                height: Math.max(panel.em * 4, scroll.height - 2 * panel.margin - y)
                color: panel.colors.buttonBackground
                border.color: panel.colors.outline
                border.width: 1
                HoverHandler { id: logHover }
                ToolTip.text: qsTr("Double-click an event to jump to its position.")
                ToolTip.visible: logHover.hovered
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
                            font: Qt.font(panel.typography.body)
                            color: eventRow.kind === 0 ? panel.colors.errorText
                                : eventRow.kind === 1 ? panel.colors.warningText : panel.colors.secondaryText
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onDoubleClicked: panel.presenter.activateEvent(eventRow.index,
                                                                            panel.Screen.devicePixelRatio)
                        }
                    }
                }
            }
        }
    }
}
