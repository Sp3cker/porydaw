pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Icons

// One Icons glyph fitted to this box and tinted. Icons are font glyphs, so no
// image element (and no Qt image plugin) is involved; an empty glyph draws nothing.
Item {
    id: root
    required property IconSpec icon
    property color color: "black"

    Text {
        anchors.centerIn: parent
        text: root.icon.glyph
        font.family: Icons.family
        font.pixelSize: Math.max(1, Math.round(Math.min(root.width, root.height)
                                               * root.icon.fit))
        font.hintingPreference: Font.PreferNoHinting
        color: root.color
        renderType: Text.NativeRendering
        // Decorative: the owning control carries the accessible name.
        Accessible.ignored: true
    }
}
