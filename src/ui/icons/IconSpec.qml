pragma ComponentBehavior: Bound

// One Icons singleton entry: a font glyph plus its square-box fit.
// Typed so icon consumers compile ahead of time.
import QtQuick

QtObject {
    required property string glyph
    required property real fit
}
