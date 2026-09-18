import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property QtObject controller
    required property font font
    required property real baseFontPx
    required property string monoFamily
    required property var gridPalette
    readonly property Item currentPage: pages.count > 0 && controller.selectedIndex >= 0 ? pages.itemAt(controller.selectedIndex) : null

    // Production layout.cpp spacing and Fusion's fixed style metrics.
    readonly property int tabMargin: Math.max(1, Math.round(baseFontPx * 0.125))
    readonly property int tabPadding: Math.max(1, Math.round(baseFontPx * 0.5))
    readonly property int closeExtent: 20
    readonly property int scrollExtent: 16
    readonly property int tabHeight: Math.max(closeExtent, Math.round(bodyMetrics.height)) + 3 * tabMargin + 2
    readonly property font bodyFont: Qt.font({
        family: root.font.family, pixelSize: root.font.pixelSize,
        weight: Font.Normal, styleName: "", hintingPreference: Font.PreferNoHinting,
        features: { "tnum": 1 }
    })
    readonly property font tabFont: Qt.font({
        family: root.font.family, pixelSize: root.font.pixelSize,
        weight: Font.DemiBold, styleName: "", hintingPreference: Font.PreferNoHinting,
        features: { "tnum": 1 }
    })
    FontMetrics {
        id: bodyMetrics
        font: root.bodyFont
    }

    function revealSelectedTab() {
        const selected = tabButtons.itemAt(root.controller.selectedIndex);
        if (!selected)
            return;
        if (selected.x < stripViewport.contentX)
            stripViewport.contentX = selected.x;
        else if (selected.x + selected.width > stripViewport.contentX + stripViewport.width)
            stripViewport.contentX = Math.max(0, selected.x + selected.width - stripViewport.width);
    }

    Connections {
        target: root.controller
        function onSelectedIndexChanged() {
            root.revealSelectedTab();
        }
    }

    component StripButton: Button {
        id: button
        font: root.font
        focusPolicy: Qt.NoFocus
        palette.button: down ? "#F5B61C" : hovered ? "#E7E2DC" : root.gridPalette.chromeBackground
        implicitWidth: caption.implicitWidth + leftPadding + rightPadding
        implicitHeight: Math.round(root.baseFontPx * 2)
        padding: Math.round(root.baseFontPx * 0.5)
        contentItem: Text {
            id: caption
            text: button.text
            font: button.font
            color: root.gridPalette.windowText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
        background: Rectangle {
            color: button.palette.button
            border.width: 1 / Screen.devicePixelRatio
            border.color: button.activeFocus ? root.gridPalette.windowText : root.gridPalette.outline
        }
    }

    component ScrollButton: Button {
        id: control
        required property bool pointsLeft
        focusPolicy: Qt.NoFocus
        width: root.scrollExtent
        padding: 0
        contentItem: Item {
            Image {
                source: "qrc:/tabart/tab-arrow-" + (control.pointsLeft ? "left" : "right") + (control.enabled ? "-enabled.png" : "-disabled.png")
                sourceSize.width: 4
                x: Math.floor((parent.width - width) / 2)
                y: Math.floor((parent.height - height) / 2)
                smooth: false
            }
        }
        background: Rectangle {
            color: control.down ? "#F5B61C" : control.hovered ? "#ECE7E1" : root.gridPalette.tabBackground
            border.width: 1
            border.color: root.gridPalette.outline
        }
        ToolTip.visible: hovered
        ToolTip.text: Accessible.name
    }

    Rectangle {
        id: strip
        objectName: "songTabStrip"
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.max(Math.round(bodyMetrics.lineSpacing), root.scrollExtent) + 2 * root.tabMargin + 2
        color: root.gridPalette.windowBackground
        enabled: root.controller.pendingCloseId < 0

        Rectangle {
            width: parent.width
            height: 1 / Screen.devicePixelRatio
            color: "#9E9893"
        }

        Flickable {
            id: stripViewport
            anchors.left: parent.left
            anchors.right: scrollControls.visible ? scrollControls.left : parent.right
            height: parent.height
            contentWidth: tabRow.width
            contentHeight: height
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            clip: true
            pixelAligned: true
            onWidthChanged: root.revealSelectedTab()

            Row {
                id: tabRow
                height: root.tabHeight
                onPositioningComplete: root.revealSelectedTab()

                Repeater {
                    id: tabButtons
                    model: root.controller.tabs
                    delegate: Button {
                        id: selectButton
                        required property var model
                        readonly property QtObject session: model.display
                        readonly property int tabId: session.tabId
                        objectName: "songTabSelect_" + tabId
                        text: session.grid.canUndo ? qsTr("%1*").arg(session.title) : session.title
                        Accessible.name: session.grid.canUndo ? qsTr("%1, modified").arg(session.title) : session.title
                        checked: root.controller.selectedId === tabId
                        font: root.tabFont
                        focusPolicy: Qt.NoFocus
                        padding: 0
                        width: Math.round(titleMetrics.advanceWidth) + 2 * (root.tabPadding + 1) + root.closeExtent + 4
                        height: root.tabHeight
                        ToolTip.visible: hovered && !closeButton.hovered
                        ToolTip.text: session.title
                        onClicked: root.controller.selectTab(tabId)

                        TextMetrics {
                            id: titleMetrics
                            font: root.bodyFont
                            text: selectButton.text
                        }
                        contentItem: Item {
                            Text {
                                x: root.tabPadding + 1
                                y: 2 * root.tabMargin + 1
                                width: Math.round(titleMetrics.advanceWidth)
                                height: Math.max(root.closeExtent, Math.round(bodyMetrics.height))
                                text: selectButton.text
                                font: selectButton.font
                                color: root.gridPalette.windowText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                renderType: Text.NativeRendering
                            }
                        }
                        background: Rectangle {
                            y: root.tabMargin
                            height: selectButton.height - root.tabMargin
                            color: selectButton.checked ? root.gridPalette.tabSelectedBackground : (selectButton.hovered || closeButton.hovered) ? root.gridPalette.tabHoverBackground : root.gridPalette.tabBackground
                            border.width: 1
                            border.color: root.gridPalette.outline
                        }

                        Button {
                            id: closeButton
                            objectName: "songTabClose_" + selectButton.tabId
                            x: parent.width - width - 1
                            y: Math.floor((parent.height - height) / 2)
                            width: root.closeExtent
                            height: root.closeExtent
                            padding: 2
                            focusPolicy: Qt.NoFocus
                            display: AbstractButton.IconOnly
                            icon.source: "qrc:/tabart/window-close.svg"
                            icon.width: root.scrollExtent
                            icon.height: root.scrollExtent
                            icon.color: root.gridPalette.windowText
                            background: Item {}
                            Accessible.name: qsTr("Close %1").arg(selectButton.session.title)
                            ToolTip.visible: hovered
                            ToolTip.text: Accessible.name
                            onClicked: root.controller.requestClose(selectButton.tabId)
                        }

                        DragHandler {
                            target: null
                            enabled: !closeButton.down
                            acceptedButtons: Qt.LeftButton
                            yAxis.enabled: false
                            onActiveChanged: {
                                if (!active) {
                                    const drop = selectButton.mapToItem(tabRow, centroid.position.x, centroid.position.y);
                                    let destination = tabButtons.count - 1;
                                    for (let i = 0; i < tabButtons.count; ++i) {
                                        const candidate = tabButtons.itemAt(i);
                                        if (drop.x < candidate.x + candidate.width) {
                                            destination = i;
                                            break;
                                        }
                                    }
                                    root.controller.moveTab(selectButton.tabId, destination);
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: scrollControls
            anchors.right: parent.right
            width: 2 * root.scrollExtent - 1
            height: parent.height
            visible: tabRow.width > strip.width

            ScrollButton {
                objectName: "songTabScrollLeft"
                pointsLeft: true
                height: parent.height
                enabled: !stripViewport.atXBeginning
                Accessible.name: qsTr("Scroll tabs left")
                onClicked: stripViewport.contentX = Math.max(0, stripViewport.contentX - stripViewport.width)
            }
            ScrollButton {
                objectName: "songTabScrollRight"
                pointsLeft: false
                x: root.scrollExtent - 1
                height: parent.height
                enabled: !stripViewport.atXEnd
                Accessible.name: qsTr("Scroll tabs right")
                onClicked: stripViewport.contentX = Math.min(Math.max(0, stripViewport.contentWidth - stripViewport.width), stripViewport.contentX + stripViewport.width)
            }
        }
    }

    Item {
        id: pageStack
        objectName: "songTabPages"
        anchors.top: strip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        Repeater {
            id: pages
            model: root.controller.tabs
            delegate: SongTab {
                required property var display
                objectName: "songTab_" + display.tabId
                anchors.fill: parent
                gridModel: display.grid
                font: root.font
                baseFontPx: root.baseFontPx
                monoFamily: root.monoFamily
                visible: display.tabId === root.controller.selectedId
                enabled: visible
                focus: visible
            }
        }

    }

    Dialog {
        id: closeDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Discard changes?")
        font: root.font
        modal: true
        focus: true
        visible: root.controller.pendingCloseId >= 0
        closePolicy: Popup.CloseOnEscape
        onRejected: root.controller.cancelClose()
        Label {
            text: qsTr("This song tab has unsaved changes.")
            font: root.font
        }
        footer: DialogButtonBox {
            StripButton {
                objectName: "songTabDiscard"
                text: qsTr("Discard")
                focusPolicy: Qt.StrongFocus
                DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                onClicked: root.controller.confirmDiscard()
            }
            StripButton {
                objectName: "songTabCancel"
                text: qsTr("Cancel")
                focusPolicy: Qt.StrongFocus
                focus: true
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: root.controller.cancelClose()
            }
        }
    }
}
