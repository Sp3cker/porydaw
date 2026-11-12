pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Porydaw.Ui
import PorydawApp as App

DrawerLanePage {
    id: page
    objectName: "effectOutputPage"

    property App.MouseHints hintService: null
    property bool hintScopeAllowed: true
    property Item modalHost: null
    readonly property App.EffectOutputPage model: page.applicationSession.songOpen
        ? page.applicationSession.effectOutputPage() : null
    readonly property App.EffectOutputPage pageModel: page.model
    readonly property App.GridPalette gridPalette: page.applicationSession.grid.palette
    readonly property real spacing: page.baseFontPx / 2
    property real measuredPlotHeight: 0
    enabled: page.pageModel !== null

    function pushBodyFacts(): void {
        if (!page.pageModel)
            return
        page.pageModel.configureBody(page.plotWidth, page.measuredPlotHeight, page.plotOrigin,
            page.Screen.devicePixelRatio, page.baseFontPx, Application.styleHints.startDragDistance)
    }

    function syncFocus(): void {
        if (page.pageModel)
            page.pageModel.setBodyFocused(page.activeFocus && page.visible)
    }

    onModelChanged: {
        page.pushBodyFacts()
        page.syncFocus()
    }
    onBodyFactsChanged: page.pushBodyFacts()
    onActiveFocusChanged: {
        page.syncFocus()
        if (!page.activeFocus && page.pageModel)
            page.pageModel.cancelSectionInteraction()
    }
    onVisibleChanged: {
        page.syncFocus()
        if (!page.visible && page.pageModel)
            page.pageModel.cancelSectionInteraction()
    }
    Component.onCompleted: {
        page.pushBodyFacts()
        page.syncFocus()
    }
    Component.onDestruction: {
        if (page.pageModel) {
            page.pageModel.setBodyFocused(false)
            page.pageModel.cancelSectionInteraction()
        }
    }
    Keys.onEscapePressed: event => event.accepted = page.pageModel !== null && page.pageModel.handleEscape()


    Rectangle {
        anchors.fill: parent
        color: page.gridPalette.windowBackground
    }

    Loader {
        anchors.fill: parent
        active: page.pageModel !== null
        sourceComponent: bodyComponent
    }

    Component {
        id: bodyComponent
    Flickable {
        id: contentView
        objectName: "effectOutputBodyScroll"
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        function reveal(top: real, itemHeight: real): void {
            const bottom = top + itemHeight
            if (top < contentY)
                contentY = top
            else if (bottom > contentY + height)
                contentY = Math.min(top, bottom - height)
        }
    component Caption: Text {
        color: page.gridPalette.windowText
        font: page.pageModel.bodyFont
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    component Action: PromptAction {
        id: action
        appearance: page.pageModel.promptStyle
        property Flickable scrollHost: controlStrip
        onActiveFocusChanged: {
            if (activeFocus) {
                const left = action.mapToItem(action.scrollHost.contentItem, 0, 0).x
                const maximum = Math.max(0, action.scrollHost.contentWidth - action.scrollHost.width)
                const offset = Math.min(left, Math.max(action.scrollHost.contentX,
                    left + action.width - action.scrollHost.width))
                action.scrollHost.contentX = Math.max(0, Math.min(maximum, offset))
                contentView.reveal(action.mapToItem(contentView.contentItem, 0, 0).y, action.height)
            }
        }
    }

        Item {
            id: body
            width: contentView.width
            height: Math.max(contentView.height, header.height + Math.max(page.baseFontPx * 8,
                emptyState.visible ? emptyState.height + 2 * page.spacing : 0))

            Column {
                id: header
                objectName: "effectOutputHeader"
                width: body.width
                spacing: page.spacing

                Flickable {
                    id: controlStrip
                    objectName: "effectOutputControls"
                    width: header.width
                    height: controls.height + page.baseFontPx
                    contentWidth: controls.width
                    contentHeight: controls.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    ScrollBar.horizontal: ScrollBar {}

                    Row {
                        id: controls
                        spacing: page.spacing

                        Action {
                            id: liveAction
                            objectName: "effectOutputLive"
                            property bool checked: page.pageModel.live
                            text: liveAction.checked ? qsTr("Live ✓") : qsTr("Live")
                            Accessible.checkable: true
                            Accessible.checked: liveAction.checked
                            enabled: page.pageModel.canOperate
                            onActivated: page.pageModel.setLive(!page.pageModel.live)
                        }
                        Action {
                            objectName: "effectOutputRender"
                            text: qsTr("Render")
                            enabled: page.pageModel.canRender
                            onActivated: page.pageModel.renderOutput()
                        }
                        Action {
                            objectName: "effectOutputCancelRender"
                            text: qsTr("Cancel Render")
                            visible: page.pageModel.rendering
                            enabled: page.pageModel.rendering
                            onActivated: page.pageModel.cancelRender()
                        }
                        Action {
                            objectName: "effectOutputGrabPlayed"
                            text: qsTr("Grab played")
                            enabled: page.pageModel.canGrab
                            onActivated: page.pageModel.grabPlayed()
                        }
                        Action {
                            objectName: "effectOutputOpenEditor"
                            text: qsTr("Open Editor")
                            enabled: page.pageModel.canOpenEditor
                            onActivated: page.pageModel.openEditor()
                        }
                        Action {
                            objectName: "effectOutputReload"
                            text: qsTr("Reload Plug-in")
                            visible: page.pageModel.canReload
                            enabled: page.pageModel.canReload
                            onActivated: page.pageModel.reloadPlugin()
                        }
                        Action {
                            objectName: "effectOutputCopy"
                            text: qsTr("Copy")
                            enabled: page.pageModel.canCopy
                            onActivated: page.pageModel.copyOutput()
                        }
                        Action {
                            objectName: "effectOutputClear"
                            text: qsTr("Clear")
                            enabled: page.pageModel.canClear
                            onActivated: page.pageModel.clearOutput()
                        }
                    }
                }

                Rectangle {
                    objectName: "effectOutputProgress"
                    width: header.width
                    height: page.baseFontPx / 2
                    visible: page.pageModel.rendering
                    color: page.gridPalette.inputBackground
                    Accessible.role: Accessible.ProgressBar
                    Accessible.name: qsTr("Render progress")
                    Accessible.description: qsTr("%1 percent").arg(Math.round(page.pageModel.progress * 100))
                    Rectangle {
                        width: parent.width * page.pageModel.progress
                        height: parent.height
                        color: page.gridPalette.selectionEdge
                    }
                }
                Caption {
                    objectName: "effectOutputStatus"
                    width: header.width
                    text: page.pageModel.status
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                }
                Caption {
                    objectName: "effectOutputDiagnostics"
                    width: header.width
                    text: page.pageModel.diagnostics
                    color: page.gridPalette.secondaryText
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                }
                Caption {
                    objectName: "effectOutputOrigin"
                    width: header.width
                    text: page.pageModel.originLabel
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                }
                onHeightChanged: page.pushBodyFacts()
            }

            Item {
                id: gutter
                objectName: "effectOutputPitchAxis"
                y: header.height
                width: Math.min(page.plotOrigin, body.width)
                height: plot.height
                clip: true
                Caption {
                    anchors.top: parent.top
                    width: parent.width
                    text: page.pageModel.noteCount > 0 ? "%1".arg(page.pageModel.maximumPitch) : ""
                    horizontalAlignment: Text.AlignRight
                    rightPadding: page.spacing
                }
                Caption {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    text: page.pageModel.noteCount > 0 ? "%1".arg(page.pageModel.minimumPitch) : ""
                    horizontalAlignment: Text.AlignRight
                    rightPadding: page.spacing
                }
                Accessible.role: Accessible.Column
                Accessible.name: qsTr("Output pitch range %1").arg(page.pageModel.pitchLabel)
            }

            Item {
                id: plot
                objectName: "effectOutputPlot"
                x: page.plotOrigin
                y: header.height
                width: page.plotWidth
                height: Math.max(0, body.height - header.height)
                clip: true
                activeFocusOnTab: true
                onHeightChanged: {
                    page.measuredPlotHeight = plot.height
                    page.pushBodyFacts()
                }
                Component.onCompleted: {
                    page.measuredPlotHeight = plot.height
                    page.pushBodyFacts()
                }
                // Pointer focus must not scroll the plot underneath the press.
                onActiveFocusChanged: {
                    if (activeFocus && !input.pressed)
                        contentView.reveal(plot.mapToItem(contentView.contentItem, 0, 0).y, plot.height)
                }
                Accessible.role: Accessible.Pane
                Accessible.name: qsTr("Effect Output")
                Accessible.description: qsTr("%1 notes, %2 selected").arg(page.pageModel.noteCount).arg(page.pageModel.selectedCount)

                DisplayList {
                    objectName: "effectOutputNotes"
                    anchors.fill: parent
                    source: page.pageModel
                    list: 0
                    revision: page.pageModel ? page.pageModel.displayRevision : 0
                }

                MouseArea {
                    id: input
                    objectName: "effectOutputInput"
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    onPressed: mouse => {
                        plot.forceActiveFocus(Qt.MouseFocusReason)
                        mouse.accepted = page.pageModel.pointerPress(mouse.x, mouse.y, mouse.modifiers)
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            page.pageModel.pointerMove(mouse.x, mouse.y)
                    }
                    onReleased: mouse => {
                        plotHint.settleRelease(input.mapToItem(null, mouse.x, mouse.y))
                        page.pageModel.pointerRelease(mouse.x, mouse.y)
                    }
                    onCanceled: {
                        plotHint.settleRelease(plotHint.point.scenePosition)
                        if (page.pageModel)
                            page.pageModel.cancelSectionInteraction()
                    }
                }

                HoverHint {
                    id: plotHint
                    source: plot
                    hintService: page.hintService
                    scopeAllowed: page.hintScopeAllowed
                    gestureOwning: input.pressed
                    profile: HintProfiles.NativeExtendedSelection
                }
            }

            Column {
                id: emptyState
                objectName: "effectOutputEmptyState"
                x: page.spacing
                y: header.height + page.spacing
                width: Math.max(0, body.width - 2 * page.spacing)
                spacing: page.spacing
                visible: page.pageModel.noteCount === 0
                Caption {
                    objectName: "effectOutputEmptyText"
                    width: emptyState.width
                    text: page.pageModel.emptyText
                    wrapMode: Text.Wrap
                }
                Flickable {
                    id: emptyActions
                    width: emptyState.width
                    height: addAction.height + page.baseFontPx
                    contentWidth: addAction.width
                    contentHeight: addAction.height
                    visible: !page.pageModel.hasEffect
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    ScrollBar.horizontal: ScrollBar {}
                    Action {
                        id: addAction
                        objectName: "effectOutputAddEffect"
                        text: qsTr("Add MIDI Effect...")
                        scrollHost: emptyActions
                        enabled: page.pageModel.canAddEffect
                        onActivated: page.pageModel.addEffect()
                    }
                }
            }
        }
    }
    }
}
