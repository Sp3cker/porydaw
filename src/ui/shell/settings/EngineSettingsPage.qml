pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import PorydawApp

Item {
    id: page
    required property EngineSettingsStore store
    required property GridPalette colors
    required property real unit
    required property TypographyFonts typography
    readonly property real labelWidth: 105 + 84 * (unit - 1)
    readonly property list<real> rates: [5734, 7884, 10512, 13379, 15768, 18157,
                                        21024, 26758, 31536, 36314, 40137, 42048, 0]
    function rateChoices(): list<real> {
        const choices = []
        for (let i = 0; i < page.rates.length; ++i)
            choices.push(page.rates[i])
        if (choices.indexOf(page.store.mixRate) < 0)
            choices.push(page.store.mixRate)
        return choices
    }
    function rateNames(): list<string> {
        const choices = page.rateChoices()
        const names = []
        for (let i = 0; i < choices.length; ++i)
            names.push(page.rateName(choices[i]))
        return names
    }
    readonly property list<string> mixers: [qsTr("Ipatix"), qsTr("Sappy")]
    function rateName(rate: real): string {
        return rate === 0 ? qsTr("Host rate (clean, no GBA resampling)")
             : rate === 13379 ? qsTr("%1 Hz (GBA default)").arg(rate)
             : page.rates.indexOf(rate) < 0 ? qsTr("%1 Hz (custom)").arg(rate)
             : qsTr("%1 Hz").arg(rate)
    }
    function reset(): void {
        polyphony.value = page.store.maxPcmChannels
        mixer.currentIndex = page.store.mixer === "sappy" ? 1 : 0
        rate.currentIndex = page.rateChoices().indexOf(page.store.mixRate)
        analog.checked = page.store.analogFilter
    }

    Column {
        y: 11 * page.unit
        width: page.width
        // Legacy fork spacing is pinned by tst_ShellSettings reference rects.
        spacing: 6
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("PCM polyphony:"); bottomInset: page.unit - 1
            SpinBox {
                id: polyphony
                objectName: "engine.polyphony"
                anchors.fill: parent
                from: 1; to: page.store.maximumPcmChannels; value: page.store.maxPcmChannels
                font: page.typography.body
                editable: true
                textFromValue: function(value: int): string { return qsTr("%1 channels").arg(value) }
                valueFromText: function(text: string): real { return parseInt(text, 10) }
                onValueModified: page.store.changeMaxPcmChannels(value)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Maximum simultaneous PCM (DirectSound) notes. The engine supports up to %1.").arg(page.store.maximumPcmChannels)
            }
        }
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("PCM mixer:"); compact: true
            ComboBox {
                id: mixer
                objectName: "pcmMixerCombo"
                anchors.fill: parent
                model: page.mixers
                font: page.typography.body
                currentIndex: page.store.mixer === "sappy" ? 1 : 0
                onActivated: function(index): void { page.store.changeMixer(index === 1 ? "sappy" : "ipatix") }
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Ipatix is the improved high-quality mixer; Sappy matches the standard Nintendo mixer.")
            }
        }
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("PCM mix rate:"); compact: true
            ComboBox {
                id: rate
                objectName: "engine.mix-rate"
                anchors.fill: parent
                model: page.rateNames()
                font: page.typography.body
                currentIndex: page.rateChoices().indexOf(page.store.mixRate)
                onActivated: function(index): void { page.store.changeMixRate(page.rateChoices()[index]) }
                ToolTip.visible: hovered
                ToolTip.text: qsTr("The GBA's DirectSound mixing rate; 13379 Hz aliases high notes as in-game.")
            }
        }
        // Legacy fork checkbox/button sizes are pinned by tst_ShellSettings reference rects.
        CheckBox {
            id: analog
            objectName: "engine.analog-filter"
            width: page.width; height: 16 + 12 * (page.unit - 1)
            text: qsTr("GBA analog output filter (low-pass)")
            font: page.typography.body
            checked: page.store.analogFilter
            onClicked: page.store.changeAnalogFilter(checked)
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Emulates the rolloff of the GBA's analog output circuit.")
        }
        Button {
            objectName: "engine.restore-defaults"
            width: 118 + 99 * (page.unit - 1); height: 18 + 12 * (page.unit - 1)
            text: qsTr("Restore Defaults")
            font: page.typography.body
            onClicked: {
                page.store.restoreDefaults()
                page.reset()
            }
        }
    }
}
