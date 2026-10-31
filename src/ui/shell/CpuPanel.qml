pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp

Item {
    id: panel
    objectName: "cpuPanel"
    required property CpuMeterPresenter presenter
    required property GridPalette colors
    required property TypographyFonts typography
    required property LayoutSpaces layoutSpaces
    required property real baseFontPx
    readonly property real em: baseFontPx
    readonly property real gap: layoutSpaces.two
    readonly property real scaleCycles: 83776 * 1.4
    readonly property color levelColor: presenter.level === 2 ? colors.errorText
                                       : presenter.level === 1 ? colors.warningText : colors.windowText
    readonly property CpuGraphScene historyScene: CpuGraphScene {
        meter: panel.presenter
        palette: panel.colors
        onMeterChanged: panel.refreshHistory()
        onPaletteChanged: panel.refreshHistory()
    }

    function refreshHistory(): void {
        if (panel.visible && chart)
            panel.historyScene.updateHistory(chart.width, chart.height)
    }

    onVisibleChanged: panel.refreshHistory()
    Component.onCompleted: panel.refreshHistory()
    Connections {
        target: panel.visible ? panel.presenter : null
        function onHistoryRevisionChanged(): void { panel.refreshHistory() }
        function onBudgetChanged(): void { panel.refreshHistory() }
    }
    Connections {
        target: panel.visible ? panel.colors : null
        function onPolyphonyActiveFillChanged(): void { panel.refreshHistory() }
        function onWarningTextChanged(): void { panel.refreshHistory() }
        function onErrorTextChanged(): void { panel.refreshHistory() }
    }

    Rectangle { anchors.fill: parent; color: panel.colors.windowBackground }
    Flickable {
        id: scroll
        objectName: "cpuPanelScroll"
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: content.height + panel.gap * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: content
            x: panel.gap; y: panel.gap
            width: scroll.width - panel.gap * 2
            spacing: panel.gap
            Text {
                objectName: "cpuStatus"
                text: !panel.presenter.loaded ? qsTr("No song")
                    : !panel.presenter.playing ? qsTr("Stopped")
                    : !panel.presenter.valid ? qsTr("Measuring or unavailable")
                    : panel.presenter.level === 2 ? qsTr("Past VBlank")
                    : panel.presenter.level === 1 ? qsTr("Over budget") : qsTr("Within budget")
                color: panel.presenter.valid ? panel.levelColor : panel.colors.secondaryText
                font: panel.typography.bodyBold
            }
            Text {
                objectName: "cpuPercent"
                text: panel.presenter.valid ? qsTr("%1%").arg(panel.presenter.percent) : "—"
                color: panel.presenter.valid ? panel.levelColor : panel.colors.secondaryText
                font.family: panel.typography.bodyBold.family
                font.weight: panel.typography.bodyBold.weight
                font.pixelSize: Math.round(panel.em * 2.5)
            }
            Text {
                width: parent.width
                text: panel.presenter.valid
                    ? qsTr("Estimated %L1 cycles · of the VBlank window").arg(panel.presenter.total)
                    : !panel.presenter.loaded ? qsTr("Open a song to see its sound-driver cost.")
                    : panel.presenter.playing ? qsTr("No song-only frame is available yet.")
                    : qsTr("Press Play to measure the sound driver frame by frame.")
                color: panel.colors.secondaryText
                font: panel.typography.body
                wrapMode: Text.WordWrap
            }
            Item {
                id: meter
                objectName: "cpuMeter"
                width: parent.width
                height: panel.em * 3.4
                Rectangle {
                    id: track
                    x: 0; y: panel.em
                    width: parent.width; height: panel.em
                    color: panel.colors.inputBackground
                    border.color: panel.colors.outline
                    Row {
                        anchors.fill: parent
                        Rectangle {
                            width: meter.width * Math.min(panel.presenter.sequencer, panel.scaleCycles) / panel.scaleCycles
                            height: parent.height
                            color: panel.colors.polyphonyShadowFill
                        }
                        Rectangle {
                            width: meter.width * Math.min(panel.presenter.cgb, Math.max(0, panel.scaleCycles - panel.presenter.sequencer)) / panel.scaleCycles
                            height: parent.height
                            color: panel.colors.polyphonyActiveFill
                        }
                        Rectangle {
                            width: meter.width * Math.min(panel.presenter.mixer, Math.max(0, panel.scaleCycles - panel.presenter.sequencer - panel.presenter.cgb)) / panel.scaleCycles
                            height: parent.height
                            color: panel.colors.polyphonyReleasingFill
                        }
                    }
                }
                Rectangle {
                    x: Math.min(meter.width - width, meter.width * panel.presenter.budget / panel.scaleCycles)
                    y: track.y - panel.em * 0.3; width: Math.max(1, panel.em / 12); height: track.height + panel.em * 0.6
                    color: panel.colors.warningText
                }
                Rectangle {
                    x: Math.min(meter.width - width, meter.width * 83776 / panel.scaleCycles)
                    y: track.y - panel.em * 0.3; width: Math.max(1, panel.em / 12); height: track.height + panel.em * 0.6
                    color: panel.colors.errorText
                }
                Rectangle {
                    visible: panel.presenter.peakVisible
                    x: Math.min(meter.width - width, meter.width * panel.presenter.peak / panel.scaleCycles)
                    y: track.y - panel.em * 0.6; width: Math.max(1, panel.em / 12); height: track.height + panel.em * 0.9
                    color: panel.colors.windowText
                }
                Text { x: 0; y: track.y + track.height; text: "0%"; color: panel.colors.secondaryText; font: panel.typography.caption }
                Text { anchors.right: parent.right; y: track.y + track.height; text: "140%"; color: panel.colors.secondaryText; font: panel.typography.caption }
            }
            Text {
                text: qsTr("LAST 10 SECONDS")
                color: panel.colors.secondaryText; font: panel.typography.bodyBold
            }
            Text {
                objectName: "cpuHistoryCaption"
                width: parent.width
                text: panel.presenter.historyCount === 0 ? qsTr("No playback history yet")
                    : !panel.presenter.playing ? qsTr("Last run")
                    : qsTr("Maximum %1% · %2 frames over budget")
                        .arg(Math.round(panel.presenter.historyMax * 100 / 83776)).arg(panel.presenter.historyOver)
                color: panel.colors.secondaryText; font: panel.typography.caption
                wrapMode: Text.WordWrap
            }
            Item {
                id: chart
                objectName: "cpuHistory"
                width: parent.width; height: panel.em * 6
                opacity: panel.presenter.playing ? 1 : 0.5
                onWidthChanged: panel.refreshHistory()
                onHeightChanged: panel.refreshHistory()
                Rectangle { anchors.fill: parent; color: panel.colors.inputBackground; border.color: panel.colors.outline }
                DisplayList {
                    anchors.fill: parent
                    source: panel.historyScene
                    list: 0
                    revision: panel.historyScene.displayRevision
                }
                Rectangle {
                    x: 0; y: chart.height * (1 - Math.min(panel.presenter.budget / panel.scaleCycles, 1))
                    width: chart.width; height: Math.max(1, panel.em / 12); color: panel.colors.warningText
                }
                Rectangle {
                    x: 0; y: chart.height * (1 - 83776 / panel.scaleCycles)
                    width: chart.width; height: Math.max(1, panel.em / 12); color: panel.colors.errorText
                }
            }
            Text { text: qsTr("WHERE IT GOES"); color: panel.colors.secondaryText; font: panel.typography.bodyBold }
            Repeater {
                readonly property list<string> labels: [qsTr("Sequencer"), qsTr("CGB"), qsTr("Mixer")]
                model: labels
                delegate: Column {
                    id: term
                    required property int index
                    required property string modelData
                    readonly property int cycles: index === 0 ? panel.presenter.sequencer : index === 1 ? panel.presenter.cgb : panel.presenter.mixer
                    readonly property color termColor: index === 0 ? panel.colors.polyphonyShadowFill
                        : index === 1 ? panel.colors.polyphonyActiveFill : panel.colors.polyphonyReleasingFill
                    width: content.width
                    spacing: panel.em * 0.2
                    Row {
                        width: parent.width; height: Math.max(panel.em * 1.4, termName.implicitHeight)
                        spacing: panel.gap
                        Text {
                            id: termName
                            width: Math.max(panel.em * 7, term.width * 0.35)
                            text: term.modelData + (term.index === 0 && panel.presenter.sequencerEstimated ? qsTr(" (est.)") : "")
                            color: panel.colors.windowText; font: panel.typography.body
                        }
                        Text {
                            width: Math.max(0, term.width - termName.width - panel.gap)
                            text: panel.presenter.valid ? qsTr("%L1 cycles · %2%")
                                .arg(term.cycles)
                                .arg(panel.presenter.total > 0 ? Math.round(term.cycles * 100 / panel.presenter.total) : 0) : "—"
                            color: panel.colors.windowText; font: panel.typography.bodyMono
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                    Rectangle {
                        width: parent.width; height: Math.max(2, panel.em * 0.3)
                        color: panel.colors.inputBackground
                        Rectangle {
                            width: panel.presenter.valid && panel.presenter.total > 0
                                ? parent.width * term.cycles / panel.presenter.total : 0
                            height: parent.height; color: term.termColor
                        }
                    }
                }
            }
            Rectangle {
                objectName: "cpuPeakCard"
                visible: panel.presenter.peakVisible
                width: parent.width; height: peakContent.height + panel.gap * 2
                color: panel.colors.alternateBackground; border.color: panel.colors.outline
                Column {
                    id: peakContent
                    x: panel.gap; y: panel.gap
                    width: parent.width - panel.gap * 2; spacing: panel.gap
                    Text {
                        text: panel.presenter.playing ? qsTr("Peak since Play") : qsTr("Peak in last run")
                        color: panel.colors.windowText; font: panel.typography.bodyBold
                    }
                    Text {
                        objectName: "cpuPeak"
                        text: qsTr("%1% · %L2 cycles at %3").arg(panel.presenter.peakPercent)
                            .arg(panel.presenter.peak).arg(panel.presenter.peakTime)
                        color: panel.presenter.peak > 83776 ? panel.colors.errorText
                             : panel.presenter.peak > panel.presenter.budget ? panel.colors.warningText : panel.colors.windowText
                        font: panel.typography.body
                    }
                }
            }
            Button {
                objectName: "cpuReset"
                text: qsTr("Reset peak")
                enabled: panel.presenter.loaded
                font: panel.typography.body
                onClicked: panel.presenter.reset()
            }
            Text { text: qsTr("REFERENCE"); color: panel.colors.secondaryText; font: panel.typography.bodyBold }
            Text {
                width: parent.width
                text: qsTr("Budget: %L1 cycles (%2%) · VBlank: 83,776 cycles (100%) · whole frame: 280,896 cycles (335%)")
                    .arg(panel.presenter.budget).arg(panel.presenter.budgetPercent)
                color: panel.colors.windowText; font: panel.typography.body; wrapMode: Text.WordWrap
            }
            Text {
                visible: panel.presenter.loaded
                width: parent.width
                text: qsTr("%1 Hz mix rate · %2 PCM channels · %3")
                    .arg(panel.presenter.mixRate).arg(panel.presenter.maxPcmChannels)
                    .arg(panel.presenter.hqMixer ? qsTr("HQ mixer") : qsTr("stock mixer"))
                color: panel.colors.secondaryText; font: panel.typography.caption; wrapMode: Text.WordWrap
            }
            Text {
                visible: panel.presenter.loaded
                width: parent.width
                text: panel.presenter.renderedTrackSlots > panel.presenter.gameTrackBudget
                    ? qsTr("Renderer: %1 track slots · game player budget: %2. The estimate includes rendered tracks beyond the game budget.")
                        .arg(panel.presenter.renderedTrackSlots).arg(panel.presenter.gameTrackBudget)
                    : qsTr("Renderer: %1 track slots · game player budget: %2.")
                        .arg(panel.presenter.renderedTrackSlots).arg(panel.presenter.gameTrackBudget)
                color: panel.presenter.renderedTrackSlots > panel.presenter.gameTrackBudget
                    ? panel.colors.warningText : panel.colors.secondaryText
                font: panel.typography.caption; wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: qsTr("The total and each term are modeled estimates of m4aSoundMain GBA cycles, not host CPU usage. Player overhead uses a BGM model; the game shares these cycles with other work and hardware can differ.")
                color: panel.colors.secondaryText; font: panel.typography.caption; wrapMode: Text.WordWrap
            }
        }
    }
}
