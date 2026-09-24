pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: picker
    required property QtObject controller
    required property QtObject draft
    required property var colors
    required property real baseFontPx
    required property bool waveMode
    property string clickedSymbol: ""
    property bool positioning: false
    readonly property var entries: {
        controller.catalogRevision
        const filter = search.text.trim().toLowerCase()
        const sections = waveMode
                         ? [{ title: qsTr("Waves"), symbols: controller.waveChoices(), split: false }]
                         : [{ title: qsTr("Keysplits"), symbols: controller.keysplitPickerSymbols(), split: true },
                            { title: qsTr("Samples"), symbols: controller.sampleSymbols(), split: false },
                            { title: qsTr("Phonemes"), symbols: controller.phonemeSymbols(), split: false }]
        const visible = sections.filter(section => section.symbols.length > 0)
        const rows = []
        let exact = false
        for (const section of visible) {
            const matches = section.symbols.filter(symbol =>
                !filter || symbol.toLowerCase().includes(filter)
                || picker.displayName(symbol).toLowerCase().includes(filter))
            if (matches.length === 0)
                continue
            if (visible.length > 1)
                rows.push({ symbol: "", label: section.title, split: false })
            for (const symbol of matches) {
                exact = exact || symbol === search.text.trim()
                rows.push({ symbol: symbol, label: waveMode ? symbol
                                                            : picker.displayName(symbol),
                            split: section.split })
            }
        }
        if (filter && !exact)
            rows.push({ symbol: search.text.trim(), label: qsTr("Use \"%1\"").arg(search.text.trim()),
                        split: false, typed: true })
        return rows
    }
    signal picked(string symbol)

    function displayName(symbol) {
        for (const prefix of ["DirectSoundWaveData_", "ProgrammableWaveData_", "voicegroup_"]) {
            if (symbol.startsWith(prefix) && symbol.length > prefix.length)
                return symbol.slice(prefix.length)
        }
        return symbol
    }

    function currentEntry() {
        const index = list.currentIndex
        return index >= 0 && index < entries.length ? entries[index] : null
    }

    function highlight(index) {
        const entry = entries[index]
        if (!entry || !entry.symbol)
            return
        list.currentIndex = index
        if (!positioning && !entry.typed) {
            controller.requestSampleAudition(entry.symbol)
            auditionOff.restart()
        }
    }

    function commit() {
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
        font.pixelSize: picker.baseFontPx
        onClicked: popup.open()
    }

    Popup {
        id: popup
        objectName: "vgSamplePickerPopup"
        parent: picker
        property real spacingPx: Math.max(1, Math.round(picker.baseFontPx / 3))
        x: 0
        y: trigger.height
        width: Math.max(picker.width, picker.baseFontPx * 28.33)
        height: picker.baseFontPx * 35
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
            let current = picker.entries.findIndex(row => row.symbol === picker.draft.symbol)
            if (current < 0)
                current = picker.entries.findIndex(row => row.symbol.length > 0)
            list.currentIndex = current
            if (current >= 0)
                list.positionViewAtIndex(current, ListView.Center)
            picker.positioning = false
            search.forceActiveFocus()
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
                font.pixelSize: picker.baseFontPx
                onAccepted: picker.commit()
                Keys.onDownPressed: {
                    for (let i = list.currentIndex + 1; i < picker.entries.length; i++) {
                        if (picker.entries[i].symbol) {
                            picker.highlight(i)
                            list.positionViewAtIndex(i, ListView.Contain)
                            break
                        }
                    }
                }
                Keys.onUpPressed: {
                    for (let i = list.currentIndex - 1; i >= 0; i--) {
                        if (picker.entries[i].symbol) {
                            picker.highlight(i)
                            list.positionViewAtIndex(i, ListView.Contain)
                            break
                        }
                    }
                }
                onTextChanged: {
                    if (!popup.opened || picker.positioning)
                        return
                    picker.clickedSymbol = ""
                    const first = picker.entries.findIndex(row => row.symbol && !row.typed)
                    if (first >= 0)
                        picker.highlight(first)
                    else
                        list.currentIndex = picker.entries.findIndex(row => row.symbol)
                }
            }
            ListView {
                id: list
                objectName: "vgSamplePickerList"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: picker.entries
                delegate: ItemDelegate {
                    id: entry
                    required property int index
                    required property var modelData
                    width: list.width
                    height: picker.baseFontPx * 1.83
                    enabled: !!modelData.symbol
                    highlighted: list.currentIndex === index
                    font.pixelSize: picker.baseFontPx
                    font.bold: !modelData.symbol
                    contentItem: Label {
                        text: entry.modelData.label
                        font: entry.font
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        color: !entry.modelData.symbol ? picker.colors.secondaryText
                               : entry.highlighted ? picker.colors.selectionText
                                                   : picker.colors.windowText
                    }
                    onClicked: {
                        const symbol = modelData.symbol
                        if (symbol === picker.clickedSymbol) {
                            picker.commit()
                        } else {
                            picker.clickedSymbol = symbol
                            picker.highlight(index)
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    objectName: "vgSamplePickerDetail"
                    Layout.fillWidth: true
                    font.pixelSize: picker.baseFontPx
                    color: picker.colors.secondaryText
                    text: {
                        const entry = picker.currentEntry()
                        return !entry ? "" : entry.typed ? qsTr("Unlisted symbol")
                               : picker.controller.pickerSampleDetail
                                 || (entry.split ? qsTr("Keysplit instrument") : "")
                    }
                }
                Label {
                    objectName: "vgSamplePickerLoop"
                    visible: picker.controller.pickerSampleLoop
                    font.pixelSize: picker.baseFontPx
                    color: picker.colors.primaryText
                    text: qsTr("Loop")
                }
            }
        }
        Timer {
            id: auditionOff
            interval: 2000
            onTriggered: picker.controller.stopSampleAudition()
        }
    }
}
