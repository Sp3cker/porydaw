import QtQuick
import Porydaw.Ui

Item {
    id: promptHost
    required property Item root
    required property Item rollInput
    required property Item rulerInput
    required property Item rollPlot
    required property Item trackHeaders
    required property Item editorDrawer
    required property var bodyFontMetrics
    Connections {
        target: root.applicationSession
        function onTimeSigPromptOpenChanged() {
            if (!root.applicationSession.timeSigPromptOpen)
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: root.rulerMenu
        function onInsertTimePromptOpenChanged() {
            if (root.rulerMenu.insertTimePromptOpen) {
                root.insertPromptHadFocus = true
            } else if (root.insertPromptHadFocus) {
                root.insertPromptHadFocus = false
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
            }
        }
    }
    Loader {
        id: headerVoicePickerLoader
        objectName: "headerVoicePickerLoader"
        anchors.fill: parent
        z: 14
        active: root.applicationSession.headerVoicePickerOpen
        Connections {
            target: root.timeSigHost
            function onAddTrackVoiceRequested() {
                if (root.timeSigHost.songTabs.selectedId === root.applicationSession.tabId
                        && root.headersModel.menuOpen)
                    root.headersModel.dismissHeaderMenu()
            }
        }
        Connections {
            target: root.applicationSession
            function onHeaderVoicePickerOpenChanged() {
                if (!root.applicationSession.headerVoicePickerOpen)
                    Qt.callLater(function() {
                        if (!root.applicationSession.headerVoicePickerOpen && trackHeaders.bandVisible)
                            trackHeaders.restoreHeaderFocus()
                    })
            }
        }
        sourceComponent: Component {
            VoicePickerPrompt {
                model: root.headerPickerModel
                promptPalette: root.gridModel.palette
                hintService: root.hintService
                showing: true
            }
        }
    }

    Loader {
        id: timeSigPromptLoader
        anchors.fill: parent
        z: 11
        active: root.applicationSession.timeSigPromptOpen
        sourceComponent: Component {
            Item {
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.timeSigHost.cancelTimeSigPrompt()
                }
                TimeSignaturePrompt {
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    bridge: root.timeSigHost
                }
            }
        }
    }
    Loader {
        id: insertTimePromptLoader
        anchors.fill: parent
        z: 11
        active: root.rulerMenu && root.rulerMenu.insertTimePromptOpen
        sourceComponent: Component {
            Item {
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.rulerMenu.cancelInsertTimePrompt()
                }
                InsertTimePrompt {
                    anchors.centerIn: parent
                    width: implicitWidth
                    height: implicitHeight
                    bridge: root.rulerMenu
                    promptPalette: root.gridModel.palette
                }
            }
        }
    }
    Loader {
        id: velocityPromptLoader
        anchors.fill: parent
        z: 13
        active: root.velocityModel && (root.velocityModel.promptOpen
                                       || root.velocityPromptRetainingRelease)
        sourceComponent: Component {
            VelocityPrompt {
                anchors.fill: parent
                model: root.velocityModel
                promptPalette: root.gridModel.palette
                focusOrigin: rollInput
                hintService: root.hintService
                onConsumingOutsidePressChanged: {
                    root.velocityPromptRetainingRelease = consumingOutsidePress
                }
            }
        }
    }

    Loader {
        id: pitchBendPopupLoader
        anchors.fill: parent
        z: 12
        active: root.pitchBendPresenter.isOpen
        visible: active
        enabled: active
        sourceComponent: Component {
            Item {
                focus: true
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: (mouse) => {
                        const rollPoint = rollInput.mapFromItem(root, mouse.x, mouse.y)
                        const overRoll = rollPlot.visible && rollPoint.x >= 0 && rollPoint.y >= 0
                            && rollPoint.x < rollInput.width && rollPoint.y < rollInput.height
                        const hit = overRoll && mouse.button === Qt.LeftButton
                            && root.gridModel.focusNoteUnderCursor(rollPoint.x, rollPoint.y)
                        root.pitchBendPresenter.cancelAndClose()
                        mouse.accepted = hit
                        if (hit)
                            rollInput.forceActiveFocus(Qt.MouseFocusReason)
                    }
                    onWheel: (wheel) => wheel.accepted = true
                }
                PitchBendPopup {
                    id: pitchBendPopup
                    bridge: root.pitchBendPresenter
                    fallbackFont: root.bodyFont
                    width: implicitWidth
                    height: implicitHeight
                    x: Math.max(0, Math.min(
                        root.timelineSplitX + root.pitchBendPresenter.anchorX
                            + root.pitchBendPresenter.anchorWidth / 2 - width / 2,
                        parent.width - width))
                    y: {
                        const below = root.gridModel.rulerHeight
                            + root.pitchBendPresenter.anchorY
                            + root.pitchBendPresenter.anchorHeight
                            + bodyFontMetrics.height / 3
                        const above = root.gridModel.rulerHeight
                            + root.pitchBendPresenter.anchorY - height
                            - bodyFontMetrics.height / 3
                        return Math.max(0, Math.min(
                            below + height <= editorDrawer.y ? below : above,
                            parent.height - height))
                    }
                    Component.onCompleted: {
                        root.pitchBendPresenter.configure(
                            root.baseFontPx,
                            bodyFontMetrics.lineSpacing,
                            root.gridModel.devicePixelRatio)
                        pitchBendPopup.focusInitialGraph()
                    }
                    onFallbackFontChanged: root.pitchBendPresenter.configure(
                        root.baseFontPx,
                        bodyFontMetrics.lineSpacing,
                        root.gridModel.devicePixelRatio)
                }
                Keys.onEscapePressed: (event) => {
                    root.pitchBendPresenter.cancelAndClose()
                    rollInput.forceActiveFocus(Qt.OtherFocusReason)
                    event.accepted = true
                }
            }
        }
    }
}
