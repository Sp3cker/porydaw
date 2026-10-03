import Foundation

/// The bundled faces (Atkinson text, Porydaw icon glyphs), staged beside each
/// executable's resources like PorydawApplication.qml so Qt registers files.
public enum BundledFont: String {
    case regular = "AtkinsonHyperlegibleNext-Regular.ttf"
    case semibold = "AtkinsonHyperlegibleNext-SemiBold.ttf"
    case mono = "AtkinsonHyperlegibleMono-Regular.ttf"
    case icons = "PorydawIcons.otf"

    /// FontLoader source. Every build stages the files, so a missing one is a packaging bug.
    public var source: String {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: nil) else {
            fatalError("Missing bundled font \(rawValue)")
        }
        return url.absoluteString
    }
}
