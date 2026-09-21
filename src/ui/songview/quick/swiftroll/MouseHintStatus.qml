import QtQuick

Rectangle {
    id: root
    objectName: "mouseHintStatus"
    required property QtObject presenter
    required property QtObject statusPalette
    color: statusPalette.windowBackground
    implicitHeight: Math.ceil(metrics.height + metrics.height / 2)

    FontMetrics {
        id: metrics
        font: Application.font
    }

    Text {
        objectName: "mouseHintStatusText"
        anchors.fill: parent
        anchors.leftMargin: metrics.height / 2
        anchors.rightMargin: metrics.height / 2
        font: Application.font
        color: root.statusPalette.windowText
        text: root.presenter.text
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
}
