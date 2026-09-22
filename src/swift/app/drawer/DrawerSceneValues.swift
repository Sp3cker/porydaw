/// Plain rectangle geometry and styling produced by drawer scene builders.
struct DrawerRectValue: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fillColor: String
    var primitiveName: String

    init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0,
         fillColor: String = "", primitiveName: String = "") {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.fillColor = fillColor
        self.primitiveName = primitiveName
    }
}

/// Native measurements copied into immutable values before a pure scene build.
struct DrawerTextMetrics: Equatable, Sendable {
    var fonts: [GridFontKind: GridFontSpec]
    var rulerAscent: Double
    var rulerHeight: Double
    var beatAscent: Double
    var beatHeight: Double
    var boldHeight: Double
    var chipHeight: Double

    init(fonts: [GridFontKind: GridFontSpec] = [:], rulerAscent: Double = 0,
         rulerHeight: Double = 0, beatAscent: Double = 0, beatHeight: Double = 0,
         boldHeight: Double = 0, chipHeight: Double = 0) {
        self.fonts = fonts
        self.rulerAscent = rulerAscent
        self.rulerHeight = rulerHeight
        self.beatAscent = beatAscent
        self.beatHeight = beatHeight
        self.boldHeight = boldHeight
        self.chipHeight = chipHeight
    }

    func font(_ kind: GridFontKind, fallback: GridFontSpec) -> GridFontSpec {
        fonts[kind] ?? fallback
    }
}

/// Plain text geometry, font and styling. QVariant maps are created only when
/// this value crosses into a Qt item model.
struct DrawerTextValue: Equatable, Sendable {
    var rect: DrawerRectValue
    var backgroundRect: DrawerRectValue
    var clipRect: DrawerRectValue
    var font: GridFontSpec
    var text: String
    var color: String
    var background: String
    var horizontalAlignment: Int
    var verticalAlignment: Int

    init(rect: DrawerRectValue, text: String, color: String, font: GridFontSpec,
         horizontalAlignment: Int = 0x1, verticalAlignment: Int = 0x80,
         background: String = "", backgroundRect: DrawerRectValue = DrawerRectValue(),
         clipRect: DrawerRectValue = DrawerRectValue()) {
        self.rect = rect
        self.backgroundRect = backgroundRect
        self.clipRect = clipRect
        self.font = font
        self.text = text
        self.color = color
        self.background = background
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
    }
}
