import Foundation

enum LayoutSpace: CaseIterable {
    case zero, half, one, two, three, four, six, eight

    var multiplier: Double {
        switch self {
        case .zero: 0
        case .half: 0.125
        case .one: 0.25
        case .two: 0.5
        case .three: 0.75
        case .four: 1
        case .six: 1.5
        case .eight: 2
        }
    }
}

@MainActor
public struct Typography {
    public let baseFontPx: Int
    public let bodyFontPx: Int

    public init(baseFontPx: Int) {
        self.baseFontPx = max(1, baseFontPx)
        bodyFontPx = max(1, Int((Double(self.baseFontPx) * 1.125).rounded()))
    }

    func space(_ token: LayoutSpace) -> Int {
        fontPx(token.multiplier)
    }

    func fontPx(_ multiplier: Double) -> Int {
        Int(PorydawApp.fontPx(Double(baseFontPx), multiplier))
    }

    func fontPxF(_ multiplier: Double) -> Double {
        PorydawApp.fontPxF(Double(baseFontPx), multiplier)
    }

    var body: GridFontSpec {
        GridFontSpec(family: gridBodyFamily, pixelSize: bodyFontPx, weight: 400,
                     letterSpacing: 0)
    }

    var bodyBold: GridFontSpec {
        GridFontSpec(family: gridBodyFamily, pixelSize: bodyFontPx, weight: 600,
                     letterSpacing: 0)
    }

    var bodyMono: GridFontSpec {
        GridFontSpec(family: gridMonoFamily, pixelSize: bodyFontPx, weight: 400,
                     letterSpacing: 0)
    }

    var tableMono: GridFontSpec {
        GridFontSpec(family: gridMonoFamily, pixelSize: bodyFontPx, weight: 400,
                     letterSpacing: Double(baseFontPx) * (-1.0 / 26.0))
    }

    var caption: GridFontSpec {
        GridFontSpec(family: gridBodyFamily, pixelSize: baseFontPx, weight: 400,
                     letterSpacing: 0)
    }

    var captionBold: GridFontSpec {
        GridFontSpec(family: gridBodyFamily, pixelSize: baseFontPx, weight: 600,
                     letterSpacing: 0)
    }

    var noteName: GridFontSpec {
        #if os(macOS)
        caption
        #else
        captionBold
        #endif
    }

    func fitted(_ role: GridFontSpec, availableHeight: Double) -> GridFontSpec? {
        guard availableHeight > 0 else { return nil }
        let maximum = min(role.pixelSize, caption.pixelSize)
        guard maximum > 0 else { return nil }
        let bounded = GridFontSpec(family: role.family, pixelSize: maximum,
                                   weight: role.weight, letterSpacing: role.letterSpacing)
        let size = NativeFontMetrics(bounded).fittedSize(rowHeight: availableHeight)
        let result = GridFontSpec(family: role.family, pixelSize: size,
                                  weight: role.weight, letterSpacing: role.letterSpacing)
        return NativeFontMetrics(result).extents.height <= availableHeight ? result : nil
    }
}
