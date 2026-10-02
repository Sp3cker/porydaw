// Automation drawer page: shared parameter gutter, model lifecycle and modals.
// The plot handles rendering and input; Swift owns all automation values.
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

FocusScope {
    id: page

    objectName: "automationPage"

    property var hintService: null
    property bool hintScopeAllowed: true
    required property QtObject applicationSession

    /// The Swift owner for this document; guarded during scene teardown.
    /// Re-evaluates when the session publishes a new document.
    readonly property var model: page.applicationSession
                                 && page.applicationSession.songOpen
                                 ? page.applicationSession.automationPage()
                                 : null
    /// Every read below resolves against this: the installed owner, or the
    /// neutral empty model while there is none.
    readonly property var pageModel: page.model !== null && page.model !== undefined
                                     ? page.model : emptyModel

    readonly property var gridModel: page.applicationSession
                                     && page.applicationSession.songOpen
                                     ? page.applicationSession.gridPresenter()
                                     : null
    /// Guard palette reads while scene teardown releases the grid presenter.
    readonly property var gridPalette: page.gridModel ? page.gridModel.palette : fallbackPalette

    QtObject {
        id: fallbackPalette

        /// Neutral fallback colors while no document is presented.
        readonly property color chromeBackground: "transparent"
        readonly property color rollBackground: "transparent"
        readonly property color outline: "transparent"
        readonly property color primaryText: "transparent"
        readonly property color secondaryText: "transparent"
        readonly property color selectionRing: "transparent"
        readonly property color selectionFill: "transparent"
        readonly property color selectionEdge: "transparent"
        readonly property color automationNodeInk: "transparent"
        readonly property color selectionText: "transparent"
        readonly property color windowText: "transparent"
    }

    QtObject {
        id: emptyModel

        readonly property var tabs: []
        readonly property var nodes: []
        readonly property var gridLines: []
        readonly property var valueLines: []
        readonly property var valueLabels: []
        readonly property var ghostNameLabels: []
        readonly property var selectionRects: []
        readonly property var previewRects: []
        readonly property var menuRows: []
        readonly property var menuChildRows: []
        readonly property int menuRowCount: 0
        readonly property int menuChildRowCount: 0
        readonly property bool bandVisible: false
        readonly property var bandRect: ({ "x": 0, "y": 0, "width": 0, "height": 0 })
        readonly property var hoverDisplay: ({ "visible": false, "text": "",
            "hasNode": false, "nodeTick": 0, "guideX": 0, "ghostY": 0,
            "hasGhost": false, "x": 0, "y": 0, "width": 0, "height": 0 })
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
        readonly property int hoverHintProfile: HintProfiles.Empty
        readonly property bool interactionActive: false
        readonly property double baseFontPx: 13
        readonly property double plotOrigin: 0
        readonly property double dragDistance: 10
        readonly property var captionFont: ({})
        readonly property var titleFont: ({})
        readonly property var noteNameFont: ({})
        readonly property var minimumFont: ({})
        readonly property real pipExtent: 0
        readonly property real minimumCellHeight: 0
        readonly property bool menuOpen: false
        readonly property double menuX: 0
        readonly property double menuY: 0
        readonly property bool promptOpen: false
        readonly property var promptAppearance: ({})
        readonly property var promptFont: ({})
        readonly property int promptInputWidth: 0
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
    readonly property real plotOrigin: page.gridModel
                                       ? (page.gridModel.trackHeaderWidth || 0)
                                         + page.gridModel.keyboardWidth : 0
    readonly property real plotWidth: Math.max(page.width - page.plotOrigin, 0)
    /// This page's own base-font seed, for the window before a document is
    /// presented.
    readonly property real seedBaseFontPx: 13
    readonly property real baseFontPx: page.gridModel ? page.gridModel.baseFontPx
                                                      : page.seedBaseFontPx

    readonly property int selectorTabCount: page.pageModel.tabCount

    function pushBodyFacts() {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.plotWidth, page.height, page.plotOrigin,
                                     page.Screen.devicePixelRatio, page.baseFontPx,
                                     Qt.styleHints.startDragDistance)
    }
    function geometryChanged() {
        if (plot.input.pressed && page.pageModel.interactionActive)
            page.pageModel.cancelSectionInteraction()
        page.pushBodyFacts()
    }

    // Reconfigure when owner, geometry, plot origin or base font changes.
    onModelChanged: {
        page.pushBodyFacts()
        page.createModals()
    }
    onWidthChanged: page.geometryChanged()
    onHeightChanged: page.geometryChanged()
    onPlotOriginChanged: page.geometryChanged()
    onBaseFontPxChanged: page.geometryChanged()
    Component.onCompleted: {
        page.pushBodyFacts()
        page.createModals()
    }
    Component.onDestruction: {
        if (page.menu !== null)
            page.menu.destroy()
        if (page.prompt !== null)
            page.prompt.destroy()
    }

    // The session fans shared-clock presentations into the Swift page owner.

    // Only active modals, gestures and tap-tempo sessions claim Escape.
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel.handleEscape()

    readonly property int tabsSurface: 0
    readonly property int plotSurface: 1


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

        // The production selector follows the active and focused tab.
        AutomationTabs {
            anchors.fill: parent
            pageModel: page.pageModel
            sceneRoot: page
            pagePalette: page.gridPalette
            hintService: page.hintService
            hintScopeAllowed: page.hintScopeAllowed
        }

        Accessible.role: Accessible.Column
        Accessible.name: qsTr("Automation parameters")
        Accessible.focusable: false
    }

    AutomationPlot {
        id: plot
        x: page.plotOrigin
        y: 0
        width: page.plotWidth
        height: page.height
        model: page.model
        pageModel: page.pageModel
        gridModel: page.gridModel
        gridPalette: page.gridPalette
        baseFontPx: page.baseFontPx
        devicePixelRatio: page.Screen.devicePixelRatio
        pageVisible: page.visible
        hintService: page.hintService
        hintScopeAllowed: page.hintScopeAllowed
        plotSurface: page.plotSurface
    }

    // ---- modal and local surfaces -------------------------------------------

    // Page model changes synchronize the two modal surfaces.
    Connections {
        target: page.pageModel

        function onMenuOpenChanged() { page.syncModals() }
        function onPromptOpenChanged() { page.syncModals() }
    }

    /// The container's unclipped modal layer, or this page when standalone.
    property var modalHost: null
    property var menu: null
    property var prompt: null

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


    function syncModals() {
        if (page.menu !== null) {
            page.menu.model = page.pageModel
            page.menu.showing = page.pageModel ? page.pageModel.menuOpen : false
        }
        if (page.prompt !== null) {
            page.prompt.model = page.pageModel
            page.prompt.showing = page.pageModel ? page.pageModel.promptOpen : false
        }
    }

    /// Modals move to the container layer without losing their identity.
    /// Page teardown retires them even when that layer survives.
    function createModals() {
        var host = page.modalHost !== null && page.modalHost !== undefined ? page.modalHost : page
        if (page.menu === null) {
            page.menu = menuComponent.createObject(host, {"model": page.pageModel,
                                                          "pageItem": page})
        } else if (page.menu.parent !== host) {
            // Move the existing modal when the container supplies its layer.
            page.menu.parent = host
        }
        if (page.prompt === null) {
            page.prompt = promptComponent.createObject(host, {"model": page.pageModel,
                                                              "pageItem": page})
        } else if (page.prompt.parent !== host) {
            page.prompt.parent = host
        }
        page.syncModals()
    }

    onModalHostChanged: page.createModals()
}
