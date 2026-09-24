import QtQuick
import QtQuick.Controls

// Base of every Porydaw top-level window. The window palette assigns every Qt
// palette role, in every color group, from the applied theme, so no control,
// popup, or menu inherits the platform palette: macOS dark mode, Windows
// high-contrast, and desktop GTK/KDE schemes pick text colors for their own
// surfaces, not ours. Text contrast is the first visual requirement
// (docs/adr/0002-text-contrast-first.md).
//
// Mapping follows the legacy application palette (themeruntime.cpp
// applyPaletteGroup). Text roles are assigned per color group so the disabled
// ink never races the enabled ink during a theme switch.
ApplicationWindow {
    required property QtObject colors

    // Every surface role is paired with a text role that keeps 4.5:1 on it:
    // text/placeholderText on base, windowText on window/dark/midlight,
    // buttonText on button, highlightedText on highlight and on light (Basic
    // item delegates paint their highlight with `light`), toolTipText on
    // toolTipBase, brightText on dark.
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
