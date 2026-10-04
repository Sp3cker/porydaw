pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Porydaw.Ui
import PorydawApp as App

FocusScope {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    enabled: applicationSession !== null
    final required property App.SongTabSession applicationSession
    final property int baseFontPx: applicationSession?.timeSigHost?.baseFontPx ?? 0
    final property font bodyFont
    final property font captionFont
    property color hoverGuideColor
    property color editGuideColor
    property color playheadColor
    property color scrollbarHandleColor
    property color scrollbarHandleHoverColor
    final property App.ShellPresenter shellRouter: null
    Binding {
        when: root.applicationSession !== null
        restoreMode: Binding.RestoreNone
        root.bodyFont: root.applicationSession?.timeSigHost?.typographyFonts?.body
        root.captionFont: root.applicationSession?.timeSigHost?.typographyFonts?.caption
    }
    signal contextMenuAt(real x, real y)
    readonly property int cancelReasonFocusLost: 0
    readonly property int cancelReasonPointerUngrabbed: 1
    readonly property int cancelReasonHidden: 2
    // A drawer modal lives on the window's content item, outside this scope;
    // a hidden surface already cancelled as hidden.
    onActiveFocusChanged: {
        if (applicationSession && !activeFocus && visible && !editorDrawer.modalOwnsFocus())
            applicationSession.cancelGridInput(cancelReasonFocusLost)
    }
    final readonly property App.PianoGrid gridModel: applicationSession ? applicationSession.gridPresenter() : null
    final readonly property App.TrackHeadersPresenter headersModel: applicationSession ? applicationSession.trackHeadersPresenter() : null
    final readonly property App.HeaderVoicePicker headerPickerModel: applicationSession ? applicationSession.headerVoicePickerModel() : null
    final readonly property App.EditorDrawerPresenter drawerPresenter: applicationSession ? applicationSession.drawerPresenter() : null
    final readonly property App.VelocityPage velocityModel: applicationSession ? applicationSession.velocityPage() : null
    property bool velocityPromptRetainingRelease: false
    final readonly property App.OtherEventsBandPresenter otherEventsPresenter: applicationSession ? applicationSession.otherEventsBand() : null
    final readonly property App.PitchBendPresenter pitchBendPresenter: applicationSession ? applicationSession.pitchBendPresenter() : null
    final readonly property App.EventListPresenter eventListPresenter: applicationSession ? applicationSession.eventListPresenter() : null
    final property bool showEvents
    Binding { target: root; property: "showEvents"; value: root.applicationSession?.showsEvents; when: root.applicationSession !== null; restoreMode: Binding.RestoreNone }
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
    final readonly property App.MouseHints hintService: applicationSession ? applicationSession.mouseHintsPresenter() : null
    readonly property bool hintWindowActive: visible && Window.window !== null
                                            && Window.window.visible && Window.window.active
    onHintWindowActiveChanged: {
        if (hintService && (hintWindowActive || (Window.window
                                 && (!Window.window.visible || !Window.window.active))))
            hintService.setWindowActive(hintWindowActive)
    }
    final readonly property bool hintScopeCovered: !applicationSession || !headersModel
        || !gridModel || !rulerMenu || !velocityModel || !pitchBendPresenter
        || headersModel.menuOpen || gridModel.gridMenuKind !== 0 || rulerMenu.isOpen
        || applicationSession.headerVoicePickerOpen || applicationSession.timeSigPromptOpen
        || rulerMenu.insertTimePromptOpen || velocityModel.promptOpen || pitchBendPresenter.isOpen
    function refreshHintScope(): void {
        if (hintService && !hintScopeCovered && hintWindowActive)
            hintService.scopeRefresh()
    }
    onHintScopeCoveredChanged: {
        if (!hintScopeCovered)
            Qt.callLater(refreshHintScope)
    }
    final property real timelineSplitX
    final property real scrollbarBreadth
    final property int noteCount
    final readonly property App.ApplicationSession timeSigHost: applicationSession?.timeSigHost ?? null
    final property point timeSigMenuPosition: Qt.point(0, 0)
    final property point gridMenuPosition: Qt.point(0, 0)
    final property point headerMenuPosition: Qt.point(0, 0)
    final readonly property App.RulerMenuPresenter rulerMenu: applicationSession ? applicationSession.rulerMenuPresenter() : null
    final property point timeSelectionMenuPosition: Qt.point(0, 0)
    property bool timeMenuFocus: false
    property bool insertPromptHadFocus: false
    final property int menuHorizontalPadding
    final property int menuVerticalPadding
    final property int menuGap
    Binding {
        when: root.headersModel !== null && root.gridModel !== null
        restoreMode: Binding.RestoreNone
        root.timelineSplitX: root.headersModel?.trackHeaderWidth + root.gridModel?.keyboardWidth
        root.scrollbarBreadth: root.headersModel?.scrollbarWidth
        root.noteCount: root.gridModel?.renderedNoteCount
    }
    Binding {
        when: root.timeSigHost !== null
        restoreMode: Binding.RestoreNone
        root.menuHorizontalPadding: root.timeSigHost?.layoutSpaces?.two
        root.menuVerticalPadding: root.timeSigHost?.layoutSpaces?.half
        root.menuGap: root.timeSigHost?.layoutSpaces?.one
    }
    final property alias rollStack: rollBandContent.rollStack
    final property alias rollPlot: rollBandContent.rollPlot
    final property alias rollInput: rollBandContent.rollInput
    final property alias rollHint: rollBandContent.rollHint
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
    final property alias eventListHost: rollBandContent.eventListHost
    final property alias eventPage: rollBandContent.eventPage
    final property alias trackHeaders: rollBandContent.trackHeaders
    final property alias rulerInput: rollBandContent.rulerInput
    final property alias menus: surfaceMenus
    final property alias drawerItem: editorDrawer
    final property alias eventBand: otherEventsBand
    final property alias fontMetrics: bodyFontMetrics
    function retargetNoteMenu(x: real, y: real): bool {
        const point = root.rollInput.mapFromItem(null, x, y)
        return root.rollPlot.visible && point.x >= 0 && point.y >= 0
            && point.x < root.rollInput.width && point.y < root.rollInput.height
            && gridModel.retargetNoteMenu(point.x, point.y)
    }


    final property string appliedRevisionText
    Binding { target: root; property: "appliedRevisionText"; value: root.gridModel?.appliedRevisionText; when: root.gridModel !== null; restoreMode: Binding.RestoreNone }
    property bool viewportConfigured: false
    final readonly property bool editorStartupReady: viewportConfigured && visible
        && applicationSession !== null && gridModel !== null && shellRouter !== null
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
    onBaseFontPxChanged: configureViewport()
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
        id: rollBackground
        objectName: "swiftRollBackground"
        anchors.fill: parent
        Binding { target: rollBackground; property: "color"; value: root.gridModel?.palette?.rollBackground; when: root.gridModel !== null; restoreMode: Binding.RestoreNone }
        z: -1
    }

    EditorRollBand {
        id: rollBandContent
        root: parent as EditorSurface
        editorDrawer: root.drawerItem
        otherEventsBand: root.eventBand
    }

    // One scroll row: its frame updates in the same dataChanged sweep as the
    // painted rows the band translates, so content and scroll never lag apart.
    property real scrollX: 0
    property real scrollY: 0
    Instantiator {
        id: scrollCarrier
        model: root.gridModel?.scene.cameraScroll ?? null
        delegate: QtObject {
            required property real x
            required property real y
            onXChanged: applyScrollFrame()
            onYChanged: applyScrollFrame()
            Component.onCompleted: applyScrollFrame()
            function applyScrollFrame(): void {
                root.scrollX = x
                root.scrollY = y
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
        Binding {
            when: root.gridModel !== null
            restoreMode: Binding.RestoreNone
            horizontalScrollBar.minimum: root.gridModel?.cameraMinHScroll
            horizontalScrollBar.maximum: root.gridModel?.cameraMaxHScroll
            horizontalScrollBar.value: root.gridModel?.cameraScrollX
        }
        pageStep: root.rollPlot.width
        singleStep: 1
        accessibleName: qsTr("Timeline")
        Binding {
            when: root.headersModel !== null
            restoreMode: Binding.RestoreNone
            horizontalScrollBar.minimumThumbLength: root.headersModel?.scrollbarMinimumThumbHeight
            root.scrollbarHandleColor: root.headersModel?.scrollbarHandle
            root.scrollbarHandleHoverColor: root.headersModel?.scrollbarHandleHover
        }
        handleColor: root.scrollbarHandleColor
        handleHoverColor: root.scrollbarHandleHoverColor
        visibleWhenNotScrollable: true
        hintService: root.hintService
        hintScopeAllowed: !root.hintScopeCovered
        thumbObjectName: "timelineHorizontalScrollThumb"
        onHintReleased: scenePosition => root.rollHint.receiveRelease(scenePosition)
        onGestureActiveChanged: {
            if (root.gridModel)
                root.gridModel.setScrollbarGrabActive(
                    horizontalScrollBar.gestureActive || (rollScrollBar && rollScrollBar.gestureActive))
        }

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
        Binding {
            when: root.gridModel !== null
            restoreMode: Binding.RestoreNone
            rollScrollBar.maximum: root.gridModel?.cameraMaxVScroll
            rollScrollBar.value: root.gridModel?.cameraScrollY
        }
        pageStep: root.rollPlot.height
        singleStep: 1
        accessibleName: qsTr("Piano roll")
        Binding {
            when: root.headersModel !== null
            restoreMode: Binding.RestoreNone
            rollScrollBar.minimumThumbLength: root.headersModel?.scrollbarMinimumThumbHeight
        }
        handleColor: root.scrollbarHandleColor
        handleHoverColor: root.scrollbarHandleHoverColor
        visibleWhenNotScrollable: true
        externalVisible: !root.showEvents
        hintService: root.hintService
        hintScopeAllowed: !root.hintScopeCovered
        thumbObjectName: "timelineRollScrollThumb"
        onHintReleased: scenePosition => root.rollHint.receiveRelease(scenePosition)
        onGestureActiveChanged: {
            if (root.gridModel)
                root.gridModel.setScrollbarGrabActive(
                    horizontalScrollBar.gestureActive || rollScrollBar.gestureActive)
        }

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
        root: parent as EditorSurface
        rollInput: root.rollInput
        rulerInput: root.rulerInput
        trackHeaders: root.trackHeaders
        bodyFontMetrics: root.fontMetrics
    }
    EditorSurfacePrompts {
        anchors.fill: parent
        z: 11
        root: parent as EditorSurface
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
        drawerPalette: root.gridModel?.palette ?? null
    }
    OtherEventsBand {
        id: otherEventsBand
        objectName: "timelineOtherEventsBand"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: horizontalScrollBar.top
        z: 2
        presenter: root.otherEventsPresenter
        colors: root.gridModel?.palette ?? null
        gridModel: root.gridModel
        overlayRoot: root as EditorSurface
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

        presenter: root.applicationSession ? root.applicationSession.playheadPresenter() : null
        guides: root.applicationSession ? root.applicationSession.playheadGuidesPresenter() : null
        Binding {
            when: root.gridModel !== null
            restoreMode: Binding.RestoreNone
            root.hoverGuideColor: root.gridModel?.palette?.secondaryText
            root.editGuideColor: root.gridModel?.palette?.editCursor
            root.playheadColor: root.gridModel?.palette?.playhead
        }
        hoverGuideColor: root.hoverGuideColor
        editGuideColor: root.editGuideColor
        playheadColor: root.playheadColor
        rollBodyVisible: !root.showEvents
        rollPlotRect: Qt.rect(root.rollStack.x + root.rollPlot.x, root.rollPlot.y,
                              root.rollPlot.width, root.rollPlot.height)
        drawerRect: Qt.rect(editorDrawer.x, editorDrawer.y,
                            editorDrawer.width, editorDrawer.height)
        velocitySection: root.drawerPresenter?.velocitySection ?? null
        voiceChangesSection: root.drawerPresenter?.voiceChangesSection ?? null
        automationSection: root.drawerPresenter?.automationSection ?? null
    }

    function configureViewport(): void {
        if (!root.gridModel || !root.headersModel || !root.drawerPresenter || !root.otherEventsPresenter
                || root.baseFontPx <= 0)
            return
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

    function deliverWheel(event: WheelEvent, overGutter: bool): void {
        root.gridModel.handleWheel(event.angleDelta.x, event.angleDelta.y,
                                   event.pixelDelta.x, event.pixelDelta.y,
                                   event.modifiers, event.phase, overGutter,
                                   event.x, event.y)
        event.accepted = true
    }

    Component.onCompleted: {
        if (hintService && hintWindowActive)
            hintService.setWindowActive(true)
        if (root.eventListPresenter)
            root.eventListPresenter.setVisible(root.showEvents)
        root.eventListHost.visible = root.showEvents
        root.eventPage.active = root.showEvents
        configureViewport()
    }
}
