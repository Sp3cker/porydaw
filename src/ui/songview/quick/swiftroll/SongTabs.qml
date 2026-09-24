import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Item {
    id: root

    required property QtObject controller
    property font applicationFont: Application.font
    property var shellRouter: null
    signal contextMenuAt(real x, real y)
    function focusOwnsLocalKeys() {
        if (closeDialog.visible)
            return true
        const window = Window.window
        let focus = window ? window.activeFocusItem : null
        if (!focus)
            return false
        while (focus) {
            if (focus.objectName === "swiftRollInput")
                return false
            if (focus === root)
                return false
            if (focus.activeFocusOnTab || focus.modal || focus.text !== undefined)
                return true
            focus = focus.parent
        }
        return true
    }
    function eventListIsActive() {
        for (let index = 0; index < pages.count; ++index) {
            const page = pages.itemAt(index)
            if (page && page.visible && page.showEvents)
                return true
        }
        return false
    }
    Keys.onPressed: event => {
        if (root.shellRouter && !root.focusOwnsLocalKeys()) {
            const route = root.eventListIsActive() ? "routeEventListKey" : "routeEditorKey"
            event.accepted = root.shellRouter[route](event.key, event.modifiers,
                                                      event.isAutoRepeat)
        }
    }
    // One physical pixel at any device ratio: the strip separator and every
    // control border draw this same hairline.
    readonly property real hairline: 1 / Screen.devicePixelRatio
    // The tab the close gate is asking about. C++ (WorkspaceUi::requestCloseTab)
    // asks about one named tab ("%1 has unsaved changes. Save them?"), so the
    // dialog names the strip's tab instead of saying "this tab". C++'s
    // bank-dirty variant of that string has no counterpart here: the tab's
    // single `dirty` flag is the union of document and voicegroup edits
    // (the protective choice for a gate that can discard work).
    readonly property string pendingCloseTitle: {
        for (let i = 0; i < tabButtons.count; ++i) {
            const button = tabButtons.itemAt(i);
            if (button && button.tabId === root.controller.pendingCloseId)
                return button.session.title;
        }
        return "";
    }

    // Production layout.cpp spacing and Fusion's fixed style metrics.
    readonly property int tabMargin: Math.max(1, Math.round(root.applicationFont.pixelSize * 0.125))
    readonly property int tabPadding: Math.max(1, Math.round(root.applicationFont.pixelSize * 0.5))
    readonly property int closeExtent: 20
    readonly property int scrollExtent: 16
    readonly property int tabHeight: Math.max(closeExtent, Math.round(bodyMetrics.height)) + 3 * tabMargin + 2
    readonly property font bodyFont: Qt.font({
        family: root.applicationFont.family, pixelSize: root.applicationFont.pixelSize,
        weight: Font.Normal, styleName: "", hintingPreference: Font.PreferNoHinting,
        features: { "tnum": 1 }
    })
    readonly property font tabFont: Qt.font({
        family: root.applicationFont.family, pixelSize: root.applicationFont.pixelSize,
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
        font: root.applicationFont
        focusPolicy: Qt.NoFocus
        palette.button: down ? root.controller.palette.tabPressedBackground : hovered ? root.controller.palette.tabHoverBackground : root.controller.palette.chromeBackground
        implicitWidth: caption.implicitWidth + leftPadding + rightPadding
        implicitHeight: Math.round(root.applicationFont.pixelSize * 2)
        padding: Math.round(root.applicationFont.pixelSize * 0.5)
        contentItem: Text {
            id: caption
            text: button.text
            font: button.font
            color: button.down ? root.controller.palette.buttonPressedText
                               : root.controller.palette.windowText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
        background: Rectangle {
            color: button.palette.button
            border.width: root.hairline
            border.color: button.activeFocus ? root.controller.palette.windowText : root.controller.palette.outline
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
                source: "tabart/tab-arrow-" + (control.pointsLeft ? "left" : "right") + (control.enabled ? "-enabled.png" : "-disabled.png")
                sourceSize.width: 4
                x: Math.floor((parent.width - width) / 2)
                y: Math.floor((parent.height - height) / 2)
                smooth: false
            }
        }
        background: Rectangle {
            color: control.down ? root.controller.palette.tabPressedBackground : control.hovered ? root.controller.palette.tabHoverBackground : root.controller.palette.tabBackground
            border.width: root.hairline
            border.color: root.controller.palette.outline
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
        color: root.controller.palette.windowBackground
        enabled: root.controller.pendingCloseId < 0

        Rectangle {
            width: parent.width
            height: root.hairline
            color: root.controller.palette.tabSeparator
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
                        text: session.dirty ? qsTr("%1*").arg(session.title) : session.title
                        Accessible.name: session.dirty ? qsTr("%1, modified").arg(session.title) : session.title
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
                                color: selectButton.down
                                       ? root.controller.palette.buttonPressedText
                                       : (selectButton.checked && !selectButton.hovered
                                          && !closeButton.hovered)
                                         ? root.controller.palette.selectionText
                                         : root.controller.palette.windowText
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                renderType: Text.NativeRendering
                            }
                        }
                        background: Rectangle {
                            y: root.tabMargin
                            height: selectButton.height - root.tabMargin
                            color: selectButton.down ? root.controller.palette.tabPressedBackground : selectButton.checked && !selectButton.hovered && !closeButton.hovered ? root.controller.palette.tabSelectedBackground : (selectButton.hovered || closeButton.hovered) ? root.controller.palette.tabHoverBackground : root.controller.palette.tabBackground
                            border.width: 1
                            border.color: root.controller.palette.outline
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
                            icon.source: "tabart/window-close.svg"
                            icon.width: root.scrollExtent
                            icon.height: root.scrollExtent
                            icon.color: selectButton.down
                                          ? root.controller.palette.buttonPressedText
                                          : (selectButton.checked && !selectButton.hovered
                                             && !closeButton.hovered)
                                            ? root.controller.palette.selectionText
                                            : root.controller.palette.windowText
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
                required property var model
                objectName: "songTab_" + model.display.tabId
                anchors.fill: parent
                session: model.display
                applicationFont: root.applicationFont
                shellRouter: root.shellRouter
                onContextMenuAt: (x, y) => root.contextMenuAt(x, y)
                controller: root.controller
                visible: model.display === root.controller.selectedPage
                enabled: visible
                focus: visible
            }
        }

    }

    Dialog {
        id: closeDialog
        objectName: "songTabCloseDialog"
        parent: Overlay.overlay
        anchors.centerIn: parent
        title: qsTr("Unsaved Changes")
        font: root.applicationFont
        modal: true
        focus: true
        visible: root.controller.pendingCloseId >= 0
        closePolicy: Popup.CloseOnEscape
        onRejected: root.controller.cancelClose()
        Label {
            text: qsTr("%1 has unsaved changes. Save them?").arg(root.pendingCloseTitle)
            font: root.applicationFont
        }
        footer: DialogButtonBox {
            StripButton {
                objectName: "songTabSave"
                text: qsTr("Save")
                focusPolicy: Qt.StrongFocus
                focus: true
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: root.controller.confirmSave()
            }
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
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: root.controller.cancelClose()
            }
        }
    }
}
