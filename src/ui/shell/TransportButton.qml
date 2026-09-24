import QtQuick
import QtQuick.Layouts

Rectangle {
    id: control
    required property QtObject colors
    required property string label
    required property string symbol
    required property int baseFontPx
    property bool checked: false
    property bool actionable: true
    signal activated()

    objectName: "transportButton"
    width: Math.round(Math.min(baseFontPx, 12) * 2.75)
    height: width
    Layout.minimumWidth: Math.round(Math.min(baseFontPx, 12) * 2.75)
    Layout.maximumWidth: Layout.minimumWidth
    radius: glyph.font.pixelSize / 6
    color: checked ? colors.buttonPressedBackground
           : hover.hovered ? colors.buttonHoverBackground : "transparent"
    enabled: actionable
    focus: false
    activeFocusOnTab: actionable
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: checked ? qsTr("On") : qsTr("Off")

    Text {
        id: glyph
        anchors.centerIn: parent
        text: control.symbol
        font.pixelSize: Math.min(Math.round(control.baseFontPx * 1.4),
                                 Math.round(control.width / (Math.max(1, control.symbol.length) * 0.65)))
        color: control.actionable ? (control.checked ? control.colors.buttonPressedText
                                                      : control.colors.buttonText)
                                  : control.colors.disabledText
        renderType: Text.NativeRendering
    }
    HoverHandler { id: hover }
    TapHandler {
        enabled: control.actionable
        onTapped: control.activated()
    }
    Keys.onReturnPressed: event => {
        if (control.actionable) { control.activated(); event.accepted = true }
    }
    Keys.onEnterPressed: event => {
        if (control.actionable) { control.activated(); event.accepted = true }
    }
}
