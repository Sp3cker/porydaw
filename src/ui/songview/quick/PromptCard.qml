pragma ComponentBehavior: Bound
// Shared padded prompt chrome; owners keep drafts, focus routing and key sinks.
import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: card

    focus: true

    required final property PromptStyle appearance

    final property real minimumWidth: 0

    default property alias contentChildren: content.data

    implicitWidth: Math.max(content.implicitWidth + 2 * card.appearance.dialogPadding,
                            card.minimumWidth)
    implicitHeight: content.implicitHeight + 2 * card.appearance.dialogPadding

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
