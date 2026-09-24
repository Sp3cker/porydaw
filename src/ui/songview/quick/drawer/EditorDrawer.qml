// The editor drawer container: chrome, section bodies and preference store.
//
// Swift owns every layout decision (EditorDrawer.swift: metrics, stacking,
// visibility, the resize including the voice-change spill, the focus requests
// and the cancel sets). This file renders published values only: it invents no
// geometry, clamp, default or focus tier, and it never reaches into a page --
// the item at each kind's contentUrl owns its own focus, input and rendering
// behind a FocusScope that fills its loader.
//
// Lifetime: one body Loader per kind, created from the URL the presenter
// resolved at attach and left instantiated for as long as the kind stays
// attached, so hiding a section never destroys its page. A released page
// arrives here as an empty contentUrl and the loader drops its item; the drawer
// keeps no reference to a page it no longer hosts, and detaching writes no key.
//
// Modal containment: one container-wide layer (`drawerModalLayer`) above every
// section hosts the modal surfaces of pages that opt in through their optional
// `modalHost` property, so a page's picker or menu is never clipped by the body
// loader that hosts its content. The layer draws nothing and takes no input of
// its own.
//
// Input: a focused toggle activates with Return/Enter, a focused grip resizes
// with Up/Down and consumes Left/Right. Bare Space is never claimed, so the
// window's transport shortcut outranks incidental focus here. Every visibility
// call passes this scope's live activeFocus as the focus observation for that
// call; no focus value is remembered.
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Porydaw.Ui

