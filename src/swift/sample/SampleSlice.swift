import Foundation

/// Renders a cropped slice through the sample pipeline and bakes its edge fades.
public enum SampleSlice {
    /// Preserves render metadata and applies half-cosine fades bounded to 4 ms and half the output.
    public static func render(
        source: ImportedSample, params: SampleEditParams,
        fadeIn: Bool = false, fadeOut: Bool = true
    ) -> ProcessedSample {
        var result = SampleRender.render(source: source, params: params)
        guard fadeIn || fadeOut else { return result }
        let count = result.preview.count
        let fade = min(Int((0.004 * result.outputRate).rounded()), count / 2)
        guard fade > 0 else { return result }
        do {
            var grid = result.preview.mutableSpan
            if fadeIn {
                for index in 0..<fade {
                    grid[index] = Float(Double(grid[index]) * 0.5 * (1 - cos(.pi * Double(index) / Double(fade))))
                }
            }
            if fadeOut {
                for index in 0..<fade {
                    let position = count - 1 - index
                    grid[position] = Float(Double(grid[position]) * 0.5 * (1 - cos(.pi * Double(index) / Double(fade))))
                }
            }
        }
        result.s8 = SampleDsp.quantizeBuffer(result.preview, dither: params.ditherOn)
        if result.looped {
            result.seam = SampleDsp.seamMetrics(result.s8, loopStart: Int(result.loopStart), loopEnd: count - 1)
        }
        return result
    }
}
