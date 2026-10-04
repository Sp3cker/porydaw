pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui
import PorydawApp as App

Item {
    id: root

    final required property App.TrackHeadersPresenter headersModel
    final required property App.TrackHeadersPresenter appearance
    final required property font controlFont
    final required property FontMetrics normalMetrics
    final required property FontMetrics boldMetrics
    final required property real rowAreaWidth
    final readonly property int rowCount: trackHeaderRows.count

    width: rowAreaWidth
    height: parent.height
    clip: true

    function itemAt(index: int): Item {
        return trackHeaderRows.itemAt(index)
    }

    component TrackHeaderToggle: Item {
        id: toggle

        required property App.SceneRect controlRect
        required property int track
        required property string label
        required property string accessibleName
        required property bool checked
        required property bool hovered
        required property bool pressed
        required property bool solo
        objectName: "timelineHeader" + (solo ? "Solo" : "Mute") + "_" + track

        Binding {
            when: toggle.controlRect !== null
            restoreMode: Binding.RestoreNone
            toggle.x: toggle.controlRect?.x
            toggle.y: toggle.controlRect?.y
            toggle.width: toggle.controlRect?.width
            toggle.height: toggle.controlRect?.height
        }
        activeFocusOnTab: true
        property color stateBackground
        property color stateText
        Binding {
            when: root.appearance !== null
            restoreMode: Binding.RestoreNone
            toggle.stateBackground: toggle.pressed
                ? toggle.solo ? root.appearance?.soloCheckedBackground : root.appearance?.buttonPressedBackground
                : toggle.checked
                  ? toggle.solo ? root.appearance?.soloCheckedBackground : root.appearance?.muteCheckedBackground
                  : toggle.hovered ? root.appearance?.buttonHoverBackground : root.appearance?.buttonBackground
            toggle.stateText: toggle.pressed
                ? toggle.solo ? root.appearance?.soloCheckedText : root.appearance?.buttonPressedText
                : toggle.checked
                  ? toggle.solo ? root.appearance?.soloCheckedText : root.appearance?.muteCheckedText
                  : toggle.hovered ? root.appearance?.buttonHoverText : root.appearance?.buttonText
        }

        function activate(): void {
            if (solo)
                root.headersModel.activateSolo(track)
            else
                root.headersModel.activateMute(track)
        }

        function activateFromKeyboard(event: KeyEvent): void {
            activate()
            event.accepted = true
        }

        Rectangle {
            id: toggleBackground
            anchors.fill: parent
            color: toggle.stateBackground
            Binding {
                when: root.appearance !== null
                restoreMode: Binding.RestoreNone
                toggleBackground.border.color: root.appearance?.buttonOutline
            }
            border.width: 1
        }

        Text {
            anchors.fill: parent
            color: toggle.stateText
            font: root.controlFont
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: toggle.label
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideNone
            maximumLineCount: 1
        }

        Keys.onReturnPressed: (event) => toggle.activateFromKeyboard(event)
        Keys.onEnterPressed: (event) => toggle.activateFromKeyboard(event)

        Accessible.role: Accessible.Button
        Accessible.name: accessibleName
        Accessible.focusable: true
        Accessible.onPressAction: toggle.activate()
    }

    Item {
        id: translatedRows

        width: parent.width
        Binding {
            when: root.headersModel !== null
            restoreMode: Binding.RestoreNone
            translatedRows.y: -root.headersModel?.scrollY
            translatedRows.height: root.headersModel?.contentHeight
        }
        z: 2

        Repeater {
            id: trackHeaderRows

            objectName: "timelineTrackHeaderRows"
            model: root.headersModel?.rows ?? null

            delegate: Item {
                id: trackHeaderRow

                required property int index
                required property bool isAddTrack
                required property int track
                required property string title
                required property string subtitle
                required property App.SceneRect titleRect
                required property App.SceneRect subtitleRect
                required property real selectedTitleOffsetX
                required property real selectedTitleOffsetY
                required property color baseColor
                required property color overlayColor
                required property color titleColor
                required property color subtitleColor
                required property font titleFont
                required property font subtitleFont
                required property bool titleBold
                required property bool muteChecked
                required property bool soloChecked
                required property bool muteHovered
                required property bool mutePressed
                required property bool soloHovered
                required property bool soloPressed
                required property bool addHovered
                required property bool addPressed
                required property color activityDimColor
                required property color activityActiveColor
                required property real activityLeftHeight
                required property real activityRightHeight

                y: index * root.headersModel.rowHeight
                width: translatedRows.width
                height: root.headersModel.rowHeight

                property bool complete: false

                property real titleWidth
                Binding {
                    target: trackHeaderRow
                    property: "titleWidth"
                    value: trackHeaderRow.titleRect?.width
                    when: trackHeaderRow.titleRect !== null
                    restoreMode: Binding.RestoreNone
                }
                function publishSelectedTitleOffset(): void {
                    if (!complete || isAddTrack || !titleBold || !titleRect || !root.headersModel)
                        return
                    const label = root.boldMetrics.elidedText(title, Text.ElideRight,
                                                             titleRect.width)
                    const normal = root.normalMetrics.tightBoundingRect(label)
                    const bold = root.boldMetrics.tightBoundingRect(label)
                    root.headersModel.setSelectedTitleOffset(track,
                        normal.x + normal.width / 2 - bold.x - bold.width / 2,
                        normal.y + normal.height / 2 - bold.y - bold.height / 2)
                }

                onTitleChanged: publishSelectedTitleOffset()
                onTitleBoldChanged: publishSelectedTitleOffset()
                onTitleWidthChanged: publishSelectedTitleOffset()
                onTitleFontChanged: publishSelectedTitleOffset()
                onTrackChanged: publishSelectedTitleOffset()
                Component.onCompleted: {
                    complete = true
                    publishSelectedTitleOffset()
                }

                Rectangle {
                    anchors.fill: parent
                    color: trackHeaderRow.baseColor
                }

                Rectangle {
                    anchors.fill: parent
                    color: trackHeaderRow.overlayColor
                    visible: trackHeaderRow.overlayColor.a > 0
                }

                Item {
                    objectName: "timelineHeaderActivity_" + trackHeaderRow.track
                    width: root.headersModel.activityWidth
                    height: Math.max(0, trackHeaderRow.height - root.headersModel.separatorWidth)
                    visible: !trackHeaderRow.isAddTrack

                    Rectangle {
                        anchors.fill: parent
                        color: trackHeaderRow.activityDimColor
                    }

                    Rectangle {
                        width: parent.width / 2
                        height: Math.max(0, Math.min(parent.height,
                                                    trackHeaderRow.activityLeftHeight))
                        anchors.bottom: parent.bottom
                        color: trackHeaderRow.activityActiveColor
                    }

                    Rectangle {
                        x: parent.width / 2
                        width: parent.width - x
                        height: Math.max(0, Math.min(parent.height,
                                                    trackHeaderRow.activityRightHeight))
                        anchors.bottom: parent.bottom
                        color: trackHeaderRow.activityActiveColor
                    }
                }

                Rectangle {
                    y: Math.max(0, trackHeaderRow.height - root.headersModel.separatorWidth)
                    width: parent.width
                    height: root.headersModel.separatorWidth
                    color: root.appearance.buttonOutline
                }

                Text {
                    id: titleLabel
                    Binding {
                        when: trackHeaderRow.titleRect !== null
                        restoreMode: Binding.RestoreNone
                        titleLabel.x: trackHeaderRow.titleRect?.x + trackHeaderRow.selectedTitleOffsetX
                        titleLabel.y: trackHeaderRow.titleRect?.y + trackHeaderRow.selectedTitleOffsetY
                        titleLabel.width: trackHeaderRow.titleRect?.width
                        titleLabel.height: trackHeaderRow.titleRect?.height
                    }
                    visible: !trackHeaderRow.isAddTrack
                    clip: contentWidth > width || contentHeight > height
                    color: trackHeaderRow.titleColor
                    font: trackHeaderRow.titleFont
                    text: trackHeaderRow.title
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }

                // The subtitle remains a voice hit target, not a button fill.
                Text {
                    id: subtitleLabel
                    Binding {
                        when: trackHeaderRow.subtitleRect !== null
                        restoreMode: Binding.RestoreNone
                        subtitleLabel.x: trackHeaderRow.subtitleRect?.x
                        subtitleLabel.y: trackHeaderRow.subtitleRect?.y
                        subtitleLabel.width: trackHeaderRow.subtitleRect?.width
                        subtitleLabel.height: trackHeaderRow.subtitleRect?.height
                    }
                    visible: !trackHeaderRow.isAddTrack
                    clip: contentWidth > width || contentHeight > height
                    color: trackHeaderRow.subtitleColor
                    font: trackHeaderRow.subtitleFont
                    text: trackHeaderRow.subtitle
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }

                TrackHeaderToggle {
                    visible: !trackHeaderRow.isAddTrack
                    controlRect: root.headersModel?.muteButtonRect ?? null
                    track: trackHeaderRow.track
                    label: qsTr("M")
                    accessibleName: qsTr("Mute")
                    checked: trackHeaderRow.muteChecked
                    hovered: trackHeaderRow.muteHovered
                    pressed: trackHeaderRow.mutePressed
                    solo: false
                }

                TrackHeaderToggle {
                    visible: !trackHeaderRow.isAddTrack
                    controlRect: root.headersModel?.soloButtonRect ?? null
                    track: trackHeaderRow.track
                    label: qsTr("S")
                    accessibleName: qsTr("Solo")
                    checked: trackHeaderRow.soloChecked
                    hovered: trackHeaderRow.soloHovered
                    pressed: trackHeaderRow.soloPressed
                    solo: true
                }

                Item {
                    id: addTrackRow

                    anchors.fill: parent
                    visible: trackHeaderRow.isAddTrack
                    activeFocusOnTab: true

                    function activate(): void {
                        root.headersModel.activateAddTrack()
                    }

                    function activateFromKeyboard(event: KeyEvent): void {
                        activate()
                        event.accepted = true
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: trackHeaderRow.addPressed
                               ? root.appearance.buttonPressedBackground
                               : trackHeaderRow.addHovered
                                 ? root.appearance.buttonHoverBackground
                                 : root.appearance.buttonBackground
                        border.color: root.appearance.buttonOutline
                        border.width: 1
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        color: trackHeaderRow.addPressed
                               ? root.appearance.buttonPressedText
                               : trackHeaderRow.addHovered
                                 ? root.appearance.buttonHoverText
                                 : root.appearance.buttonText
                        font: root.controlFont
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: trackHeaderRow.title
                        textFormat: Text.PlainText
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Keys.onReturnPressed: (event) => addTrackRow.activateFromKeyboard(event)
                    Keys.onEnterPressed: (event) => addTrackRow.activateFromKeyboard(event)

                    Accessible.role: Accessible.Button
                    Accessible.name: trackHeaderRow.title
                    Accessible.description: qsTr("Add a track")
                    Accessible.focusable: true
                    Accessible.onPressAction: addTrackRow.activate()
                }
            }
        }
    }
}
