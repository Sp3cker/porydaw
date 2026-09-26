import QtQuick
import QtQuick.Controls.impl as QtControlsImpl
import QtQuick.Layouts
import Porydaw.Ui

Rectangle {
    id: control
    required property QtObject colors
    required property string label
    required property string symbol
    // A tinted SVG replaces the text symbol when set.
    property url iconSource: ""
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
        visible: control.iconSource.toString().length === 0
        text: control.symbol
        font.pixelSize: Math.min(Math.round(control.baseFontPx * 1.4),
                                 Math.round(control.width / (Math.max(1, control.symbol.length) * 0.65)))
        color: control.foreground
        renderType: Text.NativeRendering
    }
    readonly property color foreground: actionable ? (checked ? colors.buttonPressedText
                                                              : colors.buttonText)
                                                   : colors.disabledText
    QtControlsImpl.IconImage {
        id: icon
        anchors.centerIn: parent
        height: Math.round(Math.min(control.baseFontPx, 12) * 1.9)
        width: height
        sourceSize: Qt.size(width, height)
        source: control.iconSource
        color: control.foreground
        visible: !glyph.visible
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
