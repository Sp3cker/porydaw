// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQml.Models

ApplicationWindow {
    id: root

    required property QtObject listModel

    Timer {
        id: clearStatusTimer
        interval: 1500
        onTriggered: statusDisplay.text = ""
    }

    Connections {
        target: listModel
        function onDuplicateStringFoundChanged() {
            statusDisplay.text = `List already contains entry ${listModel.duplicateStringFound}!`
            clearStatusTimer.restart();
        }
    }

    width: 640
    height: 480
    visible: true
    title: qsTr("Minimal QML app")
    // ### NOTE : editing should ideally use a Validator; but that's out of scope
    ColumnLayout {
        id: mainLayout
        anchors.fill: parent
        ListView {
            id: lv
            model: listModel.list
            delegate: Control {
                id: ld
                required property var modelData
                required property int index
                width: lv.width
                implicitHeight: Math.max(textLabel.implicitHeight, deleteButton.implicitHeight)
                RowLayout {
                    anchors.fill: parent
                    Label {
                        property bool inEditMode: false
                        id: textLabel
                        text: inEditMode ? "" : `Item ${ld.index+1}: ${ld.modelData}`
                        Layout.fillWidth: true
                        TextInput {
                            id: editField
                            visible: textLabel.inEditMode
                            anchors.fill: parent
                            onEditingFinished: {
                                textLabel.inEditMode = false
                            }
                            onAccepted: {
                                listModel.editString(ld.index, text)
                            }
                        }
                    }
                    RoundButton {
                        text: "✏️"
                        down: textLabel.inEditMode || pressed
                        onReleased: () => {
                            if (textLabel.inEditMode) {
                                textLabel.inEditMode = false
                            } else {
                                editField.text = `${ld.modelData}`
                                textLabel.inEditMode = true
                                editField.forceActiveFocus()
                                editField.selectAll()
                            }
                        }
                    }
                    RoundButton {
                        id: deleteButton
                        text: "🗑️" // could use icons if we could ensure we have them
                        onReleased: () => { listModel.removeString(ld.index) }
                    }
                }
            }
            Layout.fillHeight: true
            Layout.preferredWidth: mainLayout.width
        }

        RowLayout {
            implicitHeight: Math.max(input.implicitHeight, submitButton.implicitHeight)
            TextField {
                id: input
                placeholderText: "Enter string to add"

                function submit() {
                    listModel.addString(input.text)
                    input.clear()
                }

                onAccepted: submit()
                Layout.preferredWidth: mainLayout.width * 0.8
            }
            Button {
                id: submitButton
                text: "Add text"
                enabled: input.text !== ""
                onReleased: input.submit()
            }
        }
    }

    footer: Text {
        id: statusDisplay
    }
}
