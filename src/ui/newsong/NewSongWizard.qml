// Blank New Song flow: Song identity -> Sound settings.
// Swift owns the draft and validation. The host supplies the controller,
// palette, font and transient parent; this window performs no project writes.
// Return advances; Escape cancels after a combo popup or IME has had priority.
//
// Palette roles: windowBackground, chromeBackground, separator, outline,
// tabHoverBackground, tabSelectedBackground, windowText, secondaryText,
// buttonBackground, buttonHoverBackground, buttonPressedBackground, playhead.
pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
    id: root

    required property QtObject controller
    required property var colors

    // Production geometry is font-relative: the blank wizard floors its window
    // at 52 x 38 font units and lets the content hint grow it.
    readonly property int unit: Math.max(1, Math.round(root.font.pixelSize))
    readonly property int gap: Math.round(root.unit * 0.75)
    readonly property int margin: root.unit

    readonly property int fieldWidth: Math.round(root.unit * 22)
    readonly property int messageBand: Math.round(root.unit * 2)

    readonly property color windowFill: root.colors.windowBackground
    readonly property color headerFill: root.colors.chromeBackground
    readonly property color ruleColor: root.colors.separator
    readonly property color fieldFill: root.colors.inputBackground
    readonly property color accentFill: root.colors.tabSelectedBackground
    readonly property color fieldOutline: root.colors.outline
    readonly property color focusOutline: root.colors.tabSelectedBackground
    readonly property color textColor: root.colors.windowText
    readonly property color hintColor: root.colors.secondaryText
    readonly property color messageColor: root.colors.playhead
    readonly property color buttonFill: root.colors.buttonBackground
    readonly property color buttonHoverFill: root.colors.buttonHoverBackground
    readonly property color buttonPressedFill: root.colors.buttonPressedBackground

    objectName: "newSongWizardWindow"
    title: qsTr("New Song")
    // A real dialog window rather than a chrome-less surface; the host still
    // supplies the transient parent so the platform stacks it as a dialog.
    flags: Qt.Dialog
    modality: Qt.WindowModal
    visible: root.controller.active
    color: root.windowFill
    onClosing: root.controller.cancel()

    minimumWidth: Math.round(root.unit * 52)
    minimumHeight: Math.round(root.unit * 38)
    width: Math.max(root.minimumWidth, frame.implicitWidth)
    height: Math.max(root.minimumHeight, frame.implicitHeight)

    // One window palette feeds every Basic control: fields, buttons,
    // indicators, selections, and placeholders take the shared roles.
    palette.window: root.windowFill
    palette.windowText: root.textColor
    palette.text: root.textColor
    palette.base: root.fieldFill
    palette.button: root.buttonFill
    palette.buttonText: root.textColor
    palette.placeholderText: root.hintColor
    palette.highlight: root.focusOutline
    palette.highlightedText: root.textColor
    palette.light: root.buttonHoverFill
    palette.midlight: root.buttonPressedFill
    palette.mid: root.fieldOutline
    palette.dark: root.ruleColor
    palette.brightText: root.textColor
    palette.toolTipBase: root.fieldFill
    palette.toolTipText: root.textColor

    // Return/Enter: Next on the identity page, Finish on the sound page; both
    // stay inert while the draft fails validation.
    function advance() {
        if (root.controller.page === 0) {
            if (root.controller.canNext)
                root.controller.next()
        } else if (root.controller.canFinish) {
            root.commitVoicegroupText()
            root.controller.finish()
        }
    }

    // The editable voicegroup entry is a combo the user can type into; hand its
    // text to the draft before the draft decides on it.
    function commitVoicegroupText() {
        root.controller.editVoicegroup(voicegroupBox.editText)
    }

    // Focus follows the page like a wizard page does: the first field of the
    // page the draft is on.
    function focusCurrentPage() {
        if (root.controller.page === 0)
            nameField.forceActiveFocus()
        else
            voicegroupBox.forceActiveFocus()
    }

    Connections {
        target: root.controller
        function onPageChanged() {
            root.focusCurrentPage()
        }
    }
    onActiveChanged: {
        if (active)
            root.focusCurrentPage()
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: !playerBox.popup.visible && !voicegroupBox.popup.visible
                 && !nameField.inputMethodComposing && !constantField.inputMethodComposing
                 && !voicegroupBox.inputMethodComposing
        onActivated: root.controller.cancel()
    }

    // QWizard's classic page header: a bold title over the wrapped subtitle,
    // ruled off from the page body. The header sits directly on the window
    // surface like the Fusion wizard — no separate band fill.
    component WizardHeader: Item {
        id: header

        required property string headline
        required property string subHeadline

        implicitHeight: headerColumn.implicitHeight + 2 * root.margin

        ColumnLayout {
            id: headerColumn
            anchors.fill: parent
            anchors.margins: root.margin
            spacing: Math.round(root.gap * 0.5)

            Text {
                Layout.fillWidth: true
                text: header.headline
                // QML cannot assign the font group and override a member on the
                // same property, so the bold title takes the window font's
                // family and size one member at a time.
                font.family: root.font.family
                font.pixelSize: root.font.pixelSize
                font.bold: true
                color: root.textColor
                wrapMode: Text.Wrap
                renderType: Text.NativeRendering
            }
            Text {
                Layout.fillWidth: true
                text: header.subHeadline
                font: root.font
                color: root.textColor
                wrapMode: Text.Wrap
                renderType: Text.NativeRendering
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1 / Screen.devicePixelRatio
            color: root.ruleColor
        }
    }

    // A small filled triangle for the combo and spin indicators, matching the
    // Fusion arrow glyphs.
    component ArrowGlyph: Shape {
        id: arrow

        property bool pointingUp: false
        property color ink: root.textColor

        implicitWidth: Math.round(root.unit * 0.7)
        implicitHeight: Math.round(root.unit * 0.4)
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: 0
            fillColor: arrow.ink
            startX: 0
            startY: arrow.pointingUp ? arrow.height : 0
            PathLine { x: arrow.width; y: arrow.pointingUp ? arrow.height : 0 }
            PathLine { x: arrow.width / 2; y: arrow.pointingUp ? 0 : arrow.height }
            PathLine { x: 0; y: arrow.pointingUp ? arrow.height : 0 }
        }
    }

    // QFormLayout's label column: right-aligned next to the field column, sized
    // to the widest caption rather than a fixed width.
    component FormLabel: Text {
        id: label

        required property string caption

        text: label.caption
        font: root.font
        color: root.textColor
        renderType: Text.NativeRendering
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
    }

    // A Fusion line edit: rounded field on the input surface with a thin
    // outline that swaps to the focus ring while edited.
    component FormField: Basic.TextField {
        id: field

        font: root.font
        selectByMouse: true
        Layout.fillWidth: true
        Layout.preferredWidth: root.fieldWidth
        leftPadding: Math.round(root.gap * 0.75)
        rightPadding: Math.round(root.gap * 0.75)

        background: Rectangle {
            radius: Math.round(root.unit * 0.35)
            color: root.fieldFill
            border.width: 1 / Screen.devicePixelRatio
            border.color: field.activeFocus ? root.focusOutline : root.fieldOutline
        }
    }

    // A Fusion combo box: the same rounded field with a single down-arrow
    // indicator on the right.
    component FormCombo: Basic.ComboBox {
        id: combo

        font: root.font
        Layout.fillWidth: true
        Layout.preferredWidth: root.fieldWidth
        leftPadding: Math.round(root.gap * 0.75)
        // The Basic style derives its implicit height from a content item this
        // editable/flat configuration leaves empty; pin the field height like
        // the other controls so the row keeps its form height.
        implicitHeight: Math.round(root.unit * 2.2)
        ToolTip.visible: combo.hovered && !combo.popup.visible

        background: Rectangle {
            radius: Math.round(root.unit * 0.35)
            color: root.fieldFill
            border.width: 1 / Screen.devicePixelRatio
            border.color: combo.activeFocus ? root.focusOutline : root.fieldOutline
        }
        indicator: ArrowGlyph {
            x: combo.width - width - Math.round(root.gap * 0.75)
            y: Math.round((combo.height - height) / 2)
            ink: root.textColor
        }
        // An open popup owns Return/Enter: the style activates the item it
        // highlights, so standing down lets the key stay popup-local. A closed
        // popup passes the key through to the wizard's primary action.
        Keys.onReturnPressed: (event) => {
            if (combo.popup.visible)
                event.accepted = false
            else
                root.advance()
        }
        Keys.onEnterPressed: (event) => {
            if (combo.popup.visible)
                event.accepted = false
            else
                root.advance()
        }
    }

    // The mid2agb numeric flags: editable 0..127 spin boxes with the Fusion
    // stacked up/down arrows on the right edge.
    component FlagSpin: Basic.SpinBox {
        id: spin

        font: root.font
        editable: true
        from: 0
        to: 127
        Layout.fillWidth: true
        Layout.preferredWidth: root.fieldWidth
        leftPadding: Math.round(root.gap * 0.75)
        rightPadding: Math.round(root.unit * 1.4)

        background: Rectangle {
            radius: Math.round(root.unit * 0.35)
            color: root.fieldFill
            border.width: 1 / Screen.devicePixelRatio
            border.color: spin.activeFocus ? root.focusOutline : root.fieldOutline
        }
        up.indicator: Item {
            width: Math.round(root.unit * 1.4)
            height: Math.round(spin.height / 2)
            x: spin.width - width
            y: 0
            ArrowGlyph {
                anchors.centerIn: parent
                pointingUp: true
                ink: spin.up.pressed ? root.buttonPressedFill : root.textColor
            }
        }
        down.indicator: Item {
            width: Math.round(root.unit * 1.4)
            height: Math.round(spin.height / 2)
            x: spin.width - width
            y: Math.round(spin.height / 2)
            ArrowGlyph {
                anchors.centerIn: parent
                ink: spin.down.pressed ? root.buttonPressedFill : root.textColor
            }
        }
    }

    // The mid2agb boolean flags. QFormLayout puts them in the field column.
    // The indicator is the Fusion rounded box, filled with the accent and a
    // dark check while on.
    component FlagCheck: Basic.CheckBox {
        id: check

        font: root.font
        Layout.fillWidth: true
        spacing: Math.round(root.gap * 0.75)

        indicator: Rectangle {
            implicitWidth: Math.round(root.unit * 1.15)
            implicitHeight: Math.round(root.unit * 1.15)
            y: Math.round((check.height - height) / 2)
            radius: Math.round(root.unit * 0.25)
            color: check.checked ? root.accentFill : root.fieldFill
            border.width: 1 / Screen.devicePixelRatio
            border.color: check.activeFocus ? root.focusOutline : root.fieldOutline

            Shape {
                id: checkMark
                anchors.fill: parent
                anchors.margins: Math.round(parent.width * 0.18)
                visible: check.checked
                layer.enabled: true
                layer.samples: 4
                ShapePath {
                    strokeColor: root.textColor
                    strokeWidth: Math.max(1.5, root.unit * 0.16)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: 0
                    startY: checkMark.height * 0.55
                    PathLine { x: checkMark.width * 0.38; y: checkMark.height }
                    PathLine { x: checkMark.width; y: 0 }
                }
            }
        }
    }

    // The page's message row: reserved height, so a message that arrives or
    // clears never resizes the dialog; empty while the draft is valid.
    component MessageBand: Text {
        id: message

        font: root.font
        color: root.messageColor
        wrapMode: Text.Wrap
        verticalAlignment: Text.AlignTop
        renderType: Text.NativeRendering
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.preferredHeight: root.messageBand
    }

    // QPushButton, in the shared theme's button roles with the Fusion rounded
    // face.
    component WizardButton: Basic.Button {
        id: button

        implicitWidth: Math.max(Math.round(root.unit * 7),
                                implicitContentWidth + 2 * root.gap)
        implicitHeight: Math.max(Math.round(root.unit * 1.9),
                                 implicitContentHeight + root.gap)
        padding: Math.round(root.gap * 0.6)
        hoverEnabled: true
        // Flat buttons carry no disabled skin of their own; dim a disabled
        // Next/Finish the way the shared prompt buttons do.
        opacity: button.enabled ? 1 : 0.5

        background: Rectangle {
            radius: Math.round(root.unit * 0.35)
            color: button.pressed ? root.buttonPressedFill
                                  : button.hovered ? root.buttonHoverFill : root.buttonFill
            border.width: 1 / Screen.devicePixelRatio
            border.color: button.visualFocus ? root.focusOutline : root.fieldOutline
        }
        contentItem: Text {
            text: button.text
            font: root.font
            color: root.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }

    ColumnLayout {
        id: frame
        anchors.fill: parent
        spacing: 0

        Keys.onReturnPressed: root.advance()
        Keys.onEnterPressed: root.advance()

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.controller.page

            // ---- Identity: label, constant, music player --------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                WizardHeader {
                    Layout.fillWidth: true
                    headline: qsTr("Song identity")
                    subHeadline: qsTr("Names the .mid file, the song_table.inc entry, and the songs.h constant.")
                }

                GridLayout {
                    columns: 2
                    columnSpacing: root.gap
                    rowSpacing: root.gap
                    Layout.fillWidth: true
                    Layout.margins: root.margin

                    FormLabel {
                        caption: qsTr("Name:")
                    }
                    FormField {
                        id: nameField
                        objectName: "newSongName"
                        placeholderText: "mus_my_song"
                        validator: RegularExpressionValidator {
                            // The production validator folds typed capitals
                            // before matching, so capitals reach the draft and
                            // the draft stores the lowercase label.
                            regularExpression: /[A-Za-z_][A-Za-z0-9_]*/
                        }
                        // The draft owns the label: the field follows every
                        // value it publishes, including the fold of what was
                        // just typed. Re-applying an equal value is a no-op, so
                        // the binding never disturbs the caret.
                        Binding {
                            target: nameField
                            property: "text"
                            value: root.controller.name
                        }
                        onTextEdited: {
                            const typed = nameField.text
                            const caret = nameField.cursorPosition
                            root.controller.editName(typed)
                            // The draft folded the label; keep the caret where
                            // the user typed it.
                            if (nameField.text !== typed)
                                nameField.cursorPosition = Math.min(caret, nameField.text.length)
                        }
                    }

                    FormLabel {
                        caption: qsTr("Constant:")
                    }
                    FormField {
                        id: constantField
                        objectName: "newSongConstant"
                        // The draft derives the constant from the name until the
                        // user edits this field, after which it keeps what the
                        // user typed — so the binding is the whole story.
                        text: root.controller.constant
                        // Only a user edit is the manual override, exactly as
                        // the production page's textEdited handler.
                        onTextEdited: root.controller.editConstant(constantField.text)
                    }

                    FormLabel {
                        caption: qsTr("Player:")
                    }
                    FormCombo {
                        id: playerBox
                        objectName: "newSongPlayer"
                        model: root.controller.playerNames
                        currentIndex: root.controller.playerIndex
                        ToolTip.text: qsTr("Select Background music for a song. Select Sound effect for a sound. Also select it for a fanfare.")
                        onActivated: (index) => root.controller.selectPlayer(index)
                    }

                    // Empty label cell, as QFormLayout::addRow(QString(), hint).
                    Item {}
                    MessageBand {
                        objectName: "newSongIdentityError"
                        text: root.controller.identityError
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }

            // ---- Sound: voicegroup + midi.cfg flags -------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                WizardHeader {
                    Layout.fillWidth: true
                    headline: qsTr("Sound settings")
                    subHeadline: qsTr("The song's voicegroup and mid2agb flags — its entry in midi.cfg (or songs.mk). All of this can be changed later in Song Settings.")
                }

                GridLayout {
                    columns: 2
                    columnSpacing: root.gap
                    rowSpacing: root.gap
                    Layout.fillWidth: true
                    Layout.margins: root.margin

                    FormLabel {
                        caption: qsTr("Voicegroup:")
                    }
                    FormCombo {
                        id: voicegroupBox
                        objectName: "newSongVoicegroup"
                        editable: true
                        selectTextByMouse: true
                        model: root.controller.voicegroupNames
                        ToolTip.text: qsTr("The symbol is \"voicegroup_\" + this name (mid2agb -G).")
                        // Snapshots flow down; only user edits flow back. An
                        // index update also changes Qt's editText internally.
                        currentIndex: root.controller.voicegroupIndex
                        editText: root.controller.voicegroupText
                        onActivated: (index) => root.controller.selectVoicegroup(index)
                        Connections {
                            target: voicegroupBox.contentItem
                            function onTextEdited() {
                                root.controller.editVoicegroup(voicegroupBox.contentItem.text)
                            }
                        }
                        // An editable combo's editor takes Return for itself, so
                        // this hook hands it back to the page's action — the
                        // commit before Finish the draft needs. While the popup
                        // is open, Return belongs to the popup instead.
                        onAccepted: {
                            if (!voicegroupBox.popup.visible)
                                root.advance()
                        }
                    }

                    FormLabel {
                        caption: qsTr("Master volume (-V):")
                    }
                    FlagSpin {
                        objectName: "newSongVolume"
                        value: root.controller.masterVolume
                        onValueModified: root.controller.setMasterVolume(value)
                    }

                    FormLabel {
                        caption: qsTr("Reverb (-R):")
                    }
                    FlagSpin {
                        objectName: "newSongReverb"
                        value: root.controller.reverb
                        onValueModified: root.controller.setReverb(value)
                    }

                    FormLabel {
                        caption: qsTr("Priority (-P):")
                    }
                    FlagSpin {
                        objectName: "newSongPriority"
                        value: root.controller.priority
                        onValueModified: root.controller.setPriority(value)
                    }

                    // The three check rows have no label, as the import page's
                    // QFormLayout::addRow(QString(), checkbox).
                    Item {}
                    FlagCheck {
                        objectName: "newSongExactGate"
                        text: qsTr("Exact gate time (-E)")
                        checked: root.controller.exactGate
                        onToggled: root.controller.setExactGate(checked)
                    }
                    Item {}
                    FlagCheck {
                        objectName: "newSongExtendedClocks"
                        text: qsTr("48 clocks per beat (-X)")
                        checked: root.controller.extendedClocks
                        onToggled: root.controller.setExtendedClocks(checked)
                    }
                    Item {}
                    FlagCheck {
                        objectName: "newSongNoCompression"
                        text: qsTr("Disable compression (-N)")
                        checked: root.controller.noCompression
                        onToggled: root.controller.setNoCompression(checked)
                    }

                    Item {}
                    MessageBand {
                        objectName: "newSongSoundError"
                        text: root.controller.soundError
                    }
                }
                Item {
                    Layout.fillHeight: true
                }
            }
        }

        // QWizard's button row: Back, Next, and Finish lead; Cancel trails
        // rightmost. Back only appears after the first page and Next gives way
        // to Finish on the last one.
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: root.margin
            spacing: root.gap

            Item {
                Layout.fillWidth: true
            }
            WizardButton {
                objectName: "newSongBack"
                text: qsTr("< Back")
                visible: root.controller.page > 0
                onClicked: root.controller.back()
            }
            WizardButton {
                objectName: "newSongNext"
                text: qsTr("Next >")
                visible: root.controller.page === 0
                enabled: root.controller.canNext
                onClicked: root.controller.next()
            }
            WizardButton {
                objectName: "newSongFinish"
                text: qsTr("Finish")
                visible: root.controller.page === 1
                enabled: root.controller.canFinish
                onClicked: {
                    root.commitVoicegroupText()
                    root.controller.finish()
                }
            }
            WizardButton {
                objectName: "newSongCancel"
                text: qsTr("Cancel")
                onClicked: root.controller.cancel()
            }
        }
    }
}
