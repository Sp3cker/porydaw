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
        SampleDsp.fadeEdges(&result.preview, fadeIn: fadeIn ? fade : 0, fadeOut: fadeOut ? fade : 0)
        result.s8 = SampleDsp.quantizeBuffer(result.preview, dither: params.ditherOn)
        if result.looped {
            result.seam = SampleDsp.seamMetrics(result.s8, loopStart: Int(result.loopStart), loopEnd: count - 1)
        }
        return result
    }
}
