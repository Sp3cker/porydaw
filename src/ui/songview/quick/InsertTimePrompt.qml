import QtQuick

PromptCard {
    id: prompt

    required property var bridge

    objectName: "insertTimePrompt"
    appearance: bridge.insertTimePromptAppearance

    property int draftBars: bridge.insertTimePromptInitialBars
    property int draftBeats: bridge.insertTimePromptInitialBeats
    property int draftBeatFractions: bridge.insertTimePromptInitialBeatFractions
    property bool finishing: false

    readonly property real labelWidth: Math.max(labelMetrics.advanceWidth(qsTr("Bars:")),
                                                labelMetrics.advanceWidth(qsTr("Beats:")),
                                                labelMetrics.advanceWidth(qsTr("Beat fractions (¼ beat):")))
    readonly property real inputWidth: Math.max(barsInput.implicitWidth, beatsInput.implicitWidth,
                                                fractionsInput.implicitWidth)

    FontMetrics {
        id: labelMetrics

        font: prompt.appearance.font
    }
    function acceptDisplayed() {
        acceptCommittedDrafts(barsInput.commitDisplayed(), beatsInput.commitDisplayed(),
                              fractionsInput.commitDisplayed())
    }

    function acceptFromEditing(field, committed) {
        acceptCommittedDrafts(field === "bars" ? committed : barsInput.commitDisplayed(),
                              field === "beats" ? committed : beatsInput.commitDisplayed(),
                              field === "fractions" ? committed : fractionsInput.commitDisplayed())
    }

    function acceptCommittedDrafts(bars, beats, fractions) {
        if (bars !== null && beats !== null && fractions !== null)
            acceptCommitted(bars, beats, fractions)
    }

    function acceptCommitted(bars, beats, fractions) {
        if (finishing)
            return
        finishing = true
        bridge.acceptInsertTimePrompt(bars, beats, fractions)
    }

    function cancelDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.cancelInsertTimePrompt()
    }

    function activateInitialFocus() {
        barsInput.focusInput(Qt.PopupFocusReason)
        barsInput.selectAll()
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // The focused DragInput receives normal numeric editing first. This
    // terminal sink claims declined keys so timeline commands never leak out
    // of the shared popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            acceptDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.insertTimePromptTitle

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.insertTimePromptTitle
        renderType: Text.NativeRendering
    }

    Row {
        spacing: appearance.spacing

        Text {
            anchors.verticalCenter: barsInput.verticalCenter
            width: prompt.labelWidth
            horizontalAlignment: Text.AlignRight
            color: appearance.text
            font: appearance.font
            text: qsTr("Bars:")
            renderType: Text.NativeRendering
        }

        DragInput {
            id: barsInput

            appearance: prompt.appearance
            value: prompt.draftBars
            width: prompt.inputWidth
            minimumValue: bridge.insertTimePromptMinimumBars
            maximumValue: bridge.insertTimePromptMaximumBars
            inputObjectName: "insertTimeBars"
            accessibleName: qsTr("Bars")
            accessibleDescription: bridge.insertTimePromptTitle
            onValueCommitted: (committed) => prompt.draftBars = committed
            onEditingAccepted: (committed) => prompt.acceptFromEditing("bars", committed)
            textInput.KeyNavigation.backtab: cancelButton
        }
    }

    Row {
        spacing: appearance.spacing

        Text {
            anchors.verticalCenter: beatsInput.verticalCenter
            width: prompt.labelWidth
            horizontalAlignment: Text.AlignRight
            color: appearance.text
            font: appearance.font
            text: qsTr("Beats:")
            renderType: Text.NativeRendering
        }

        DragInput {
            id: beatsInput

            appearance: prompt.appearance
            value: prompt.draftBeats
            width: prompt.inputWidth
            minimumValue: bridge.insertTimePromptMinimumBeats
            maximumValue: bridge.insertTimePromptMaximumBeats
            inputObjectName: "insertTimeBeats"
            accessibleName: qsTr("Beats")
            accessibleDescription: bridge.insertTimePromptTitle
            onValueCommitted: (committed) => prompt.draftBeats = committed
            onEditingAccepted: (committed) => prompt.acceptFromEditing("beats", committed)
        }
    }

    Row {
        spacing: appearance.spacing

        Text {
            anchors.verticalCenter: fractionsInput.verticalCenter
            width: prompt.labelWidth
            horizontalAlignment: Text.AlignRight
            color: appearance.text
            font: appearance.font
            text: qsTr("Beat fractions (¼ beat):")
            renderType: Text.NativeRendering
        }

        DragInput {
            id: fractionsInput

            appearance: prompt.appearance
            value: prompt.draftBeatFractions
            width: prompt.inputWidth
            minimumValue: bridge.insertTimePromptMinimumBeatFractions
            maximumValue: bridge.insertTimePromptMaximumBeatFractions
            inputObjectName: "insertTimeBeatFractions"
            accessibleName: qsTr("Beat fractions")
            accessibleDescription: bridge.insertTimePromptTitle
            onValueCommitted: (committed) => prompt.draftBeatFractions = committed
            onEditingAccepted: (committed) => prompt.acceptFromEditing("fractions", committed)
        }
    }

    Row {
        spacing: appearance.spacing

        PromptButton {
            id: acceptButton

            objectName: "insertTimeAccept"
            appearance: prompt.appearance
            text: qsTr("OK")
            minimumWidth: barsInput.implicitWidth
            onActivated: prompt.acceptDisplayed()
        }

        PromptButton {
            id: cancelButton

            objectName: "insertTimeCancel"
            appearance: prompt.appearance
            text: qsTr("Cancel")
            minimumWidth: barsInput.implicitWidth
            KeyNavigation.tab: barsInput.textInput
            onActivated: prompt.cancelDisplayed()
        }
    }
}
