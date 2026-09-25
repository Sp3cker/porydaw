import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    width: 250
    height: 200
    visible: true
    title: "Hello from Qt Bridges!"

    required property var ___VARIABLE_modelContextName:identifier___

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Text {
            id: output
            opacity: 0
            text: ___VARIABLE_modelContextName:identifier___.greeting
            color: "green"
            font.pixelSize: 22
            font.bold: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        TextField {
            id: nameField
            placeholderText: "What is your name?"
            text: ___VARIABLE_modelContextName:identifier___.name
            onTextChanged: ___VARIABLE_modelContextName:identifier___.name = text
            Layout.fillWidth: true
            onAccepted: greetBtn.clicked()
        }

        Button {
            id: greetBtn
            text: "Greet"
            Layout.preferredHeight: 40
            Layout.preferredWidth: 120
            font.pixelSize: 18
            onClicked: {
                ___VARIABLE_modelContextName:identifier___.greet()
                output.opacity = 1
            }
            Layout.alignment: Qt.AlignCenter
        }
    }
}
