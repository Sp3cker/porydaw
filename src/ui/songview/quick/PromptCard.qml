// Shared canvas-prompt chrome: the bordered dialog rectangle and its padded
// content column. Owners keep semantics — drafts, focus routing, key sinks —
// and declare rows as default children; appearance injects the shared theme
// keys, and minimumWidth optionally floors dialogs whose content runs narrow.
import QtQuick

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
