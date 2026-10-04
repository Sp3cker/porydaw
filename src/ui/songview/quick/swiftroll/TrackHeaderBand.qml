pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui
import PorydawApp as App

Item {
    id: root

    final required property rect bandRect
    final required property bool bandVisible
    final required property App.TrackHeadersPresenter model
    final required property font controlFont
    final required property App.MouseHints hintService
    final required property bool hintScopeAllowed

    final readonly property App.TrackHeadersPresenter headersModel: model
    final readonly property App.TrackHeadersPresenter appearance: headersModel
    final property color inputBackground
    final property color inputText
    final property color inputOutline
    final property color focusOutline
    final property color scrollbarHandle
    final property color scrollbarHandleHover
    final property color reorderIndicator
    final property color selectionBackground
    final property color selectionText
    property real rowAreaWidth
    Binding {
        when: root.appearance !== null
        restoreMode: Binding.RestoreNone
        root.inputBackground: root.appearance?.inputBackground
        root.inputText: root.appearance?.inputText
        root.inputOutline: root.appearance?.inputOutline
        root.focusOutline: root.appearance?.focusOutline
        root.scrollbarHandle: root.appearance?.scrollbarHandle
        root.scrollbarHandleHover: root.appearance?.scrollbarHandleHover
        root.reorderIndicator: root.appearance?.reorderIndicator
        root.selectionBackground: root.appearance?.selectionBackground
        root.selectionText: root.appearance?.selectionText
        normalTitleMetrics.font: root.headersModel?.normalTitleFont
        boldTitleMetrics.font: root.headersModel?.boldTitleFont
        subtitleMetrics.font: root.headersModel?.subtitleFont
        root.rowAreaWidth: Math.max(0, trackHeaderViewport.width - root.headersModel?.scrollbarWidth)
    }

    width: bandRect.width
    height: bandRect.height

    FontMetrics {
        id: normalTitleMetrics
        onLineSpacingChanged: Qt.callLater(root.configureTextMetrics)
    }

    FontMetrics {
        id: boldTitleMetrics
        onLineSpacingChanged: Qt.callLater(root.configureTextMetrics)
    }

    FontMetrics {
        id: subtitleMetrics
        onLineSpacingChanged: Qt.callLater(root.configureTextMetrics)
    }

    function configureTextMetrics(): void {
        if (!root.headersModel)
            return
        root.headersModel.configureTextMetrics(Math.round(normalTitleMetrics.lineSpacing),
                                               Math.round(boldTitleMetrics.lineSpacing),
                                               Math.round(subtitleMetrics.lineSpacing))
    }

    function restoreHeaderFocus(): void {
        headerInput.forceActiveFocus(Qt.OtherFocusReason)
    }

    Component.onCompleted: {
        root.headersModel.dragDistance = Qt.styleHints.startDragDistance
        configureTextMetrics()
    }

    function rowIndexForTrack(track: int): int {
        if (track < 0 || !root.headersModel)
            return -1
        for (let index = 0; index < trackHeaderRowArea.rowCount; ++index) {
            const row = root.headersModel.rowAt(index)
            if (row && row.track === track)
                return index
        }
        return -1
    }
    function hintProfileAt(x: real, y: real): int {
        if (!root.headersModel || root.headersModel.rowHeight <= 0)
            return HintProfiles.Empty
        const index = Math.floor((y + root.headersModel.scrollY) / root.headersModel.rowHeight)
        const row = root.headersModel.rowAt(index)
        if (!row || row.isAddTrack)
            return HintProfiles.Empty
        const localY = y + root.headersModel.scrollY - index * root.headersModel.rowHeight
        const mute = root.headersModel.muteButtonRect
        const solo = root.headersModel.soloButtonRect
        if ((x >= mute.x && x < mute.x + mute.width
             && localY >= mute.y && localY < mute.y + mute.height)
                || (x >= solo.x && x < solo.x + solo.width
                    && localY >= solo.y && localY < solo.y + solo.height))
            return HintProfiles.Empty
        return HintProfiles.TrackScope
    }

    function deliverWheel(event: WheelEvent): void {
        const direction = event.inverted ? -1 : 1
        root.headersModel.handleWheel(direction * event.angleDelta.x,
                                      direction * event.angleDelta.y,
                                      direction * event.pixelDelta.x,
                                      direction * event.pixelDelta.y,
                                      event.modifiers, event.phase)
        event.accepted = true
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

            TrackHeaderRows {
                id: trackHeaderRowArea

                headersModel: root.headersModel
                appearance: root.appearance
                controlFont: root.controlFont
                normalMetrics: normalTitleMetrics
                boldMetrics: boldTitleMetrics
                rowAreaWidth: root.rowAreaWidth
            }

            MouseArea {
                id: headerInput

                objectName: "timelineTrackHeadersInput"
                width: trackHeaderRowArea.width
                height: trackHeaderRowArea.height
                z: 1
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                Accessible.description: qsTr("Track headers")

                onPressed: (mouse) => {
                    headerMoves.flush()
                    forceActiveFocus(Qt.MouseFocusReason)
                    mouse.accepted = root.headersModel.beginPointer(mouse.x, mouse.y,
                                                                    mouse.button, mouse.modifiers)
                }
                onPositionChanged: (mouse) => {
                    headerMoves.enqueue(mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
                }
                onReleased: (mouse) => {
                    headerMoves.flush()
                    headerHint.settleRelease(headerInput.mapToItem(null, mouse.x, mouse.y))
                    mouse.accepted = root.headersModel.endPointer(mouse.x, mouse.y,
                                                                  mouse.button, mouse.modifiers)
                }
                onDoubleClicked: (mouse) => {
                    headerMoves.flush()
                    mouse.accepted = root.headersModel.doublePointer(mouse.x, mouse.y,
                                                                     mouse.button, mouse.modifiers)
                }
                onCanceled: {
                    headerMoves.flush()
                    headerHint.settleRelease(headerInput.mapToItem(null,
                        headerInput.mouseX, headerInput.mouseY))
                    root.headersModel.inputCancelled(1) // PointerUngrabbed
                }
                onExited: {
                    headerMoves.flush()
                    if (!pressed)
                        root.headersModel.clearHover()
                }
                MoveCoalescer {
                    id: headerMoves
                    dispatch: headerMoves.dispatchMove
                    function dispatchMove(x: real, y: real, buttons: int, modifiers: int): void {
                        if (buttons !== Qt.NoButton)
                            root.headersModel.updatePointer(x, y, modifiers)
                        else
                            root.headersModel.updateHover(x, y)
                    }
                }

                // As in TimelineScrollbar, exactly one handler owns diagonal input.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        if (event.pixelDelta.x === 0 && event.angleDelta.x === 0)
                            root.deliverWheel(event)
                    }
                }

                WheelHandler {
                    orientation: Qt.Horizontal
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        if (event.pixelDelta.x !== 0 || event.angleDelta.x !== 0)
                            root.deliverWheel(event)
                    }
                }
            }
            HoverHint {
                id: headerHint
                source: headerInput
                hintService: root.hintService
                scopeAllowed: root.hintScopeAllowed && !renameEditor.visible
                gestureOwning: headerInput.pressed
                profile: root.hintProfileAt(point.position.x, point.position.y)
            }

            Rectangle {
                objectName: "timelineTrackHeaderReorderMarker"
                id: reorderMarker
                Binding {
                    when: root.headersModel !== null
                    restoreMode: Binding.RestoreNone
                    reorderMarker.y: Math.min(Math.max(0, root.headersModel?.reorderIndicatorY),
                                             Math.max(0, trackHeaderRowArea.height - reorderMarker.height))
                    reorderMarker.height: root.headersModel?.reorderIndicatorHeight
                }
                width: trackHeaderRowArea.width
                visible: root.headersModel !== null && root.headersModel.reorderIndicatorVisible && height > 0
                color: root.reorderIndicator
                z: 3
            }

            TrackHeaderScrollbar {
                id: trackHeaderScrollBar

                headersModel: root.headersModel
                bandVisible: root.bandVisible
                scrollbarHandle: root.scrollbarHandle
                scrollbarHandleHover: root.scrollbarHandleHover
                rowAreaWidth: trackHeaderRowArea.width
                onWheelDelivered: (event) => root.deliverWheel(event)
            }
            HoverHint {
                source: trackHeaderScrollBar
                hintService: root.hintService
                scopeAllowed: root.hintScopeAllowed
                profile: HintProfiles.Empty
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

                readonly property int rowIndex: root.headersModel ? root.rowIndexForTrack(root.headersModel.renamingTrack) : -1
                Binding {
                    when: root.headersModel !== null && root.headersModel.renameEditorRect !== null
                    restoreMode: Binding.RestoreNone
                    renameEditor.x: root.headersModel?.renameEditorRect?.x
                    renameEditor.y: renameEditor.rowIndex * root.headersModel?.rowHeight - root.headersModel?.scrollY
                                    + root.headersModel?.renameEditorRect?.y
                    renameEditor.width: root.headersModel?.renameEditorRect?.width
                    renameEditor.height: root.headersModel?.renameEditorRect?.height
                }
                visible: headerBand.visible && rowIndex >= 0
                property bool finishing: false

                function adoptRenameDraft(): void {
                    renameInput.text = root.headersModel.renameDraft
                    renameInput.forceActiveFocus(Qt.PopupFocusReason)
                    renameInput.selectAll()
                }

                function finishRename(commit: bool, entered: bool): void {
                    if (finishing || !visible)
                        return
                    finishing = true
                    root.headersModel.finishRename(commit, entered)
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

                HoverHint {
                    source: renameEditor
                    hintService: root.hintService
                    scopeAllowed: root.hintScopeAllowed
                    cursorShape: Qt.IBeamCursor
                    profile: HintProfiles.TextSelection
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
                    selectionColor: root.selectionBackground
                    selectedTextColor: root.selectionText
                    font: root.controlFont
                    selectByMouse: true

                    onTextEdited: root.headersModel.renameDraft = text
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
                    Binding {
                        when: root.headersModel !== null
                        restoreMode: Binding.RestoreNone
                        renameInput.Accessible.description: root.headersModel?.renameDraft
                    }
                    Accessible.focusable: true
                }

                Connections {
                    target: root.headersModel

                    function onRenameDraftChanged(): void {
                        if (renameEditor.visible && renameInput.text !== root.headersModel.renameDraft)
                            renameInput.text = root.headersModel.renameDraft
                    }
                }
            }
        }
    }
}
