pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import PorydawApp

ColumnLayout {
    id: chrome
    required property TypographyFonts typography
    required property LayoutSpaces layoutSpaces
    required property int baseFontPx
    required property color headerBackground
    required property color textColor
    required property color outlineColor
    required property int currentIndex
    required property string titleText
    property string titleObjectName: ""
    property string subtitleObjectName: ""
    required property string subtitleText
    default property alias pages: stack.data
    property alias footer: buttons.data
    spacing: 0

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: header.implicitHeight + chrome.layoutSpaces.three * 2
        color: chrome.headerBackground
        ColumnLayout {
            id: header
            anchors.fill: parent
            anchors.margins: chrome.layoutSpaces.three
            spacing: chrome.layoutSpaces.one
            Text {
                objectName: chrome.titleObjectName
                text: chrome.titleText
                font: chrome.typography.bodyBold
                color: chrome.textColor
            }
            Text {
                objectName: chrome.subtitleObjectName
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: chrome.subtitleText
                font: chrome.typography.body
                color: chrome.textColor
            }
        }
    }
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Math.round(chrome.baseFontPx / 12); color: chrome.outlineColor }
    StackLayout {
        id: stack
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: chrome.currentIndex
    }
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Math.round(chrome.baseFontPx / 12); color: chrome.outlineColor }
    RowLayout {
        id: buttons
        Layout.fillWidth: true
        Layout.margins: chrome.layoutSpaces.three
        spacing: chrome.layoutSpaces.two
        Item { Layout.fillWidth: true }
    }
}
