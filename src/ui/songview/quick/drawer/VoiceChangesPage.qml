// The Voice Changes drawer page: the gutter title/summary, the plot's grid, the
// held program spans, the change markers with their labels, the hover label,
// the current-context readout, and the page's two modal surfaces.
//
// Swift owns every value (VoiceChangesPage.swift): the shared camera
// projection, the bank-slot labels, the context resolution, the marker layout
// with its elision and stair placement, the frozen drag, and the picker/menu
// transactions. This file renders published primitives and delivers real
// pointer, wheel, keyboard and accessibility input to that owner. It holds no
// tick, no label, no camera and no clock, and it reads no document: the plot
// origin and base font arrive through `configureBody` from the same published
// facts the roll and the container use.
//
// The two input surfaces are the legacy band's: `voiceGutter` never edits, and
// `voicePlot` owns editing in the plot-local coordinate space the shared camera
// projects into. Bare Space is never claimed here, so the window transport
// keeps it; only the picker's search field consumes text keys, which is the
// explicit text-entry surface the modal keeps.
//
// Modal surfaces: the context menu and the picker compose into the container's
// one modal layer (`EditorDrawer.qml`'s `drawerModalLayer`), which the container
// hands this page as its optional `modalHost` after loading, and into the page
// itself when a composition mounts the page without one. The layer is unclipped
// and above every section's bodies and chrome, so a modal is never cut off by
// the body it belongs to; each modal states its anchors in this page's own
// coordinate space and maps them into whatever surface hosts it. No legacy
// native popup infrastructure is imported.
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

