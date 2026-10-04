pragma ComponentBehavior: Bound
// Shared padded prompt chrome; owners keep drafts, focus routing and key sinks.
import QtQuick
import Porydaw.Ui

Item {
    id: card

    focus: true

    required property var appearance

    property real minimumWidth: 0

    default property alias contentChildren: content.data

    implicitWidth: Math.max(content.implicitWidth + 2 * appearance.dialogPadding,
                            minimumWidth)
    implicitHeight: content.implicitHeight + 2 * appearance.dialogPadding

    Rectangle {
        parent: card
        anchors.fill: parent
        color: card.appearance.background
        border.width: card.appearance.borderWidth
        border.color: card.appearance.outline
        radius: card.appearance.radius
    }

    Column {
        parent: card
        id: content

        x: card.appearance.dialogPadding
        y: card.appearance.dialogPadding
        spacing: card.appearance.spacing
    }
}
