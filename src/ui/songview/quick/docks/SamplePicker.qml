pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

Item {
    id: picker
    required property VoiceListController controller
    required property VoiceEditorController draft
    required property GridPalette colors
    required property ApplicationSession applicationSession
    readonly property real baseFontPx: applicationSession.baseFontPx
    final readonly property real hostWindowWidth: Window.width
    final readonly property real hostWindowHeight: Window.height
    required property bool waveMode
    property string clickedSymbol: ""
    property bool positioning: false
    onVisibleChanged: {
        if (!visible)
            popup.close()
    }
    readonly property SamplePickerRow selectedEntry: controller.samplePickerRow(list.currentIndex) as SamplePickerRow
    onWaveModeChanged: controller.configureSamplePicker(search.text, waveMode)
    Component.onCompleted: controller.configureSamplePicker(search.text, waveMode)
    signal picked(string symbol)
    readonly property font typedEntryFont: {
        const result = picker.applicationSession.typographyFonts.body
        result.italic = true
        return result
    }

    function displayName(symbol: string): string {
        return picker.controller.sampleDisplayName(symbol)
    }

    function currentEntry(): SamplePickerRow {
        return picker.selectedEntry
    }

    function entryIndex(symbol: string, listedOnly: bool): int {
        for (let index = 0; index < picker.controller.samplePickerCount; index++) {
            const entry = picker.controller.samplePickerRow(index) as SamplePickerRow
            if (entry && entry.symbol && (!symbol || entry.symbol === symbol)
                    && (!listedOnly || !entry.typed))
                return index
        }
        return -1
    }

    function highlight(index: int): void {
        const entry = controller.samplePickerRow(index) as SamplePickerRow
        if (!entry || !entry.symbol)
            return
        list.currentIndex = index
        if (!positioning && !entry.typed) {
            controller.requestSampleAudition(entry.symbol)
            auditionOff.restart()
        }
    }

    function commit(): void {
        const entry = currentEntry()
        if (!entry || !entry.symbol)
            return
        popup.close()
        picked(entry.symbol)
    }

    Button {
        id: trigger
        objectName: "vgSamplePickerButton"
        anchors.fill: parent
        text: picker.draft.symbol ? (picker.waveMode ? picker.draft.symbol
                                                   : picker.displayName(picker.draft.symbol))
                                  : qsTr("(none)")
        onClicked: popup.open()
    }

    Popup {
        id: popup
        objectName: "vgSamplePickerPopup"
        parent: picker
        font: picker.applicationSession.typographyFonts.body
        property real spacingPx: Math.max(1, Math.round(picker.baseFontPx / 3))
        x: 0
        y: trigger.height
        width: Math.min(Math.max(picker.width, picker.baseFontPx * 28.33),
                        picker.hostWindowWidth - leftMargin - rightMargin)
        height: Math.min(picker.baseFontPx * 35, picker.hostWindowHeight - topMargin - bottomMargin)
        // Like the style's ComboBox and Menu popups, stay inside the window.
        margins: spacingPx
        padding: spacingPx
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: picker.colors.windowBackground
            border.color: picker.colors.outline
            border.width: 1
        }
        onOpened: {
            picker.positioning = true
            search.text = ""
            picker.clickedSymbol = ""
            picker.controller.configureSamplePicker(search.text, picker.waveMode)
            let current = picker.entryIndex(picker.draft.symbol, false)
            if (current < 0)
                current = picker.entryIndex("", false)
            list.currentIndex = current
            if (current >= 0)
                list.positionViewAtIndex(current, ListView.Center)
            picker.positioning = false
            search.forceActiveFocus()
        }
        onVisibleChanged: {
            if (visible)
                picker.controller.requestPickerSampleInfo()
        }
        onClosed: {
            auditionOff.stop()
            picker.controller.stopSampleAudition()
        }
        contentItem: ColumnLayout {
            spacing: popup.spacingPx
            TextField {
                id: search
                objectName: "vgSamplePickerSearch"
                Layout.fillWidth: true
                placeholderText: qsTr("Search samples…")
                onAccepted: picker.commit()
                Keys.onDownPressed: {
                    for (let i = list.currentIndex + 1; i < picker.controller.samplePickerCount; i++) {
                        if ((picker.controller.samplePickerRow(i) as SamplePickerRow).symbol) {
                            picker.highlight(i)
                            list.positionViewAtIndex(i, ListView.Contain)
                            break
                        }
                    }
                }
                Keys.onUpPressed: {
                    for (let i = list.currentIndex - 1; i >= 0; i--) {
                        if ((picker.controller.samplePickerRow(i) as SamplePickerRow).symbol) {
                            picker.highlight(i)
                            list.positionViewAtIndex(i, ListView.Contain)
                            break
                        }
                    }
                }
                onTextChanged: {
                    picker.controller.configureSamplePicker(text, picker.waveMode)
                    if (!popup.opened || picker.positioning)
                        return
                    picker.clickedSymbol = ""
                    const first = picker.entryIndex("", true)
                    if (first >= 0)
                        picker.highlight(first)
                    else
                        list.currentIndex = picker.entryIndex("", false)
                }
            }
            ListView {
                id: list
                objectName: "vgSamplePickerList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: picker.controller.samplePickerRows
                // Delegates draw highlight; a following highlight animates frames while hidden.
                highlightFollowsCurrentItem: false
                delegate: ItemDelegate {
                    id: entry
                    required property int index
                    required property string symbol
                    required property string label
                    required property bool split
                    required property bool typed
                    required property bool loops
                    width: list.width
                    height: picker.baseFontPx * 1.83
                    enabled: !!symbol
                    highlighted: list.currentIndex === index
                    contentItem: RowLayout {
                        spacing: popup.spacingPx
                        Label {
                            objectName: "vgSamplePickerRowText"
                            Layout.fillWidth: true
                            text: entry.typed ? qsTr("Use \"%1\"").arg(entry.symbol)
                                  : entry.symbol ? entry.label
                                  : entry.label === "Keysplits" ? qsTr("Keysplits")
                                  : entry.label === "Samples" ? qsTr("Samples")
                                  : entry.label === "Phonemes" ? qsTr("Phonemes") : qsTr("Waves")
                            font: entry.typed ? picker.typedEntryFont
                                  : !entry.symbol ? picker.applicationSession.typographyFonts.bodyBold
                                                  : entry.font
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                            color: !entry.symbol ? picker.colors.secondaryText
                                   : entry.highlighted ? picker.colors.selectionText
                                                       : picker.colors.windowText
                        }
                        Label {
                            objectName: "vgSamplePickerLoopBadge"
                            Layout.preferredWidth: implicitWidth
                            visible: !!entry.symbol && !entry.split && !entry.typed && entry.loops
                            text: "∞"
                            color: entry.highlighted ? picker.colors.selectionText
                                                     : picker.colors.windowText
                            ToolTip.text: qsTr("Loops")
                            ToolTip.visible: badgeHover.hovered
                            HoverHandler { id: badgeHover }
                        }
                    }
                    onClicked: {
                        const symbol = entry.symbol
                        if (symbol === picker.clickedSymbol) {
                            picker.commit()
                        } else {
                            picker.clickedSymbol = symbol
                            picker.highlight(index)
                        }
                    }
                }
            }
            Label {
                objectName: "vgSamplePickerDetail"
                Layout.fillWidth: true
                color: picker.colors.secondaryText
                text: !picker.selectedEntry ? ""
                      : picker.selectedEntry.typed ? qsTr("Unlisted symbol")
                      : picker.selectedEntry.split ? qsTr("Keysplit instrument")
                      : picker.selectedEntry.detail
            }
        }
        Timer {
            id: auditionOff
            interval: 2000
            onTriggered: picker.controller.stopSampleAudition()
        }
    }
}
