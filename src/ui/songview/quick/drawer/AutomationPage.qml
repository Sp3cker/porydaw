// The Automation drawer page: the parameter selector in the shared gutter, the
// value axis, the step/ramp curve with its ghost pins, the nodes and the origin
// phantom, the explicit time selection, the range band, the live gesture
// transient, the hover/preview value labels, the context readout, the tap-tempo
// panel and the page's two modal surfaces.
//
// Swift owns every value (AutomationPage.swift): the shared camera projection,
// the parameter catalog and row facts, the explicit selection, the frozen
// gesture with its press-time camera, the prompts, the menu rows, the accepted
// clipboard and the tap-tempo session. This file renders published primitives
// and delivers real pointer, wheel, keyboard and accessibility input to that
// owner; it holds no tick, no value, no camera, no clock and no document model.
//
// Surfaces: the selector column owns the gutter (its two-column grid is the
// production `AutomationTabs.qml` layout, built from the published tab records),
// and the plot beside it owns editing in the plot-local coordinates the shared
// camera projects into. Bare Space is never claimed here, so the window
// transport keeps it; only the value prompt's text field consumes text keys.
//
// Cursor policy: `cursorKind` publishes the production shape set. Production's
// pencil tool uses a bundled pixmap cursor; this product registers no cursor
// image resource and QML's `cursorShape` carries no pixmap, so the pencil tool
// draws the standard cross cursor instead. That substitution is named here
// rather than hidden.
//
// Modal surfaces: `AutomationPrompt` and `AutomationMenu` compose into the
// container's one modal layer (`EditorDrawer.qml`'s `drawerModalLayer`), which
// the container hands this page as its optional `modalHost` after loading, and
// into the page itself when a composition mounts the page without one. The
// tap-tempo panel is the page's own local surface: production keeps the plot
// live while a session accumulates, so it takes only its own input.
pragma ComponentBehavior: Bound

import QtQuick
import "../swiftroll"

