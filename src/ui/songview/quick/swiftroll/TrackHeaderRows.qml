pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui

Item {
    id: root

    required property var headersModel
    required property var appearance
    required property font controlFont
    required property var normalMetrics
    required property var boldMetrics
    required property real rowAreaWidth
    readonly property int rowCount: trackHeaderRows.count

    width: rowAreaWidth
    height: parent.height
    clip: true

    function itemAt(index: int): Item {
        return trackHeaderRows.itemAt(index)
    }

    component TrackHeaderToggle: Item {
        id: toggle

        required property var controlRect
        required property int track
        required property string label
        required property string accessibleName
        required property bool checked
        required property bool hovered
        required property bool pressed
        required property bool solo
        objectName: "timelineHeader" + (solo ? "Solo" : "Mute") + "_" + track

        x: controlRect.x
        y: controlRect.y
        width: controlRect.width
        height: controlRect.height
        activeFocusOnTab: true
        readonly property color stateBackground: pressed
                                              ? solo ? root.appearance.soloCheckedBackground
                                                     : root.appearance.buttonPressedBackground
                                              : checked
                                                ? solo ? root.appearance.soloCheckedBackground
                                                       : root.appearance.muteCheckedBackground
                                                : hovered ? root.appearance.buttonHoverBackground
                                                          : root.appearance.buttonBackground
        readonly property color stateText: pressed
                                        ? solo ? root.appearance.soloCheckedText
                                               : root.appearance.buttonPressedText
                                        : checked
                                          ? solo ? root.appearance.soloCheckedText
                                                 : root.appearance.muteCheckedText
                                          : hovered ? root.appearance.buttonHoverText
                                                    : root.appearance.buttonText

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
            anchors.fill: parent
            color: toggle.stateBackground
            border.color: root.appearance.buttonOutline
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

        y: -root.headersModel.scrollY
        width: parent.width
        height: root.headersModel.contentHeight
        z: 2

        Repeater {
            id: trackHeaderRows

            objectName: "timelineTrackHeaderRows"
            model: root.headersModel.rows

            delegate: Item {
                id: trackHeaderRow

                required property int index
                required property bool isAddTrack
                required property int track
                required property string title
                required property string subtitle
                required property var titleRect
                required property var subtitleRect
                required property var selectedTitleOffset
                required property color baseColor
                required property color overlayColor
                required property color titleColor
                required property color subtitleColor
                required property var titleFont
                required property var subtitleFont
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

                function publishSelectedTitleOffset(): void {
                    if (!complete || isAddTrack || !titleBold)
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
                onTitleRectChanged: publishSelectedTitleOffset()
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
                    x: trackHeaderRow.titleRect.x
                       + trackHeaderRow.selectedTitleOffset.x
                    y: trackHeaderRow.titleRect.y
                       + trackHeaderRow.selectedTitleOffset.y
                    width: trackHeaderRow.titleRect.width
                    height: trackHeaderRow.titleRect.height
                    visible: !trackHeaderRow.isAddTrack
                    clip: contentWidth > width || contentHeight > height
                    color: trackHeaderRow.titleColor
                    font: Qt.font(trackHeaderRow.titleFont)
                    text: trackHeaderRow.title
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }

                // The subtitle remains a voice hit target, not a button fill.
                Text {
                    x: trackHeaderRow.subtitleRect.x
                    y: trackHeaderRow.subtitleRect.y
                    width: trackHeaderRow.subtitleRect.width
                    height: trackHeaderRow.subtitleRect.height
                    visible: !trackHeaderRow.isAddTrack
                    clip: contentWidth > width || contentHeight > height
                    color: trackHeaderRow.subtitleColor
                    font: Qt.font(trackHeaderRow.subtitleFont)
                    text: trackHeaderRow.subtitle
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }

                TrackHeaderToggle {
                    visible: !trackHeaderRow.isAddTrack
                    controlRect: root.headersModel.muteButtonRect
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
                    controlRect: root.headersModel.soloButtonRect
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
