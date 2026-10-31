pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import PorydawStyle
import Porydaw.Ui
import Porydaw.Icons
import PorydawApp

// The Virtual MIDI Keyboard: a tool window above Porydaw's windows, hidden with the
// app, whose piano plays the selected track's voice. While it has the keys its focus
// item claims the note keys and - / =; every other key reaches the shell's shortcuts.
ThemedWindow {
    id: keyboardWindow
    objectName: "virtualKeyboardWindow"
    required property VirtualKeyboardPresenter presenter
    required property ShellPresenter shell
    required property Window hostWindow
    required property ApplicationSession applicationSession
    readonly property real unit: applicationSession.baseFontPx
    readonly property LayoutSpaces spaces: applicationSession.layoutSpaces
    readonly property alias keySurface: keys
    flags: Qt.Tool
    title: qsTr("Virtual MIDI Keyboard")
    font: applicationSession.typographyFonts.body
    width: Math.round(16 * 2.5 * unit)
    height: controls.implicitHeight + Math.max(8 * unit, piano.minimumHeight) + 3 * spaces.two
    minimumWidth: Math.round(16 * 1.6 * unit)
    minimumHeight: controls.implicitHeight + piano.minimumHeight + 3 * spaces.two

    Component.onCompleted: {
        keyboardWindow.presenter.configurePlatform(Qt.platform.pluginName)
        const saved = keyboardWindow.presenter
        if (saved.windowWidth <= 0)
            return
        const centerX = saved.windowX + saved.windowWidth / 2
        const centerY = saved.windowY + saved.windowHeight / 2
        const screens = Application.screens
        for (let index = 0; index < screens.length; ++index) {
            const screen = screens[index]
            if (centerX >= screen.virtualX && centerX < screen.virtualX + screen.width
                    && centerY >= screen.virtualY && centerY < screen.virtualY + screen.height) {
                keyboardWindow.x = saved.windowX
                keyboardWindow.y = saved.windowY
                keyboardWindow.width = Math.max(keyboardWindow.minimumWidth, saved.windowWidth)
                keyboardWindow.height = Math.max(keyboardWindow.minimumHeight, saved.windowHeight)
                return
            }
        }
    }
    Component.onDestruction: keyboardWindow.rememberGeometry()

    // The user's toggle hands it the keys; startup's restore leaves them with the shell.
    function present(): void {
        keyboardWindow.show()
        keyboardWindow.raise()
        if (keyboardWindow.presenter.activateOnShow) {
            keyboardWindow.requestActivate()
            keys.forceActiveFocus(Qt.ActiveWindowFocusReason)
        } else {
            keyboardWindow.hostWindow.requestActivate()
        }
    }
    function dismiss(): void {
        keyboardWindow.rememberGeometry()
        keyboardWindow.hide()
    }
    function rememberGeometry(): void {
        if (keyboardWindow.visible && keyboardWindow.width > 0 && keyboardWindow.height > 0)
            keyboardWindow.presenter.persistGeometry(keyboardWindow.x, keyboardWindow.y,
                                                     keyboardWindow.width, keyboardWindow.height)
    }

    // A hide by the window system (the owner minimised) lets every note go too.
    onVisibleChanged: {
        if (!keyboardWindow.visible)
            keyboardWindow.presenter.focusLost()
    }
    // The title bar's close hides it for good; a quit's close leaves it shown next launch.
    onClosing: {
        keyboardWindow.rememberGeometry()
        if (keyboardWindow.hostWindow.visible && keyboardWindow.shell.sceneActive)
            keyboardWindow.presenter.closeRequested()
    }

    // Every shell window command (Space, Alt+B, Ctrl+Z...) still works from here; the
    // focus item's ShortcutOverride claim keeps the note keys from them.
    WindowActionShortcuts {
        shell: keyboardWindow.shell
        namePrefix: "virtualKeyboardShortcut_"
    }

    FontMetrics {
        id: metrics
        font: keyboardWindow.font
    }

    Item {
        id: keys
        objectName: "virtualKeyboardKeys"
        anchors.fill: parent
        focus: true
        Accessible.role: Accessible.Grouping
        Accessible.name: keyboardWindow.title

        NativeKeyCodes {
            id: nativeCodes
            target: keys
        }
        Keys.onShortcutOverride: event => {
            event.accepted = keyboardWindow.presenter.claimsKey(
                event.key, event.modifiers, nativeCodes.scanCode(), nativeCodes.virtualKey())
        }
        Keys.onPressed: event => {
            event.accepted = keyboardWindow.presenter.keyPressed(
                event.key, event.modifiers, nativeCodes.scanCode(), nativeCodes.virtualKey(),
                event.isAutoRepeat)
        }
        Keys.onReleased: event => {
            event.accepted = keyboardWindow.presenter.keyReleased(
                event.key, event.modifiers, nativeCodes.scanCode(), nativeCodes.virtualKey(),
                event.isAutoRepeat)
        }
        // Deactivation, a modal dialog or a popup taking the keys: their releases
        // will go elsewhere, so everything held stops now.
        onActiveFocusChanged: {
            if (!keys.activeFocus)
                keyboardWindow.presenter.focusLost()
        }

        RowLayout {
            id: controls
            objectName: "virtualKeyboardControls"
            x: keyboardWindow.spaces.two
            y: keyboardWindow.spaces.two
            width: parent.width - 2 * keyboardWindow.spaces.two
            spacing: keyboardWindow.spaces.one
            IconToolButton {
                objectName: "virtualKeyboardOctaveDown"
                glyph: Icons.scrollTabsLeft
                colors: keyboardWindow.colors
                unit: keyboardWindow.unit
                focusPolicy: Qt.NoFocus
                enabled: keyboardWindow.presenter.canOctaveDown
                Accessible.name: qsTr("One octave down")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("One octave down")
                onClicked: keyboardWindow.presenter.shiftOctave(-1)
            }
            Label {
                objectName: "virtualKeyboardOctave"
                Layout.preferredWidth: metrics.advanceWidth("C-1") + keyboardWindow.spaces.two
                horizontalAlignment: Text.AlignHCenter
                text: keyboardWindow.presenter.octaveText
                color: keyboardWindow.colors.windowText
                ToolTip.visible: octaveHover.hovered
                ToolTip.text: qsTr("The lowest key's note")
                HoverHandler { id: octaveHover }
            }
            IconToolButton {
                objectName: "virtualKeyboardOctaveUp"
                glyph: Icons.scrollTabsRight
                colors: keyboardWindow.colors
                unit: keyboardWindow.unit
                focusPolicy: Qt.NoFocus
                enabled: keyboardWindow.presenter.canOctaveUp
                Accessible.name: qsTr("One octave up")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("One octave up")
                onClicked: keyboardWindow.presenter.shiftOctave(1)
            }
            Label {
                Layout.leftMargin: keyboardWindow.spaces.three
                text: qsTr("Velocity")
                color: keyboardWindow.colors.windowText
            }
            Slider {
                id: velocitySlider
                objectName: "virtualKeyboardVelocity"
                Layout.preferredWidth: 8 * keyboardWindow.unit
                from: 1
                to: 127
                stepSize: 1
                focusPolicy: Qt.NoFocus
                Accessible.name: qsTr("Velocity")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("How hard clicked and typed notes are struck")
                onMoved: keyboardWindow.presenter.setVelocity(Math.round(velocitySlider.value))
                // Persisted when it settles: on the release of a drag, not at each step.
                onPressedChanged: {
                    if (!velocitySlider.pressed)
                        keyboardWindow.presenter.commitVelocity()
                }
                Binding on value {
                    value: keyboardWindow.presenter.velocity
                    when: !velocitySlider.pressed
                }
            }
            Label {
                objectName: "virtualKeyboardVelocityValue"
                Layout.preferredWidth: metrics.advanceWidth("127")
                horizontalAlignment: Text.AlignRight
                text: keyboardWindow.presenter.velocity
                color: keyboardWindow.colors.windowText
            }
            Label {
                objectName: "virtualKeyboardTarget"
                Layout.fillWidth: true
                Layout.leftMargin: keyboardWindow.spaces.three
                elide: Text.ElideRight
                text: keyboardWindow.presenter.targetText
                color: keyboardWindow.colors.secondaryText
                ToolTip.visible: targetHover.hovered
                ToolTip.text: qsTr("The selected track, whose voice the keyboard plays: %1")
                    .arg(keyboardWindow.presenter.targetText)
                HoverHandler { id: targetHover }
            }
        }

        VirtualKeyboardPiano {
            id: piano
            x: keyboardWindow.spaces.two
            y: controls.y + controls.height + keyboardWindow.spaces.two
            width: parent.width - 2 * keyboardWindow.spaces.two
            height: parent.height - y - keyboardWindow.spaces.two
            presenter: keyboardWindow.presenter
            colors: keyboardWindow.colors
            unit: keyboardWindow.unit
            labelPadding: keyboardWindow.spaces.half
            labelHeight: metrics.height
            font: keyboardWindow.font
        }
    }
}
