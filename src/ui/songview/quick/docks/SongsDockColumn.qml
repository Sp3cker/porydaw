import QtQuick
import QtQuick.Controls

SplitView {
    id: dock
    objectName: "swiftDockColumn"
    orientation: Qt.Vertical
    required property var controller
    required property var colors
    required property font applicationFont
    required property real baseFontPx

    SongsPanel {
        objectName: "swiftSongsPanel"
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        controller: dock.controller
        colors: dock.colors
        applicationFont: dock.applicationFont
        baseFontPx: dock.baseFontPx
    }
}
