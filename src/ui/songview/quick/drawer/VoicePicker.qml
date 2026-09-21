// The Voice Changes picker: the bank's slots as rows, filtered by the search
// field, with the captured target's own row selected when it is visible.
//
// The page owns the capture (revision, track, occurrence, tick), the filter, the
// current program and the acceptance transaction; this file renders the rows the
// page publishes and delivers real pointer, keyboard and accessibility input
// back to that owner. It reads no document and writes nothing itself.
//
// Audition: production's rows audition the voice they name on a held press.
// That needs the native voice preview the authorized Swift audio service does
// not expose (`VoiceChangesPage.swift` records the exact blocked legacy cases
// and the minimal native contract that would unblock them), so no control here
// claims it and the page's own diagnostic is shown instead — the absent action
// is stated, not hidden.
//
// Cancellation: an outside press, Escape, a filter that leaves no match, a
// section hide, a window deactivation or a document/track replacement all end
// the picker without a write.
import QtQuick

pragma ComponentBehavior: Bound

FocusScope {
    id: pickerRoot

    objectName: "voicePicker"

    /// The page's published model for the current document. A `QtObject`-typed
    /// property cannot hold the bridged Swift object, so the page hands it over
    /// as the variant the rest of the composition uses for bridged owners.
    required property var model

    signal closed()

    readonly property bool ready: pickerRoot.model !== null && pickerRoot.model !== undefined
    /// The page's own publication decides modality: this file renders the open
    /// picker and delivers the input that drives it. The flag is read through a
    /// `var`-typed bridge object, whose nested properties a binding does not
    /// track across this component boundary, so the picker follows the page's
    /// own change signal — the same shape the drawer uses for its presenter's
    /// preference records.
    property bool showing: false

    readonly property real baseFontPx: pickerRoot.model && pickerRoot.model.baseFontPx > 0
                                       ? pickerRoot.model.baseFontPx : 13
    readonly property real padding: Math.max(1, Math.round(pickerRoot.baseFontPx / 2))
    readonly property real titleHeight: Math.max(1, Math.round(pickerRoot.baseFontPx * 1.4))
    readonly property real searchHeight: Math.max(1, Math.round(pickerRoot.baseFontPx * 1.6))
    readonly property real buttonHeight: Math.max(1, Math.round(pickerRoot.baseFontPx * 1.6))
    readonly property real noticeHeight: Math.max(1, Math.round(pickerRoot.baseFontPx * 2.4))
    readonly property real frameWidth: Math.min(
        Math.max(1, Math.round(pickerRoot.baseFontPx * 30)),
        Math.max(1, pickerRoot.width - 2 * pickerRoot.padding))
    readonly property real frameHeight: Math.min(
        Math.max(1, Math.round(pickerRoot.baseFontPx * 110 / 3))
            + pickerRoot.titleHeight + pickerRoot.searchHeight + pickerRoot.buttonHeight
            + pickerRoot.noticeHeight + 5 * pickerRoot.padding,
        Math.max(1, pickerRoot.height - 2 * pickerRoot.padding))
    readonly property real listHeight: Math.max(
        1, pickerRoot.frameHeight - (pickerRoot.titleHeight + pickerRoot.searchHeight
            + pickerRoot.buttonHeight + pickerRoot.noticeHeight + 5 * pickerRoot.padding))

    // The page composes this modal into the container's unclipped modal layer
    // when the container hosts it, and into the page itself otherwise; either way
    // it fills the surface it was given.
    anchors.fill: parent
    visible: showing
    enabled: showing

    onShowingChanged: {
        if (showing) {
            pickerRoot.forceActiveFocus(Qt.PopupFocusReason)
            Qt.callLater(pickerRoot.focusSearch)
        } else {
            pickerRoot.closed()
        }
    }

    function focusSearch() {
        if (pickerRoot.showing)
            search.forceActiveFocus(Qt.PopupFocusReason)
    }

    Keys.onUpPressed: (event) => {
        pickerRoot.model.movePickerSelection(-1)
        event.accepted = true
    }
    Keys.onDownPressed: (event) => {
        pickerRoot.model.movePickerSelection(1)
        event.accepted = true
    }
    Keys.onReturnPressed: (event) => {
        pickerRoot.model.acceptPicker()
        event.accepted = true
    }
    Keys.onEnterPressed: (event) => {
        pickerRoot.model.acceptPicker()
        event.accepted = true
    }
    Keys.onEscapePressed: (event) => {
        pickerRoot.model.cancelPicker()
        event.accepted = true
    }
    // Only Return/Enter are claimed here; a Space typed into the search field is
    // text, and every Space outside it stays the window's transport.
    Keys.onShortcutOverride: (event) => event.accepted =
        event.key === Qt.Key_Return || event.key === Qt.Key_Enter

    Accessible.role: Accessible.Client
    Accessible.name: pickerRoot.model ? pickerRoot.model.pickerTitle : ""
    Accessible.focusable: true

    // Every outside press dismisses and writes nothing.
    MouseArea {
        objectName: "voicePickerUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: pickerRoot.model.cancelPicker()
    }

    Rectangle {
        id: card

        objectName: "voicePickerCard"
        anchors.centerIn: parent
        width: pickerRoot.frameWidth
        height: pickerRoot.frameHeight
        color: "#E9E4E0"
        border.width: 1
        border.color: "#8C857F"
        radius: Math.max(1, Math.round(pickerRoot.baseFontPx / 4))

        Text {
            id: title

            objectName: "voicePickerTitle"
            x: pickerRoot.padding
            y: pickerRoot.padding
            width: Math.max(0, card.width - 2 * pickerRoot.padding)
            height: pickerRoot.titleHeight
            text: pickerRoot.model ? pickerRoot.model.pickerTitle : ""
            color: "#302C29"
            font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Rectangle {
            id: searchFrame

            objectName: "voicePickerSearchFrame"
            x: pickerRoot.padding
            y: title.y + title.height
            width: Math.max(0, card.width - 2 * pickerRoot.padding)
            height: pickerRoot.searchHeight
            color: "#F4F4F4"
            border.width: 1
            border.color: search.activeFocus ? "#00CADB" : "#8C857F"

            Text {
                objectName: "voicePickerSearchHint"
                anchors.fill: parent
                anchors.leftMargin: pickerRoot.padding
                anchors.rightMargin: pickerRoot.padding
                text: qsTr("Search voices...")
                visible: search.text.length === 0
                color: "#8C857F"
                font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                verticalAlignment: Text.AlignVCenter
            }

            TextInput {
                id: search

                objectName: "voicePickerSearch"
                anchors.fill: parent
                anchors.leftMargin: pickerRoot.padding
                anchors.rightMargin: pickerRoot.padding
                clip: true
                color: "#302C29"
                font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
                renderType: TextInput.NativeRendering
                activeFocusOnTab: true
                selectByMouse: true
                // The field shows the page's filter and reports every keystroke
                // back to it; an equal filter is a no-op, so the two stay in
                // step without a loop.
                text: pickerRoot.model ? pickerRoot.model.pickerFilter : ""
                onTextChanged: pickerRoot.model.setPickerFilter(search.text)
                // The navigation keys belong to the page's own current program:
                // the field is a text surface, so the handler runs before the
                // field's own cursor movement and claims the cross-axis arrows.
                // Bare Space stays text here, which is the one text-entry
                // surface the modal keeps.
                Keys.priority: Keys.BeforeItem
                Keys.onUpPressed: (event) => {
                    pickerRoot.model.movePickerSelection(-1)
                    event.accepted = true
                }
                Keys.onDownPressed: (event) => {
                    pickerRoot.model.movePickerSelection(1)
                    event.accepted = true
                }
                Keys.onReturnPressed: (event) => {
                    pickerRoot.model.acceptPicker()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    pickerRoot.model.acceptPicker()
                    event.accepted = true
                }

                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Search voices")
                Accessible.description: pickerRoot.model ? pickerRoot.model.pickerTitle : ""
                Accessible.editable: true
            }
        }

        ListView {
            id: list

            objectName: "voicePickerList"
            x: pickerRoot.padding
            y: searchFrame.y + searchFrame.height + pickerRoot.padding / 2
            width: Math.max(0, card.width - 2 * pickerRoot.padding)
            height: pickerRoot.listHeight
            clip: true
            activeFocusOnTab: true
            model: pickerRoot.model ? pickerRoot.model.pickerRows : []
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 0
            // The page owns the current program, so the view never re-points it
            // itself: arrows reach the page's own navigation instead.
            keyNavigationEnabled: false
            currentIndex: pickerRoot.model ? pickerRoot.model.pickerIndex : -1

            Connections {
                target: pickerRoot.model

                function onPickerIndexChanged() {
                    if (!pickerRoot.showing)
                        return
                    list.currentIndex = pickerRoot.model.pickerIndex
                    if (list.currentIndex >= 0)
                        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
                }
            }

            Keys.onUpPressed: (event) => {
                pickerRoot.model.movePickerSelection(-1)
                event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                pickerRoot.model.movePickerSelection(1)
                event.accepted = true
            }
            Keys.onReturnPressed: (event) => {
                pickerRoot.model.acceptPicker()
                event.accepted = true
            }
            Keys.onEnterPressed: (event) => {
                pickerRoot.model.acceptPicker()
                event.accepted = true
            }
            Keys.onEscapePressed: (event) => {
                pickerRoot.model.cancelPicker()
                event.accepted = true
            }

            highlight: Rectangle {
                color: "#D5CEC8"
                radius: Math.max(1, Math.round(pickerRoot.baseFontPx / 4))
            }

            delegate: Item {
                id: pickerRow

                required property int index
                required property var model

                objectName: "voicePickerRow_" + model.program
                width: list.width
                height: Math.max(1, Math.round(pickerRoot.baseFontPx * 1.5))

                Text {
                    id: rowText

                    anchors.fill: parent
                    anchors.leftMargin: pickerRoot.padding
                    anchors.rightMargin: pickerRoot.padding
                    text: pickerRow.model.label
                    color: "#302C29"
                    font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    hoverEnabled: true

                    onEntered: list.currentIndex = pickerRow.index
                    onPressed: pickerRoot.model.selectPickerRow(pickerRow.index)
                    onDoubleClicked: pickerRoot.model.acceptPicker()
                }

                Accessible.role: Accessible.ListItem
                Accessible.name: pickerRow.model.label
                Accessible.selected: pickerRow.model.selected
                Accessible.focusable: true
                Accessible.onPressAction: {
                    pickerRoot.model.selectPickerRow(pickerRow.index)
                    pickerRoot.model.acceptPicker()
                }
            }

            Text {
                objectName: "voicePickerEmptyText"
                anchors.centerIn: parent
                text: pickerRoot.model ? pickerRoot.model.pickerEmptyText : ""
                visible: !(pickerRoot.model ? pickerRoot.model.pickerHasMatch : false)
                color: "#57514C"
                font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
            }

            Accessible.role: Accessible.List
            Accessible.name: qsTr("Voices")
            Accessible.focusable: true
        }

        Row {
            id: buttons

            x: pickerRoot.padding
            y: card.height - pickerRoot.padding - pickerRoot.buttonHeight
                - pickerRoot.noticeHeight - pickerRoot.padding / 2
            spacing: pickerRoot.padding

            Rectangle {
                id: acceptButton

                objectName: "voicePickerAccept"
                width: Math.max(1, Math.round(pickerRoot.baseFontPx * 4))
                height: pickerRoot.buttonHeight
                enabled: pickerRoot.model ? pickerRoot.model.pickerHasMatch : false
                color: acceptButton.enabled ? "#BDB5AF" : "#D5CEC8"
                border.width: 1
                border.color: "#8C857F"
                activeFocusOnTab: true

                function activate() {
                    pickerRoot.model.acceptPicker()
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("OK")
                    color: "#302C29"
                    font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: acceptButton.activate()
                }

                Keys.onReturnPressed: (event) => {
                    acceptButton.activate()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    acceptButton.activate()
                    event.accepted = true
                }

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Accept voice")
                Accessible.focusable: true
                Accessible.onPressAction: acceptButton.activate()
            }

            Rectangle {
                id: cancelButton

                objectName: "voicePickerCancel"
                width: Math.max(1, Math.round(pickerRoot.baseFontPx * 4))
                height: pickerRoot.buttonHeight
                color: "#BDB5AF"
                border.width: 1
                border.color: "#8C857F"
                activeFocusOnTab: true

                function activate() {
                    pickerRoot.model.cancelPicker()
                }

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    color: "#302C29"
                    font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx))
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: cancelButton.activate()
                }

                Keys.onReturnPressed: (event) => {
                    cancelButton.activate()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    cancelButton.activate()
                    event.accepted = true
                }

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Cancel voice selection")
                Accessible.focusable: true
                Accessible.onPressAction: cancelButton.activate()
            }
        }

        // The capability statement: production auditions a row's voice on a held
        // press, and this surface cannot. The page publishes both facts, so the
        // absent action is visible and covered instead of silently missing.
        Text {
            objectName: "voicePickerAuditionNotice"

            x: pickerRoot.padding
            y: buttons.y + buttons.height + pickerRoot.padding / 2
            width: Math.max(0, card.width - 2 * pickerRoot.padding)
            height: pickerRoot.noticeHeight
            visible: !(pickerRoot.model ? pickerRoot.model.auditionAvailable : false)
            text: pickerRoot.model ? pickerRoot.model.auditionDiagnostic : ""
            color: "#57514C"
            font.pixelSize: Math.max(1, Math.round(pickerRoot.baseFontPx * 0.85))
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            clip: true
        }
    }
}
