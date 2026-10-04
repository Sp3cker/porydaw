pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: appearance

    final property color background: "transparent"
    final property color outline: "transparent"
    final property color text: "transparent"
    final property color hoverBackground: "transparent"
    final property color hoverText: appearance.text
    final property color pressedBackground: appearance.hoverBackground
    final property color pressedText: appearance.hoverText
    final property color disabledText: appearance.text
    final property color separator: "transparent"
    final property font font
}
