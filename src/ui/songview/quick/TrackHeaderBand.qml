import QtQuick
import Porydaw.Ui

Item {
    id: root

    required property rect bandRect
    required property bool bandVisible
    required property var model
    required property font controlFont

    readonly property var appearance: model.appearance
    readonly property color buttonBackground: appearance.buttonBackground
    readonly property color buttonText: appearance.buttonText
    readonly property color buttonHoverBackground: appearance.buttonHoverBackground
    readonly property color buttonHoverText: appearance.buttonHoverText
    readonly property color buttonPressedBackground: appearance.buttonPressedBackground
    readonly property color buttonPressedText: appearance.buttonPressedText
    readonly property color buttonOutline: appearance.buttonOutline
    readonly property color muteCheckedBackground: appearance.muteCheckedBackground
    readonly property color muteCheckedText: appearance.muteCheckedText
    readonly property color soloCheckedBackground: appearance.soloCheckedBackground
    readonly property color soloCheckedText: appearance.soloCheckedText
    readonly property color inputBackground: appearance.inputBackground
    readonly property color inputText: appearance.inputText
    readonly property color inputOutline: appearance.inputOutline
    readonly property color focusOutline: appearance.focusOutline
    readonly property color scrollbarHandle: appearance.scrollbarHandle
    readonly property color scrollbarHandleHover: appearance.scrollbarHandleHover
    readonly property color reorderIndicator: appearance.reorderIndicator

    function rowIndexForTrack(track) {
        if (track < 0)
            return -1
        for (let index = 0; index < trackHeaderRows.count; ++index) {
            const row = trackHeaderRows.itemAt(index)
            if (row && row.track === track)
                return index
        }
        return -1
    }

    component TrackHeaderToggle: Item {
        id: toggle

        required property rect controlRect
        required property int track
        required property string label
        required property string accessibleName
        required property bool checked
        required property bool hovered
        required property bool pressed
        required property bool solo

        x: controlRect.x
        y: controlRect.y
        width: controlRect.width
        height: controlRect.height
        activeFocusOnTab: true
        readonly property color stateBackground: pressed
                                              ? solo ? root.soloCheckedBackground
                                                     : root.buttonPressedBackground
                                              : checked
                                                ? solo ? root.soloCheckedBackground
                                                       : root.muteCheckedBackground
                                                : hovered ? root.buttonHoverBackground
                                                          : root.buttonBackground
        readonly property color stateText: pressed
                                        ? solo ? root.soloCheckedText : root.buttonPressedText
                                        : checked
                                          ? solo ? root.soloCheckedText : root.muteCheckedText
                                          : hovered ? root.buttonHoverText : root.buttonText

        function activate() {
            if (solo)
                root.model.activateSolo(track)
            else
                root.model.activateMute(track)
        }

        function activateFromKeyboard(event) {
            activate()
            event.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            color: toggle.stateBackground
            border.color: root.buttonOutline
            border.width: 1
        }

        Text {
            anchors.fill: parent
            color: toggle.stateText
            font: root.controlFont
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: toggle.label
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideNone
            maximumLineCount: 1
        }

        Keys.onReturnPressed: (event) => toggle.activateFromKeyboard(event)
        Keys.onEnterPressed: (event) => toggle.activateFromKeyboard(event)
        Keys.onSpacePressed: (event) => toggle.activateFromKeyboard(event)

        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.focusable: true
        Accessible.onPressAction: toggle.activate()
    }

    Item {
        id: headerBand

        objectName: "timelineQuickTrackHeaders"
        x: root.bandRect.x
        y: root.bandRect.y
        width: root.bandRect.width
        height: root.bandRect.height
        clip: true
        visible: root.bandVisible

        Item {
            id: trackHeaderViewport

            anchors.fill: parent
            clip: true

            Item {
                id: trackHeaderRowArea

                width: Math.max(0, trackHeaderViewport.width - root.model.scrollbarWidth)
                height: parent.height
                clip: true

                Item {
                    id: translatedRows

                    y: -root.model.scrollY
                    width: parent.width
                    height: root.model.contentHeight
                    z: 2

                    Repeater {
                        id: trackHeaderRows

                        objectName: "timelineTrackHeaderRows"
                        model: root.model

                        delegate: Item {
                            id: trackHeaderRow

                            required property int index
                            required property bool isAddTrack
                            required property int track
                            required property string title
                            required property string subtitle
                            required property rect titleRect
                            required property rect subtitleRect
                            required property point selectedTitleOffset
                            required property color baseColor
                            required property color overlayColor
                            required property color titleColor
                            required property color subtitleColor
                            required property font titleFont
                            required property font subtitleFont
                            required property bool muteChecked
                            required property bool soloChecked
                            required property bool muteHovered
                            required property bool mutePressed
                            required property bool soloHovered
                            required property bool soloPressed
                            required property bool addHovered
                            required property bool addPressed
                            required property bool voiceHovered
                            required property bool voicePressed
                            required property color activityDimColor
                            required property color activityActiveColor
                            required property real activityLeftHeight
                            required property real activityRightHeight

                            y: index * root.model.rowHeight
                            width: translatedRows.width
                            height: root.model.rowHeight

                            Rectangle {
                                anchors.fill: parent
                                color: trackHeaderRow.baseColor
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: trackHeaderRow.overlayColor
                                visible: trackHeaderRow.overlayColor.a > 0
                            }

                            Item {
                                width: root.model.activityWidth
                                height: Math.max(0, trackHeaderRow.height - root.model.separatorWidth)
                                visible: !trackHeaderRow.isAddTrack

                                Rectangle {
                                    anchors.fill: parent
                                    color: trackHeaderRow.activityDimColor
                                }

                                Rectangle {
                                    width: parent.width / 2
                                    height: Math.max(0, Math.min(parent.height,
                                                                trackHeaderRow.activityLeftHeight))
                                    anchors.bottom: parent.bottom
                                    color: trackHeaderRow.activityActiveColor
                                }

                                Rectangle {
                                    x: parent.width / 2
                                    width: parent.width - x
                                    height: Math.max(0, Math.min(parent.height,
                                                                trackHeaderRow.activityRightHeight))
                                    anchors.bottom: parent.bottom
                                    color: trackHeaderRow.activityActiveColor
                                }
                            }

                            Rectangle {
                                y: Math.max(0, trackHeaderRow.height - root.model.separatorWidth)
                                width: parent.width
                                height: root.model.separatorWidth
                                color: root.buttonOutline
                            }

                            Text {
                                x: trackHeaderRow.titleRect.x
                                   + trackHeaderRow.selectedTitleOffset.x
                                y: trackHeaderRow.titleRect.y
                                   + trackHeaderRow.selectedTitleOffset.y
                                width: trackHeaderRow.titleRect.width
                                height: trackHeaderRow.titleRect.height
                                visible: !trackHeaderRow.isAddTrack
                                clip: true
                                color: trackHeaderRow.titleColor
                                font: trackHeaderRow.titleFont
                                text: trackHeaderRow.title
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                elide: Text.ElideNone
                                maximumLineCount: 1
                                verticalAlignment: Text.AlignVCenter
                            }

                            // The model resolves this subtitle box as the sole voice target and
                            // publishes its hover/pressed state roles.
                            Text {
                                x: trackHeaderRow.subtitleRect.x
                                y: trackHeaderRow.subtitleRect.y
                                width: trackHeaderRow.subtitleRect.width
                                height: trackHeaderRow.subtitleRect.height
                                visible: !trackHeaderRow.isAddTrack
                                clip: true
                                color: trackHeaderRow.voicePressed ? root.buttonPressedText
                                                                   : trackHeaderRow.voiceHovered
                                                                     ? root.buttonHoverText
                                                                     : trackHeaderRow.subtitleColor
                                font: trackHeaderRow.subtitleFont
                                text: trackHeaderRow.subtitle
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                elide: Text.ElideNone
                                maximumLineCount: 1
                                verticalAlignment: Text.AlignVCenter
                            }

                            TrackHeaderToggle {
                                visible: !trackHeaderRow.isAddTrack
                                controlRect: root.model.muteButtonRect
                                track: trackHeaderRow.track
                                label: qsTr("M")
                                accessibleName: qsTr("Mute")
                                checked: trackHeaderRow.muteChecked
                                hovered: trackHeaderRow.muteHovered
                                pressed: trackHeaderRow.mutePressed
                                solo: false
                            }

                            TrackHeaderToggle {
                                visible: !trackHeaderRow.isAddTrack
                                controlRect: root.model.soloButtonRect
                                track: trackHeaderRow.track
                                label: qsTr("S")
                                accessibleName: qsTr("Solo")
                                checked: trackHeaderRow.soloChecked
                                hovered: trackHeaderRow.soloHovered
                                pressed: trackHeaderRow.soloPressed
                                solo: true
                            }

                            Item {
                                id: addTrackRow

                                anchors.fill: parent
                                visible: trackHeaderRow.isAddTrack
                                activeFocusOnTab: true

                                function activate() {
                                    root.model.activateAddTrack()
                                }

                                function activateFromKeyboard(event) {
                                    activate()
                                    event.accepted = true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: trackHeaderRow.addPressed
                                           ? root.buttonPressedBackground
                                           : trackHeaderRow.addHovered
                                             ? root.buttonHoverBackground : root.buttonBackground
                                    border.color: root.buttonOutline
                                    border.width: 1
                                }

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    color: trackHeaderRow.addPressed
                                           ? root.buttonPressedText
                                           : trackHeaderRow.addHovered
                                             ? root.buttonHoverText : root.buttonText
                                    font: root.controlFont
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: trackHeaderRow.title
                                    textFormat: Text.PlainText
                                    renderType: Text.NativeRendering
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                Keys.onReturnPressed: (event) => addTrackRow.activateFromKeyboard(event)
                                Keys.onEnterPressed: (event) => addTrackRow.activateFromKeyboard(event)
                                Keys.onSpacePressed: (event) => addTrackRow.activateFromKeyboard(event)

                                Accessible.role: Accessible.Button
                                Accessible.name: trackHeaderRow.title
                                Accessible.description: qsTr("Add a track")
                                Accessible.focusable: true
                                Accessible.onPressAction: addTrackRow.activate()
                            }
                        }
                    }
                }
            }

            TimelineInputItem {
                objectName: "timelineTrackHeadersInput"
                width: trackHeaderRowArea.width
                height: trackHeaderRowArea.height
                z: 1
                Accessible.description: accessibilityDescription
            }

            Rectangle {
                objectName: "timelineTrackHeaderReorderMarker"
                y: Math.min(Math.max(0, root.model.reorderIndicatorY),
                            Math.max(0, trackHeaderRowArea.height - height))
                width: trackHeaderRowArea.width
                height: root.model.reorderIndicatorHeight
                visible: root.model.reorderIndicatorVisible && height > 0
                color: root.reorderIndicator
                z: 3
            }

            TimelineScrollbar {
                id: trackHeaderScrollBar

                objectName: "timelineTrackHeaderScrollBar"
                x: trackHeaderRowArea.width
                width: Math.max(0, root.model.scrollbarWidth)
                height: parent.height
                scrollY: root.model.scrollY
                contentHeight: root.model.contentHeight
                viewportHeight: root.model.viewportHeight
                maximumScrollY: root.model.maximumScrollY
                minimumThumbHeight: root.model.scrollbarMinimumThumbHeight
                accessibleName: qsTr("Track headers")
                lineStep: root.model.rowHeight
                handleColor: root.scrollbarHandle
                handleHoverColor: root.scrollbarHandleHover
                externalVisible: root.bandVisible
                thumbObjectName: "timelineTrackHeaderScrollThumb"
                z: 4

                onScrollYRequested: (value) => root.model.scrollY = value
                onPageRequested: (localY) => {
                    const direction = localY < trackHeaderScrollBar.thumbY ? -1 : 1
                    root.model.scrollY = root.model.scrollY
                                         + direction * root.model.viewportHeight
                }
                onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) => {
                    const pixelHorizontal = Math.abs(pixelX) > Math.abs(pixelY)
                    const angleHorizontal = Math.abs(angleX) > Math.abs(angleY)
                    if (pixelHorizontal || (pixelY === 0 && angleHorizontal))
                        return
                    const delta = pixelY !== 0 ? pixelY : angleY / 120 * root.model.rowHeight
                    if (delta === 0)
                        return
                    root.model.scrollY = root.model.scrollY + (inverted ? delta : -delta)
                }
            }
        }

        Item {
            id: renameClip

            width: trackHeaderRowArea.width
            height: parent.height
            clip: true
            z: 10

            Item {
                id: renameEditor

                readonly property int rowIndex: root.rowIndexForTrack(root.model.renamingTrack)
                x: root.model.renameEditorRect.x
                y: rowIndex * root.model.rowHeight - root.model.scrollY
                   + root.model.renameEditorRect.y
                width: root.model.renameEditorRect.width
                height: root.model.renameEditorRect.height
                visible: headerBand.visible && rowIndex >= 0
                property bool finishing: false

                function adoptRenameDraft() {
                    renameInput.text = root.model.renameDraft
                    renameInput.forceActiveFocus(Qt.PopupFocusReason)
                    renameInput.selectAll()
                }

                function finishRename(commit, entered) {
                    if (finishing || !visible)
                        return
                    finishing = true
                    root.model.finishRename(commit, entered)
                }

                onVisibleChanged: {
                    if (visible) {
                        finishing = false
                        adoptRenameDraft()
                    } else {
                        finishing = false
                    }
                }

                Component.onCompleted: {
                    if (visible)
                        adoptRenameDraft()
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.inputBackground
                    border.color: renameInput.activeFocus ? root.focusOutline : root.inputOutline
                    border.width: 1
                }

                TextInput {
                    id: renameInput

                    objectName: "timelineTrackHeaderRename"
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 2
                    clip: true
                    color: root.inputText
                    font: root.controlFont
                    selectByMouse: true

                    onTextEdited: root.model.renameDraft = text
                    onActiveFocusChanged: {
                        if (renameEditor.visible && !activeFocus && !renameEditor.finishing)
                            renameEditor.finishRename(true, false)
                    }

                    Keys.onReturnPressed: (event) => {
                        renameEditor.finishRename(true, true)
                        event.accepted = true
                    }
                    Keys.onEnterPressed: (event) => {
                        renameEditor.finishRename(true, true)
                        event.accepted = true
                    }
                    Keys.onEscapePressed: (event) => {
                        renameEditor.finishRename(false, true)
                        event.accepted = true
                    }

                    Accessible.role: Accessible.EditableText
                    Accessible.name: qsTr("Rename track")
                    Accessible.description: root.model.renameDraft
                    Accessible.focusable: true
                }

                Connections {
                    target: root.model

                    function onRenameChanged() {
                        if (renameEditor.visible && renameInput.text !== root.model.renameDraft)
                            renameInput.text = root.model.renameDraft
                    }
                }
            }
        }
    }

}
