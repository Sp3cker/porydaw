pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

RowLayout {
    id: picker
    objectName: "splitStudioSlotPicker"
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    spacing: paneSpacing
    Label { text: qsTr("Kit slot"); color: picker.colors.windowText }
    ComboBox {
        id: slots
        objectName: "splitStudioSlotChoice"
        Layout.fillWidth: true
        model: picker.editor.slotRows
        textRole: "title"
        valueRole: "slot"
        currentIndex: { void picker.editor.stateRevision; return indexOfValue(picker.editor.selectedSlot) }
        onActivated: index => picker.editor.selectSlot(index)
    }
}
