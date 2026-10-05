import PorydawProject

extension ProjectService {
    /// Reads committed sample metadata for the picker without copying audio frames.
    /// - Returns: Metadata keyed by full direct-sound symbol.
    public func pickerSampleInfo() async -> [String: PickerSampleInfo] {
        guard let store else { return [:] }
        return await store.pickerSampleInfo()
    }
}
