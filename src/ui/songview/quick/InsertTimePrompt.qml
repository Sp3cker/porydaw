pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui
import PorydawApp

PromptCard {
    id: prompt

    required final property RulerMenuPresenter bridge

    objectName: "insertTimePrompt"
    appearance: bridge.promptStyle

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
    function acceptDisplayed(): void {
        const bars = barsInput.commitDisplayed()
        const beats = beatsInput.commitDisplayed()
        const fractions = fractionsInput.commitDisplayed()
        acceptCommittedDrafts(bars, beats, fractions)
    }

    function acceptFromEditing(field: string, committed: int): void {
        const bars = field === "bars" ? committed : barsInput.commitDisplayed()
        const beats = field === "beats" ? committed : beatsInput.commitDisplayed()
        const fractions = field === "fractions" ? committed : fractionsInput.commitDisplayed()
        acceptCommittedDrafts(bars, beats, fractions)
    }

    function acceptCommittedDrafts(bars: var, beats: var, fractions: var): void {
        if (bars !== null && beats !== null && fractions !== null)
            acceptCommitted(bars, beats, fractions)
    }

    function acceptCommitted(bars: int, beats: int, fractions: int): void {
        if (finishing)
            return
        finishing = true
        bridge.acceptInsertTimePrompt(bars, beats, fractions)
    }

    function cancelDisplayed(): void {
        if (finishing)
            return
        finishing = true
        bridge.cancelInsertTimePrompt()
    }

    function activateInitialFocus(): void {
        barsInput.focusInput(Qt.PopupFocusReason)
        barsInput.selectAll()
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // DragInput edits first; declined keys stop here, inside the popup session.
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
        color: prompt.appearance.text
        font: prompt.appearance.font
        text: prompt.bridge.insertTimePromptTitle
        renderType: Text.NativeRendering
    }

    Row {
        spacing: prompt.appearance.spacing

        Text {
            anchors.verticalCenter: barsInput.verticalCenter
            width: prompt.labelWidth
            horizontalAlignment: Text.AlignRight
            color: prompt.appearance.text
            font: prompt.appearance.font
            text: qsTr("Bars:")
            renderType: Text.NativeRendering
        }

        DragInput {
            id: barsInput

            appearance: prompt.appearance
            value: prompt.draftBars
            width: prompt.inputWidth
            minimumValue: prompt.bridge.insertTimePromptMinimumBars
            maximumValue: prompt.bridge.insertTimePromptMaximumBars
            inputObjectName: "insertTimeBars"
            accessibleName: qsTr("Bars")
            accessibleDescription: prompt.bridge.insertTimePromptTitle
            onValueCommitted: (committed) => prompt.draftBars = committed
            onEditingAccepted: (committed) => prompt.acceptFromEditing("bars", committed)
            textInput.KeyNavigation.backtab: cancelButton
        }
    }

    Row {
        spacing: prompt.appearance.spacing

        Text {
            anchors.verticalCenter: beatsInput.verticalCenter
            width: prompt.labelWidth
            horizontalAlignment: Text.AlignRight
            color: prompt.appearance.text
            font: prompt.appearance.font
            text: qsTr("Beats:")
            renderType: Text.NativeRendering
        }

        DragInput {
            id: beatsInput

            appearance: prompt.appearance
            value: prompt.draftBeats
            width: prompt.inputWidth
            minimumValue: prompt.bridge.insertTimePromptMinimumBeats
            maximumValue: prompt.bridge.insertTimePromptMaximumBeats
            inputObjectName: "insertTimeBeats"
            accessibleName: qsTr("Beats")
            accessibleDescription: prompt.bridge.insertTimePromptTitle
            onValueCommitted: (committed) => prompt.draftBeats = committed
            onEditingAccepted: (committed) => prompt.acceptFromEditing("beats", committed)
        }
    }

    Row {
        spacing: prompt.appearance.spacing

        Text {
            anchors.verticalCenter: fractionsInput.verticalCenter
            width: prompt.labelWidth
            horizontalAlignment: Text.AlignRight
            color: prompt.appearance.text
            font: prompt.appearance.font
            text: qsTr("Beat fractions (¼ beat):")
            renderType: Text.NativeRendering
        }

        DragInput {
            id: fractionsInput

            appearance: prompt.appearance
            value: prompt.draftBeatFractions
            width: prompt.inputWidth
            minimumValue: prompt.bridge.insertTimePromptMinimumBeatFractions
            maximumValue: prompt.bridge.insertTimePromptMaximumBeatFractions
            inputObjectName: "insertTimeBeatFractions"
            accessibleName: qsTr("Beat fractions")
            accessibleDescription: prompt.bridge.insertTimePromptTitle
            onValueCommitted: (committed) => prompt.draftBeatFractions = committed
            onEditingAccepted: (committed) => prompt.acceptFromEditing("fractions", committed)
        }
    }

    Row {
        spacing: prompt.appearance.spacing

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
