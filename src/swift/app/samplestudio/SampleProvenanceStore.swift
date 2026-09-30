import Foundation
import PorydawSample

/// Keeps each committed sample's provenance in app preferences, never inside the project.
/// Records are keyed by the standardized project root and the registered sample name.
@MainActor
struct SampleProvenanceStore {
    let preferences: PreferencesStore

    func load(projectRoot: String, name: String) -> SampleProvenance? {
        preferences.data(Self.key(projectRoot: projectRoot, name: name)).flatMap(SampleProvenance.decode)
    }

    func save(_ provenance: SampleProvenance, projectRoot: String, name: String) {
        preferences.setData(Self.key(projectRoot: projectRoot, name: name), provenance.jsonData())
        preferences.synchronize()
    }

    func remove(projectRoot: String, name: String) {
        preferences.remove(key: Self.key(projectRoot: projectRoot, name: name))
        preferences.synchronize()
    }

    private static func key(projectRoot: String, name: String) -> String {
        "sampleProvenance/" + URL(fileURLWithPath: projectRoot).standardizedFileURL.path + "/" + name
    }
}
