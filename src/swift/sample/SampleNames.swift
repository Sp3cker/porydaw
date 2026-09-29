public enum SampleNames {
    public static func sanitize(_ raw: String) -> String {
        var result = ""
        var separator = false
        for character in raw.lowercased().unicodeScalars {
            if (97...122).contains(character.value) || (48...57).contains(character.value) {
                if separator && !result.isEmpty { result.append("_") }
                result.unicodeScalars.append(character)
                separator = false
            } else {
                separator = true
            }
        }
        return result
    }
}
