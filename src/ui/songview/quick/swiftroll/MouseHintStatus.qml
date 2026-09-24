import QtQuick
import Porydaw.Ui

Rectangle {
    id: root
    objectName: "mouseHintStatus"
    required property QtObject presenter
    required property QtObject statusPalette
    property font applicationFont: Application.font
    color: statusPalette.windowBackground
    implicitHeight: Math.ceil(metrics.height + metrics.height / 2)

    FontMetrics {
        id: metrics
        font: root.applicationFont
    }

    Text {
        objectName: "mouseHintStatusText"
        anchors.fill: parent
        anchors.leftMargin: metrics.height / 2
        anchors.rightMargin: metrics.height / 2
        font: root.applicationFont
        color: root.statusPalette.windowText
        text: root.presenter.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
}
