pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

// Every top-level window maps every palette group to the applied theme, so
// controls and popups never inherit platform colors.
T.ApplicationWindow {
    required property QtObject colors
    color: palette.window

    // Surface/text pairs preserve contrast in every palette group.
    palette.window: colors.windowBackground
    palette.base: colors.inputBackground
    palette.alternateBase: colors.alternateBackground
    palette.button: colors.buttonBackground
    palette.highlight: colors.tabSelectedBackground
    palette.toolTipBase: colors.inputBackground
    palette.accent: colors.selectionEdge
    palette.light: colors.tabSelectedBackground
    palette.midlight: colors.buttonHoverBackground
    palette.mid: colors.outline
    palette.dark: colors.chromeBackground
    palette.shadow: colors.separator

    palette.active.windowText: colors.windowText
    palette.active.text: colors.windowText
    palette.active.buttonText: colors.buttonText
    palette.active.brightText: colors.windowText
    palette.active.highlightedText: colors.selectionText
    palette.active.placeholderText: colors.placeholderText
    palette.active.toolTipText: colors.windowText
    palette.active.link: colors.windowText
    palette.active.linkVisited: colors.windowText

    palette.inactive.windowText: colors.windowText
    palette.inactive.text: colors.windowText
    palette.inactive.buttonText: colors.buttonText
    palette.inactive.brightText: colors.windowText
    palette.inactive.highlightedText: colors.selectionText
    palette.inactive.placeholderText: colors.placeholderText
    palette.inactive.toolTipText: colors.windowText
    palette.inactive.link: colors.windowText
    palette.inactive.linkVisited: colors.windowText

    palette.disabled.windowText: colors.disabledText
    palette.disabled.text: colors.disabledText
    palette.disabled.buttonText: colors.disabledText
    palette.disabled.brightText: colors.disabledText
    palette.disabled.highlightedText: colors.disabledText
    palette.disabled.placeholderText: colors.disabledText
    palette.disabled.toolTipText: colors.disabledText
    palette.disabled.link: colors.disabledText
    palette.disabled.linkVisited: colors.disabledText
}
