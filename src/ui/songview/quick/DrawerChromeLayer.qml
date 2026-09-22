import QtQuick
import Porydaw.Ui

Item {
    id: layer

    required property var chrome
    required property font controlFont

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
        accessibleName: qsTr("Resize voice-change drawer")
        inputObjectName: "drawerVoiceChangesHandleInput"
        handleObjectName: "drawerVoiceChangesHandle"
        controlChrome: layer.chrome
    }

    ResizeHandle {
        controlRect: layer.chrome.velocityHandleRect
        controlVisible: layer.chrome.velocityHandleVisible
        target: 1
        accessibleName: qsTr("Resize velocity drawer")
        inputObjectName: "drawerVelocityHandleInput"
        handleObjectName: "drawerVelocityHandle"
        controlChrome: layer.chrome
    }

    ResizeHandle {
        controlRect: layer.chrome.automationHandleRect
        controlVisible: layer.chrome.automationHandleVisible
        target: 2
        accessibleName: qsTr("Resize automation drawer")
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
        // Claim only the plain Return/Enter activation keys before
        // window-level shortcuts can take them from this focused control: an
        // item beats a shortcut only by accepting the ShortcutOverride
        // event. Bare Space stays unclaimed so the transport play/pause
        // window shortcut outranks incidental focus in this persistent
        // control.
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Return || event.key === Qt.Key_Enter

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
            source: "image://drawerchrome/" + toggle.iconName
                    + (toggle.checked ? "On/" : "/") + controlChrome.iconRevision
        }
    }

    DrawerToggle {
        controlRect: layer.chrome.voiceChangesToggleRect
        controlVisible: layer.chrome.voiceChangesToggleVisible
        checked: layer.chrome.voiceChangesChecked
        page: 2
        accessibleName: qsTr("Voice-change drawer")
        iconName: "voiceChanges"
        toggleObjectName: "drawerVoiceChangesToggle"
        controlChrome: layer.chrome
    }

    DrawerToggle {
        controlRect: layer.chrome.automationToggleRect
        controlVisible: layer.chrome.automationToggleVisible
        checked: layer.chrome.automationChecked
        page: 0
        accessibleName: qsTr("Automation drawer")
        iconName: "automation"
        toggleObjectName: "drawerAutomationToggle"
        controlChrome: layer.chrome
    }

    DrawerToggle {
        controlRect: layer.chrome.velocityToggleRect
        controlVisible: layer.chrome.velocityToggleVisible
        checked: layer.chrome.velocityChecked
        page: 1
        accessibleName: qsTr("Velocity drawer")
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
        source: "image://drawerchrome/detent/" + layer.chrome.iconRevision
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
        // Same non-transport claim as DrawerToggle above: only the plain
        // Return/Enter activation keys.
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Return || event.key === Qt.Key_Enter

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

    // Prompt session state mirrors the track-header rename editor: the
    // finishing guard keeps a focus loss from cancelling after an accept or
    // cancel already ran, and the visibility flip resets it.

}
