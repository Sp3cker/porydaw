pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property rect bandRect
    required property bool bandVisible
    required property var model
    required property font controlFont

    readonly property var headersModel: model
    readonly property var appearance: headersModel.appearance
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

    width: bandRect.width
    height: bandRect.height

    FontMetrics {
        id: normalTitleMetrics
        font: Qt.font(root.headersModel.normalTitleFont)
        onLineSpacingChanged: Qt.callLater(root.configureTextMetrics)
    }

    FontMetrics {
        id: boldTitleMetrics
        font: Qt.font(root.headersModel.boldTitleFont)
        onLineSpacingChanged: Qt.callLater(root.configureTextMetrics)
    }

    FontMetrics {
        id: subtitleMetrics
        font: Qt.font(root.headersModel.subtitleFont)
        onLineSpacingChanged: Qt.callLater(root.configureTextMetrics)
    }

    function configureTextMetrics() {
        root.headersModel.configureTextMetrics(Math.round(normalTitleMetrics.lineSpacing),
                                               Math.round(boldTitleMetrics.lineSpacing),
                                               Math.round(subtitleMetrics.lineSpacing))
    }

    Component.onCompleted: {
        root.headersModel.dragDistance = Qt.styleHints.startDragDistance
        configureTextMetrics()
    }

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

    function deliverWheel(event) {
        const direction = event.inverted ? -1 : 1
        root.headersModel.handleWheel(direction * event.angleDelta.x,
                                      direction * event.angleDelta.y,
                                      direction * event.pixelDelta.x,
                                      direction * event.pixelDelta.y,
                                      event.modifiers, event.phase)
        event.accepted = true
    }

    component TrackHeaderToggle: Item {
        id: toggle

        required property var controlRect
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
                root.headersModel.activateSolo(track)
            else
                root.headersModel.activateMute(track)
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

            Item {
                id: trackHeaderRowArea

                width: Math.max(0, trackHeaderViewport.width - root.headersModel.scrollbarWidth)
                height: parent.height
                clip: true

                Item {
                    id: translatedRows

                    y: -root.headersModel.scrollY
                    width: parent.width
                    height: root.headersModel.contentHeight
                    z: 2

                    Repeater {
                        id: trackHeaderRows

                        objectName: "timelineTrackHeaderRows"
                        model: root.headersModel.rows

                        delegate: Item {
                            id: trackHeaderRow

                            required property int index
                            required property bool isAddTrack
                            required property int track
                            required property string title
                            required property string subtitle
                            required property var titleRect
                            required property var subtitleRect
                            required property var selectedTitleOffset
                            required property color baseColor
                            required property color overlayColor
                            required property color titleColor
                            required property color subtitleColor
                            required property var titleFont
                            required property var subtitleFont
                            required property bool titleBold
                            required property bool muteChecked
                            required property bool soloChecked
                            required property bool muteHovered
                            required property bool mutePressed
                            required property bool soloHovered
                            required property bool soloPressed
                            required property bool addHovered
                            required property bool addPressed
                            required property color activityDimColor
                            required property color activityActiveColor
                            required property real activityLeftHeight
                            required property real activityRightHeight

                            y: index * root.headersModel.rowHeight
                            width: translatedRows.width
                            height: root.headersModel.rowHeight

                            property bool complete: false

                            function publishSelectedTitleOffset() {
                                if (!complete || isAddTrack || !titleBold)
                                    return
                                const label = boldTitleMetrics.elidedText(title, Text.ElideRight,
                                                                          titleRect.width)
                                const normal = normalTitleMetrics.tightBoundingRect(label)
                                const bold = boldTitleMetrics.tightBoundingRect(label)
                                root.headersModel.setSelectedTitleOffset(track,
                                    normal.x + normal.width / 2 - bold.x - bold.width / 2,
                                    normal.y + normal.height / 2 - bold.y - bold.height / 2)
                            }

                            onTitleChanged: publishSelectedTitleOffset()
                            onTitleBoldChanged: publishSelectedTitleOffset()
                            onTitleRectChanged: publishSelectedTitleOffset()
                            onTitleFontChanged: publishSelectedTitleOffset()
                            onTrackChanged: publishSelectedTitleOffset()
                            Component.onCompleted: {
                                complete = true
                                publishSelectedTitleOffset()
                            }

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
                                width: root.headersModel.activityWidth
                                height: Math.max(0, trackHeaderRow.height - root.headersModel.separatorWidth)
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
                                y: Math.max(0, trackHeaderRow.height - root.headersModel.separatorWidth)
                                width: parent.width
                                height: root.headersModel.separatorWidth
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
                                clip: contentWidth > width || contentHeight > height
                                color: trackHeaderRow.titleColor
                                font: Qt.font(trackHeaderRow.titleFont)
                                text: trackHeaderRow.title
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                verticalAlignment: Text.AlignVCenter
                            }

                            // The subtitle remains a voice hit target, not a button fill.
                            Text {
                                x: trackHeaderRow.subtitleRect.x
                                y: trackHeaderRow.subtitleRect.y
                                width: trackHeaderRow.subtitleRect.width
                                height: trackHeaderRow.subtitleRect.height
                                visible: !trackHeaderRow.isAddTrack
                                clip: contentWidth > width || contentHeight > height
                                color: trackHeaderRow.subtitleColor
                                font: Qt.font(trackHeaderRow.subtitleFont)
                                text: trackHeaderRow.subtitle
                                textFormat: Text.PlainText
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                verticalAlignment: Text.AlignVCenter
                            }

                            TrackHeaderToggle {
                                visible: !trackHeaderRow.isAddTrack
                                controlRect: root.headersModel.muteButtonRect
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
                                controlRect: root.headersModel.soloButtonRect
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
                                    root.headersModel.activateAddTrack()
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
                    forceActiveFocus(Qt.MouseFocusReason)
                    mouse.accepted = root.headersModel.beginPointer(mouse.x, mouse.y,
                                                                    mouse.button, mouse.modifiers)
                }
                onPositionChanged: (mouse) => {
                    if (pressed)
                        root.headersModel.updatePointer(mouse.x, mouse.y, mouse.modifiers)
                    else
                        root.headersModel.updateHover(mouse.x, mouse.y)
                }
                onReleased: (mouse) => {
                    mouse.accepted = root.headersModel.endPointer(mouse.x, mouse.y,
                                                                  mouse.button, mouse.modifiers)
                }
                onDoubleClicked: (mouse) => {
                    mouse.accepted = root.headersModel.doublePointer(mouse.x, mouse.y,
                                                                     mouse.button, mouse.modifiers)
                }
                onCanceled: root.headersModel.inputCancelled(1) // PointerUngrabbed
                onExited: {
                    if (!pressed)
                        root.headersModel.clearHover()
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

            Rectangle {
                objectName: "timelineTrackHeaderReorderMarker"
                y: Math.min(Math.max(0, root.headersModel.reorderIndicatorY),
                            Math.max(0, trackHeaderRowArea.height - height))
                width: trackHeaderRowArea.width
                height: root.headersModel.reorderIndicatorHeight
                visible: root.headersModel.reorderIndicatorVisible && height > 0
                color: root.reorderIndicator
                z: 3
            }

            // TimelineScrollbar's vertical chrome and gesture geometry, without
            // its legacy TimelineGestureScrollbar and HoverHint C++ dependencies.
            Item {
                id: trackHeaderScrollBar

                objectName: "timelineTrackHeaderScrollBar"
                x: trackHeaderRowArea.width
                width: Math.max(0, root.headersModel.scrollbarWidth)
                height: parent.height
                z: 4
                visible: root.bandVisible && scrollable
                activeFocusOnTab: scrollable || activeFocus

                readonly property real span: Math.max(0, root.headersModel.maximumScrollY)
                readonly property bool scrollable: span > 0
                readonly property real thumbLength: {
                    if (!(height > 0) || !scrollable)
                        return 0
                    const pageStep = root.headersModel.viewportHeight
                    const fraction = pageStep > 0 ? Math.min(1, pageStep / (span + pageStep)) : 0
                    return Math.min(height, Math.max(root.headersModel.scrollbarMinimumThumbHeight,
                                                    fraction * height))
                }
                readonly property real thumbTravel: Math.max(0, height - thumbLength)
                readonly property real thumbPos: !scrollable || thumbTravel <= 0
                                                 ? 0
                                                 : Math.min(span, Math.max(0, root.headersModel.scrollY))
                                                   / span * thumbTravel
                property real dragStartValue: 0
                property real dragStartPosition: 0
                property real dragLastPosition: 0
                property bool dragThresholdReached: false

                onSpanChanged: rebaseDrag()
                onThumbTravelChanged: rebaseDrag()

                function requestScroll(value) {
                    if (scrollable)
                        root.headersModel.scrollY = Math.max(0, Math.min(span, value))
                }

                function requestLine(direction) {
                    requestScroll(root.headersModel.scrollY
                                  + direction * Math.max(0, root.headersModel.rowHeight))
                }

                function requestPage(direction) {
                    requestScroll(root.headersModel.scrollY
                                  + direction * Math.max(0, root.headersModel.viewportHeight))
                }

                function rebaseDrag() {
                    if (!thumbMouse || !thumbMouse.pressed || !dragThresholdReached)
                        return
                    dragStartValue = Math.max(0, Math.min(span, root.headersModel.scrollY))
                    dragStartPosition = dragLastPosition
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Up)
                        requestLine(-1)
                    else if (event.key === Qt.Key_Down)
                        requestLine(1)
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                        // Cross-axis arrows stay consumed, as in TimelineScrollbar.
                    } else if (event.key === Qt.Key_PageUp)
                        requestPage(-1)
                    else if (event.key === Qt.Key_PageDown)
                        requestPage(1)
                    else if (event.key === Qt.Key_Home)
                        requestScroll(0)
                    else if (event.key === Qt.Key_End)
                        requestScroll(span)
                    else
                        return
                    event.accepted = true
                }

                Accessible.role: Accessible.ScrollBar
                Accessible.name: qsTr("Track headers")
                Accessible.description: qsTr("Use arrow or page keys to scroll")
                Accessible.focusable: activeFocusOnTab
                Accessible.onIncreaseAction: requestLine(1)
                Accessible.onDecreaseAction: requestLine(-1)
                Accessible.onScrollUpAction: requestPage(-1)
                Accessible.onScrollDownAction: requestPage(1)
                Accessible.onScrollLeftAction: requestPage(-1)
                Accessible.onScrollRightAction: requestPage(1)
                Accessible.onPreviousPageAction: requestPage(-1)
                Accessible.onNextPageAction: requestPage(1)

                MouseArea {
                    anchors.fill: parent
                    enabled: trackHeaderScrollBar.scrollable

                    onClicked: (mouse) => {
                        if (mouse.y >= trackHeaderScrollBar.thumbPos
                                && mouse.y < trackHeaderScrollBar.thumbPos
                                             + trackHeaderScrollBar.thumbLength)
                            return
                        trackHeaderScrollBar.requestPage(mouse.y < trackHeaderScrollBar.thumbPos ? -1 : 1)
                    }
                }

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

                Rectangle {
                    objectName: "timelineTrackHeaderScrollThumb"
                    y: trackHeaderScrollBar.thumbPos
                    width: parent.width
                    height: trackHeaderScrollBar.thumbLength
                    visible: trackHeaderScrollBar.scrollable && width > 0 && height > 0
                    color: thumbHover.hovered ? root.scrollbarHandleHover : root.scrollbarHandle

                    HoverHandler {
                        id: thumbHover
                    }
                }

                MouseArea {
                    id: thumbMouse

                    anchors.fill: parent
                    enabled: trackHeaderScrollBar.scrollable && trackHeaderScrollBar.thumbTravel > 0
                    hoverEnabled: false
                    z: 1

                    onPressed: (mouse) => {
                        if (mouse.y < trackHeaderScrollBar.thumbPos
                                || mouse.y >= trackHeaderScrollBar.thumbPos
                                              + trackHeaderScrollBar.thumbLength) {
                            mouse.accepted = false
                            return
                        }
                        trackHeaderScrollBar.dragStartValue = Math.max(0,
                            Math.min(trackHeaderScrollBar.span, root.headersModel.scrollY))
                        trackHeaderScrollBar.dragStartPosition = mouse.y
                        trackHeaderScrollBar.dragLastPosition = mouse.y
                        trackHeaderScrollBar.dragThresholdReached = false
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed)
                            return
                        trackHeaderScrollBar.dragLastPosition = mouse.y
                        if (!trackHeaderScrollBar.dragThresholdReached) {
                            if (Math.abs(mouse.y - trackHeaderScrollBar.dragStartPosition)
                                    < Qt.styleHints.startDragDistance)
                                return
                            trackHeaderScrollBar.dragThresholdReached = true
                        }
                        if (trackHeaderScrollBar.thumbTravel <= 0)
                            return
                        trackHeaderScrollBar.requestScroll(trackHeaderScrollBar.dragStartValue
                            + (mouse.y - trackHeaderScrollBar.dragStartPosition)
                              / trackHeaderScrollBar.thumbTravel * trackHeaderScrollBar.span)
                    }
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

                readonly property int rowIndex: root.rowIndexForTrack(root.headersModel.renamingTrack)
                x: root.headersModel.renameEditorRect.x
                y: rowIndex * root.headersModel.rowHeight - root.headersModel.scrollY
                   + root.headersModel.renameEditorRect.y
                width: root.headersModel.renameEditorRect.width
                height: root.headersModel.renameEditorRect.height
                visible: headerBand.visible && rowIndex >= 0
                property bool finishing: false

                function adoptRenameDraft() {
                    renameInput.text = root.headersModel.renameDraft
                    renameInput.forceActiveFocus(Qt.PopupFocusReason)
                    renameInput.selectAll()
                }

                function finishRename(commit, entered) {
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

                HoverHandler {
                    cursorShape: Qt.IBeamCursor
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
                    Accessible.description: root.headersModel.renameDraft
                    Accessible.focusable: true
                }

                Connections {
                    target: root.headersModel

                    function onRenameDraftChanged() {
                        if (renameEditor.visible && renameInput.text !== root.headersModel.renameDraft)
                            renameInput.text = root.headersModel.renameDraft
                    }
                }
            }
        }
    }
}
