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


    Rectangle {
        id: frame
        parent: card
        anchors.fill: parent
    }

    Column {
        parent: card
        id: content

    }

    Binding {
        when: card.appearance !== null
        restoreMode: Binding.RestoreNone
        card.implicitWidth: Math.max(content.implicitWidth + 2 * card.appearance?.dialogPadding,
                                     card.minimumWidth)
        card.implicitHeight: content.implicitHeight + 2 * card.appearance?.dialogPadding
        frame.color: card.appearance?.background
        frame.border.width: card.appearance?.borderWidth
        frame.border.color: card.appearance?.outline
        frame.radius: card.appearance?.radius
        content.x: card.appearance?.dialogPadding
        content.y: card.appearance?.dialogPadding
        content.spacing: card.appearance?.spacing
    }
}