FocusScope {
    id: drawerScope

    objectName: "editorDrawer"

    required property QtObject applicationSession
    required property QtObject presenter
    // Named `drawerPalette`, never `palette`: QQuickItem already declares a
    // virtual `palette` member of an unrelated type, and shadowing it makes the
    // engine warn on every instantiation and mis-handle the base property.
    required property QtObject drawerPalette
    // Empty selects the application's default QSettings store; every lane case
    // points this at a private file under its own scratch directory.
    property url preferenceLocation: ""
    property var hintService: null
    readonly property bool hintScopeAllowed: {
        for (let child of modalLayer.children) {
            if (child.visible)
                return false
        }
        return true
    }
    readonly property var velocityModel: applicationSession.songOpen
                                        ? applicationSession.velocityPage() : null

    // DrawerSectionKind raw values. Only the container maps a kind to its
    // stored key names, page name and icon resource; every layout fact stays
    // in the presenter.
    readonly property int automationKind: 0
    readonly property int velocityKind: 1
    readonly property int voiceChangesKind: 2

    // The composition places the container and gives it the surface width; the
    // height is the presenter's own aggregate, zero while no page is attached.
    height: presenter.height
    clip: true

    // Historical store: category "editorDrawer", one category the two
    // preference signals write and one read performed at mount.
    Settings {
        id: drawerSettings

        category: "editorDrawer"
        location: drawerScope.preferenceLocation
    }

    function keyNameFor(kind) {
        switch (kind) {
        case drawerScope.automationKind: return "automation"
        case drawerScope.velocityKind: return "velocity"
        case drawerScope.voiceChangesKind: return "voiceChanges"
        }
        return ""
    }

    function pageNameFor(kind) {
        switch (kind) {
        case drawerScope.automationKind: return "automations"
        case drawerScope.velocityKind: return "velocity"
        case drawerScope.voiceChangesKind: return "voiceChanges"
        }
        return ""
    }

    function iconResourceFor(kind) {
        switch (kind) {
        case drawerScope.automationKind: return "qrc:/icons/automation.svg"
        case drawerScope.velocityKind: return "qrc:/icons/velocity.svg"
        case drawerScope.voiceChangesKind: return "qrc:/icons/flat-music.svg"
        }
        return ""
    }

    // Read once, at mount: children complete before this item, so the Settings
    // object has already loaded its values. A key is passed as its raw value,
    // an absent visibility or page as -1 and an absent height as 0; the
    // presenter applies state, records no preference change and writes nothing
    // back. Restoring is the only place this file reads the store.
    function storedVisibility(key) {
        var value = drawerSettings.value(key)
        if (value === undefined || value === null)
            return -1
        if (value === true || value === 1 || value === "1" || value === "true")
            return 1
        if (value === false || value === 0 || value === "0" || value === "false")
            return 0
        return -1
    }

    function storedHeight(key) {
        var value = drawerSettings.value(key)
        if (value === undefined || value === null)
            return 0
        var height = Number(value)
        return isNaN(height) ? 0 : Math.round(height)
    }

    function storedPage() {
        var value = drawerSettings.value("activePage")
        if (value === undefined || value === null)
            return -1
        switch (String(value)) {
        case "velocity": return drawerScope.velocityKind
        case "voiceChanges": return drawerScope.voiceChangesKind
        case "automations": return drawerScope.automationKind
        }
        return -1
    }

    function restoreStoredPreferences() {
        drawerScope.presenter.restoreStoredPreferences(drawerScope.storedVisibility("velocityVisible"),
                                                       drawerScope.storedHeight("velocityHeight"),
                                                       drawerScope.storedVisibility("automationVisible"),
                                                       drawerScope.storedHeight("automationHeight"),
                                                       drawerScope.storedVisibility("voiceChangesVisible"),
                                                       drawerScope.storedHeight("voiceChangesHeight"),
                                                       drawerScope.storedPage())
    }

    function writeSectionPreference(kind, visible, height) {
        var key = drawerScope.keyNameFor(kind)
        if (key.length === 0)
            return
        drawerSettings.setValue(key + "Visible", visible)
        drawerSettings.setValue(key + "Height", height)
        drawerSettings.sync()
    }

    function writeActivePagePreference(page) {
        var name = drawerScope.pageNameFor(page)
        if (name.length === 0)
            return
        drawerSettings.setValue("activePage", name)
        drawerSettings.sync()
    }

    // A monotonic request names the kind whose loaded page takes focus, or -1
    // for the roll. A request whose loader has no item yet is skipped rather
    // than retried; the next transition publishes a new request.
    function sectionLoader(kind) {
        switch (kind) {
        case drawerScope.automationKind: return automationSection.pageLoader
        case drawerScope.velocityKind: return velocitySection.pageLoader
        case drawerScope.voiceChangesKind: return voiceChangesSection.pageLoader
        }
        return null
    }

    // The roll input is a sibling with no shared id, so its stable objectName
    // is the handle the presenter's -1 target resolves through. The search
    // starts at the top of this item tree so it also crosses the composition
    // that places this container.
    function findItemByName(item, name) {
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

    function executeFocusRequest() {
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
        if (loader && loader.item)
            loader.item.forceActiveFocus(Qt.OtherFocusReason)
    }

    component DrawerSection: Item {
        id: section

        required property int kind
        required property string toggleName
        required property string handleName

        // The host covers the drawer: its children carry the published
        // drawer-local rectangles, so the host itself owns no geometry and
        // never clips; it exists to group one kind's chrome and body.
        anchors.fill: parent

        readonly property string keyName: drawerScope.keyNameFor(section.kind)
        readonly property string iconResource: drawerScope.iconResourceFor(section.kind)
        readonly property var sectionState: drawerScope.presenter.section(section.kind)
        // Available means a page is attached with a resolved URL: that kind owns
        // a toggle, however hidden it is, and only an available visible kind
        // owns a handle or a body. The published `visible` is already effective
        // (requested and available), and the conjunction here keeps an
        // unavailable kind control-free even if it still publishes intent.
        readonly property bool available: section.sectionState.available
        readonly property bool shown: section.sectionState.available && section.sectionState.visible
        readonly property var pageLoader: body

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

            function adjust(direction) {
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
            // Claim only the plain Return/Enter activation keys before
            // window-level shortcuts can take them from this focused control.
            // A grip has no Return action, and bare Space stays unclaimed so
            // the transport play/pause shortcut outranks incidental focus.
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

                // A drag toward the top grows the body, so the delta is
                // measured against the scene position the press started at,
                // never against a rect that moves with the drag.
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
                onCanceled: drawerScope.presenter.cancelResize()
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
            color: section.sectionState.visible ? drawerScope.drawerPalette.selectionRing
                                                 : drawerScope.drawerPalette.windowBackground
            activeFocusOnTab: true

            function activate() {
                drawerScope.presenter.toggleSection(section.kind, drawerScope.activeFocus)
            }

            function activateFromKeyboard(event) {
                activate()
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
            Accessible.checked: section.sectionState.visible
            Accessible.focusable: true
            Accessible.onPressAction: toggle.activate()

            // The kind's own SVG, tinted in QML: the image is loaded once at the
            // button size and drawn from that URL (Canvas paints only images
            // loaded through loadImage), then the same rect is refilled with
            // source-in. That is the retired chrome's
            // QPainter::CompositionMode_SourceIn result with no image provider,
            // no effect item and no second icon set.
            Canvas {
                id: icon

                anchors.fill: parent

                onImageLoaded: icon.requestPaint()
                onWidthChanged: icon.sync()
                onHeightChanged: icon.sync()
                onPaint: icon.paintIcon()
                Component.onCompleted: icon.sync()

                // The drawn rect is this canvas's own size, so a resize always
                // repaints. loadImage only starts a load, and a cached URL
                // emits nothing, so the first paint must never wait on it.
                function sync() {
                    if (width <= 0 || height <= 0)
                        return
                    if (isImageLoaded(section.iconResource)
                            || isImageLoading(section.iconResource)) {
                        requestPaint()
                        return
                    }
                    loadImage(section.iconResource, Qt.size(width, height))
                }

                function paintIcon() {
                    if (width <= 0 || height <= 0)
                        return
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "source-over"
                    ctx.drawImage(section.iconResource, 0, 0, width, height)
                    ctx.globalCompositeOperation = "source-in"
                    ctx.fillStyle = drawerScope.drawerPalette.keyboardLabel
                    ctx.fillRect(0, 0, width, height)
                }
            }

            MouseArea {
                id: toggleInput

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: toggle.activate()
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

            // The container's one modal layer reaches the page after it loads,
            // and only when the page declares the property: a page with no modal
            // surface simply has none to fill.
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
            function syncSource() {
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

                function onContentUrlChanged() {
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

        function activate() {
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

        Canvas {
            id: detentIcon
            anchors.fill: parent
            anchors.margins: drawerScope.presenter.detentIconInset
            readonly property color tint: drawerScope.velocityModel
                                          && drawerScope.velocityModel.detentsEnabled
                                          ? drawerScope.drawerPalette.selectionRing
                                          : drawerScope.drawerPalette.keyboardLabel
            onTintChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onImageLoaded: requestPaint()
            Component.onCompleted: loadImage("qrc:/icons/velocity_labels.svg")
            onPaint: {
                if (width <= 0 || height <= 0
                        || !isImageLoaded("qrc:/icons/velocity_labels.svg"))
                    return
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.globalCompositeOperation = "source-over"
                ctx.drawImage("qrc:/icons/velocity_labels.svg", 0, 0, width, height)
                ctx.globalCompositeOperation = "source-in"
                ctx.fillStyle = tint
                ctx.fillRect(0, 0, width, height)
            }
        }

        MouseArea {
            objectName: "drawerDetentInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: detent.activate()
        }
    }

    // Generic modal containment, one layer for the whole container: a page's
    // modal surface (a picker, a menu) must not be clipped by the body loader
    // that hosts the page's content, and it must sit above every section's
    // bodies and chrome, whichever section it belongs to. The layer is declared
    // after all of them, spans the container, takes no input and draws nothing
    // of its own; a page that composes no modal never populates it. Opt-in pages
    // receive it as their optional `modalHost` property right after loading.
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

        // Swift decides what changed; QML performs the historical write for the
        // kind the signal names, then syncs so the bytes are on disk. No other
        // path in this file writes the store.
        function onDrawerSectionPreferenceChanged(kind, visible, height) {
            drawerScope.writeSectionPreference(kind, visible, height)
        }

        function onDrawerActivePagePreferenceChanged(page) {
            drawerScope.writeActivePagePreference(page)
        }

        function onFocusRequestChanged() {
            drawerScope.executeFocusRequest()
        }
    }

    Component.onCompleted: drawerScope.restoreStoredPreferences()
}
