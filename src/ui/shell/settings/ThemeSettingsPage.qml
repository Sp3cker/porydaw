pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import PorydawApp

Item {
    id: page
    required property ShellPresenter presenter
    required property QtObject colors
    required property real unit
    required property var typography

    function syncThemeChecks(): void {
        vanillaButton.checked = page.presenter.themeMode === "vanilla"
        darkNeutralHighButton.checked = page.presenter.themeMode === "dark-neutral-high"
        immaterialButton.checked = page.presenter.themeMode === "immaterial"
        contrastSlider.value = page.presenter.gridLineContrast
    }
    Component.onCompleted: page.syncThemeChecks()
    Connections {
        target: page.presenter
        function onThemeModeChanged(): void { page.syncThemeChecks() }
        function onGridLineContrastChanged(): void { contrastSlider.value = page.presenter.gridLineContrast }
    }

    Column {
        y: 11 * page.unit
        width: page.width
        spacing: page.unit * 4
        Column {
            id: themeRow
            objectName: "themeModeGroup"
            width: parent.width
            spacing: page.unit * 4
            Text {
                width: parent.width
                text: qsTr("Theme:")
                color: page.colors.windowText
                font: Qt.font(page.typography.body)
            }
            RadioButton {
                id: vanillaButton
                objectName: "vanillaModeButton"
                width: themeRow.width
                text: qsTr("Vanilla")
                font: Qt.font(page.typography.body)
                onClicked: page.presenter.previewThemeMode("vanilla")
                // Keep visible labels in the themed windowText ink.
                contentItem: Item {}
                Text {
                    objectName: "vanillaModeLabel"
                    x: vanillaButton.leftPadding + vanillaButton.indicator.width + vanillaButton.spacing
                    y: (parent.height - height) / 2
                    width: parent.width - x
                    text: vanillaButton.text
                    color: page.colors.windowText
                    font: vanillaButton.font
                    elide: Text.ElideRight
                }
            }
            RadioButton {
                id: darkNeutralHighButton
                objectName: "darkNeutralHighModeButton"
                width: themeRow.width
                text: qsTr("Dark Neutral High")
                font: Qt.font(page.typography.body)
                onClicked: page.presenter.previewThemeMode("dark-neutral-high")
                contentItem: Item {}
                Text {
                    objectName: "darkNeutralHighModeLabel"
                    x: darkNeutralHighButton.leftPadding + darkNeutralHighButton.indicator.width + darkNeutralHighButton.spacing
                    y: (parent.height - height) / 2
                    width: parent.width - x
                    text: darkNeutralHighButton.text
                    color: page.colors.windowText
                    font: darkNeutralHighButton.font
                    elide: Text.ElideRight
                }
            }
            RadioButton {
                id: immaterialButton
                objectName: "immaterialModeButton"
                width: themeRow.width
                text: qsTr("Immaterial")
                font: Qt.font(page.typography.body)
                onClicked: page.presenter.previewThemeMode("immaterial")
                contentItem: Item {}
                Text {
                    objectName: "immaterialModeLabel"
                    x: immaterialButton.leftPadding + immaterialButton.indicator.width + immaterialButton.spacing
                    y: (parent.height - height) / 2
                    width: parent.width - x
                    text: immaterialButton.text
                    color: page.colors.windowText
                    font: immaterialButton.font
                    elide: Text.ElideRight
                }
            }
        }
        Row {
            id: contrastRow
            objectName: "gridContrastRow"
            width: parent.width
            height: page.typography.body.pixelSize * 3
            spacing: page.unit * 8
            Text {
                id: contrastLabel
                width: implicitWidth
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Grid contrast:")
                color: page.colors.windowText
                font: Qt.font(page.typography.body)
            }
            Slider {
                id: contrastSlider
                objectName: "gridLineContrastSlider"
                width: contrastRow.width - contrastLabel.width - contrastRow.spacing
                height: parent.height
                from: 0
                to: 100
                stepSize: 1
                Accessible.name: qsTr("Grid Line Contrast")
                ToolTip.visible: hovered
                ToolTip.text: qsTr("50 uses the theme default. Lower values soften grid lines; higher values strengthen them.")
                font: Qt.font(page.typography.body)
                onMoved: page.presenter.setGridLineContrast(Math.round(value))
            }
        }
    }
}
