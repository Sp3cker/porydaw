import QtQuick
import QtQuick.Controls.Basic
import Porydaw.Ui

DialogWindow {
    id: dialog
    objectName: "settingsDialog"
    required property QtObject store
    required property QtObject presenter
    required property QtObject applicationSession
    readonly property real unit: applicationSession.baseFontPx / 12
    property int selectedTab: 0
    width: 560
    height: 580
    minimumWidth: width
    minimumHeight: height
    maximumWidth: width
    maximumHeight: height
    title: qsTr("Settings")
    font: Qt.font(applicationSession.typographyFonts.body)

    function showSettings(songFirst) {
        store.open()
        if (enginePage.item)
            enginePage.item.reset()
        if (songPage.item)
            songPage.item.reset()
        selectedTab = songFirst && store.songAvailable ? 1 : 0
        present()
    }
    function commit() {
        if (store.songAvailable)
            songPage.item.finishVoicegroupEdit()
        store.apply()
        presenter.commitThemeMode()
        presenter.commitGridLineContrast()
    }
    onClosing: {
        presenter.discardThemeMode()
        presenter.discardGridLineContrast()
    }
    Rectangle {
        id: body
        objectName: "settingsBody"
        anchors.fill: parent
        color: dialog.colors.windowBackground
    }

    Item {
        id: tabs
        objectName: "tabs"
        parent: body
        x: 11; y: 11
        width: dialog.width - 22
        height: dialog.height - 46 - 12 * (dialog.unit - 1)
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: dialog.colors.outline
            border.width: Math.max(1, dialog.unit)
        }
        Row {
            id: tabBar
            objectName: "tab-bar"
            width: 212 + 177 * (dialog.unit - 1)
            height: 22 + 12 * (dialog.unit - 1)
            Button {
                id: engineTab
                objectName: "settingsEngineTab"
                height: tabBar.height
                width: 64 + 42 * (dialog.unit - 1)
                text: qsTr("Engine")
                font: Qt.font(dialog.applicationSession.typographyFonts.body)
                palette.active.buttonText: dialog.selectedTab === 0 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.inactive.buttonText: dialog.selectedTab === 0 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.disabled.buttonText: dialog.colors.disabledText
                onClicked: dialog.selectedTab = 0
                background: Rectangle {
                    color: dialog.selectedTab === 0 ? dialog.colors.tabSelectedBackground
                                                    : dialog.colors.tabBackground
                    border.color: dialog.colors.outline
                }
            }
            Button {
                id: songTab
                objectName: "settingsSongTab"
                height: tabBar.height
                width: tabBar.width - engineTab.width
                text: dialog.store.songLabel.length > 0
                      ? qsTr("Song (%1)").arg(dialog.store.songLabel) : qsTr("Song")
                font: Qt.font(dialog.applicationSession.typographyFonts.body)
                enabled: dialog.store.songAvailable
                palette.active.buttonText: dialog.selectedTab === 1 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.inactive.buttonText: dialog.selectedTab === 1 ? dialog.colors.selectionText : dialog.colors.buttonText
                palette.disabled.buttonText: dialog.colors.disabledText
                onClicked: dialog.selectedTab = 1
                background: Rectangle {
                    color: dialog.selectedTab === 1 ? dialog.colors.tabSelectedBackground
                                                    : dialog.colors.tabBackground
                    border.color: dialog.colors.outline
                }
            }
        }
    }
    Loader {
        id: enginePage
        parent: body
        x: 20; y: 31
        width: dialog.width - 40
        height: tabs.height - 20 * dialog.unit
        active: dialog.visible
        visible: dialog.selectedTab === 0
        onLoaded: item.reset()
        sourceComponent: EngineSettingsPage {
            objectName: "settingsEnginePage"
            unit: dialog.unit; store: dialog.store; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Loader {
        id: songPage
        parent: body
        x: 20; y: 31
        width: dialog.width - 40
        height: tabs.height - 20 * dialog.unit
        active: dialog.visible
        visible: dialog.selectedTab === 1
        onLoaded: item.reset()
        sourceComponent: SongSettingsPage {
            objectName: "settingsSongPage"
            unit: dialog.unit; store: dialog.store; colors: dialog.colors
            typography: dialog.applicationSession.typographyFonts
        }
    }
    Column {
        id: themeRow
        parent: body
        objectName: "themeModeGroup"
        x: enginePage.x
        y: contrastRow.y - height - dialog.unit * 4
        width: enginePage.width
        height: implicitHeight
        spacing: dialog.unit * 4
        visible: dialog.selectedTab === 0
        Text {
            width: parent.width
            height: implicitHeight
            text: qsTr("Theme:")
            color: dialog.colors.windowText
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
        }
        RadioButton {
            id: vanillaButton
            objectName: "vanillaModeButton"
            width: themeRow.width
            text: qsTr("Vanilla")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            checked: dialog.presenter.themeMode === "vanilla"
            onClicked: dialog.presenter.previewThemeMode("vanilla")
            // Basic CheckLabel offsets its glyphs by the 28px indicator, so the
            // label below carries the visible text in the themed windowText ink.
            contentItem: Item {}
            Text {
                objectName: "vanillaModeLabel"
                x: vanillaButton.leftPadding + vanillaButton.indicator.width + vanillaButton.spacing
                y: (parent.height - height) / 2
                width: parent.width - x
                text: vanillaButton.text
                color: dialog.colors.windowText
                font: vanillaButton.font
                elide: Text.ElideRight
            }
        }
        RadioButton {
            id: darkNeutralHighButton
            objectName: "darkNeutralHighModeButton"
            width: themeRow.width
            text: qsTr("Dark Neutral High")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            checked: dialog.presenter.themeMode === "dark-neutral-high"
            onClicked: dialog.presenter.previewThemeMode("dark-neutral-high")
            contentItem: Item {}
            Text {
                objectName: "darkNeutralHighModeLabel"
                x: darkNeutralHighButton.leftPadding + darkNeutralHighButton.indicator.width + darkNeutralHighButton.spacing
                y: (parent.height - height) / 2
                width: parent.width - x
                text: darkNeutralHighButton.text
                color: dialog.colors.windowText
                font: darkNeutralHighButton.font
                elide: Text.ElideRight
            }
        }
        RadioButton {
            id: immaterialButton
            objectName: "immaterialModeButton"
            width: themeRow.width
            text: qsTr("Immaterial")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            checked: dialog.presenter.themeMode === "immaterial"
            onClicked: dialog.presenter.previewThemeMode("immaterial")
            contentItem: Item {}
            Text {
                objectName: "immaterialModeLabel"
                x: immaterialButton.leftPadding + immaterialButton.indicator.width + immaterialButton.spacing
                y: (parent.height - height) / 2
                width: parent.width - x
                text: immaterialButton.text
                color: dialog.colors.windowText
                font: immaterialButton.font
                elide: Text.ElideRight
            }
        }
    }
    function syncThemeChecks() {
        vanillaButton.checked = dialog.presenter.themeMode === "vanilla"
        darkNeutralHighButton.checked = dialog.presenter.themeMode === "dark-neutral-high"
        immaterialButton.checked = dialog.presenter.themeMode === "immaterial"
        contrastSlider.value = dialog.presenter.gridLineContrast
    }
    Connections {
        target: dialog.presenter
        function onThemeModeChanged() { dialog.syncThemeChecks() }
        function onGridLineContrastChanged() { contrastSlider.value = dialog.presenter.gridLineContrast }
    }
    Row {
        id: contrastRow
        parent: body
        objectName: "gridContrastRow"
        x: enginePage.x
        y: enginePage.y + enginePage.height - height - dialog.unit * 2
        width: enginePage.width
        height: dialog.applicationSession.typographyFonts.body.pixelSize * 3
        spacing: dialog.unit * 8
        visible: dialog.selectedTab === 0
        Text {
            id: contrastLabel
            width: enginePage.item ? enginePage.item.labelWidth : 0
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Grid contrast:")
            color: dialog.colors.windowText
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
        }
        Slider {
            id: contrastSlider
            objectName: "gridLineContrastSlider"
            width: contrastRow.width - contrastLabel.width - contrastRow.spacing
            height: parent.height
            from: 0
            to: 100
            stepSize: 1
            value: dialog.presenter.gridLineContrast
            Accessible.name: qsTr("Grid Line Contrast")
            ToolTip.visible: hovered
            ToolTip.text: qsTr("50 uses the theme default. Lower values soften grid lines; higher values strengthen them.")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            onMoved: dialog.presenter.setGridLineContrast(Math.round(value))
        }
    }
    Item {
        objectName: "button-box"
        parent: body
        x: dialog.width - 11 - (240 - 21 * (dialog.unit - 1))
        y: dialog.height - 29 - 12 * (dialog.unit - 1)
        width: 240 - 21 * (dialog.unit - 1)
        height: 18 + 12 * (dialog.unit - 1)
        Button {
            id: applyButton
            objectName: "settingsApply"
            x: 0; width: (parent.width - 2 * dialog.unit) / 3
            height: parent.height; text: qsTr("Apply")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            enabled: !dialog.store.isApplying
            onClicked: dialog.commit()
        }
        Button {
            id: cancelButton
            objectName: "settingsCancel"
            x: applyButton.width + dialog.unit
            width: applyButton.width; height: parent.height; text: qsTr("Cancel")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            onClicked: dialog.close()
        }
        Button {
            id: okButton
            objectName: "settingsOK"
            x: cancelButton.x + cancelButton.width + dialog.unit
            width: applyButton.width; height: parent.height; text: qsTr("OK")
            font: Qt.font(dialog.applicationSession.typographyFonts.body)
            enabled: !dialog.store.isApplying
            onClicked: {
                dialog.commit()
                dialog.close()
            }
        }
    }
}
