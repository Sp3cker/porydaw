pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui

PromptCard {
    id: prompt

    required property var bridge

    objectName: "timeSignaturePrompt"
    appearance: Object.assign({}, bridge.timeSigPromptAppearance, {
        font: Qt.font(bridge.timeSigPromptFont),
        // Pressed text must match the hoverChipFill surface.
        pressedText: bridge.palette.hoverChipText,
        disabledText: bridge.palette.disabledText
    })

    property int draftNumerator: bridge.timeSigPromptInitialNumerator
    property int draftDenominatorPow2: bridge.timeSigPromptInitialDenominatorPow2
    property bool finishing: false

    function acceptDisplayed(): void {
        const numerator = numeratorInput.commitDisplayed()
        if (numerator !== null)
            acceptCommitted(numerator)
    }

    function acceptCommitted(numerator: int): void {
        if (finishing)
            return
        finishing = true
        bridge.acceptTimeSigPrompt(numerator, draftDenominatorPow2)
    }

    function cancelDisplayed(): void {
        if (finishing)
            return
        finishing = true
        bridge.cancelTimeSigPrompt()
    }

    function moveDenominator(from: int, step: int): void {
        const exponent = Math.max(bridge.timeSigPromptMinimumDenominatorPow2,
                                  Math.min(bridge.timeSigPromptMaximumDenominatorPow2, from + step))
        draftDenominatorPow2 = exponent
        const button = denominatorRepeater.itemAt(exponent)
        if (button)
            button.forceActiveFocus(Qt.OtherFocusReason)
    }

    function activateInitialFocus(): void {
        numeratorInput.focusInput(Qt.PopupFocusReason)
        numeratorInput.selectAll()
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // DragInput edits first; declined keys stop here, inside the popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.timeSigPromptTitle

    Text {
        color: prompt.appearance.text
        font: prompt.appearance.font
        text: prompt.bridge.timeSigPromptTitle
        renderType: Text.NativeRendering
    }

    Text {
        color: prompt.appearance.text
        font: prompt.appearance.font
        text: prompt.bridge.timeSigPromptLabel
        renderType: Text.NativeRendering
    }

    DragInput {
        id: numeratorInput

        appearance: prompt.appearance
        value: prompt.draftNumerator
        minimumValue: prompt.bridge.timeSigPromptMinimumNumerator
        maximumValue: prompt.bridge.timeSigPromptMaximumNumerator
        inputMaximumValue: 999
        inputObjectName: "timeSignatureNumerator"
        accessibleName: prompt.bridge.timeSigPromptLabel
        accessibleDescription: prompt.bridge.timeSigPromptTitle
        onValueCommitted: (committed) => prompt.draftNumerator = committed
        onEditingAccepted: (committed) => prompt.acceptCommitted(committed)
        textInput.KeyNavigation.backtab: cancelButton
    }

    Text {
        color: prompt.appearance.text
        font: prompt.appearance.font
        text: qsTr("Denominator:")
        renderType: Text.NativeRendering
    }

    Row {
        spacing: prompt.appearance.spacing

        Repeater {
            id: denominatorRepeater
            model: 6

            delegate: Rectangle {
                id: denominatorButton

                required property int modelData

                objectName: "timeSignatureDenominator" + modelData
                activeFocusOnTab: selected
                readonly property bool selected: prompt.draftDenominatorPow2 === modelData
                function select(): void {
                    prompt.draftDenominatorPow2 = modelData
                }
                function activate(): void {
                    select()
                    forceActiveFocus(Qt.MouseFocusReason)
                }
                function selectFromKeyboard(event: KeyEvent): void {
                    select()
                    event.accepted = true
                }
                function acceptFromKeyboard(event: KeyEvent): void {
                    select()
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                function moveBy(step: int, event: KeyEvent): void {
                    prompt.moveDenominator(modelData, step)
                    event.accepted = true
                }

                width: denominatorText.implicitWidth + 2 * prompt.appearance.buttonPadding
                height: denominatorText.implicitHeight + 2 * prompt.appearance.buttonPadding
                color: denominatorTap.pressed || selected ? prompt.appearance.pressedBackground
                                                          : prompt.appearance.buttonBackground
                border.width: prompt.appearance.borderWidth
                border.color: activeFocus ? prompt.appearance.focus : prompt.appearance.outline
                radius: prompt.appearance.radius

                Text {
                    id: denominatorText

                    anchors.centerIn: parent
                    // Selected and pressed chips use the pressed surface's ink.
                    color: denominatorTap.pressed || denominatorButton.selected
                           ? prompt.appearance.pressedText : prompt.appearance.buttonText
                    font: prompt.appearance.font
                    text: String(1 << denominatorButton.modelData)
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: (event) => denominatorButton.acceptFromKeyboard(event)
                Keys.onEnterPressed: (event) => denominatorButton.acceptFromKeyboard(event)
                Keys.onSpacePressed: (event) => denominatorButton.selectFromKeyboard(event)
                Keys.onLeftPressed: (event) => denominatorButton.moveBy(-1, event)
                Keys.onRightPressed: (event) => denominatorButton.moveBy(1, event)
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Space || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter

                Accessible.role: Accessible.RadioButton
                Accessible.name: denominatorText.text
                Accessible.checked: selected
                Accessible.focusable: true
                Accessible.onPressAction: denominatorButton.activate()

                TapHandler {
                    id: denominatorTap

                    onTapped: denominatorButton.activate()
                }
            }
        }
    }

    Row {
        spacing: prompt.appearance.spacing

        PromptButton {
            id: acceptButton

            objectName: "timeSignatureAccept"
            appearance: prompt.appearance
            text: qsTr("OK")
            minimumWidth: numeratorInput.implicitWidth
            onActivated: prompt.acceptDisplayed()
        }

        PromptButton {
            id: cancelButton

            objectName: "timeSignatureCancel"
            appearance: prompt.appearance
            text: qsTr("Cancel")
            minimumWidth: numeratorInput.implicitWidth
            KeyNavigation.tab: numeratorInput.textInput
            onActivated: prompt.cancelDisplayed()
        }
    }
}
