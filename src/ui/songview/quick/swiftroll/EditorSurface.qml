pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

FocusScope {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    required property QtObject applicationSession
    readonly property int baseFontPx: applicationSession.timeSigHost
                                      ? applicationSession.timeSigHost.baseFontPx
                                      : applicationSession.baseFontPx
    readonly property font bodyFont: Qt.font(applicationSession.timeSigHost.typographyFonts.body)
    readonly property font captionFont: Qt.font(applicationSession.timeSigHost.typographyFonts.caption)
    property var shellRouter: null
    signal contextMenuAt(real x, real y)
    readonly property int cancelReasonFocusLost: 0
    readonly property int cancelReasonPointerUngrabbed: 1
    readonly property int cancelReasonHidden: 2
    // A drawer modal lives on the window's content item, outside this scope;
    // a hidden surface already cancelled as hidden.
    onActiveFocusChanged: {
        if (!activeFocus && visible && !editorDrawer.modalOwnsFocus())
            applicationSession.cancelGridInput(cancelReasonFocusLost)
    }
    readonly property var gridModel: applicationSession.gridPresenter()
    readonly property var headersModel: applicationSession.trackHeadersPresenter()
    readonly property var headerPickerModel: applicationSession.headerVoicePickerModel()
    readonly property var drawerPresenter: applicationSession.drawerPresenter()
    readonly property var velocityModel: applicationSession.velocityPage()
    property bool velocityPromptRetainingRelease: false
    readonly property var otherEventsPresenter: applicationSession.otherEventsBand()
    readonly property var pitchBendPresenter: applicationSession.pitchBendPresenter()
    readonly property var eventListPresenter: applicationSession.eventListPresenter()
    readonly property bool showEvents: applicationSession.showsEvents
    onShowEventsChanged: {
        // Current-state arbitration: the toggle returns focus to the roll only
        // when the events surface owned it or the teardown orphaned focus.
        const eventsHeldFocus = root.eventPage.item && (root.eventPage.item as Item).activeFocus
        if (!root.showEvents)
            root.eventPage.active = false
        if (root.eventListPresenter)
            root.eventListPresenter.setVisible(root.showEvents)
        root.eventListHost.visible = root.showEvents
        if (root.showEvents)
            root.eventPage.active = true
        else if (eventsHeldFocus || root.focusOrphanedByToggle())
            root.rollInput.forceActiveFocus(Qt.OtherFocusReason)
    }
    // Teardown falls back up the destroyed page's parent chain, so focus on the
    // events host or above owns no control.
    function focusOrphanedByToggle(): bool {
        const window = root.Window.window
        if (!window)
            return false
        const focused = window.activeFocusItem
        if (!focused || !focused.visible || !focused.enabled)
            return true
        let host = root.eventListHost
        while (host) {
            if (focused === host)
                return true
            host = host.parent
        }
        return false
    }
    readonly property var hintService: applicationSession.mouseHintsPresenter()
    readonly property bool hintWindowActive: visible && Window.window !== null
                                            && Window.window.visible && Window.window.active
    onHintWindowActiveChanged: {
        if (hintWindowActive || (Window.window
                                 && (!Window.window.visible || !Window.window.active)))
            hintService.setWindowActive(hintWindowActive)
    }
    readonly property bool hintScopeCovered: headersModel.menuOpen
        || gridModel.gridMenuKind !== 0 || rulerMenu.isOpen
        || applicationSession.headerVoicePickerOpen || applicationSession.timeSigPromptOpen
        || rulerMenu.insertTimePromptOpen || velocityModel.promptOpen
        || pitchBendPresenter.isOpen
    function refreshHintScope(): void {
        if (!hintScopeCovered && hintWindowActive)
            hintService.scopeRefresh()
    }
    onHintScopeCoveredChanged: {
        if (!hintScopeCovered)
            Qt.callLater(refreshHintScope)
    }
    readonly property real timelineSplitX: headersModel.trackHeaderWidth + gridModel.keyboardWidth
    readonly property real scrollbarBreadth: headersModel.scrollbarWidth
    readonly property int noteCount: gridModel.renderedNoteCount
    readonly property var timeSigHost: applicationSession.timeSigHost
    property point timeSigMenuPosition: Qt.point(0, 0)
    property point gridMenuPosition: Qt.point(0, 0)
    property point headerMenuPosition: Qt.point(0, 0)
    readonly property var rulerMenu: applicationSession.rulerMenuPresenter()
    property point timeSelectionMenuPosition: Qt.point(0, 0)
    property bool timeMenuFocus: false
    property bool insertPromptHadFocus: false
    readonly property int menuHorizontalPadding: applicationSession.timeSigHost.layoutSpaces.two
    readonly property int menuVerticalPadding: applicationSession.timeSigHost.layoutSpaces.half
    readonly property int menuGap: applicationSession.timeSigHost.layoutSpaces.one
    property alias rollStack: rollBandContent.rollStack
    property alias rollPlot: rollBandContent.rollPlot
    property alias rollInput: rollBandContent.rollInput
    property alias rollHint: rollBandContent.rollHint
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Control && root.rollInput.containsMouse && !root.rollInput.pressed)
            gridModel.updateHover(root.rollInput.mouseX, root.rollInput.mouseY,
                                  event.modifiers | Qt.ControlModifier)
        event.accepted = false
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control && root.rollInput.containsMouse && !root.rollInput.pressed)
            gridModel.updateHover(root.rollInput.mouseX, root.rollInput.mouseY,
                                  event.modifiers & ~Qt.ControlModifier)
        event.accepted = false
    }
    property alias eventListHost: rollBandContent.eventListHost
    property alias eventPage: rollBandContent.eventPage
    property alias trackHeaders: rollBandContent.trackHeaders
    property alias rulerInput: rollBandContent.rulerInput
    property alias menus: surfaceMenus
    property alias drawerItem: editorDrawer
    property alias eventBand: otherEventsBand
    property alias fontMetrics: bodyFontMetrics
    function retargetNoteMenu(x: real, y: real): bool {
        const point = root.rollInput.mapFromItem(null, x, y)
        return root.rollPlot.visible && point.x >= 0 && point.y >= 0
            && point.x < root.rollInput.width && point.y < root.rollInput.height
            && gridModel.retargetNoteMenu(point.x, point.y)
    }


    readonly property string appliedRevisionText: gridModel.appliedRevisionText
    property bool viewportConfigured: false
    readonly property bool editorStartupReady: viewportConfigured && visible
        && shellRouter !== null
        && shellRouter.session.songTabs.selectedId === applicationSession.tabId
        && !showEvents && root.rollPlot.visible && applicationSession.isReady
        && root.rollPlot.width > 0 && root.rollPlot.height > 0
        && gridModel.scene.displayRevision > 0 && appliedRevisionText.length > 0
    onEditorStartupReadyChanged: observeStartupEditor()
    onShellRouterChanged: observeStartupEditor()

    function observeStartupEditor(): void {
        if (root.shellRouter && root.shellRouter.startupTraceEnabled
                && root.editorStartupReady)
            root.shellRouter.editorReady(root.applicationSession.tabId)
    }

    FontMetrics {
        id: bodyFontMetrics
        font: root.bodyFont
    }

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()
    onVisibleChanged: {
        // Cancellation reaches presenters even if this surface is already hidden.
        if (!visible && root.applicationSession)
            root.applicationSession.cancelGridInput(root.cancelReasonHidden)
        if (visible && root.showEvents && root.eventPage.item)
            Qt.callLater(function() {
                if (root.visible && root.showEvents && root.eventPage.item)
                    (root.eventPage.item as Item).forceActiveFocus(Qt.OtherFocusReason)
            })
    }

    Connections {
        target: root.gridModel
        function onContextMenuRequested(x: real, y: real): void {
            if (root.shellRouter) {
                const position = root.rollInput.mapToItem(null, x, y)
                root.contextMenuAt(position.x, position.y)
            }
        }
        function onScrollbarGrabCancelRequested(): void {
            horizontalScrollBar.cancelGrab()
            rollScrollBar.cancelGrab()
        }
    }

    Connections {
        target: root.headersModel
        function onContextMenuRequested(x: real, y: real): void {
            root.headerMenuPosition = root.trackHeaders.mapToItem(root, x, y)
        }
        // Fork SongView::focusContent: the event-list input owns the band's
        // space while shown, else the roll band input takes focus back.
        function onRestoreRollFocusRequested(): void {
            if (root.showEvents && root.eventPage.item)
                (root.eventPage.item as Item).forceActiveFocus(Qt.OtherFocusReason)
            else
                root.rollInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }

    Rectangle {
        objectName: "swiftRollBackground"
        anchors.fill: parent
        color: root.gridModel.palette.rollBackground
        z: -1
    }

    EditorRollBand {
        id: rollBandContent
        root: parent
        editorDrawer: root.drawerItem
        otherEventsBand: root.eventBand
    }

    // One scroll row: its frame updates in the same dataChanged sweep as the
    // painted rows the band translates, so content and scroll never lag apart.
    property real scrollX: 0
    property real scrollY: 0
    Repeater {
        id: scrollCarrier
        model: root.gridModel.scene.cameraScroll
        delegate: Item {
            required property var frame
            onFrameChanged: applyScrollFrame()
            Component.onCompleted: applyScrollFrame()
            function applyScrollFrame(): void {
                if (frame) {
                    root.scrollX = frame.x
                    root.scrollY = frame.y
                }
            }
        }
    }

    // Keep the timeline row below the drawer; its value is owned by the Swift
    // camera and the control only requests a new scroll position.
    TimelineScrollbar {
        id: horizontalScrollBar
        objectName: "timelineHorizontalScrollBar"
        z: 2
        x: root.timelineSplitX
        y: root.height - height
        width: Math.max(root.width - x, 0)
        height: root.scrollbarBreadth
        orientation: Qt.Horizontal
        minimum: root.gridModel.cameraMinHScroll
        maximum: root.gridModel.cameraMaxHScroll
        value: root.gridModel.cameraScrollX
        pageStep: root.rollPlot.width
        singleStep: 1
        minimumThumbLength: root.headersModel.scrollbarMinimumThumbHeight
        accessibleName: qsTr("Timeline")
        handleColor: root.headersModel.appearance.scrollbarHandle
        handleHoverColor: root.headersModel.appearance.scrollbarHandleHover
        visibleWhenNotScrollable: true
        hintService: root.hintService
        hintScopeAllowed: !root.hintScopeCovered
        thumbObjectName: "timelineHorizontalScrollThumb"
        onHintReleased: scenePosition => root.rollHint.receiveRelease(scenePosition)
        onGestureActiveChanged: root.gridModel.setScrollbarGrabActive(
                                    horizontalScrollBar.gestureActive
                                    || (rollScrollBar && rollScrollBar.gestureActive))

        onValueRequested: (value) => root.gridModel.setCameraHScroll(value)
        onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) =>
                              root.gridModel.scrollHorizontalByWheel(
                                  pixelX, pixelY, angleX, angleY,
                                  Qt.styleHints.wheelScrollLines)
    }

    TimelineScrollbar {
        id: rollScrollBar
        objectName: "timelineRollScrollBar"
        z: 2
        x: root.rollStack.x + root.rollStack.width
        y: root.rollPlot.y
        width: root.scrollbarBreadth
        height: root.rollPlot.height
        orientation: Qt.Vertical
        minimum: 0
        maximum: root.gridModel.cameraMaxVScroll
        value: root.gridModel.cameraScrollY
        pageStep: root.rollPlot.height
        singleStep: 1
        minimumThumbLength: root.headersModel.scrollbarMinimumThumbHeight
        accessibleName: qsTr("Piano roll")
        handleColor: root.headersModel.appearance.scrollbarHandle
        handleHoverColor: root.headersModel.appearance.scrollbarHandleHover
        visibleWhenNotScrollable: true
        externalVisible: !root.showEvents
        hintService: root.hintService
        hintScopeAllowed: !root.hintScopeCovered
        thumbObjectName: "timelineRollScrollThumb"
        onHintReleased: scenePosition => root.rollHint.receiveRelease(scenePosition)
        onGestureActiveChanged: root.gridModel.setScrollbarGrabActive(
                                    horizontalScrollBar.gestureActive || rollScrollBar.gestureActive)

        onValueRequested: (value) => root.gridModel.setCameraVScroll(value)
        onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) =>
                              root.gridModel.scrollVerticalByWheel(
                                  pixelX, pixelY, angleX, angleY,
                                  Qt.styleHints.wheelScrollLines)
    }

    EditorSurfaceMenus {
        id: surfaceMenus
        anchors.fill: parent
        z: 10
        root: parent
        rollInput: root.rollInput
        rulerInput: root.rulerInput
        trackHeaders: root.trackHeaders
        bodyFontMetrics: root.fontMetrics
    }
    EditorSurfacePrompts {
        anchors.fill: parent
        z: 11
        root: parent
        rollInput: root.rollInput
        rulerInput: root.rulerInput
        rollPlot: root.rollPlot
        trackHeaders: root.trackHeaders
        editorDrawer: root.drawerItem
        bodyFontMetrics: root.fontMetrics
    }

    // The container sizes its own height from the presenter.
    EditorDrawer {
        id: editorDrawer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: otherEventsBand.top
        z: 2

        applicationSession: root.applicationSession
        hintService: root.hintService
        presenter: root.drawerPresenter
        drawerPalette: root.gridModel.palette
    }
    OtherEventsBand {
        id: otherEventsBand
        objectName: "timelineOtherEventsBand"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: horizontalScrollBar.top
        z: 2
        presenter: root.otherEventsPresenter
        colors: root.gridModel.palette
        gridModel: root.gridModel
        overlayRoot: root
        timelineSplitX: root.timelineSplitX
        plotWidth: root.rollPlot.width
        applicationFont: root.bodyFont
        onHeightChanged: root.configureViewport()
    }



    // One input-transparent playhead paints the roll and drawer above both.
    SharedPlayhead {
        id: sharedPlayhead
        anchors.fill: parent
        z: 3

        presenter: root.applicationSession.playheadPresenter()
        guides: root.applicationSession.playheadGuidesPresenter()
        hoverGuideColor: root.gridModel.palette.secondaryText
        editGuideColor: root.gridModel.palette.editCursor
        playheadColor: root.gridModel.palette.playhead
        rollBodyVisible: !root.showEvents
        rollPlotRect: Qt.rect(root.rollStack.x + root.rollPlot.x, root.rollPlot.y,
                              root.rollPlot.width, root.rollPlot.height)
        drawerRect: Qt.rect(editorDrawer.x, editorDrawer.y,
                            editorDrawer.width, editorDrawer.height)
        velocitySection: root.drawerPresenter.velocitySection
        voiceChangesSection: root.drawerPresenter.voiceChangesSection
        automationSection: root.drawerPresenter.automationSection
    }

    function configureViewport(): void {
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
        root.gridModel.configureViewport(Math.max(root.rollPlot.width, 1.0),
                                         Math.max(root.rollPlot.height, 1.0),
                                         root.baseFontPx, dpr)
        root.headersModel.configureViewport(
            Math.max(0, root.trackHeaders.width - root.headersModel.scrollbarWidth),
            root.trackHeaders.height, root.baseFontPx, dpr)
        // Drawer plots share the roll viewport, not the scrollbar strips;
        // the container still spans the full surface behind that chrome.
        root.drawerPresenter.configureLayout(Math.max(0, root.width - root.scrollbarBreadth),
                                             Math.max(0, root.height
                                                      - root.scrollbarBreadth - otherEventsBand.height),
                                             root.timelineSplitX,
                                             root.baseFontPx,
                                             bodyFontMetrics.lineSpacing)
        root.otherEventsPresenter.configureViewport(root.baseFontPx, bodyFontMetrics.lineSpacing)
        root.viewportConfigured = true
        root.observeStartupEditor()
    }

    function deliverWheel(event: var, overGutter: bool): void {
        root.gridModel.handleWheel(event.angleDelta.x, event.angleDelta.y,
                                   event.pixelDelta.x, event.pixelDelta.y,
                                   event.modifiers, event.phase, overGutter,
                                   event.x, event.y)
        event.accepted = true
    }

    Component.onCompleted: {
        if (hintWindowActive)
            hintService.setWindowActive(true)
        if (root.eventListPresenter)
            root.eventListPresenter.setVisible(root.showEvents)
        root.eventListHost.visible = root.showEvents
        root.eventPage.active = root.showEvents
        configureViewport()
    }
}
