// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    width: 420;
    height: 560;
    visible: true
    required property var chatModel

    ListView {
        id: chat
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: userInput.top
        model: chatModel.msgs
        spacing: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        onCountChanged: positionViewAtEnd()

        delegate: Item {
            width: chat.width
            readonly property real bubbleMax: chat.width * 0.75

            required property string author
            required property string date
            required property string textmessage
            required property var model

            property bool fromUser: author === "Me"
            property bool editing: false
            implicitHeight: authorName.implicitHeight + bubble.implicitHeight + dateLabel.implicitHeight + 14

            Column {
                anchors.margins: 8
                anchors.right: fromUser ? parent.right : undefined
                anchors.left:  fromUser ? undefined    : parent.left
                spacing: 2

                Text {
                    id: authorName
                    text: author
                    font.pixelSize: 12
                    color: fromUser ? "#3a7be0" : "#606060"
                    horizontalAlignment: fromUser ? Text.AlignRight : Text.AlignLeft
                    width: bubble.implicitWidth
                }

                Rectangle {
                    id: bubble
                    radius: 18
                    color: fromUser ? "#007aff" : "#e5e5ea"
                    property real maxW: bubbleMax
                    implicitWidth:  Math.min(contentItem.implicitWidth + 20, maxW)
                    implicitHeight: contentItem.implicitHeight + 20

                    Loader {
                        id: contentItem
                        anchors.fill: parent
                        anchors.margins: 10
                        sourceComponent: editing && fromUser ? editorComponent : textComponent
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        gesturePolicy: TapHandler.WithinBounds
                        onDoubleTapped: if (fromUser) editing = true
                    }
                }

                Text {
                    id: dateLabel
                    text: date
                    visible: date.length
                    font.pixelSize: 10
                    color: fromUser ? "#3a7be0" : "#606060"
                    horizontalAlignment: fromUser ? Text.AlignRight : Text.AlignLeft
                    width: bubble.implicitWidth
                }
            }

            Component {
                id: textComponent
                Text {
                    text: textmessage
                    wrapMode: Text.Wrap
                    font.pixelSize: 16
                    color: fromUser ? "white" : "black"
                    width: Math.min(implicitWidth, bubbleMax - 20)
                }
            }
            Component {
                id: editorComponent
                TextField {
                    text: textmessage
                    font.pixelSize: 16
                    selectByMouse: true
                    focus: true
                    function commitEdit() {
                        model.textmessage = text
                        editing = false
                    }
                    onAccepted: commitEdit()
                    Keys.onEscapePressed: editing = false
                    onActiveFocusChanged: if (!activeFocus && editing) commitEdit()
                }
            }
        }
    }

    Rectangle {
        id: userInput
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 56
        color: "#f7f7f8"
        border.color: "#e0e0e0"
        z: 10

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Rectangle {
                id: inputFrame
                radius: 18
                color: "white"
                border.color: "#d0d0d0"

                implicitHeight: input.implicitHeight + 18
                implicitWidth: 220

                TextField {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10

                    background: null
                    color: "black"
                    Layout.fillWidth: true
                    font.pixelSize: 16
                    onAccepted: sendBtn.clicked()
                }
            }

            Button {
                id: sendBtn
                text: "Send"
                implicitWidth: 80
                palette.buttonText: "black"
                enabled: input.text.length > 0
                onClicked: {
                    chatModel.insertReply("Me", input.text, Qt.formatDateTime(new Date(), "hh:mm"))
                    input.text = ""
                }
            }

            Button {
                id: clearBtn
                text: "Clear"
                implicitWidth: 80
                palette.buttonText: "black"
                onClicked: chatModel.clearMessages()
            }
        }
    }
}
