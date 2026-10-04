pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Dialogs
import QtQuick.Layouts
import PorydawApp

Item {
    id: surface
    required property WavExportPresenter presenter
    required property GridPalette colors
    required property ShellWindow windowRoot
    required property TypographyFonts typography
    readonly property bool exportActive: surface.presenter.active
    readonly property bool optionsVisible: surface.presenter.optionsVisible
    readonly property bool rendering: surface.presenter.rendering
    readonly property bool choosing: surface.presenter.choosingFile
    readonly property int failureRevision: surface.presenter.failureRevision
    visible: false

    onExportActiveChanged: surface.windowRoot.shellPresenter.refreshActionStates()
    onOptionsVisibleChanged: {
        if (optionsVisible && !optionsLoader.active)
            optionsLoader.active = true
        else if (optionsLoader.status === Loader.Ready && optionsLoader.item) {
            if (optionsVisible)
                (optionsLoader.item as DialogWindow).present()
            else
                (optionsLoader.item as DialogWindow).close()
        }
    }
    onRenderingChanged: {
        if (rendering && !progressLoader.active)
            progressLoader.active = true
        else if (progressLoader.status === Loader.Ready && progressLoader.item) {
            if (rendering)
                (progressLoader.item as DialogWindow).present()
            else
                (progressLoader.item as DialogWindow).close()
        }
    }
    onChoosingChanged: {
        if (choosing)
            shellWavExportFileDialog.open()
    }
    onFailureRevisionChanged: {
        if (failureRevision <= 0)
            return
        if (!errorLoader.active)
            errorLoader.active = true
        else if (errorLoader.status === Loader.Ready && errorLoader.item)
            (errorLoader.item as DialogWindow).present()
    }

    FontMetrics {
        id: metrics
        font: surface.typography.body
    }

    // Keep first-use dialogs mounted for subsequent requests, like shell chrome.
    Loader {
        id: optionsLoader
        active: false
        onLoaded: {
            if (optionsLoader.status === Loader.Ready && optionsLoader.item && surface.optionsVisible)
                (optionsLoader.item as DialogWindow).present()
        }
        sourceComponent: DialogWindow {
            id: shellWavExportDialog
            objectName: "shellWavExportDialog"
            transientParent: surface.windowRoot
            colors: surface.colors
            title: qsTr("Export WAV")
            visible: false
            width: metrics.averageCharacterWidth * 47
            height: metrics.height * 13
            font: surface.typography.body
            onClosing: function(close) {
                if (surface.presenter.optionsVisible) {
                    close.accepted = false
                    surface.presenter.rejectOptions()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: metrics.averageCharacterWidth
                spacing: metrics.height / 3
                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    columnSpacing: metrics.averageCharacterWidth
                    rowSpacing: metrics.height / 3
                    Label {
                        text: qsTr("Sample rate:")
                        color: surface.colors.windowText
                    }
                    ComboBox {
                        id: wavExportRate
                        objectName: "wavExportRate"
                        Layout.fillWidth: true
                        model: surface.presenter.rateLabels
                        currentIndex: surface.presenter.rateIndex
                        onActivated: function(index) { surface.presenter.setRateIndex(index) }
                    }
                    Label {
                        text: qsTr("Loop count:")
                        color: surface.colors.windowText
                        visible: surface.presenter.hasLoop
                    }
                    SpinBox {
                        id: wavExportLoopCount
                        objectName: "wavExportLoopCount"
                        visible: surface.presenter.hasLoop
                        from: 1
                        to: 99
                        value: surface.presenter.loopCount
                        onValueModified: surface.presenter.setLoopCount(value)
                    }
                    Label {
                        text: qsTr("Fadeout:")
                        color: surface.colors.windowText
                        visible: surface.presenter.hasLoop
                    }
                    SpinBox {
                        id: wavExportFade
                        objectName: "wavExportFade"
                        visible: surface.presenter.hasLoop
                        from: 0
                        to: 600
                        stepSize: 10
                        value: surface.presenter.fadeTenths
                        textFromValue: function(value: int): string { return (value / 10).toFixed(1) + " s" }
                        valueFromText: function(text: string): real { return Math.round(parseFloat(text) * 10) }
                        onValueModified: surface.presenter.setFadeTenths(value)
                    }
                    Label {
                        objectName: "wavExportTailLabel"
                        text: qsTr("Tail (no loop markers):")
                        color: surface.colors.windowText
                        visible: !surface.presenter.hasLoop
                    }
                    SpinBox {
                        id: wavExportTail
                        objectName: "wavExportTail"
                        visible: !surface.presenter.hasLoop
                        from: 0
                        to: 600
                        stepSize: 10
                        value: surface.presenter.tailTenths
                        textFromValue: function(value: int): string { return (value / 10).toFixed(1) + " s" }
                        valueFromText: function(text: string): real { return Math.round(parseFloat(text) * 10) }
                        onValueModified: surface.presenter.setTailTenths(value)
                    }
                    Label {
                        text: qsTr("Duration:")
                        color: surface.colors.windowText
                    }
                    Label {
                        objectName: "wavExportDuration"
                        text: surface.presenter.durationText
                        color: surface.colors.windowText
                    }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    Button {
                        objectName: "wavExportCancel"
                        text: qsTr("Cancel")
                        onClicked: surface.presenter.rejectOptions()
                    }
                    Button {
                        objectName: "wavExportOK"
                        text: qsTr("OK")
                        onClicked: surface.presenter.acceptOptions()
                    }
                }
            }
        }
    }

    FileDialog {
        id: shellWavExportFileDialog
        objectName: "shellWavExportFileDialog"
        parentWindow: surface.windowRoot
        title: qsTr("Export WAV")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("WAV files (*.wav)")]
        currentFolder: surface.presenter.startFolder
        selectedFile: surface.presenter.suggestedFile
        modality: Qt.WindowModal
        onAccepted: surface.presenter.choosePath(selectedFile.toString())
        onRejected: surface.presenter.rejectPath()
    }

    Loader {
        id: progressLoader
        active: false
        onLoaded: {
            if (progressLoader.status === Loader.Ready && progressLoader.item && surface.rendering)
                (progressLoader.item as DialogWindow).present()
        }
        sourceComponent: DialogWindow {
            id: shellWavExportProgress
            objectName: "shellWavExportProgress"
            transientParent: surface.windowRoot
            colors: surface.colors
            modality: Qt.ApplicationModal
            escapeCloses: false
            title: Qt.application.name
            visible: false
            width: metrics.averageCharacterWidth * 42
            height: metrics.height * 8
            font: surface.typography.body
            onClosing: function(close) {
                if (surface.presenter.rendering) {
                    close.accepted = false
                    surface.presenter.cancelRender()
                }
            }
            Shortcut {
                sequence: "Esc"
                context: Qt.WindowShortcut
                onActivated: surface.presenter.cancelRender()
            }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: metrics.averageCharacterWidth
                Label {
                    objectName: "wavExportProgressLabel"
                    text: surface.presenter.renderText
                    color: surface.colors.windowText
                }
                ProgressBar {
                    objectName: "wavExportProgressBar"
                    Layout.fillWidth: true
                    from: 0
                    to: 1000
                    value: surface.presenter.progress
                }
                Button {
                    objectName: "wavExportProgressCancel"
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("Cancel")
                    onClicked: surface.presenter.cancelRender()
                }
            }
        }
    }

    Loader {
        id: errorLoader
        active: false
        onLoaded: {
            if (errorLoader.status === Loader.Ready && errorLoader.item && surface.failureRevision > 0)
                (errorLoader.item as DialogWindow).present()
        }
        sourceComponent: DialogWindow {
            id: shellWavExportErrorDialog
            objectName: "shellWavExportErrorDialog"
            transientParent: surface.windowRoot
            colors: surface.colors
            title: qsTr("Export WAV")
            width: metrics.averageCharacterWidth * 52
            height: metrics.height * 7
            font: surface.typography.body
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: metrics.averageCharacterWidth
                Label {
                    objectName: "wavExportErrorText"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: surface.presenter.failureMessage
                    color: surface.colors.windowText
                }
                Button {
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("OK")
                    onClicked: shellWavExportErrorDialog.close()
                }
            }
        }
    }
}
