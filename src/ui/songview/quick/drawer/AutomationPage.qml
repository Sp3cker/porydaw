// Automation drawer page: shared parameter gutter, model lifecycle and modals.
// The plot handles rendering and input; Swift owns all automation values.
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

DrawerLanePage {
    id: page

    objectName: "automationPage"

    final property App.MouseHints hintService: null
    final property bool hintScopeAllowed: true

    /// The Swift owner for this document, or null when no document is presented.
    readonly final property App.AutomationPage model: page.applicationSession
                                 && page.applicationSession.songOpen
                                 ? page.applicationSession.automationPage() : null
    readonly final property App.AutomationPage pageModel: page.model

    readonly final property App.GridPalette gridPalette: page.applicationSession.grid.palette

    baseFontPx: page.applicationSession.grid.baseFontPx

    readonly property int selectorTabCount: page.pageModel ? page.pageModel.tabCount : 0

    function pushBodyFacts(): void {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.plotWidth, page.height, page.plotOrigin,
                                     page.Screen.devicePixelRatio, page.baseFontPx,
                                     Qt.styleHints.startDragDistance)
    }
    function geometryChanged(): void {
        if (plot.input.pressed && page.pageModel && page.pageModel.interactionActive)
            page.pageModel.cancelSectionInteraction()
        page.pushBodyFacts()
    }

    // Reconfigure when owner, geometry, plot origin or base font changes.
    onModelChanged: {
        page.pushBodyFacts()
        page.createModals()
    }
    onBodyFactsChanged: page.geometryChanged()
    Component.onCompleted: {
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
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel !== null && page.pageModel.handleEscape()

    readonly property int tabsSurface: 0
    readonly property int plotSurface: 1


    /// Where focus returns after a modal closes: this page's plot.
    function focusOrigin(): void {
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
        Loader {
            anchors.fill: parent
            active: page.pageModel !== null && page.gridPalette !== null
            sourceComponent: AutomationTabs {
                pageModel: page.pageModel
                sceneRoot: page
                pagePalette: page.gridPalette
                hintService: page.hintService
                hintScopeAllowed: page.hintScopeAllowed
            }
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

        function onMenuOpenChanged(): void { page.syncModals() }
        function onPromptOpenChanged(): void { page.syncModals() }
    }

    /// The container's unclipped modal layer, or this page when standalone.
    final property Item modalHost: null
    final property AutomationMenu menu: null
    final property AutomationPrompt prompt: null

    Component {
        id: menuComponent

        AutomationMenu {
            model: page.pageModel
            pageItem: page
            menuColors: page.gridPalette
            hintService: page.hintService
            onClosed: page.focusOrigin()
        }
    }

    Component {
        id: promptComponent

        AutomationPrompt {
            model: page.pageModel
            pageItem: page
            promptPalette: page.gridPalette
            hintService: page.hintService
            onClosed: page.focusOrigin()
        }
    }


    function syncModals(): void {
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
    function createModals(): void {
        if (!page.pageModel)
            return
        const host = page.modalHost !== null ? page.modalHost : page
        if (page.menu === null) {
            page.menu = menuComponent.createObject(host) as AutomationMenu
        } else if (page.menu.parent !== host) {
            // Move the existing modal when the container supplies its layer.
            page.menu.parent = host
        }
        if (page.prompt === null) {
            page.prompt = promptComponent.createObject(host) as AutomationPrompt
        } else if (page.prompt.parent !== host) {
            page.prompt.parent = host
        }
        page.syncModals()
    }

    onModalHostChanged: page.createModals()
}