FocusScope {
    id: page

    objectName: "automationPage"

    required property QtObject applicationSession

    /// The page's Swift owner for the current document, and the neutral empty
    /// model while there is none: `automationPage()` fails once no document is
    /// presented, and the host removes this scene before the session releases the
    /// page. A guarded binding is therefore what a teardown re-evaluation
    /// resolves, and it re-reads the owner when the session publishes the next
    /// document.
    readonly property var model: page.applicationSession
                                 && page.applicationSession.songOpen
                                 ? page.applicationSession.automationPage()
                                 : null
    /// Every read below resolves against this: the installed owner, or the
    /// neutral empty model while there is none.
    readonly property var pageModel: page.model !== null && page.model !== undefined
                                     ? page.model : emptyModel

    /// The session's grid presenter while a document presentation exists, and the
    /// palette this page draws with. The page can be re-evaluated during scene
    /// teardown, after the session released the grid, so every palette and
    /// geometry read below goes through these guarded expressions.
    readonly property var gridModel: page.applicationSession
                                     && page.applicationSession.songOpen
                                     ? page.applicationSession.gridPresenter()
                                     : null
    readonly property var gridPalette: page.gridModel ? page.gridModel.palette : fallbackPalette

    QtObject {
        id: fallbackPalette

        /// Neutral colors for the window between scene removal and the session's
        /// release; nothing drawn then reaches a frame.
        readonly property color chromeBackground: "transparent"
        readonly property color rollBackground: "transparent"
        readonly property color outline: "transparent"
        readonly property color primaryText: "transparent"
        readonly property color secondaryText: "transparent"
        readonly property color selectionRing: "transparent"
        readonly property color selectionFill: "transparent"
        readonly property color selectionEdge: "transparent"
    }

    QtObject {
        id: emptyModel

        readonly property var tabs: []
        readonly property var nodes: []
        readonly property var curveRuns: []
        readonly property var ramps: []
        readonly property var gridLines: []
        readonly property var valueLines: []
        readonly property var valueLabels: []
        readonly property var selectionRects: []
        readonly property var previewRects: []
        readonly property var menuRows: []
        readonly property bool bandVisible: false
        readonly property var bandRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property bool hoverVisible: false
        readonly property string hoverText: ""
        readonly property var hoverLabelRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property double hoverTick: 0
        readonly property bool previewLabelVisible: false
        readonly property string previewLabelText: ""
        readonly property var previewLabelRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property bool readoutVisible: false
        readonly property string readoutText: ""
        readonly property var readoutRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property string accessibleDescription: "Automation"
        readonly property int cursorKind: 0
        readonly property bool trackAvailable: false
        readonly property string plotMessage: ""
        readonly property bool isPencilMode: false
        readonly property bool interactionActive: false
        readonly property double baseFontPx: 13
        readonly property double plotOrigin: 0
        readonly property double dragDistance: 10
        readonly property var captionFont: ({})
        readonly property var titleFont: ({})
        readonly property bool menuOpen: false
        readonly property double menuX: 0
        readonly property double menuY: 0
        readonly property bool promptOpen: false
        readonly property int promptKind: 0
        readonly property string promptTitle: ""
        readonly property string promptLabel: ""
        readonly property string promptMessage: ""
        readonly property string promptDraft: ""
        readonly property string promptError: ""
        readonly property int promptMinimum: 0
        readonly property int promptMaximum: 0
        readonly property bool tapTempoActive: false
        readonly property int tapTempoTapCount: 0
        readonly property int tapTempoDraftBpm: 0
        readonly property int tapTempoIdleCommitMs: 2000
        readonly property bool tapTempoReady: false

        function configureBody(width, height, gutter, devicePixelRatio, baseFontPx,
                               dragDistance) {}
        function pointerPress(x, y, surface, button, modifiers) { return false }
        function pointerMove(x, y, buttons, modifiers) { return false }
        function pointerRelease(x, y, button, modifiers) { return false }
        function pointerDoubleClick(x, y) { return false }
        function pointerLeave() {}
        function handleEscape() { return false }
        function activateParameter(index) { return false }
        function toggleGhostParameter(index) { return false }
        function openParameterMenu(index, x, y) { return false }
        function dismissMenu() {}
        function consumeMenuAction(index) { return false }
        function updatePromptDraft(draft) {}
        function acceptPromptDraft() { return false }
        function cancelPrompt() {}
        function tapTempoTap() {}
        function tapTempoIdleElapsed() { return false }
        function resetTapTempo() {}
        function cancelSectionInteraction() {}
    }

    /// The shared plot origin: the gutter the roll draws at and the container
    /// publishes as `plotOrigin`.
    readonly property real plotOrigin: page.gridModel ? page.gridModel.keyboardWidth : 0
    readonly property real plotWidth: Math.max(page.width - page.plotOrigin, 0)
    /// This page's own base-font seed, for the window before a document is
    /// presented.
    readonly property real seedBaseFontPx: 13
    readonly property real baseFontPx: page.gridModel ? page.gridModel.baseFontPx
                                                      : page.seedBaseFontPx

    /// The production selector's font-relative metrics.
    readonly property real tabStroke: Math.max(1, Math.round(page.baseFontPx / 12))
    readonly property real tabRowHeight: Math.max(1, Math.round(page.baseFontPx * 4 / 3))
    readonly property real tabInset: Math.max(1, Math.round(page.baseFontPx / 3))
    readonly property real tabPip: Math.max(2, Math.round(page.baseFontPx / 2))
    readonly property int selectorTabCount: page.pageModel.tabCount

    function pushBodyFacts() {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.plotWidth, page.height, page.plotOrigin,
                                     page.Screen.devicePixelRatio, page.baseFontPx,
                                     page.styleHints ? page.styleHints.startDragDistance : 10)
    }

    // Every fact `configureBody` publishes is a dependency: the owner's arrival,
    // the drawn size, the plot origin and the font the page's own geometry is
    // measured from. The owner compares and rebuilds only for real changes.
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

    // The shared clock reaches this page in Swift: `ApplicationSession` fans the
    // presenter's distinct presentations into the page owner, so no QML surface
    // reads the presenter or calls a page mutator through a bridge wrapper.

    // A modal surface, a live gesture or a tap-tempo session claims Escape;
    // everything else passes on to the window, so the shared routing keeps
    // owning Escape.
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel.handleEscape()

    readonly property int tabsSurface: 0
    readonly property int plotSurface: 1

    function cursorFor(kind) {
        switch (kind) {
        case 1: return Qt.CrossCursor
        case 2: return Qt.SizeVerCursor
        case 3: return Qt.SizeHorCursor
        case 4: return Qt.ClosedHandCursor
        default: return Qt.ArrowCursor
        }
    }

    /// Where focus returns after a modal closes: this page's plot.
    function focusOrigin() {
        plot.forceActiveFocus(Qt.OtherFocusReason)
    }

    // ---- selector column ----------------------------------------------------

    Item {
        id: gutter

        objectName: "automationGutter"
        x: 0
        y: 0
        width: page.plotOrigin
        height: page.height
        clip: true

        Rectangle {
            anchors.fill: parent
            color: page.gridPalette.chromeBackground
        }

        // The production selector is a scrollable two-column grid whose
        // Tempo row spans both columns. The scroll position follows the active
        // and focused tab, exactly as the production `ensureVisible` does.
        Flickable {
            id: tabScroller

            objectName: "automationTabsScroller"
            anchors.fill: parent
            interactive: false
            clip: true
            contentWidth: width
            contentHeight: Math.ceil(Math.max(0, page.selectorTabCount - 1) / 2)
                           * page.tabRowHeight + page.tabRowHeight + 3 * page.tabStroke

            function ensureVisible(item) {
                if (!item)
                    return
                var top = item.y
                var bottom = top + item.height
                if (top < contentY)
                    contentY = top
                else if (bottom > contentY + height)
                    contentY = bottom - height
            }

            Repeater {
                model: page.pageModel.tabs

                delegate: Item {
                    id: tab

                    required property var model

                    readonly property bool tempoTab: tab.model.tempo
                    readonly property int cellColumn: tab.tempoTab ? 0 : tab.model.index % 2
                    readonly property int cellRow: tab.tempoTab
                                                   ? Math.ceil(Math.max(0, page.selectorTabCount - 1)
                                                               / 2)
                                                   : Math.floor(tab.model.index / 2)

                    objectName: "automationParameterTab" + tab.model.index
                    x: tab.cellColumn * (page.plotOrigin / 2)
                    y: page.tabStroke + tab.cellRow * page.tabRowHeight
                    width: tab.tempoTab ? page.plotOrigin : page.plotOrigin / 2
                    height: page.tabRowHeight
                    activeFocusOnTab: true

                    function activate() {
                        if (!tab.model.available)
                            return
                        page.pageModel.activateParameter(tab.model.index)
                    }

                    function press(modifiers) {
                        if (!tab.model.available)
                            return
                        if (modifiers & Qt.ControlModifier) {
                            page.pageModel.toggleGhostParameter(tab.model.index)
                            return
                        }
                        page.pageModel.activateParameter(tab.model.index)
                    }

                    Keys.onReturnPressed: (event) => {
                        tab.activate()
                        event.accepted = true
                    }
                    Keys.onEnterPressed: (event) => {
                        tab.activate()
                        event.accepted = true
                    }
                    // Only plain Return/Enter are claimed: bare Space stays the
                    // window's transport shortcut.
                    Keys.onShortcutOverride: (event) => event.accepted =
                        event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                    onActiveFocusChanged: if (activeFocus) tabScroller.ensureVisible(tab)
                    onModelChanged: if (tab.model.active) tabScroller.ensureVisible(tab)

                    Accessible.role: Accessible.Button
                    Accessible.name: tab.model.label
                    Accessible.checkable: true
                    Accessible.checked: tab.model.active
                    Accessible.focusable: true
                    Accessible.description: (tab.tempoTab ? qsTr("Song-global tempo parameter")
                                                          : qsTr("Track automation parameter"))
                                            + (tab.model.included
                                               ? qsTr("; included in shared selection")
                                               : qsTr("; not in shared selection"))
                                            + (tab.model.ghosted
                                               ? qsTr("; shown as ghost nodes") : "")
                                            + (tab.model.active && tab.model.eventCount > 0
                                               ? qsTr("; %1 events").arg(tab.model.eventCount)
                                               : "")
                    Accessible.onPressAction: tab.activate()

                    // Active, ghosted, selection-included and focused states keep
                    // their own indicators, exactly as the production selector
                    // publishes them.
                    Rectangle {
                        anchors.fill: parent
                        color: tab.model.active ? page.gridPalette.selectionRing
                                                : tabHover.hovered
                                                  ? page.gridPalette.selectionFill
                                                  : page.gridPalette.chromeBackground

                        Rectangle {
                            visible: tab.model.ghosted
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: page.tabStroke
                            height: page.tabStroke
                            color: page.gridPalette.outline
                        }

                        Rectangle {
                            visible: tab.model.included && !tab.model.active
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.topMargin: page.tabStroke
                            anchors.rightMargin: page.tabStroke
                            anchors.bottomMargin: page.tabStroke
                            width: page.tabPip
                            color: page.gridPalette.selectionRing
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: page.tabStroke
                            color: "transparent"
                            border.width: page.tabStroke
                            border.color: tab.activeFocus ? page.gridPalette.primaryText
                                                          : "transparent"
                        }
                    }

                    // The event pip, the label and the active row's event count
                    // and tap-tempo readout.
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: page.tabInset
                        anchors.rightMargin: page.tabInset + (tab.tempoTab
                                                               ? tapControl.width + page.tabInset
                                                               : 0)
                        spacing: page.tabInset

                        Rectangle {
                            visible: tab.model.eventCount > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: page.tabPip
                            height: page.tabPip
                            radius: width / 2
                            color: page.gridPalette.primaryText
                            Accessible.ignored: true
                        }

                        Text {
                            objectName: "automationParameterTabText"
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(1, parent.width - page.tabPip - page.tabInset
                                               - countLabel.width - draftLabel.width)
                            text: tab.model.label
                            color: tab.model.active ? page.gridPalette.primaryText
                                                    : page.gridPalette.secondaryText
                            font: Qt.font(page.pageModel.titleFont)
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: Math.max(1, Math.round(page.baseFontPx / 2))
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            clip: true
                            Accessible.ignored: true
                        }

                        Text {
                            id: countLabel

                            objectName: "automationParameterEventCount"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tab.model.active && tab.model.eventCount > 0
                            text: tab.model.eventCount === 1 ? qsTr("1 event")
                                                             : qsTr("%1 events")
                                                               .arg(tab.model.eventCount)
                            color: page.gridPalette.secondaryText
                            font: Qt.font(page.pageModel.captionFont)
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                            Accessible.ignored: true
                        }

                        Text {
                            id: draftLabel

                            objectName: tab.tempoTab ? "automationTempoTapDraft" : ""
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tab.tempoTab && page.pageModel.tapTempoTapCount > 0
                            text: page.pageModel.tapTempoTapCount >= 2
                                  ? "%1 BPM".arg(page.pageModel.tapTempoDraftBpm) : "…"
                            color: page.gridPalette.secondaryText
                            font: Qt.font(page.pageModel.captionFont)
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                            Accessible.ignored: true
                        }
                    }

                    // The Tempo row's own Tap control: a press registers a tap at
                    // that event boundary and never activates the parameter row.
                    Rectangle {
                        id: tapControl

                        objectName: tab.tempoTab ? "automationTempoTapButton" : ""
                        visible: tab.tempoTab
                        // Above the tab's own press area: a tap registers a tap
                        // and never activates the parameter row.
                        z: 1
                        anchors.right: parent.right
                        anchors.rightMargin: page.tabInset
                        anchors.verticalCenter: parent.verticalCenter
                        width: tapLabel.implicitWidth + 2 * page.tabInset
                        height: page.tabRowHeight - 2 * page.tabStroke
                        color: tapControlPress.pressed ? page.gridPalette.selectionRing
                                                       : page.gridPalette.chromeBackground
                        border.width: page.tabStroke
                        border.color: page.gridPalette.outline
                        activeFocusOnTab: true

                        function tap() {
                            page.pageModel.tapTempoTap()
                        }

                        Text {
                            id: tapLabel

                            anchors.centerIn: parent
                            text: qsTr("Tap")
                            color: page.gridPalette.primaryText
                            font: Qt.font(page.pageModel.captionFont)
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                            Accessible.ignored: true
                        }

                        Keys.onReturnPressed: (event) => {
                            tapControl.tap()
                            event.accepted = true
                        }
                        Keys.onEnterPressed: (event) => {
                            tapControl.tap()
                            event.accepted = true
                        }
                        // Plain nonrepeating Return/Enter registers a tap; bare
                        // Space remains the transport shortcut.
                        Keys.onShortcutOverride: (event) => event.accepted =
                            (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && !event.isAutoRepeat

                        Accessible.role: Accessible.Button
                        Accessible.name: qsTr("Tap tempo")
                        Accessible.description:
                            page.pageModel.tapTempoTapCount >= 2
                                ? qsTr("Draft tempo: %1 BPM")
                                  .arg(page.pageModel.tapTempoDraftBpm)
                                : page.pageModel.tapTempoTapCount > 0
                                  ? qsTr("Listening for tempo taps")
                                  : qsTr("Tap repeatedly to set the song tempo")
                        Accessible.focusable: true
                        Accessible.onPressAction: tapControl.tap()

                        MouseArea {
                            id: tapControlPress

                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onPressed: tapControl.tap()
                        }
                    }

                    // One press area for both buttons, exactly as the production
                    // selector's own handler splits them: the left button activates
                    // or toggles the ghost, and the right button is the context
                    // request that opens the captured lane menu for this tab at the
                    // press's own position in the page's coordinate space.
                    MouseArea {
                        id: tabPress

                        objectName: "automationParameterTabPress" + tab.model.index
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onPressed: (mouse) => {
                            tab.forceActiveFocus()
                            if (mouse.button === Qt.RightButton) {
                                var origin = tab.mapToItem(page, mouse.x, mouse.y)
                                page.pageModel.openParameterMenu(tab.model.index, origin.x,
                                                                 origin.y)
                            } else {
                                tab.press(mouse.modifiers)
                            }
                            mouse.accepted = true
                        }
                    }

                    HoverHandler {
                        id: tabHover
                    }
                }
            }
        }

        Accessible.role: Accessible.Column
        Accessible.name: qsTr("Automation parameters")
        Accessible.focusable: false
    }

    // ---- plot ---------------------------------------------------------------

    Item {
        id: plot

        objectName: "automationPlot"
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

        TimelineQuickItem {
            objectName: "automationGridLines"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.gridLines : [])
        }

        TimelineQuickItem {
            objectName: "automationValueLines"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.valueLines : [])
        }

        Repeater {
            model: (page.pageModel ? page.pageModel.valueLabels : [])

            delegate: Text {
                required property var model

                x: model.labelRect.x
                y: model.labelRect.y
                width: model.labelRect.width
                height: model.labelRect.height
                text: model.labelText
                color: model.labelColor
                font: Qt.font(model.labelFont)
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                horizontalAlignment: model.labelHorizontalAlignment
                verticalAlignment: model.labelVerticalAlignment
                elide: Text.ElideRight
                maximumLineCount: 1
                clip: true
            }
        }

        TimelineQuickItem {
            objectName: "automationSelectionRects"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.selectionRects : [])
        }

        // The step curve's runs (ghost pins first, the active curve second, in
        // the order the page publishes them) and the ramp segments.
        TimelineQuickItem {
            objectName: "automationCurveRuns"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.curveRuns : [])
        }

        Repeater {
            model: (page.pageModel ? page.pageModel.ramps : [])

            delegate: Rectangle {
                required property var model

                objectName: model.primitiveName
                x: model.x0
                y: model.y0
                width: Math.max(1, Math.sqrt(model.dx * model.dx + model.dy * model.dy))
                height: 1
                color: model.color
                transformOrigin: Item.TopLeft
                rotation: model.dx !== 0
                          ? Math.atan2(model.dy, model.dx) * 180 / Math.PI : 0
                Accessible.ignored: true
            }
        }

        // One drawn node per published entry, plus the origin phantom at the plot
        // edge. A selected node keeps its ring, a hovered one its own ring, and
        // the projected engine node is drawn in the secondary ink.
        Repeater {
            model: (page.pageModel ? page.pageModel.nodes : [])

            delegate: Item {
                id: node

                required property var model

                objectName: node.model.primitiveName + (node.model.phantom ? "Phantom" : "")
                x: 0
                y: 0
                width: plot.width
                height: plot.height
                Accessible.ignored: true

                Rectangle {
                    objectName: "automationNodeRing"
                    visible: node.model.selected
                    x: node.model.x - node.model.ringRadius
                    y: node.model.y - node.model.ringRadius
                    width: 2 * node.model.ringRadius
                    height: 2 * node.model.ringRadius
                    radius: node.model.ringRadius
                    color: "transparent"
                    border.width: Math.max(1, node.model.outlineWidth)
                    border.color: node.model.ringColor
                }

                Rectangle {
                    objectName: "automationNodeHover"
                    visible: node.model.hovered && !node.model.selected
                    x: node.model.x - node.model.ringRadius
                    y: node.model.y - node.model.ringRadius
                    width: 2 * node.model.ringRadius
                    height: 2 * node.model.ringRadius
                    radius: node.model.ringRadius
                    color: "transparent"
                    border.width: Math.max(1, node.model.outlineWidth)
                    border.color: node.model.ringColor
                }

                Rectangle {
                    objectName: "automationNodeFill"
                    x: node.model.x - node.model.radius
                    y: node.model.y - node.model.radius
                    width: 2 * node.model.radius
                    height: 2 * node.model.radius
                    radius: node.model.radius
                    color: node.model.fillColor
                    border.width: Math.max(1, node.model.outlineWidth)
                    border.color: node.model.outlineColor
                }
            }
        }

        // The range press's own band.
        Rectangle {
            objectName: "automationRangeBand"

            visible: (page.pageModel ? page.pageModel.bandVisible : false)
            x: (page.pageModel ? page.pageModel.bandRect.x : 0)
            y: (page.pageModel ? page.pageModel.bandRect.y : 0)
            width: (page.pageModel ? page.pageModel.bandRect.width : 0)
            height: (page.pageModel ? page.pageModel.bandRect.height : 0)
            color: page.gridPalette.selectionFill
            border.width: 1
            border.color: page.gridPalette.selectionEdge
            Accessible.ignored: true
        }

        // The frozen gesture's draft markers.
        TimelineQuickItem {
            objectName: "automationPreviewRects"
            anchors.fill: parent
            rects: (page.pageModel ? page.pageModel.previewRects : [])
        }

        // The hover value label and the live gesture's own readout.
        Text {
            objectName: "automationHoverLabel"

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

        Text {
            objectName: "automationPreviewLabel"

            visible: (page.pageModel ? page.pageModel.previewLabelVisible : false)
            x: (page.pageModel ? page.pageModel.previewLabelRect.x : 0)
            y: (page.pageModel ? page.pageModel.previewLabelRect.y : 0)
            width: (page.pageModel ? page.pageModel.previewLabelRect.width : 0)
            height: (page.pageModel ? page.pageModel.previewLabelRect.height : 0)
            text: (page.pageModel ? page.pageModel.previewLabelText : "")
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

        // The effective context readout: the active parameter and the value it
        // holds at the shared tick.
        Text {
            objectName: "automationReadout"

            visible: (page.pageModel ? page.pageModel.readoutVisible : false)
            x: (page.pageModel ? page.pageModel.readoutRect.x : 0)
            y: (page.pageModel ? page.pageModel.readoutRect.y : 0)
            width: (page.pageModel ? page.pageModel.readoutRect.width : 0)
            height: (page.pageModel ? page.pageModel.readoutRect.height : 0)
            text: (page.pageModel ? page.pageModel.readoutText : "")
            color: page.gridPalette.secondaryText
            font: Qt.font(page.pageModel ? page.pageModel.titleFont : {})
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            clip: true
        }

        Text {
            objectName: "automationPlotMessage"

            visible: !(page.pageModel ? page.pageModel.trackAvailable : false)
                     && (page.pageModel ? page.pageModel.plotMessage : "").length > 0
            anchors.centerIn: parent
            text: (page.pageModel ? page.pageModel.plotMessage : "")
            color: page.gridPalette.secondaryText
            font: Qt.font(page.pageModel ? page.pageModel.captionFont : {})
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: plotInput

            objectName: "automationPlotInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: page.cursorFor(page.pageModel ? page.pageModel.cursorKind : 0)

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
            onReleased: (mouse) => mouse.accepted =
                page.pageModel.pointerRelease(mouse.x, mouse.y, mouse.button, mouse.modifiers)
            onCanceled: page.pageModel.cancelSectionInteraction()
            onExited: page.pageModel.pointerLeave()
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
        Accessible.name: qsTr("Automation")
        Accessible.description: (page.pageModel ? page.pageModel.accessibleDescription : "")
        Accessible.focusable: true
    }

    // ---- modal and local surfaces -------------------------------------------

    // The page owns modality for its two modal surfaces; each renders the flag
    // it is pushed and delivers the input that drives the page. The push happens
    // on the page's own change signals instead of a binding inside the modal's
    // scope, which would have to read through the `var`-typed model.
    Connections {
        target: page.pageModel

        function onMenuOpenChanged() { page.syncModals() }
        function onPromptOpenChanged() { page.syncModals() }
        function onTapTempoActiveChanged() { page.syncModals() }
    }

    /// The container's one unclipped modal layer, when the container hosts this
    /// page (a composition that mounts the page elsewhere keeps the modals inside
    /// the page). Filled in `createModals`.
    property var modalHost: null
    property var menu: null
    property var prompt: null
    property var tapTempo: null

    Component {
        id: menuComponent

        AutomationMenu {
            onClosed: page.focusOrigin()
        }
    }

    Component {
        id: promptComponent

        AutomationPrompt {
            onClosed: page.focusOrigin()
        }
    }

    Component {
        id: tapTempoComponent

        TapTempo {}
    }

    function syncModals() {
        if (page.menu !== null) {
            page.menu.model = page.model
            page.menu.showing = page.pageModel ? page.pageModel.menuOpen : false
        }
        if (page.prompt !== null) {
            page.prompt.model = page.model
            page.prompt.showing = page.pageModel ? page.pageModel.promptOpen : false
        }
        if (page.tapTempo !== null) {
            page.tapTempo.model = page.model
            page.tapTempo.showing = page.pageModel ? page.pageModel.tapTempoActive : false
        }
    }

    /// Composes the two modal surfaces into the container's one modal layer, or
    /// into the page when no layer was handed over, and the tap-tempo panel into
    /// the page itself: production keeps the plot live while a session
    /// accumulates, so a local panel takes only its own input. They are created
    /// once and only re-pointed at the current document owner, so a case's modal
    /// state is never a fresh object per interaction.
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
        if (page.prompt === null) {
            page.prompt = promptComponent.createObject(host, {"model": page.model,
                                                              "pageItem": page})
        } else if (page.prompt.parent !== host) {
            page.prompt.parent = host
        }
        if (page.tapTempo === null)
            page.tapTempo = tapTempoComponent.createObject(page, {"model": page.model,
                                                                  "hostPage": page})
        page.syncModals()
    }

    onModalHostChanged: page.createModals()
}
