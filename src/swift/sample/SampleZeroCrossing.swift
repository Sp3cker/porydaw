/// Bounded, allocation-free nearest-sign-change search on a sample grid.
public enum SampleZeroCrossing {
    /// Returns the closing frame of the nearest crossing, preferring the left on ties.
    /// If snapping is disabled or no crossing is found, returns the clamped input index.
    public static func nearest(buffer: Span<Float>, index: Int, windowFrames: Int) -> Int {
        let center = min(max(0, index), max(0, buffer.count - 1))
        guard buffer.count >= 2, windowFrames > 0 else { return center }
        let last = buffer.count - 1
        let bound = min(windowFrames, max(center, last - center))
        for distance in 0...bound {
            let left = center - distance
            if left > 0,
                (buffer[left - 1] < 0 && buffer[left] >= 0) || (buffer[left - 1] >= 0 && buffer[left] < 0)
            {
                return left
            }
            if distance > 0, distance <= last - center {
                let right = center + distance
                if (buffer[right - 1] < 0 && buffer[right] >= 0) || (buffer[right - 1] >= 0 && buffer[right] < 0) {
                    return right
                }
            }
        }
        return center
    }
}
