import QtQuick
import Porydaw.Ui

Item {
    id: layer

    required property var chrome
    required property rect automationBandRect
    required property bool automationBandVisible
    required property font controlFont

    // Hiding the automation page cancels a pending value prompt: the page
    // hide path from the drawer plan.
    onAutomationBandVisibleChanged: {
        if (!automationBandVisible)
            promptState.requestCancel()
    }


    anchors.fill: parent

    component ResizeHandle: Rectangle {
        id: handle

        required property rect controlRect
        required property bool controlVisible
        required property int target
        required property string accessibleName
        required property string inputObjectName
        required property string handleObjectName
        required property var controlChrome

        objectName: handleObjectName
        x: controlRect.x
        y: controlRect.y
        width: controlRect.width
        height: controlRect.height
        visible: controlVisible
        color: controlChrome.hoveredHandle === target
               ? controlChrome.handleHoverColor : controlChrome.handleColor
        border.width: activeFocus ? 1 : 0
        border.color: controlChrome.toggleOutline
        activeFocusOnTab: true

        function adjust(direction) {
            controlChrome.adjustResizeHandle(target, direction)
        }

        Keys.onUpPressed: (event) => {
            handle.adjust(1)
            event.accepted = true
        }
        Keys.onDownPressed: (event) => {
            handle.adjust(-1)
            event.accepted = true
        }
        // Cross-axis arrows are deliberate consumed no-ops on this grip, so a
        // focused control never forwards unowned song-edit arrows.
        Keys.onLeftPressed: (event) => event.accepted = true
        Keys.onRightPressed: (event) => event.accepted = true

        Accessible.role: Accessible.Grip
        Accessible.name: accessibleName
        Accessible.description: qsTr("Use Up and Down to resize")
        Accessible.focusable: true
        Accessible.onIncreaseAction: handle.adjust(1)
        Accessible.onDecreaseAction: handle.adjust(-1)

        TimelineInputItem {
            objectName: handle.inputObjectName
            anchors.fill: parent
        }
    }

    ResizeHandle {
        controlRect: layer.chrome.voiceChangesHandleRect
        controlVisible: layer.chrome.voiceChangesHandleVisible
        target: 0
        accessibleName: qsTr("Resize voice changes")
        inputObjectName: "drawerVoiceChangesHandleInput"
        handleObjectName: "drawerVoiceChangesHandle"
        controlChrome: layer.chrome
    }

    ResizeHandle {
        controlRect: layer.chrome.velocityHandleRect
        controlVisible: layer.chrome.velocityHandleVisible
        target: 1
        accessibleName: qsTr("Resize velocity")
        inputObjectName: "drawerVelocityHandleInput"
        handleObjectName: "drawerVelocityHandle"
        controlChrome: layer.chrome
    }

    ResizeHandle {
        controlRect: layer.chrome.automationHandleRect
        controlVisible: layer.chrome.automationHandleVisible
        target: 2
        accessibleName: qsTr("Resize automation")
        inputObjectName: "drawerAutomationHandleInput"
        handleObjectName: "drawerAutomationHandle"
        controlChrome: layer.chrome
    }

    Rectangle {
        id: drawerBar

        x: layer.chrome.barRect.x
        y: layer.chrome.barRect.y
        width: layer.chrome.barRect.width
        height: layer.chrome.barRect.height
        visible: layer.chrome.barVisible
        color: layer.chrome.barBackground
        border.width: layer.chrome.barBorderWidth
        border.color: layer.chrome.barOutline
    }

    component DrawerToggle: Rectangle {
        id: toggle

        required property rect controlRect
        required property bool controlVisible
        required property bool checked
        required property int page
        required property string accessibleName
        required property string iconName
        required property string toggleObjectName
        required property var controlChrome

        objectName: toggleObjectName
        x: controlRect.x
        y: controlRect.y
        width: controlRect.width
        height: controlRect.height
        visible: controlVisible
        color: checked ? controlChrome.toggleCheckedBackground : controlChrome.toggleBackground
        border.width: controlChrome.barBorderWidth
        border.color: controlChrome.toggleOutline
        activeFocusOnTab: true

        function activate() {
            controlChrome.activateToggle(page)
        }

        function activateFromKeyboard(event) {
            activate()
            event.accepted = true
        }

        Keys.onReturnPressed: (event) => toggle.activateFromKeyboard(event)
        Keys.onEnterPressed: (event) => toggle.activateFromKeyboard(event)
        Keys.onSpacePressed: (event) => toggle.activateFromKeyboard(event)
        // Claim the activation keys before window-level shortcuts (the
        // transport play/pause Space binding) can take them from this
        // focused control: an item beats a shortcut only by accepting the
        // ShortcutOverride event.
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Space || event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter

        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.checkable: true
        Accessible.checked: checked
        Accessible.focusable: true
        Accessible.onPressAction: toggle.activate()

        Image {
            anchors.fill: parent
            anchors.margins: controlChrome.toggleIconInset
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width
            sourceSize.height: height
            source: controlChrome.iconSourcePrefix + toggle.iconName
                    + (toggle.checked ? "On/" : "/") + controlChrome.iconRevision
        }
    }

    DrawerToggle {
        controlRect: layer.chrome.voiceChangesToggleRect
        controlVisible: layer.chrome.voiceChangesToggleVisible
        checked: layer.chrome.voiceChangesChecked
        page: 2
        accessibleName: qsTr("Voice changes")
        iconName: "voiceChanges"
        toggleObjectName: "drawerVoiceChangesToggle"
        controlChrome: layer.chrome
    }

    DrawerToggle {
        controlRect: layer.chrome.automationToggleRect
        controlVisible: layer.chrome.automationToggleVisible
        checked: layer.chrome.automationChecked
        page: 0
        accessibleName: qsTr("Automation lanes")
        iconName: "automation"
        toggleObjectName: "drawerAutomationToggle"
        controlChrome: layer.chrome
    }

    DrawerToggle {
        controlRect: layer.chrome.velocityToggleRect
        controlVisible: layer.chrome.velocityToggleVisible
        checked: layer.chrome.velocityChecked
        page: 1
        accessibleName: qsTr("Velocity")
        iconName: "velocity"
        toggleObjectName: "drawerVelocityToggle"
        controlChrome: layer.chrome
    }

    TimelineInputItem {
        objectName: "drawerBarInput"
        x: layer.chrome.barRect.x
        y: layer.chrome.barRect.y
        width: layer.chrome.barRect.width
        height: layer.chrome.barRect.height
        visible: drawerBar.visible
        z: 1
    }

    Image {
        id: drawerDetent
        objectName: "drawerDetent"

        x: layer.chrome.detentRect.x + layer.chrome.detentIconInset
        y: layer.chrome.detentRect.y + layer.chrome.detentIconInset
        width: layer.chrome.detentRect.width - 2 * layer.chrome.detentIconInset
        height: layer.chrome.detentRect.height - 2 * layer.chrome.detentIconInset
        visible: layer.chrome.detentVisible
        fillMode: Image.PreserveAspectFit
        sourceSize.width: width
        sourceSize.height: height
        source: layer.chrome.iconSourcePrefix + "detent/" + layer.chrome.iconRevision
        z: 2
        activeFocusOnTab: layer.chrome.detentEnabled

        function activate() {
            if (layer.chrome.detentEnabled)
                layer.chrome.setDetentChecked(!layer.chrome.detentChecked)
        }

        function activateFromKeyboard(event) {
            activate()
            event.accepted = true
        }

        Keys.onReturnPressed: (event) => drawerDetent.activateFromKeyboard(event)
        Keys.onEnterPressed: (event) => drawerDetent.activateFromKeyboard(event)
        Keys.onSpacePressed: (event) => drawerDetent.activateFromKeyboard(event)
        // Same activation-key claim as DrawerToggle above.
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Space || event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter

        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Velocity detents")
        Accessible.checkable: true
        Accessible.checked: layer.chrome.detentChecked
        Accessible.focusable: layer.chrome.detentEnabled
        Accessible.onPressAction: drawerDetent.activate()

    }

    TimelineInputItem {
        objectName: "drawerDetentInput"
        x: layer.chrome.detentRect.x
        y: layer.chrome.detentRect.y
        width: layer.chrome.detentRect.width
        height: layer.chrome.detentRect.height
        visible: layer.chrome.detentVisible
    }

    TimelineScrollbar {
        id: automationScrollBar
        objectName: "drawerAutomationScrollBar"
        x: layer.chrome.automationScrollbarRect.x
        y: layer.chrome.automationScrollbarRect.y
        width: layer.chrome.automationScrollbarRect.width
        height: layer.chrome.automationScrollbarRect.height
        orientation: Qt.Vertical
        minimum: 0
        value: layer.chrome.automationScrollY
        maximum: layer.chrome.automationMaximumScrollY
        pageStep: layer.chrome.automationViewportHeight
        singleStep: Math.max(1, layer.chrome.automationViewportHeight / 10)
        minimumThumbLength: layer.chrome.scrollbarMinimumThumbHeight
        accessibleName: qsTr("Automation lanes")
        handleColor: layer.chrome.scrollbarHandle
        handleHoverColor: layer.chrome.scrollbarHandleHover
        externalVisible: layer.chrome.automationScrollbarVisible
        visibleWhenNotScrollable: true
        thumbObjectName: "drawerAutomationScrollThumb"

        onValueRequested: (value) => layer.chrome.setAutomationScrollY(Math.round(value))
        onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) =>
                              layer.chrome.scrollAutomationByWheel(pixelY, angleY, inverted)
    }

    // Prompt session state mirrors the track-header rename editor: the
    // finishing guard keeps a focus loss from cancelling after an accept or
    // cancel already ran, and the visibility flip resets it.
    QtObject {
        id: promptState

        property bool finishing: false

        function adoptDraft() {
            valuePromptInput.text = String(layer.chrome.valuePromptInitialValue)
            valuePromptInput.forceActiveFocus(Qt.PopupFocusReason)
            valuePromptInput.selectAll()
        }

        function requestCancel() {
            if (finishing || !layer.chrome.valuePromptVisible)
                return
            finishing = true
            layer.chrome.cancelNodeValuePrompt()
        }

        function acceptDisplayed() {
            // QInputDialog parity: a cleared or intermediate draft (the lone
            // minus sign) keeps the prompt open instead of committing.
            if (finishing || !layer.chrome.valuePromptVisible
                    || !valuePromptInput.acceptableInput)
                return
            finishing = true
            layer.chrome.acceptNodeValuePrompt(
                Number.parseInt(valuePromptInput.text, 10))
        }
    }

    // Inline node value prompt (drawer plan Cleanup phase 2): one Rectangle
    // and TextInput, no QtQuick.Controls and no modal window.
    // AutomationCanvas owns the pending edit and the document revision, so
    // this surface only mirrors the published prompt and reports the
    // displayed value through the chrome invokables.
    Rectangle {
        id: valuePrompt

        objectName: "drawerValuePrompt"
        z: 10
        visible: layer.chrome.valuePromptVisible
        color: layer.chrome.barBackground
        border.width: layer.chrome.barBorderWidth
        border.color: layer.chrome.barOutline

        // Published band rectangles are canonical viewport coordinates:
        // the Quick window is the full viewport, so centering is direct.
        x: layer.automationBandRect.x
           + Math.max(0, (layer.automationBandRect.width - width) / 2)
        y: layer.automationBandRect.y
           + Math.max(0, (layer.automationBandRect.height - height) / 2)

        // Card-local pointer shield: presses, drags and the wheel on the
        // card chrome stop here so the automation lane underneath never
        // sees them. The field keeps its own pointer handling and the
        // open draft stays untouched.
        MouseArea {
            id: promptShield

            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onWheel: (wheel) => wheel.accepted = true
        }

        // Font-derived sizing with the tiny raw insets OtherStripToolTip
        // already uses for overlay chrome.
        readonly property real outerPadding: 8
        readonly property real rowGap: 6
        readonly property real edgeMargin: 4
        readonly property real fieldInsetH: 6
        readonly property real fieldInsetV: 3
        readonly property real maximumWidth:
            Math.max(0, layer.automationBandRect.width - 2 * edgeMargin)
        readonly property real promptFieldMinWidth:
            Math.max(promptFontMetrics.advanceWidth(
                         String(layer.chrome.valuePromptMinimum)),
                     promptFontMetrics.advanceWidth(
                         String(layer.chrome.valuePromptMaximum)))
            + 2 * (fieldInsetH + layer.chrome.barBorderWidth)
        readonly property real contentWidth:
            Math.max(promptTitle.implicitWidth,
                     promptLabel.implicitWidth, promptFieldMinWidth)
        readonly property real fieldHeight:
            promptFontMetrics.height
            + 2 * (fieldInsetV + layer.chrome.barBorderWidth)
        width: Math.min(maximumWidth, contentWidth + 2 * outerPadding)
        height: promptTitle.implicitHeight + rowGap + promptLabel.implicitHeight
                + rowGap + fieldHeight + 2 * outerPadding

        onVisibleChanged: {
            if (visible) {
                promptState.finishing = false
                promptState.adoptDraft()
            } else {
                promptState.finishing = false
            }
        }

        // A pending prompt replaced without an intermediate hide (the canvas
        // clears then sets) re-arms the draft too; consult the chrome
        // property, not the lagging visible binding of this item.
        Connections {
            target: layer.chrome

            function onValuePromptChanged() {
                if (layer.chrome.valuePromptVisible)
                    promptState.adoptDraft()
            }
        }

        // Terminal key sink for the open prompt: this handler only sees keys
        // the focused TextInput already declined, so everything is consumed
        // here — including left-over command chords — instead of bubbling to
        // the shared timeline policy and mutating the song.
        Keys.onPressed: (event) => event.accepted = true
        Keys.onReleased: (event) => event.accepted = true

        Accessible.role: Accessible.Client
        Accessible.name: layer.chrome.valuePromptTitle

        FontMetrics {
            id: promptFontMetrics

            font: layer.controlFont
        }

        Text {
            id: promptTitle

            x: valuePrompt.outerPadding
            y: valuePrompt.outerPadding
            width: valuePrompt.width - 2 * valuePrompt.outerPadding
            color: layer.chrome.toggleIconTint
            font: layer.controlFont
            text: layer.chrome.valuePromptTitle
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Text {
            id: promptLabel

            x: valuePrompt.outerPadding
            y: promptTitle.y + promptTitle.implicitHeight + valuePrompt.rowGap
            width: valuePrompt.width - 2 * valuePrompt.outerPadding
            color: layer.chrome.toggleIconTint
            font: layer.controlFont
            text: layer.chrome.valuePromptLabel
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Rectangle {
            id: promptField

            objectName: "drawerValuePromptField"

            x: valuePrompt.outerPadding
            y: promptLabel.y + promptLabel.implicitHeight + valuePrompt.rowGap
            width: valuePrompt.width - 2 * valuePrompt.outerPadding
            height: valuePrompt.fieldHeight
            color: layer.chrome.toggleBackground
            border.width: layer.chrome.barBorderWidth
            border.color: valuePromptInput.activeFocus
                          ? layer.chrome.toggleCheckedBackground
                          : layer.chrome.toggleOutline

            TextInput {
                id: valuePromptInput

                objectName: "drawerValuePromptInput"
                anchors.fill: parent
                anchors.leftMargin: valuePrompt.fieldInsetH
                anchors.rightMargin: valuePrompt.fieldInsetH
                clip: true
                color: layer.chrome.toggleIconTint
                font: layer.controlFont
                selectionColor: layer.chrome.toggleCheckedBackground
                selectedTextColor: layer.chrome.toggleCheckedIconTint
                renderType: TextInput.NativeRendering
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                validator: IntValidator {
                    bottom: layer.chrome.valuePromptMinimum
                    top: layer.chrome.valuePromptMaximum
                }

                onActiveFocusChanged: {
                    if (valuePrompt.visible && !activeFocus
                            && !promptState.finishing)
                        promptState.requestCancel()
                }
                Keys.onReturnPressed: (event) => {
                    promptState.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    promptState.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onEscapePressed: (event) => {
                    promptState.requestCancel()
                    event.accepted = true
                }
                // Blanket shortcut claim while the prompt owns focus: no window
                // QAction chord may fire over the draft. Accepting the
                // override delivers the key as a normal press to this
                // TextInput, which still performs its native Copy, Paste,
                // Undo and SelectAll processing; keys it does not handle end
                // in the card terminal sink.
                Keys.onShortcutOverride: (event) => event.accepted = true

                Accessible.role: Accessible.EditableText
                Accessible.name: layer.chrome.valuePromptLabel
                Accessible.description: layer.chrome.valuePromptTitle
                Accessible.editable: true
                Accessible.focusable: true
            }
        }
    }
}
