pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

Item {
    id: promptHost
    final required property EditorSurface root
    final required property MouseArea rollInput
    final required property MouseArea rulerInput
    final required property Item rollPlot
    final required property TrackHeaderBand trackHeaders
    final required property EditorDrawer editorDrawer
    final required property FontMetrics bodyFontMetrics
    Connections {
        target: promptHost.root.applicationSession
        function onTimeSigPromptOpenChanged(): void {
            if (!promptHost.root.applicationSession.timeSigPromptOpen)
                promptHost.rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: promptHost.root.rulerMenu
        function onInsertTimePromptOpenChanged(): void {
            if (promptHost.root.rulerMenu.insertTimePromptOpen) {
                promptHost.root.insertPromptHadFocus = true
            } else if (promptHost.root.insertPromptHadFocus) {
                promptHost.root.insertPromptHadFocus = false
                promptHost.rulerInput.forceActiveFocus(Qt.OtherFocusReason)
            }
        }
    }
    Loader {
        id: headerVoicePickerLoader
        objectName: "headerVoicePickerLoader"
        anchors.fill: parent
        z: 14
        active: promptHost.root.applicationSession !== null && promptHost.root.headerPickerModel !== null
                && promptHost.root.applicationSession.headerVoicePickerOpen
        Connections {
            target: promptHost.root.timeSigHost
            function onAddTrackVoiceRequested(): void {
                if (promptHost.root.timeSigHost.songTabs.selectedId === promptHost.root.applicationSession.tabId
                        && promptHost.root.headersModel.menuOpen)
                    promptHost.root.headersModel.dismissHeaderMenu()
            }
        }
        Connections {
            target: promptHost.root.applicationSession
            function onHeaderVoicePickerOpenChanged(): void {
                if (!promptHost.root.applicationSession.headerVoicePickerOpen)
                    Qt.callLater(function() {
                        if (promptHost.root.applicationSession
                                && !promptHost.root.applicationSession.headerVoicePickerOpen && promptHost.trackHeaders.bandVisible)
                            promptHost.trackHeaders.restoreHeaderFocus()
                    })
            }
        }
        sourceComponent: Component {
            VoicePickerPrompt {
                model: promptHost.root.headerPickerModel
                hintService: promptHost.root.hintService
                showing: true
            }
        }
    }

    Loader {
        id: timeSigPromptLoader
        anchors.fill: parent
        z: 11
        active: promptHost.root.applicationSession !== null && promptHost.root.timeSigHost !== null
                && promptHost.root.applicationSession.timeSigPromptOpen
        sourceComponent: Component {
            Item {
                MouseArea {
                    anchors.fill: parent
                    onPressed: promptHost.root.timeSigHost.cancelTimeSigPrompt()
                }
                TimeSignaturePrompt {
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    bridge: promptHost.root.timeSigHost
                }
            }
        }
    }
    Loader {
        id: insertTimePromptLoader
        anchors.fill: parent
        z: 11
        active: promptHost.root.rulerMenu && promptHost.root.rulerMenu.insertTimePromptOpen
        sourceComponent: Component {
            Item {
                MouseArea {
                    anchors.fill: parent
                    onPressed: promptHost.root.rulerMenu.cancelInsertTimePrompt()
                }
                InsertTimePrompt {
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    bridge: promptHost.root.rulerMenu
                }
            }
        }
    }
    Loader {
        id: velocityPromptLoader
        anchors.fill: parent
        z: 13
        active: promptHost.root.velocityModel && (promptHost.root.velocityModel.promptOpen
                                       || promptHost.root.velocityPromptRetainingRelease)
        sourceComponent: Component {
            VelocityPrompt {
                anchors.fill: parent
                model: promptHost.root.velocityModel
                focusOrigin: promptHost.rollInput
                hintService: promptHost.root.hintService
                onConsumingOutsidePressChanged: {
                    promptHost.root.velocityPromptRetainingRelease = consumingOutsidePress
                }
            }
        }
    }

    Loader {
        id: pitchBendPopupLoader
        anchors.fill: parent
        z: 12
        active: promptHost.root.pitchBendPresenter !== null && promptHost.root.gridModel !== null
                && promptHost.root.pitchBendPresenter.isOpen
        visible: active
        enabled: active
        sourceComponent: Component {
            Item {
                focus: true
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: (mouse) => {
                        const rollPoint = promptHost.rollInput.mapFromItem(promptHost.root, mouse.x, mouse.y)
                        const overRoll = promptHost.rollPlot.visible && rollPoint.x >= 0 && rollPoint.y >= 0
                            && rollPoint.x < promptHost.rollInput.width && rollPoint.y < promptHost.rollInput.height
                        const hit = overRoll && mouse.button === Qt.LeftButton
                            && promptHost.root.gridModel.focusNoteUnderCursor(rollPoint.x, rollPoint.y)
                        promptHost.root.pitchBendPresenter.cancelAndClose()
                        mouse.accepted = hit
                        if (hit)
                            promptHost.rollInput.forceActiveFocus(Qt.MouseFocusReason)
                    }
                    onWheel: (wheel) => wheel.accepted = true
                }
                PitchBendPopup {
                    id: pitchBendPopup
                    bridge: promptHost.root.pitchBendPresenter
                    fallbackFont: promptHost.root.bodyFont
                    width: implicitWidth
                    height: implicitHeight
                    x: Math.max(0, Math.min(
                        promptHost.root.timelineSplitX + promptHost.root.pitchBendPresenter.anchorX
                            + promptHost.root.pitchBendPresenter.anchorWidth / 2 - width / 2,
                        parent.width - width))
                    y: {
                        const below = promptHost.root.gridModel.rulerHeight
                            + promptHost.root.pitchBendPresenter.anchorY
                            + promptHost.root.pitchBendPresenter.anchorHeight
                            + promptHost.bodyFontMetrics.height / 3
                        const above = promptHost.root.gridModel.rulerHeight
                            + promptHost.root.pitchBendPresenter.anchorY - height
                            - promptHost.bodyFontMetrics.height / 3
                        return Math.max(0, Math.min(
                            below + height <= promptHost.editorDrawer.y ? below : above,
                            parent.height - height))
                    }
                    Component.onCompleted: {
                        promptHost.root.pitchBendPresenter.configure(
                            promptHost.root.baseFontPx,
                            promptHost.bodyFontMetrics.lineSpacing,
                            promptHost.root.gridModel.devicePixelRatio)
                        pitchBendPopup.focusInitialGraph()
                    }
                    onFallbackFontChanged: {
                        if (promptHost.root.pitchBendPresenter && promptHost.root.gridModel)
                            promptHost.root.pitchBendPresenter.configure(
                                promptHost.root.baseFontPx,
                                promptHost.bodyFontMetrics.lineSpacing,
                                promptHost.root.gridModel.devicePixelRatio)
                    }
                }
                Keys.onEscapePressed: (event) => {
                    promptHost.root.pitchBendPresenter.cancelAndClose()
                    promptHost.rollInput.forceActiveFocus(Qt.OtherFocusReason)
                    event.accepted = true
                }
            }
        }
    }
}
