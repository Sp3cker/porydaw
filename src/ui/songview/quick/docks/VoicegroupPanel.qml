pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Porydaw.Ui

ColumnLayout {
    id: panel
    objectName: "voicegroupPanel"
    required property QtObject applicationSession
    required property QtObject controller
    readonly property QtObject colors: applicationSession.palette
    readonly property real baseFontPx: applicationSession.baseFontPx
    readonly property int rowHeight: Math.round(baseFontPx * 1.33)
    readonly property int headerHeight: Math.round(baseFontPx * 1.83)
    readonly property int typeWidth: Math.round(baseFontPx * 3.75)
    readonly property int adsrWidth: Math.round(baseFontPx * 8.33)
    readonly property var iconNames: ["waveform.svg", "waveform.svg",
                                      "wave-square.svg", "wave-triangle.svg",
                                      "wave-sine.svg", "waveform-path.svg",
                                      "piano-keyboard.svg", "drum.svg"]
    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: panel.baseFontPx * 2.17
        Layout.leftMargin: Math.round(panel.baseFontPx * 0.33)
        Layout.rightMargin: Math.round(panel.baseFontPx * 0.33)
        spacing: Math.round(panel.baseFontPx * 0.16)
        Label {
            text: qsTr("voicegroup_")
            Layout.preferredWidth: Math.round(panel.baseFontPx * 6.08)
            color: panel.colors.primaryText
        }
        ComboBox {
            id: selector
            objectName: "vgArgCombo"
            Layout.fillWidth: true
            Layout.preferredHeight: panel.baseFontPx * 1.83
            editable: true
            enabled: panel.controller.selectorEnabled
            model: panel.controller.argChoices
            textRole: "name"
            editText: panel.controller.selectorText
            onActivated: {
                panel.controller.selectorText = editText
                panel.controller.commitVoicegroupSelection()
            }
            onAccepted: {
                panel.controller.selectorText = editText
                panel.controller.commitVoicegroupSelection()
            }
            ToolTip.text: qsTr("The song's voicegroup (-G). Changing it is undoable.")
            ToolTip.visible: hovered
        }
    }

    Rectangle {
        id: tree
        objectName: "voicegroupTree"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: panel.rowHeight * 3
        color: panel.colors.windowBackground
        border.width: 1
        border.color: panel.colors.outline

        Rectangle {
            id: treeHeader
            objectName: "voicegroupTreeHeader"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            anchors.rightMargin: Math.round(panel.baseFontPx * 0.58)
            height: panel.headerHeight
            color: panel.colors.chromeBackground
            RowLayout {
                anchors.fill: parent
                spacing: 0
                Label {
                    text: qsTr("Voice")
                    objectName: "voicegroupVoiceHeader"
                    Layout.fillWidth: true
                    Layout.leftMargin: panel.applicationSession.layoutSpaces.one
                    color: panel.colors.primaryText
                }
                Label {
                    text: qsTr("Type")
                    objectName: "voicegroupTypeHeader"
                    Layout.preferredWidth: panel.typeWidth
                    color: panel.colors.primaryText
                }
                Label {
                    text: qsTr("ADSR")
                    objectName: "voicegroupAdsrHeader"
                    Layout.preferredWidth: panel.adsrWidth
                    color: panel.colors.primaryText
                }
            }
        }
        Rectangle {
            anchors.left: treeHeader.left
            anchors.right: treeHeader.right
            anchors.top: treeHeader.bottom
            height: 1
            color: panel.colors.outline
        }
        ListView {
            id: voiceList
            objectName: "voicegroupRows"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: treeHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            clip: true
            model: panel.controller.rows
            boundsBehavior: Flickable.StopAtBounds
            // -1 stops the unused highlight animating ~470 ms of frames after each bank load.
            currentIndex: -1
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: row
                required property int slot
                required property string title
                required property string typeName
                required property string adsr
                required property int typeIconKey
                required property bool altChip
                required property bool used
                objectName: "voicegroupRow_" + slot
                width: voiceList.width - Math.round(panel.baseFontPx * 0.67)
                height: panel.rowHeight
                color: panel.controller.currentSlot === slot ? panel.colors.selectionRing
                       : used ? Qt.tint(panel.colors.windowBackground, "#22b4e4ee")
                              : panel.colors.windowBackground
                RowLayout {
                    anchors.fill: parent
                    spacing: 0
                    Label {
                        text: row.title
                        objectName: "voicegroupTitle_" + row.slot
                        Layout.fillWidth: true
                        Layout.leftMargin: panel.applicationSession.layoutSpaces.one
                        color: panel.controller.currentSlot === row.slot ? panel.colors.selectionText
                                                                       : panel.colors.primaryText
                        elide: Text.ElideRight
                    }
                    Item {
                        objectName: "voicegroupTypeIcon_" + row.slot
                        Layout.preferredWidth: panel.typeWidth
                        Layout.fillHeight: true
                        HoverHandler { id: iconHover }
                        Rectangle {
                            anchors.centerIn: parent
                            width: panel.baseFontPx * 1.25
                            height: width
                            radius: height * 0.25
                            color: Qt.tint(panel.colors.windowBackground, "#59666666")
                            visible: row.altChip
                        }
                        Image {
                            id: sourceGlyph
                            anchors.centerIn: parent
                            width: panel.baseFontPx * 1.25
                            height: width
                            sourceSize: Qt.size(width, height)
                            source: row.typeIconKey < 0 ? ""
                                    : "qrc:/porydaw/voiceicons/"
                                      + panel.iconNames[Math.floor(row.typeIconKey / 2)]
                            rotation: Math.floor(row.typeIconKey / 2) === 1 ? 180 : 0
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: sourceGlyph
                            source: sourceGlyph
                            visible: row.typeIconKey >= 0
                            colorization: 1
                            colorizationColor: row.altChip ? panel.colors.windowBackground
                                                           : panel.colors.primaryText
                        }
                        ToolTip.text: row.typeName
                        ToolTip.visible: iconHover.hovered && row.typeName.length > 0
                    }
                    Label {
                        objectName: "voicegroupAdsr_" + row.slot
                        Layout.preferredWidth: panel.adsrWidth
                        text: row.adsr
                        color: panel.controller.currentSlot === row.slot ? panel.colors.selectionText
                                                                       : panel.colors.primaryText
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: {
                        panel.controller.selectSlot(row.slot)
                        panel.controller.pressVoice(row.slot)
                    }
                    onReleased: panel.controller.releaseVoice()
                    onCanceled: panel.controller.releaseVoice()
                }
            }
        }
        Connections {
            target: panel.controller
            function onRevealRequestChanged() {
                voiceList.positionViewAtIndex(panel.controller.revealSlotId, ListView.Contain)
            }
        }
    }

    Flickable {
        id: editorScroll
        objectName: "voiceEditorScrollView"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        Layout.preferredHeight: voiceEditor.Layout.preferredHeight
        Layout.maximumHeight: voiceEditor.Layout.preferredHeight
        Layout.leftMargin: Math.round(panel.baseFontPx * 0.33)
        Layout.rightMargin: Math.round(panel.baseFontPx * 0.25)
        Layout.topMargin: Math.round(panel.baseFontPx * 0.33)
        contentWidth: width
        contentHeight: voiceEditor.Layout.preferredHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        VoiceEditor {
            id: voiceEditor
            objectName: "voicegroupEditorSurface"
            width: editorScroll.width
            height: editorScroll.contentHeight
            controller: panel.controller
            colors: panel.colors
            applicationSession: panel.applicationSession
        }
    }
}
