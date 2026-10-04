// Swift owns drawer layout, visibility, resizing and focus requests.
// Persistent body loaders share one unclipped modal layer.
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import Porydaw.Icons
import PorydawApp as App

FocusScope {
    id: drawerScope

    objectName: "editorDrawer"

    required property App.SongTabSession applicationSession
    required property App.EditorDrawerPresenter presenter
    required property App.GridPalette drawerPalette
    property App.MouseHints hintService: null
    readonly property bool hintScopeAllowed: {
        for (let i = 0; i < modalLayer.children.length; ++i) {
            if (modalLayer.children[i].visible)
                return false
        }
        return true
    }
    readonly property App.VelocityPage velocityModel: applicationSession.songOpen
                                                    ? applicationSession.velocityPage() : null

    // DrawerSectionKind raw values; layout facts stay in the presenter.
    readonly property int automationKind: 0
    readonly property int velocityKind: 1
    readonly property int voiceChangesKind: 2

    // Composition supplies width; Swift owns the aggregate height.
    height: presenter.height
    clip: true

    function keyNameFor(kind: int): string {
        switch (kind) {
        case drawerScope.automationKind: return "automation"
        case drawerScope.velocityKind: return "velocity"
        case drawerScope.voiceChangesKind: return "voiceChanges"
        }
        return ""
    }

    function iconFor(kind: int): var {
        switch (kind) {
        case drawerScope.automationKind: return Icons.automation
        case drawerScope.velocityKind: return Icons.velocity
        case drawerScope.voiceChangesKind: return Icons.flat
        }
        return emptyIcon
    }

    QtObject {
        id: emptyIcon
        readonly property string glyph: ""
        readonly property real fit: 1
    }


    // Requests with no loaded page are skipped until the next transition.
    function sectionLoader(kind: int): Loader {
        switch (kind) {
        case drawerScope.automationKind: return automationSection.pageLoader
        case drawerScope.velocityKind: return velocitySection.pageLoader
        case drawerScope.voiceChangesKind: return voiceChangesSection.pageLoader
        }
        return null
    }

    // Resolve the roll sibling through its stable objectName.
    function findItemByName(item: Item, name: string): Item {
        if (!item)
            return null
        if (item.objectName === name)
            return item
        for (var i = 0; i < item.children.length; ++i) {
            var found = drawerScope.findItemByName(item.children[i], name)
            if (found)
                return found
        }
        return null
    }
    // True when keyboard focus sits inside the container-wide modal layer:
    // a menu, picker or prompt owns it, not the section chrome.
    function modalOwnsFocus(): bool {
        const window = drawerScope.Window.window
        let focus = window ? window.activeFocusItem : null
        while (focus) {
            if (focus === modalLayer)
                return true
            focus = focus.parent
        }
        return false
    }

    function executeFocusRequest(): void {
        // A queued section request predates a modal the user has since opened;
        // the modal keeps keyboard focus until it dismisses itself.
        if (drawerScope.modalOwnsFocus())
            return
        var target = drawerScope.presenter.focusTarget
        if (target < 0) {
            var root = drawerScope
            while (root.parent)
                root = root.parent
            var roll = drawerScope.findItemByName(root, "swiftRollInput")
            if (roll)
                roll.forceActiveFocus(Qt.OtherFocusReason)
            return
        }
        var loader = drawerScope.sectionLoader(target)
        if (loader && loader.item) {
            const content = loader.item as Item
            content.forceActiveFocus(Qt.OtherFocusReason)
        }
    }

    component DrawerSection: Item {
        id: section

        required property int kind
        required property string toggleName
        required property string handleName

        // Children own drawer-local geometry; this grouping host never clips.
        anchors.fill: parent

        readonly property string keyName: drawerScope.keyNameFor(section.kind)
        readonly property var icon: drawerScope.iconFor(section.kind)
        readonly property App.EditorDrawerSectionState sectionState: drawerScope.presenter.section(section.kind)
        // Only available sections own chrome; shown sections also own a body.
        readonly property bool available: section.sectionState.available
        readonly property bool shown: section.available && section.sectionState.visible
        readonly property Loader pageLoader: body

        Rectangle {
            id: handle

            objectName: "drawerHandle_" + section.keyName
            x: 0
            y: section.sectionState.handleY
            width: drawerScope.width
            height: section.sectionState.handleHeight
            visible: section.shown
            color: handleInput.containsMouse || handleInput.pressed
                   ? drawerScope.drawerPalette.selectionRing : drawerScope.drawerPalette.outline
            activeFocusOnTab: true

            function adjust(direction: int): void {
                drawerScope.presenter.adjustResizeHandle(section.kind, direction)
            }

            Keys.onUpPressed: (event) => {
                handle.adjust(1)
                event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                handle.adjust(-1)
                event.accepted = true
            }
            // Cross-axis arrows are deliberate consumed no-ops on this grip, so
            // a focused control never forwards unowned song-edit arrows.
            Keys.onLeftPressed: (event) => event.accepted = true
            Keys.onRightPressed: (event) => event.accepted = true
            // Return/Enter belong to this grip; bare Space stays with transport.
            Keys.onShortcutOverride: (event) => event.accepted =
                event.key === Qt.Key_Return || event.key === Qt.Key_Enter

            Accessible.role: Accessible.Grip
            Accessible.name: section.handleName
            Accessible.description: qsTr("Use Up and Down to resize")
            Accessible.focusable: true
            Accessible.onIncreaseAction: handle.adjust(1)
            Accessible.onDecreaseAction: handle.adjust(-1)

            MouseArea {
                id: handleInput

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                cursorShape: Qt.SizeVerCursor

                // Measure growth from the press scene position, not the moving body.
                property real pressY: 0

                onPressed: (mouse) => {
                    pressY = handleInput.mapToItem(null, mouse.x, mouse.y).y
                    drawerScope.presenter.beginResize(section.kind)
                    mouse.accepted = true
                }
                onPositionChanged: (mouse) => {
                    if (pressed)
                        drawerScope.presenter.applyResize(
                            section.kind,
                            pressY - handleInput.mapToItem(null, mouse.x, mouse.y).y)
                }
                onReleased: (mouse) => {
                    drawerScope.presenter.endResize(section.kind)
                    mouse.accepted = true
                }
                onCanceled: {
                    if (drawerScope.presenter)
                        drawerScope.presenter.cancelResize()
                }
            }
        }

        Rectangle {
            id: toggle

            objectName: "drawerToggle_" + section.keyName
            x: section.sectionState.toggleX
            y: section.sectionState.toggleY
            width: section.sectionState.toggleSize
            height: section.sectionState.toggleSize
            visible: section.available
            color: section.shown ? drawerScope.drawerPalette.selectionRing
                                 : drawerScope.drawerPalette.windowBackground
            activeFocusOnTab: true

            function activate(): void {
                drawerScope.presenter.toggleSection(section.kind, drawerScope.activeFocus)
            }

            function activateFromPointer(): void {
                const hadVisibleSection = drawerScope.presenter.automationSection.visible
                                          || drawerScope.presenter.velocitySection.visible
                                          || drawerScope.presenter.voiceChangesSection.visible
                drawerScope.presenter.toggleSection(section.kind,
                                                    drawerScope.activeFocus
                                                    && (toggle.activeFocus || hadVisibleSection))
            }

            function activateFromKeyboard(event: KeyEvent): void {
                toggle.activate()
                event.accepted = true
            }

            Keys.onReturnPressed: (event) => toggle.activateFromKeyboard(event)
            Keys.onEnterPressed: (event) => toggle.activateFromKeyboard(event)
            // Same non-transport claim as the grip: only plain Return/Enter.
            Keys.onShortcutOverride: (event) => event.accepted =
                event.key === Qt.Key_Return || event.key === Qt.Key_Enter

            Accessible.role: Accessible.Button
            Accessible.name: section.toggleName
            Accessible.checkable: true
            Accessible.checked: section.shown
            Accessible.focusable: true
            Accessible.onPressAction: toggle.activate()

            AppIcon {
                anchors.fill: parent
                icon: section.icon
                color: section.shown ? drawerScope.drawerPalette.selectionText
                                     : drawerScope.drawerPalette.windowText
            }

            MouseArea {
                id: toggleInput

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: (mouse) => {
                    if (!toggle.activeFocus)
                        bar.forceActiveFocus(Qt.MouseFocusReason)
                    mouse.accepted = true
                }
                onClicked: toggle.activateFromPointer()
            }
        }

        Loader {
            id: body

            objectName: "drawerBody_" + section.keyName
            x: section.sectionState.bodyX
            y: section.sectionState.bodyY
            width: section.sectionState.bodyWidth
            height: section.sectionState.bodyHeight
            visible: section.shown
            enabled: section.shown
            active: section.available
            focus: true
            clip: true

            // Supply the shared modal layer only to pages that declare it.
            onLoaded: {
                if (body.item && body.item.hasOwnProperty("modalHost"))
                    body.item.modalHost = modalLayer
                if (body.item && body.item.hasOwnProperty("hintService"))
                    body.item.hintService = Qt.binding(() => drawerScope.hintService)
                if (body.item && body.item.hasOwnProperty("hintScopeAllowed"))
                    body.item.hintScopeAllowed = Qt.binding(() => drawerScope.hintScopeAllowed)
            }

            // The URL is resolved once per attach and never re-pointed, so a
            // reload happens only when the presenter publishes another one.
            function syncSource(): void {
                var url = String(section.sectionState.contentUrl)
                if (url.length === 0) {
                    if (String(body.source).length > 0)
                        body.setSource("")
                    return
                }
                if (String(body.source) === url)
                    return
                body.setSource(url, {"applicationSession": drawerScope.applicationSession})
            }

            Connections {
                target: section.sectionState

                function onContentUrlChanged(): void {
                    body.syncSource()
                }
            }

            Component.onCompleted: body.syncSource()
        }
    }

    // Drawn below the sections: the bar's toggles live inside its rectangle, so
    // the chrome strip must stay behind the controls it carries.
    Rectangle {
        id: bar

        objectName: "drawerBar"
        x: drawerScope.presenter.barX
        y: drawerScope.presenter.barY
        width: drawerScope.presenter.barWidth
        height: drawerScope.presenter.barHeight
        visible: drawerScope.presenter.barVisible
        color: drawerScope.drawerPalette.chromeBackground
        border.width: 1
        border.color: drawerScope.drawerPalette.outline

        MouseArea {
            objectName: "drawerBarInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: (mouse) => {
                bar.forceActiveFocus(Qt.MouseFocusReason)
                mouse.accepted = true
            }
        }
    }

    DrawerSection {
        id: velocitySection

        kind: drawerScope.velocityKind
        toggleName: qsTr("Velocity drawer")
        handleName: qsTr("Resize velocity drawer")
    }

    DrawerSection {
        id: voiceChangesSection

        kind: drawerScope.voiceChangesKind
        toggleName: qsTr("Voice-change drawer")
        handleName: qsTr("Resize voice-change drawer")
    }

    DrawerSection {
        id: automationSection

        kind: drawerScope.automationKind
        toggleName: qsTr("Automation drawer")
        handleName: qsTr("Resize automation drawer")
    }

    Item {
        id: detent
        objectName: "drawerDetent"
        x: drawerScope.presenter.detentX
        y: drawerScope.presenter.detentY
        width: drawerScope.presenter.detentSize
        height: drawerScope.presenter.detentSize
        visible: drawerScope.presenter.velocitySection.visible
                 && !!drawerScope.velocityModel
                 && drawerScope.velocityModel.detentsAvailable
        activeFocusOnTab: visible

        function activate(): void {
            if (visible && drawerScope.velocityModel)
                drawerScope.velocityModel.toggleDetents()
        }

        Keys.onReturnPressed: (event) => {
            detent.activate()
            event.accepted = true
        }
        Keys.onEnterPressed: (event) => {
            detent.activate()
            event.accepted = true
        }
        Keys.onShortcutOverride: (event) => event.accepted =
            event.key === Qt.Key_Return || event.key === Qt.Key_Enter

        Accessible.role: Accessible.CheckBox
        Accessible.name: qsTr("Velocity detents")
        Accessible.checkable: true
        Accessible.checked: !!drawerScope.velocityModel && drawerScope.velocityModel.detentsEnabled
        Accessible.focusable: true
        Accessible.onPressAction: detent.activate()

        AppIcon {
            anchors.fill: parent
            anchors.margins: drawerScope.presenter.detentIconInset
            icon: Icons.velocityLabels
            color: drawerScope.velocityModel && drawerScope.velocityModel.detentsEnabled
                   ? drawerScope.drawerPalette.selectionRing
                   : drawerScope.drawerPalette.keyboardLabel
        }

        MouseArea {
            objectName: "drawerDetentInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: detent.activate()
        }
    }

    // One unclipped modal layer sits above all drawer bodies and chrome.
    Item {
        id: modalLayer

        objectName: "drawerModalLayer"
        parent: drawerScope.Window.window ? drawerScope.Window.window.contentItem : null
        anchors.fill: parent
        visible: drawerScope.visible
        z: 100
    }

    Connections {
        target: drawerScope.presenter
        function onFocusRequestChanged(): void {
            drawerScope.executeFocusRequest()
        }
    }

}
