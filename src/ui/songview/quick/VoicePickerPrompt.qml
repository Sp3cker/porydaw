pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

PromptOverlay {
    id: pickerRoot
    objectName: "voicePicker"
    required final property QtObject model
    final property Item pageItem: null
    final property App.MouseHints hintService: null
    final readonly property App.HeaderVoicePicker headerModel: model as App.HeaderVoicePicker
    final readonly property App.VoiceChangesPage voiceModel: model as App.VoiceChangesPage
    final readonly property App.PromptStyle appearance: headerModel
        ? headerModel.promptStyle : voiceModel.promptStyle
    final readonly property string pickerTitle: headerModel ? headerModel.pickerTitle : voiceModel.pickerTitle
    final readonly property string pickerFilter: headerModel ? headerModel.pickerFilter : voiceModel.pickerFilter
    final readonly property int pickerIndex: headerModel ? headerModel.pickerIndex : voiceModel.pickerIndex
    final readonly property bool pickerHasMatch: headerModel ? headerModel.pickerHasMatch : voiceModel.pickerHasMatch

    function releasePickerAudition(): void {
        if (headerModel) headerModel.releasePickerAudition()
        else if (voiceModel) voiceModel.releasePickerAudition()
    }
    function acceptPicker(): void {
        if (headerModel) headerModel.acceptPicker()
        else if (voiceModel) voiceModel.acceptPicker()
    }
    function cancelPicker(): void {
        if (headerModel) headerModel.cancelPicker()
        else if (voiceModel) voiceModel.cancelPicker()
    }
    function setPickerFilter(text: string): void {
        if (headerModel) headerModel.setPickerFilter(text)
        else if (voiceModel) voiceModel.setPickerFilter(text)
    }
    function currentPickerIndex(): int {
        return headerModel ? headerModel.pickerIndex : voiceModel ? voiceModel.pickerIndex : -1
    }
    function selectPickerRow(index: int): void {
        if (headerModel) headerModel.selectPickerRow(index)
        else if (voiceModel) voiceModel.selectPickerRow(index)
    }
    function pressAndHoldPickerRow(index: int): void {
        if (headerModel) headerModel.pressAndHoldPickerRow(index)
        else if (voiceModel) voiceModel.pressAndHoldPickerRow(index)
    }
    property bool showing: false
    signal closed()
    anchors.fill: parent
    overlayOpen: showing
    cardItem: prompt
    underlayObjectName: "voicePickerUnderlay"
    onInitialFocusRequested: prompt.activateInitialFocus()
    onOverlayClosed: {
        releasePickerAudition()
        closed()
    }
    onDismissRequested: cancelPicker()
    Component.onDestruction: releasePickerAudition()
    Keys.onShortcutOverride: event => {
        event.accepted = event.key !== Qt.Key_Space || search.activeFocus
    }

    // Every picker label: the prompt's own font and neutral-surface ink.
    component PickerText: Text {
        color: pickerRoot.appearance.text
        font: pickerRoot.appearance.font
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    FontMetrics {
        id: metrics
        font: pickerRoot.appearance.font
    }

    PromptCard {
        id: prompt

        objectName: "voicePickerCard"
        anchors.centerIn: parent
        // The card follows its sections, which follow the overlay's own size.
        width: bodyWidth + 2 * appearance.dialogPadding
        height: implicitHeight
        appearance: pickerRoot.appearance
        minimumWidth: pickerRoot.appearance.minimumWidth
        property bool viewReady: false

        // Rhythm from the rendered prompt font, so larger text keeps proportion.
        readonly property real line: Math.ceil(metrics.height)
        readonly property real gap: Math.round(line / 2)
        readonly property real tight: Math.max(appearance.spacing, Math.round(gap / 2))
        // Sections sit inside the card's own padding; together they make one gap.
        readonly property real inset: Math.max(0, gap - appearance.dialogPadding)
        readonly property real fieldPadding: Math.max(appearance.horizontalPadding, gap)
        readonly property real fieldVerticalPadding: Math.max(appearance.verticalPadding, Math.round(line / 4))
        readonly property real rowInset: tight
        readonly property real rowHeight: line + gap
        readonly property real controlHeight: line + gap
        readonly property real indicatorWidth: Math.max(2 * appearance.borderWidth, Math.round(line / 6))
        readonly property real buttonWidth: Math.max(cancelButton.labelWidth, acceptButton.labelWidth)
            + 2 * Math.max(appearance.buttonPadding, line)

        readonly property real preferredBodyWidth: Math.max(
            appearance.minimumWidth - 2 * appearance.dialogPadding,
            Math.max(titleText.implicitWidth + 2 * inset, 2 * buttonWidth + tight + 2 * inset))
        readonly property real bodyWidth: Math.max(0, Math.min(preferredBodyWidth,
            pickerRoot.width - 2 * line - 2 * appearance.dialogPadding))
        // Everything but the list viewport; the viewport takes what remains.
        readonly property real chromeHeight: 2 * appearance.dialogPadding
            + header.implicitHeight + footer.implicitHeight + 2 * appearance.borderWidth
            + body.topPadding + body.bottomPadding + body.spacing
            + searchFrame.height + 2 * appearance.borderWidth
        readonly property real listViewportHeight: Math.max(rowHeight + 2 * rowInset,
            Math.min(appearance.listHeight, pickerRoot.height - 2 * line - chromeHeight))

        MouseArea {
            parent: prompt
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        function acceptDisplayed(): void {
            pickerRoot.acceptPicker()
        }
        function cancelDisplayed(): void {
            pickerRoot.cancelPicker()
        }
        function activateInitialFocus(): void {
            search.forceActiveFocus(Qt.PopupFocusReason)
            if (pickerRoot.pickerIndex >= 0) {
                list.currentIndex = pickerRoot.pickerIndex
                list.positionViewAtIndex(pickerRoot.pickerIndex, ListView.Center)
            }
            viewReady = true
        }

        // TextInput and ListView edit first; declined keys stop inside the popup.
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape)
                cancelDisplayed()
            event.accepted = true
        }
        Keys.onReleased: (event) => event.accepted = true

        Accessible.role: Accessible.Client
        Accessible.name: pickerRoot.pickerTitle

        Column {
            Item {
                id: header

                width: prompt.bodyWidth
                implicitHeight: prompt.inset + titleText.implicitHeight + prompt.gap

                PickerText {
                    id: titleText

                    objectName: "voicePickerTitle"
                    anchors.left: parent.left
                    anchors.leftMargin: prompt.inset
                    anchors.right: parent.right
                    anchors.rightMargin: prompt.inset
                    y: prompt.inset
                    text: pickerRoot.pickerTitle
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                x: -prompt.appearance.dialogPadding
                width: prompt.width
                height: prompt.appearance.borderWidth
                color: prompt.appearance.outline
            }

            Column {
                id: body

                width: prompt.bodyWidth
                leftPadding: prompt.inset
                rightPadding: prompt.inset
                topPadding: prompt.gap
                bottomPadding: prompt.gap
                spacing: prompt.tight

                Rectangle {
                    id: searchFrame
                    objectName: "voicePickerSearchFrame"
                    width: body.width - body.leftPadding - body.rightPadding
                    height: metrics.height
                        + 2 * (prompt.fieldVerticalPadding + pickerRoot.appearance.borderWidth)
                    color: pickerRoot.appearance.background
                    border.width: pickerRoot.appearance.borderWidth
                    border.color: search.activeFocus ? pickerRoot.appearance.focus : pickerRoot.appearance.outline
                    radius: pickerRoot.appearance.radius

                    Text {
                        id: searchHint
                        objectName: "voicePickerSearchHint"

                        anchors.fill: parent
                        anchors.leftMargin: prompt.fieldPadding + pickerRoot.appearance.borderWidth
                        anchors.rightMargin: anchors.leftMargin
                        color: pickerRoot.appearance.placeholderText
                        font: pickerRoot.appearance.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: qsTr("Search by name or number")
                        visible: search.text.length === 0
                        renderType: Text.NativeRendering
                    }

                    TextInput {
                        id: search

                        objectName: "voicePickerSearch"
                        HoverHint {
                            source: search
                            hintService: pickerRoot.hintService
                            scopeAllowed: pickerRoot.showing
                            cursorShape: Qt.IBeamCursor
                            // Modern TextInput's own Shift-click marking; no availability
                            // check. Session scope is enforced inside HoverHint.
                            profile: HintProfiles.TextSelection
                        }
                        anchors.fill: parent
                        clip: true
                        color: pickerRoot.appearance.text
                        font: pickerRoot.appearance.font
                        padding: pickerRoot.appearance.borderWidth
                        leftPadding: prompt.fieldPadding + pickerRoot.appearance.borderWidth
                        topPadding: prompt.fieldVerticalPadding + pickerRoot.appearance.borderWidth
                        selectionColor: pickerRoot.appearance.selection
                        selectedTextColor: pickerRoot.appearance.selectionText
                        rightPadding: leftPadding
                        bottomPadding: topPadding
                        renderType: TextInput.NativeRendering
                        activeFocusOnTab: true
                        selectByMouse: true
                        text: pickerRoot.pickerFilter
                        Accessible.role: Accessible.EditableText
                        Accessible.name: searchHint.text
                        Accessible.description: pickerRoot.pickerTitle
                        Accessible.editable: true
                        KeyNavigation.tab: list
                        KeyNavigation.backtab: pickerRoot.pickerHasMatch ? acceptButton : cancelButton

                        onTextChanged: pickerRoot.setPickerFilter(text)
                        Keys.onReturnPressed: (event) => {
                            prompt.acceptDisplayed()
                            event.accepted = true
                        }
                        Keys.onEnterPressed: (event) => {
                            prompt.acceptDisplayed()
                            event.accepted = true
                        }
                        Keys.onDownPressed: (event) => {
                            if (pickerRoot.pickerHasMatch)
                                list.forceActiveFocus(Qt.TabFocusReason)
                            event.accepted = true
                        }
                    }
                }

                Rectangle {
                    id: listFrame

                    objectName: "voicePickerListFrame"
                    width: searchFrame.width
                    height: list.height + 2 * pickerRoot.appearance.borderWidth
                    color: pickerRoot.appearance.background
                    border.width: pickerRoot.appearance.borderWidth
                    border.color: list.activeFocus ? pickerRoot.appearance.focus : pickerRoot.appearance.outline
                    radius: pickerRoot.appearance.radius

                    ListView {
                        id: list
                        acceptedButtons: Qt.NoButton

                        objectName: "voicePickerList"
                        x: pickerRoot.appearance.borderWidth
                        y: pickerRoot.appearance.borderWidth
                        width: listFrame.width - 2 * pickerRoot.appearance.borderWidth
                        height: prompt.listViewportHeight
                        topMargin: prompt.rowInset
                        bottomMargin: prompt.rowInset
                        model: pickerRoot.headerModel ? pickerRoot.headerModel.pickerRows : pickerRoot.voiceModel.pickerRows
                        clip: true
                        focus: false
                        activeFocusOnTab: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: 0
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Voices")
                        Accessible.description: qsTr("Click and hold to audition (middle C).")
                        KeyNavigation.tab: cancelButton
                        KeyNavigation.backtab: search

                        Connections {
                            target: pickerRoot.model
                            function onPickerIndexChanged(): void {
                                list.currentIndex = pickerRoot.currentPickerIndex()
                            }
                            function onPickerFilterChanged(): void {
                                if (list.currentIndex >= 0)
                                    list.positionViewAtIndex(list.currentIndex, ListView.Center)
                            }
                        }

                        onCurrentIndexChanged: {
                            if (prompt.viewReady && currentIndex !== pickerRoot.currentPickerIndex())
                                pickerRoot.selectPickerRow(currentIndex)
                        }

                        Keys.onReturnPressed: (event) => {
                            prompt.acceptDisplayed()
                            event.accepted = true
                        }
                        Keys.onEnterPressed: (event) => {
                            prompt.acceptDisplayed()
                            event.accepted = true
                        }
                        Keys.onEscapePressed: (event) => {
                            prompt.cancelDisplayed()
                            event.accepted = true
                        }

                        // An inset rounded selection, not a full-bleed band.
                        highlight: Item {
                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: prompt.rowInset
                                anchors.rightMargin: prompt.rowInset + prompt.indicatorWidth
                                color: prompt.appearance.selection
                                radius: prompt.appearance.radius
                            }
                        }

                        delegate: Item {
                            id: row

                            required property int index
                            required property int program
                            required property string label

                            objectName: "voicePickerRow_" + program
                            width: list.width
                            height: prompt.rowHeight
                            Accessible.role: Accessible.ListItem
                            Accessible.name: label
                            Accessible.selected: ListView.isCurrentItem
                            Accessible.onPressAction: pickerRoot.selectPickerRow(row.index)

                            PickerText {
                                id: rowText

                                anchors.left: parent.left
                                anchors.leftMargin: prompt.fieldPadding
                                anchors.right: parent.right
                                anchors.rightMargin: prompt.fieldPadding + prompt.indicatorWidth
                                anchors.verticalCenter: parent.verticalCenter
                                color: row.ListView.isCurrentItem ? prompt.appearance.selectionText : prompt.appearance.text
                                text: row.label
                                elide: Text.ElideRight
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onPressed: {
                                    list.currentIndex = row.index
                                    pickerRoot.pressAndHoldPickerRow(row.index)
                                }
                                onReleased: pickerRoot.releasePickerAudition()
                                onCanceled: pickerRoot.releasePickerAudition()
                                onClicked: list.forceActiveFocus(Qt.MouseFocusReason)
                                onDoubleClicked: prompt.acceptDisplayed()
                            }
                        }
                    }

                    // Passive position cue: where the viewport sits in the voice list.
                    Rectangle {
                        objectName: "voicePickerScrollIndicator"
                        readonly property real span: list.contentHeight + list.topMargin + list.bottomMargin
                        readonly property real ratio: span > 0 ? Math.min(1, list.height / span) : 1
                        readonly property real offset: span > 0
                            ? (list.contentY - list.originY + list.topMargin) / span : 0
                        visible: ratio < 1
                        x: list.x + list.width - width - pickerRoot.appearance.borderWidth
                        y: list.y + Math.max(0, Math.min(1 - ratio, offset)) * list.height
                        width: prompt.indicatorWidth
                        height: Math.max(prompt.indicatorWidth, ratio * list.height)
                        radius: width / 2
                        color: pickerRoot.appearance.outline
                    }

                    PickerText {
                        objectName: "voicePickerEmptyText"
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - 2 * prompt.fieldPadding)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: qsTr("No matching voices")
                        visible: !pickerRoot.pickerHasMatch
                    }
                }
            }

            Rectangle {
                x: -prompt.appearance.dialogPadding
                width: prompt.width
                height: prompt.appearance.borderWidth
                color: prompt.appearance.outline
            }

            Item {
                id: footer

                width: prompt.bodyWidth
                implicitHeight: prompt.gap + prompt.controlHeight + prompt.inset

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: prompt.inset
                    y: prompt.gap
                    spacing: prompt.tight

                    PromptButton {
                        id: cancelButton

                        objectName: "voicePickerCancel"
                        claimsShortcuts: false
                        appearance: prompt.appearance
                        text: qsTr("Cancel")
                        width: prompt.buttonWidth
                        height: Math.max(implicitHeight, prompt.controlHeight)
                        KeyNavigation.tab: pickerRoot.pickerHasMatch ? acceptButton : search
                        KeyNavigation.backtab: list
                        onActivated: prompt.cancelDisplayed()
                    }

                    PromptButton {
                        id: acceptButton

                        objectName: "voicePickerAccept"
                        claimsShortcuts: false
                        appearance: prompt.appearance
                        text: qsTr("OK")
                        enabled: pickerRoot.pickerHasMatch
                        width: prompt.buttonWidth
                        height: Math.max(implicitHeight, prompt.controlHeight)
                        KeyNavigation.tab: search
                        KeyNavigation.backtab: cancelButton
                        onActivated: prompt.acceptDisplayed()
                    }
                }
            }
        }
    }
}
