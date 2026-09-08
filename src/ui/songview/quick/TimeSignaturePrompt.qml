import QtQuick

PromptCard {
    id: prompt

    required property var bridge

    objectName: "timeSignaturePrompt"
    appearance: bridge.timeSigPromptAppearance

    property int draftNumerator: bridge.timeSigPromptInitialNumerator
    property int draftDenominatorPow2: bridge.timeSigPromptInitialDenominatorPow2
    property bool finishing: false

    function acceptDisplayed() {
        const numerator = numeratorInput.commitDisplayed()
        if (numerator !== null)
            acceptCommitted(numerator)
    }

    function acceptCommitted(numerator) {
        if (finishing)
            return
        finishing = true
        bridge.acceptTimeSigPrompt(numerator, draftDenominatorPow2)
    }

    function cancelDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.cancelTimeSigPrompt()
    }

    function moveDenominator(from, step) {
        const exponent = Math.max(bridge.timeSigPromptMinimumDenominatorPow2,
                                  Math.min(bridge.timeSigPromptMaximumDenominatorPow2, from + step))
        draftDenominatorPow2 = exponent
        const button = denominatorRepeater.itemAt(exponent)
        if (button)
            button.forceActiveFocus(Qt.OtherFocusReason)
    }

    function activateInitialFocus() {
        numeratorInput.focusInput(Qt.PopupFocusReason)
        numeratorInput.selectAll()
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // The focused DragInput receives normal numeric editing first. This
    // terminal sink claims declined keys so timeline commands never leak out
    // of the shared popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.timeSigPromptTitle

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.timeSigPromptTitle
        renderType: Text.NativeRendering
    }

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.timeSigPromptLabel
        renderType: Text.NativeRendering
    }

    DragInput {
        id: numeratorInput

        appearance: prompt.appearance
        value: prompt.draftNumerator
        minimumValue: bridge.timeSigPromptMinimumNumerator
        maximumValue: bridge.timeSigPromptMaximumNumerator
        inputObjectName: "timeSignatureNumerator"
        accessibleName: bridge.timeSigPromptLabel
        accessibleDescription: bridge.timeSigPromptTitle
        onValueCommitted: (committed) => prompt.draftNumerator = committed
        onEditingAccepted: (committed) => prompt.acceptCommitted(committed)
        textInput.KeyNavigation.backtab: cancelButton
    }

    Text {
        color: appearance.text
        font: appearance.font
        text: qsTr("Denominator:")
        renderType: Text.NativeRendering
    }

    Row {
        spacing: appearance.spacing

        Repeater {
            id: denominatorRepeater
            model: [0, 1, 2, 3, 4, 5]

            delegate: Rectangle {
                id: denominatorButton

                required property int modelData

                objectName: "timeSignatureDenominator" + modelData
                activeFocusOnTab: selected
                readonly property bool selected: prompt.draftDenominatorPow2 === modelData
                function select() {
                    prompt.draftDenominatorPow2 = modelData
                }
                function activate() {
                    select()
                    forceActiveFocus(Qt.MouseFocusReason)
                }
                function selectFromKeyboard(event) {
                    select()
                    event.accepted = true
                }
                function acceptFromKeyboard(event) {
                    select()
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                function moveBy(step, event) {
                    prompt.moveDenominator(modelData, step)
                    event.accepted = true
                }

                width: denominatorText.implicitWidth + 2 * appearance.buttonPadding
                height: denominatorText.implicitHeight + 2 * appearance.buttonPadding
                color: denominatorTap.pressed || selected ? appearance.pressedBackground
                                                          : appearance.buttonBackground
                border.width: appearance.borderWidth
                border.color: activeFocus ? appearance.focus : appearance.outline
                radius: appearance.radius

                Text {
                    id: denominatorText

                    anchors.centerIn: parent
                    color: appearance.buttonText
                    font: appearance.font
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
        spacing: appearance.spacing

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
