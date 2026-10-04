// Swift owns voice-change projection, editing and modal transactions.
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

FocusScope {
    id: page

    objectName: "voiceChangesPage"

    final property App.SongTabSession applicationSession
    required applicationSession
    property App.MouseHints hintService: null
    property bool hintScopeAllowed: true

    readonly property App.VoiceChangesPage model: page.applicationSession.songOpen
                                                ? page.applicationSession.voiceChangesPage() : null
    readonly property App.VoiceChangesPage pageModel: page.model
    readonly property App.PianoGrid gridModel: page.applicationSession.songOpen
                                              ? page.applicationSession.gridPresenter() : null
    final readonly property App.GridPalette gridPalette: page.applicationSession.timeSigHost.palette
    enabled: page.pageModel !== null

    /// The shared plot origin: the gutter the roll draws at and the container
    /// publishes as `plotOrigin`.
    readonly property real plotOrigin: page.gridModel
                                       ? (page.gridModel.trackHeaderWidth || 0)
                                         + page.gridModel.keyboardWidth : 0
    readonly property real plotWidth: Math.max(page.width - page.plotOrigin, 0)
    readonly property real baseFontPx: page.gridModel ? page.gridModel.baseFontPx
                                                      : page.applicationSession.timeSigHost.baseFontPx

    function pushBodyFacts(): void {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.width, page.height, page.plotOrigin,
                                     page.Screen.devicePixelRatio, page.baseFontPx,
                                     Application.styleHints.startDragDistance)
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
    Component.onDestruction: page.destroyModals()

    function destroyModals(): void {
        if (page.picker !== null) {
            const pickerModel = page.picker.model as App.VoiceChangesPage
            if (pickerModel)
                pickerModel.releasePickerAudition()
            page.picker.showing = false
            page.picker.destroy()
            page.picker = null
        }
        if (page.menu !== null) {
            page.menu.showing = false
            page.menu.destroy()
            page.menu = null
        }
    }

    // The session fans shared-playhead publications into the Swift page owner.

    // A modal surface or a live gesture claims Escape; everything else passes on
    // to the window, so the shared routing keeps owning Escape.
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel ? page.pageModel.handleEscape() : false

    // Modal dismissal restores focus to this page's plot.
    function focusOrigin(): void {
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
            model: page.pageModel ? page.pageModel.gutterTexts : null

            delegate: Text {
                id: gutterLabel
                required property var model
                required property string labelText
                required property font labelFont
                required property int horizontal
                required property int vertical
                required x
                required y
                required width
                required height
                required color

                text: gutterLabel.labelText
                font: gutterLabel.labelFont
                horizontalAlignment: gutterLabel.horizontal
                verticalAlignment: gutterLabel.vertical
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

        DisplayList {
            objectName: "voiceGridLines"
            anchors.fill: parent
            clip: true
            source: page.pageModel
            list: 0
            revision: page.pageModel ? page.pageModel.displayRevision : 0
        }

        // One delegate per marker: the vertical rule at its projected position
        // and the label box Swift laid out (already elided and stair-placed).
        Item {
            x: -(page.gridModel ? page.gridModel.cameraScrollX : 0)
            width: plot.width
            height: plot.height
        Repeater {
            model: page.pageModel ? page.pageModel.markers : null

            delegate: Item {
                id: marker

                required property var model
                required property string primitiveName
                required property real lineTop
                required property real lineBottom
                required property real lineWidth
                required property color lineColor
                required property bool selected
                required property bool hovered
                required property bool offscreen
                required property string label
                required property real labelX
                required property real labelY
                required property real labelWidth
                required property real labelHeight
                readonly property real markerX: marker.model.x

                x: 0
                y: 0
                width: plot.width
                height: plot.height

                Rectangle {
                    objectName: marker.primitiveName + "Line"
                    x: marker.markerX
                    y: marker.lineTop
                    width: marker.lineWidth
                    height: Math.max(0, marker.lineBottom - marker.lineTop)
                    color: marker.lineColor
                }

                Rectangle {
                    objectName: marker.primitiveName + "Selection"
                    visible: marker.selected || marker.hovered
                    x: marker.markerX - marker.lineWidth
                    y: marker.lineTop
                    width: 3 * marker.lineWidth
                    height: Math.max(0, marker.lineBottom - marker.lineTop)
                    color: "transparent"
                    border.width: marker.lineWidth
                    border.color: page.gridPalette.selectionRing
                }

                Text {
                    objectName: marker.primitiveName + "Label"
                    x: marker.labelX
                    y: marker.labelY
                    width: marker.labelWidth
                    height: marker.labelHeight
                    visible: !marker.offscreen
                    text: marker.label
                    color: page.gridPalette.primaryText
                    font: page.model ? page.model.captionFont : page.applicationSession.timeSigHost.typographyFonts.caption
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    maximumLineCount: 1
                    clip: true
                }
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
            x: page.pageModel ? page.pageModel.hoverLabelX : 0
            y: page.pageModel ? page.pageModel.hoverLabelY : 0
            width: page.pageModel ? page.pageModel.hoverLabelWidth : 0
            height: page.pageModel ? page.pageModel.hoverLabelHeight : 0
            text: (page.pageModel ? page.pageModel.hoverText : "")
            color: page.gridPalette.primaryText
            font: page.model ? page.model.noteNameFont : page.applicationSession.timeSigHost.typographyFonts.noteName
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
            x: page.pageModel ? page.pageModel.readoutX : 0
            y: page.pageModel ? page.pageModel.readoutY : 0
            width: page.pageModel ? page.pageModel.readoutWidth : 0
            height: page.pageModel ? page.pageModel.readoutHeight : 0
            text: (page.pageModel ? page.pageModel.readoutText : "")
            color: page.gridPalette.primaryText
            font: page.model ? page.model.captionFont : page.applicationSession.timeSigHost.typographyFonts.caption
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
            font: page.model ? page.model.captionFont : page.applicationSession.timeSigHost.typographyFonts.caption
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

            onPressed: (mouse) => {
                plotMoves.flush()
                mouse.accepted =
                    page.pageModel.pointerPress(mouse.x, mouse.y, page.plotSurface,
                                                mouse.button, mouse.modifiers)
            }
            onDoubleClicked: (mouse) => {
                plotMoves.flush()
                if (mouse.button === Qt.LeftButton)
                    page.pageModel.pointerDoubleClick(mouse.x, mouse.y)
                mouse.accepted = true
            }
            onPositionChanged: (mouse) => plotMoves.enqueue(
                mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
            onReleased: (mouse) => {
                plotMoves.flush()
                plotHint.settleRelease(plotInput.mapToItem(null, mouse.x, mouse.y))
                mouse.accepted = page.pageModel.pointerRelease(mouse.x, mouse.y, mouse.button)
            }
            onCanceled: {
                plotMoves.flush()
                plotHint.settleRelease(plotHint.point.scenePosition)
                if (page.pageModel)
                    page.pageModel.cancelSectionInteraction()
            }
            onExited: {
                plotMoves.flush()
                if (page.pageModel)
                    page.pageModel.pointerLeave()
            }
            MoveCoalescer {
                id: plotMoves
                function dispatchMove(x: real, y: real, buttons: int, modifiers: int): bool {
                    return page.pageModel ? page.pageModel.pointerMove(x, y, buttons, modifiers) : false
                }
                dispatch: plotMoves.dispatchMove
            }
        }

        HoverHint {
            id: plotHint

            source: plot
            hintService: page.hintService
            scopeAllowed: page.hintScopeAllowed
            gestureOwning: plotInput.pressed
            profile: page.pageModel ? page.pageModel.hoverHintProfile : HintProfiles.HorizontalScroll
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

    // Modal flags follow their notifying Swift owner.
    Connections {
        target: page.pageModel

        function onPickerOpenChanged(): void { page.syncModals() }
        function onMenuOpenChanged(): void { page.syncModals() }
    }

    function syncModals(): void {
        if (page.model === null) {
            page.destroyModals()
            return
        }
        if (page.menu !== null) {
            page.menu.model = page.model
            page.menu.showing = page.pageModel ? page.pageModel.menuOpen : false
        }
        if (page.picker !== null) {
            const pickerModel = page.picker.model as App.VoiceChangesPage
            if (pickerModel && pickerModel !== page.model)
                pickerModel.releasePickerAudition()
            page.picker.model = page.model
            page.picker.showing = page.pageModel ? page.pageModel.pickerOpen : false
        }
    }

    property Item modalHost: null
    property VoiceChangeMenu menu: null
    property VoicePickerPrompt picker: null

    Component {
        id: menuComponent

        VoiceChangeMenu {
            onClosed: page.focusOrigin()
        }
    }

    Component {
        id: pickerComponent

        VoicePickerPrompt {
            hintService: page.hintService
            onClosed: page.focusOrigin()
        }
    }

    // Modals are retained once and reparented onto the container's unclipped layer.
    function createModals(): void {
        if (page.model === null) {
            page.destroyModals()
            return
        }
        const host = page.modalHost !== null ? page.modalHost : page
        if (page.menu === null) {
            page.menu = menuComponent.createObject(host, {"model": page.model,
                                                          "pageItem": page}) as VoiceChangeMenu
        } else if (page.menu.parent !== host) {
            // The container supplies its modal layer after the page completes.
            page.menu.parent = host
        }
        if (page.picker === null) {
            page.picker = pickerComponent.createObject(host, {"model": page.model,
                                                              "pageItem": page}) as VoicePickerPrompt
        } else if (page.picker.parent !== host) {
            page.picker.parent = host
        }
        page.syncModals()
    }

    onModalHostChanged: page.createModals()
}