FocusScope {
    id: page

    objectName: "voiceChangesPage"

    required property QtObject applicationSession
    property var hintService: null
    property bool hintScopeAllowed: true

    /// The page's Swift owner for the current document, and the neutral empty
    /// model while there is none: `voiceChangesPage()` fails once no document is
    /// presented, and the host removes this scene before the session releases
    /// the page. A guarded binding is what a teardown re-evaluation resolves.
    readonly property var model: page.applicationSession
                                 && page.applicationSession.songOpen
                                 ? page.applicationSession.voiceChangesPage()
                                 : null
    readonly property var pageModel: page.model !== null && page.model !== undefined
                                     ? page.model : emptyModel

    readonly property var gridModel: page.applicationSession
                                     && page.applicationSession.songOpen
                                     ? page.applicationSession.gridPresenter()
                                     : null
    /// The session's grid presenter while a document presentation exists, and the
    /// palette this page draws with. The page can be re-evaluated during scene
    /// teardown, after the session released the grid, so every palette read
    /// below goes through this guarded expression; the fallback draws nothing.
    readonly property var gridPalette: page.gridModel ? page.gridModel.palette : fallbackPalette

    QtObject {
        id: fallbackPalette

        /// Neutral colors for the window between scene removal and the session's
        /// release; nothing drawn then reaches a frame. Covers every role this
        /// page reads plus the roles VoicePickerPrompt reads through promptPalette.
        readonly property color chromeBackground: "transparent"
        readonly property color rollBackground: "transparent"
        readonly property color outline: "transparent"
        readonly property color primaryText: "transparent"
        readonly property color selectionRing: "transparent"
        readonly property color selectionEdge: "transparent"
        readonly property color windowBackground: "transparent"
        readonly property color windowText: "transparent"
        readonly property color focusOutline: "transparent"
        readonly property color buttonBackground: "transparent"
        readonly property color buttonText: "transparent"
        readonly property color buttonPressedBackground: "transparent"
        readonly property color buttonPressedText: "transparent"
        readonly property color disabledText: "transparent"
        readonly property color placeholderText: "transparent"
    }
    QtObject {
        id: emptyModel

        readonly property var markers: []
        readonly property var heldSpans: []
        readonly property var gridLines: []
        readonly property var gutterTexts: []
        readonly property var pickerRows: []
        readonly property var menuRows: []
        readonly property bool trackAvailable: false
        readonly property string plotMessage: ""
        readonly property string gutterTitle: "Voice"
        readonly property bool readoutVisible: false
        readonly property string readoutText: ""
        readonly property int readoutAlignment: 2
        readonly property var readoutRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property bool hoverVisible: false
        readonly property string hoverText: ""
        readonly property var hoverLabelRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property int hoverHintProfile: HintProfiles.HorizontalScroll
        readonly property var captionFont: ({})
        readonly property var titleFont: ({})
        readonly property double baseFontPx: 13
        readonly property int cursorKind: 0
        readonly property bool previewVisible: false
        readonly property double previewX: 0
        readonly property bool menuOpen: false
        readonly property double menuX: 0
        readonly property double menuY: 0
        readonly property bool pickerOpen: false
        readonly property string pickerTitle: ""
        readonly property string pickerFilter: ""
        readonly property int pickerIndex: -1
        readonly property bool pickerHasMatch: false
        readonly property string pickerEmptyText: "No matching voices"
        readonly property bool auditionAvailable: false
        readonly property string auditionDiagnostic: ""

        function configureBody(width, height, gutter, devicePixelRatio, baseFontPx,
                               dragDistance) {}
        function pointerPress(x, y, surface, button, modifiers) { return false }
        function pointerMove(x, y, buttons) { return false }
        function pointerRelease(x, y, button) { return false }
        function pointerLeave() {}
        function pointerDoubleClick(x, y) { return false }
        function handleEscape() { return false }
        function setPickerFilter(text) {}
        function selectPickerRow(index) {}
        function movePickerSelection(delta) {}
        function acceptPicker() { return false }
        function cancelPicker() {}
        function activateMenuAction(actionId) { return false }
        function dismissVoiceMenu() {}
        function dismissModal() {}
        function cancelSectionInteraction() {}
    }

    /// The shared plot origin: the gutter the roll draws at and the container
    /// publishes as `plotOrigin`.
    readonly property real plotOrigin: page.gridModel
                                       ? (page.gridModel.trackHeaderWidth || 0)
                                         + page.gridModel.keyboardWidth : 0
    readonly property real plotWidth: Math.max(page.width - page.plotOrigin, 0)
    readonly property real seedBaseFontPx: 13
    readonly property real baseFontPx: page.gridModel ? page.gridModel.baseFontPx
                                                      : page.seedBaseFontPx
    /// `layout::fontPx` in the page's own base font, for this file's chrome.
    function fontPx(multiplier) {
        return Math.max(1, Math.round(page.baseFontPx * multiplier))
    }

    function pushBodyFacts() {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.width, page.height, page.plotOrigin,
                                     page.Screen.devicePixelRatio, page.baseFontPx,
                                     Qt.styleHints.startDragDistance)
    }

    onModelChanged: {
        page.pushBodyFacts()
        page.createModals()
    }
    onWidthChanged: page.pushBodyFacts()
    onHeightChanged: page.pushBodyFacts()
    onPlotOriginChanged: page.pushBodyFacts()
    onBaseFontPxChanged: page.pushBodyFacts()
    Component.onCompleted: {
        page.pushBodyFacts()
        page.createModals()
    }
    Component.onDestruction: {
        if (page.picker !== null) {
            if (page.picker.model)
                page.picker.model.releasePickerAudition()
            page.picker.destroy()
        }
        if (page.menu !== null)
            page.menu.destroy()
    }

    // The shared clock reaches this page in Swift: `ApplicationSession` fans the
    // presenter's distinct presentations into the page owner, so no QML surface
    // reads the presenter or calls a page mutator through a bridge wrapper.

    // A modal surface or a live gesture claims Escape; everything else passes on
    // to the window, so the shared routing keeps owning Escape.
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel.handleEscape()

    // Where focus returns after a modal closes: this page's plot, which stays in
    // the page even when the modal surfaces are composed into the container's
    // modal layer.
    function focusOrigin() {
        plot.forceActiveFocus(Qt.OtherFocusReason)
    }

    readonly property int gutterSurface: 0
    readonly property int plotSurface: 1

    // ---- gutter -------------------------------------------------------------

    Item {
        id: gutter

        objectName: "voiceGutter"
        x: 0
        y: 0
        width: page.plotOrigin
        height: page.height
        clip: true

        Rectangle {
            anchors.fill: parent
            color: page.gridPalette.chromeBackground
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: page.gridPalette.outline
        }

        Repeater {
            model: (page.pageModel ? page.pageModel.gutterTexts : [])

            delegate: Text {
                required property var model

                x: model.labelRect.x
                y: model.labelRect.y
                width: model.labelRect.width
                height: model.labelRect.height
                text: model.labelText
                color: model.labelColor
                font: Qt.font(model.labelFont)
                horizontalAlignment: model.labelHorizontalAlignment
                verticalAlignment: model.labelVerticalAlignment
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideRight
                maximumLineCount: 1
                clip: true
            }
        }

        Accessible.role: Accessible.Column
        Accessible.name: qsTr("Voice changes gutter")
        Accessible.focusable: false
    }

    // ---- plot ---------------------------------------------------------------

    Item {
        id: plot

        objectName: "voicePlot"
        x: page.plotOrigin
        y: 0
        width: page.plotWidth
        height: page.height
        clip: true
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            color: page.gridPalette.rollBackground
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: page.gridPalette.outline
        }

        TimelineQuickItem {
            objectName: "voiceGridLines"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.gridLines : [])
        }

        TimelineQuickItem {
            objectName: "voiceHeldSpans"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.heldSpans : [])
        }

        // One delegate per marker: the vertical rule at its projected position
        // and the label box Swift laid out (already elided and stair-placed).
        Repeater {
            model: (page.pageModel ? page.pageModel.markers : [])

            delegate: Item {
                id: marker

                required property var model

                x: 0
                y: 0
                width: plot.width
                height: plot.height

                Rectangle {
                    objectName: marker.model.primitiveName + "Line"
                    x: marker.model.x
                    y: marker.model.lineTop
                    width: marker.model.lineWidth
                    height: Math.max(0, marker.model.lineBottom - marker.model.lineTop)
                    color: marker.model.lineColor
                }

                Rectangle {
                    objectName: marker.model.primitiveName + "Selection"
                    visible: marker.model.selected || marker.model.hovered
                    x: marker.model.x - marker.model.lineWidth
                    y: marker.model.lineTop
                    width: 3 * marker.model.lineWidth
                    height: Math.max(0, marker.model.lineBottom - marker.model.lineTop)
                    color: "transparent"
                    border.width: marker.model.lineWidth
                    border.color: page.gridPalette.selectionRing
                }

                Text {
                    objectName: marker.model.primitiveName + "Label"

                    x: marker.model.labelRect.x
                    y: marker.model.labelRect.y
                    width: marker.model.labelRect.width
                    height: marker.model.labelRect.height
                    visible: !marker.model.offscreen
                    text: marker.model.label
                    color: page.gridPalette.primaryText
                    font: Qt.font(page.pageModel ? page.pageModel.captionFont : {})
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    maximumLineCount: 1
                    clip: true
                }
            }
        }

        // The frozen drag's draft position: the marker itself is projected at
        // the draft tick, so this only marks where the pointer is working.
        Rectangle {
            objectName: "voiceDragPreview"

            visible: (page.pageModel ? page.pageModel.previewVisible : false)
            x: (page.pageModel ? page.pageModel.previewX : 0) - width / 2
            y: 0
            width: 1
            height: plot.height
            color: page.gridPalette.selectionEdge
        }

        // The background hover's slot label, and the marker hover's own tick.
        Text {
            objectName: "voiceHoverLabel"

            visible: (page.pageModel ? page.pageModel.hoverVisible : false)
            x: (page.pageModel ? page.pageModel.hoverLabelRect.x : 0)
            y: (page.pageModel ? page.pageModel.hoverLabelRect.y : 0)
            width: (page.pageModel ? page.pageModel.hoverLabelRect.width : 0)
            height: (page.pageModel ? page.pageModel.hoverLabelRect.height : 0)
            text: (page.pageModel ? page.pageModel.hoverText : "")
            color: page.gridPalette.primaryText
            font: Qt.font(page.pageModel ? page.pageModel.captionFont : {})
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            clip: true
        }

        // The current-context readout.
        Text {
            objectName: "voiceReadout"

            visible: (page.pageModel ? page.pageModel.readoutVisible : false)
            x: (page.pageModel ? page.pageModel.readoutRect.x : 0)
            y: (page.pageModel ? page.pageModel.readoutRect.y : 0)
            width: (page.pageModel ? page.pageModel.readoutRect.width : 0)
            height: (page.pageModel ? page.pageModel.readoutRect.height : 0)
            text: (page.pageModel ? page.pageModel.readoutText : "")
            color: page.gridPalette.primaryText
            font: Qt.font(page.pageModel ? page.pageModel.captionFont : {})
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            horizontalAlignment: page.pageModel ? page.pageModel.readoutAlignment
                                                : Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            clip: true
        }

        Text {
            objectName: "voicePlotMessage"

            visible: !(page.pageModel ? page.pageModel.trackAvailable : false)
            anchors.centerIn: parent
            text: (page.pageModel ? page.pageModel.plotMessage : "")
            color: page.gridPalette.primaryText
            font: Qt.font(page.pageModel ? page.pageModel.captionFont : {})
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: plotInput

            objectName: "voicePlotInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: {
                switch (page.pageModel ? page.pageModel.cursorKind : 0) {
                case 3: return Qt.SizeHorCursor
                default: return Qt.ArrowCursor
                }
            }

            onPressed: (mouse) => mouse.accepted =
                page.pageModel.pointerPress(mouse.x, mouse.y, page.plotSurface, mouse.button,
                                            mouse.modifiers)
            onDoubleClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)
                    page.pageModel.pointerDoubleClick(mouse.x, mouse.y)
                mouse.accepted = true
            }
            onPositionChanged: (mouse) => page.pageModel.pointerMove(mouse.x, mouse.y,
                                                                     mouse.buttons,
                                                                     mouse.modifiers)
            onReleased: (mouse) => {
                plotHint.settleRelease(plotInput.mapToItem(null, mouse.x, mouse.y))
                mouse.accepted = page.pageModel.pointerRelease(mouse.x, mouse.y, mouse.button)
            }
            onCanceled: {
                plotHint.settleRelease(plotHint.point.scenePosition)
                page.pageModel.cancelSectionInteraction()
            }
            onExited: page.pageModel.pointerLeave()
        }

        HoverHint {
            id: plotHint

            source: plot
            hintService: page.hintService
            scopeAllowed: page.hintScopeAllowed
            gestureOwning: plotInput.pressed
            profile: page.pageModel.hoverHintProfile
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: (event) => {
                // The shared navigation owner: the roll's own wheel entry, with
                // this plot's anchor, so zoom stays anchored where the pointer is.
                if (!page.gridModel)
                    return
                page.gridModel.handleWheel(
                    event.angleDelta.x, event.angleDelta.y,
                    event.pixelDelta.x, event.pixelDelta.y,
                    event.modifiers, event.phase, false, event.x, event.y)
                event.accepted = true
            }
        }

        Accessible.role: Accessible.Canvas
        Accessible.name: qsTr("Voice changes")
        Accessible.description: (page.pageModel ? page.pageModel.readoutText : "")
        Accessible.focusable: true
    }

    // ---- modal surfaces -----------------------------------------------------

    // The page owns modality for its two modal surfaces; each one renders the
    // flag it is pushed and delivers the input that drives the page. The push
    // happens on the page's own change signals instead of a binding inside the
    // modal's scope, which would have to read through the `var`-typed model.
    Connections {
        target: page.pageModel

        function onPickerOpenChanged() { page.syncModals() }
        function onMenuOpenChanged() { page.syncModals() }
    }

    function syncModals() {
        if (page.menu !== null) {
            page.menu.model = page.model
            page.menu.showing = page.pageModel ? page.pageModel.menuOpen : false
        }
        if (page.picker !== null) {
            if (page.picker.model && page.picker.model !== page.model)
                page.picker.model.releasePickerAudition()
            page.picker.model = page.model
            page.picker.showing = page.pageModel ? page.pageModel.pickerOpen : false
        }
    }

    /// The container's one unclipped modal layer, when the container hosts this
    /// page (a composition that mounts the page elsewhere keeps the modals inside
    /// the page). Filled in `createModals`.
    property var modalHost: null
    property var menu: null
    property var picker: null

    Component {
        id: menuComponent

        VoiceChangeMenu {
            onClosed: page.focusOrigin()
        }
    }

    Component {
        id: pickerComponent

        VoicePickerPrompt {
            promptPalette: page.gridPalette
            hintService: page.hintService
            onClosed: page.focusOrigin()
        }
    }

    /// Composes the two modal surfaces into the container's one modal layer, or
    /// into the page when no layer was handed over. They are created once and only
    /// re-pointed at the current document owner, so a case's modal state is never
    /// a fresh object per interaction. Each modal receives this page as its
    /// coordinate origin: the page publishes its anchors in its own space, and a
    /// modal hosted in the container's layer maps them there.
    function createModals() {
        var host = page.modalHost !== null && page.modalHost !== undefined ? page.modalHost : page
        if (page.menu === null) {
            page.menu = menuComponent.createObject(host, {"model": page.model,
                                                          "pageItem": page})
        } else if (page.menu.parent !== host) {
            // The container hands its modal layer over after the page completes,
            // so a modal created in that window moves onto the layer it belongs
            // to instead of being rebuilt (its anchors re-resolve on the move).
            page.menu.parent = host
        }
        if (page.picker === null) {
            page.picker = pickerComponent.createObject(host, {"model": page.model,
                                                              "pageItem": page})
        } else if (page.picker.parent !== host) {
            page.picker.parent = host
        }
        page.syncModals()
    }

    onModalHostChanged: page.createModals()
}
