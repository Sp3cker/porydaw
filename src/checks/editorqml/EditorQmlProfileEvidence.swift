import Foundation

extension EditorQmlLane {
    /// One reference pane's production identity: the composition component the
    /// pane is authoritative for, and the drawn root the capture grabs. Every
    /// artifact records both and the parent rejects anything else, so a capture
    /// can never be read as another pane's reference.
    struct ReferencePaneIdentity {
        let component: String
        let drawnRoot: String
    }

    /// One entry per pane `referenceProfiles` names, mapped to its production
    /// component path and the drawn root the capture holds. `voice-picker` grabs
    /// the container's one modal layer, which the Voice Changes page composes the
    /// production picker into (`EditorDrawer.qml`'s `drawerModalLayer`).
    static let paneIdentities: [String: ReferencePaneIdentity] = [
        "velocity-lane": ReferencePaneIdentity(
            component: "src/ui/songview/quick/drawer/VelocityPage.qml",
            drawnRoot: "velocityPage"),
        "editor-drawer": ReferencePaneIdentity(
            component: "src/ui/songview/quick/drawer/EditorDrawer.qml",
            drawnRoot: "editorDrawer"),
        "velocity-prompt": ReferencePaneIdentity(
            component: "src/ui/songview/quick/VelocityPrompt.qml",
            drawnRoot: "velocityPromptCard"),
        "voice-picker": ReferencePaneIdentity(
            component: "src/ui/songview/quick/VoicePickerPrompt.qml",
            drawnRoot: "drawerModalLayer"),
        "automation-tabs": ReferencePaneIdentity(
            component: "src/ui/songview/quick/drawer/AutomationPage.qml",
            drawnRoot: "automationPage"),
        "track-headers": ReferencePaneIdentity(
            component: "src/ui/songview/quick/swiftroll/TrackHeaderBand.qml",
            drawnRoot: "timelineQuickTrackHeaders"),
    ]

    /// The theme the reference profiles are authoritative for: `themes::vanilla`,
    /// the same identity the sibling `quick/vanilla/…` baselines carry.
    static let profileTheme = "vanilla"

    /// What every artifact says about its own capture: these profiles are
    /// offscreen composition grabs, and the parent rejects a record that claims
    /// anything else.
    static let profileCaptureLabel = "offscreen composition grab (not physical-DPR proof)"

    /// The production palette every artifact records: the grid's own `GridPalette`
    /// role table — the object the captured pages were attached to — under the
    /// roles the record must carry. The parent validates exactly these names, so a
    /// role that stops being recorded fails the lane instead of vanishing.
    static let profilePaletteSource = "GridPalette"
    static let profilePaletteRoles = [
        "windowBackground", "chromeBackground", "rollBackground",
        "keyboardLabel", "selectionRing",
    ]

    /// The fixture root `run_checks.ts` stages for `fixtureRootKind`
    /// `decomp-project` (`src/checks/fixtures/decompproject`).
    static let profileFixtureRoot = "decompproject"

    /// The staged fixture identity: the fixture root, the song the lane opened
    /// from it, and the voicegroup the staged `midi.cfg` builds that song with.
    /// Read from the staged project itself, so an artifact can never claim a
    /// fixture set its document was not built from. `-G` carries the voicegroup
    /// argument, whose name drops a leading underscore exactly as
    /// `SongRegistry::voicegroupDisplayName` resolves it.
    static func fixtureIdentity(root: String, label: String) -> String? {
        guard !root.isEmpty, !label.isEmpty else { return nil }
        let path = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("sound/songs/midi/midi.cfg").path
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let entry = String(line).trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix(label + ".mid:") else { continue }
            for token in entry.split(separator: " ") where token.hasPrefix("-G") {
                let argument = token.dropFirst(2)
                let name = argument.hasPrefix("_") ? argument.dropFirst() : argument
                return "\(profileFixtureRoot)/\(label) + \(name)"
            }
        }
        return nil
    }
    /// The captured record's own facts, for the run's evidence line: the metadata
    /// the parent just verified — production component, drawn root, theme, palette
    /// source and fixture, the DPR and font it rendered at, and the logical size,
    /// region and physical PNG size it covered — or a note that it could not be
    /// read.
    static func profileEvidence(path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path),
            let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return " (no readable metadata)" }
        func value(_ key: String) -> String {
            record[key].map { "\($0)" } ?? "?"
        }
        let region = record["region"] as? [String: Int] ?? [:]
        let palette = record["palette"] as? [String: Any] ?? [:]
        let png = URL(fileURLWithPath: path).deletingPathExtension()
            .appendingPathExtension("png").path
        let pixels = pngPixelSize(path: png).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
        return " [profile=\(value("profile")) pane=\(value("pane"))"
            + " component=\(value("component")) drawnRoot=\(value("drawnRoot"))"
            + " theme=\(value("theme")) palette=\(palette["source"].map { "\($0)" } ?? "?")"
            + " fixture=\(value("fixture"))"
            + " dpr=\(value("observedDpr")) font=\(value("observedFontPx"))"
            + " logical=\(value("logicalWidth"))x\(value("logicalHeight"))"
            + " png=\(pixels)"
            + " region=\(region["x"] ?? -1),\(region["y"] ?? -1)"
            + " \(region["width"] ?? -1)x\(region["height"] ?? -1)]"
    }

    /// What the pane's own metadata says when it is not the capture the profile
    /// asked for, or `nil` when it is: the record must be readable and must name
    /// this profile, pane, production component, drawn root, theme, palette and
    /// staged fixture, must carry the profile's own DPR and font as both requested
    /// and observed values, the offscreen capture disclaimer, the exact logical
    /// size its region covers, and must be backed by a PNG of that size at the
    /// requested device pixel ratio. A pane that was never captured, or captured
    /// under another identity, is never accepted on the strength of the file's
    /// name.
    static func profileMetadataMismatch(
        path: String, profile: String, pane: String,
        staged: (root: String, label: String)
    ) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return "unreadable metadata"
        }
        guard let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return "metadata is not a JSON object"
        }
        guard record["profile"] as? String == profile else {
            return "metadata names profile \(record["profile"].map { "\($0)" } ?? "nothing")"
        }
        guard record["pane"] as? String == pane else {
            return "metadata names pane \(record["pane"].map { "\($0)" } ?? "nothing")"
        }
        guard let referenceProfile = referenceProfiles.first(where: { $0.name == profile }) else {
            return "the lane declares no reference profile \(profile)"
        }
        guard let requestedDpr = (record["requestedDpr"] as? NSNumber)?.doubleValue,
            let requestedFont = (record["requestedFontPx"] as? NSNumber)?.doubleValue,
            let observedDpr = (record["observedDpr"] as? NSNumber)?.doubleValue,
            let observedFont = (record["observedFontPx"] as? NSNumber)?.doubleValue
        else {
            return "metadata carries no requested or observed device pixel ratio and font"
        }
        guard abs(requestedDpr - referenceProfile.dpr) < 0.001,
            abs(observedDpr - requestedDpr) < 0.001
        else {
            return "metadata records dpr \(requestedDpr) requested / \(observedDpr) observed,"
                + " not the profile's \(referenceProfile.dpr)"
        }
        guard abs(requestedFont - Double(referenceProfile.fontPx)) < 0.001,
            abs(observedFont - requestedFont) < 0.001
        else {
            return "metadata records font \(requestedFont) requested / \(observedFont) observed,"
                + " not the profile's \(referenceProfile.fontPx)"
        }
        guard let identity = paneIdentities[pane] else {
            return "the lane declares no production component for pane \(pane)"
        }
        guard record["component"] as? String == identity.component else {
            return "metadata names component \(record["component"].map { "\($0)" } ?? "nothing")"
                + ", not \(identity.component)"
        }
        guard record["drawnRoot"] as? String == identity.drawnRoot else {
            return "metadata names drawn root \(record["drawnRoot"].map { "\($0)" } ?? "nothing")"
                + ", not \(identity.drawnRoot)"
        }
        guard record["theme"] as? String == profileTheme else {
            return "metadata names theme \(record["theme"].map { "\($0)" } ?? "nothing")"
                + ", not \(profileTheme)"
        }
        guard let palette = record["palette"] as? [String: Any] else {
            return "metadata carries no production palette identity"
        }
        guard palette["source"] as? String == profilePaletteSource else {
            return "metadata names palette \(palette["source"].map { "\($0)" } ?? "nothing")"
                + ", not \(profilePaletteSource)"
        }
        for role in profilePaletteRoles {
            guard let value = palette[role] as? String, value.hasPrefix("#"), value.count > 1 else {
                return "metadata records no \(role) palette role"
            }
        }
        let expectedFixture = fixtureIdentity(root: staged.root, label: staged.label)
        guard let expectedFixture, record["fixture"] as? String == expectedFixture else {
            return "metadata names fixture \(record["fixture"].map { "\($0)" } ?? "nothing")"
                + ", not \(expectedFixture ?? "nothing")"
        }
        guard let logicalWidth = (record["logicalWidth"] as? NSNumber)?.doubleValue,
            let logicalHeight = (record["logicalHeight"] as? NSNumber)?.doubleValue,
            logicalWidth > 0, logicalHeight > 0
        else {
            return "metadata carries no logical size"
        }
        guard let region = record["region"] as? [String: Any],
            let regionWidth = (region["width"] as? NSNumber)?.doubleValue,
            let regionHeight = (region["height"] as? NSNumber)?.doubleValue,
            abs(regionWidth - logicalWidth) <= 1, abs(regionHeight - logicalHeight) <= 1
        else {
            return "metadata's region does not cover its logical size"
        }
        guard let capture = record["capture"] as? String, capture == profileCaptureLabel else {
            return "metadata names capture \(record["capture"].map { "\($0)" } ?? "nothing")"
                + ", not \"\(profileCaptureLabel)\""
        }
        let png = URL(fileURLWithPath: path).deletingPathExtension()
            .appendingPathExtension("png").path
        guard let pixels = pngPixelSize(path: png) else {
            return "the capture's PNG carries no readable header"
        }
        guard abs(pixels.width - logicalWidth * requestedDpr) <= 1,
            abs(pixels.height - logicalHeight * requestedDpr) <= 1
        else {
            return "the PNG is \(Int(pixels.width))x\(Int(pixels.height)) at dpr \(requestedDpr),"
                + " not the recorded \(logicalWidth)x\(logicalHeight) logical size"
        }
        return nil
    }

    /// The PNG's own pixel size, read from its header: the artifact's two files
    /// must describe one capture, so the record's logical size is checked against
    /// the image it names at the requested device pixel ratio.
    private static func pngPixelSize(path: String) -> (width: Double, height: Double)? {
        guard let handle = FileHandle(forReadingAtPath: path),
            let data = try? handle.read(upToCount: 24), data.count == 24,
            data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        else { return nil }
        func bigEndian32(_ offset: Int) -> Double {
            data.dropFirst(offset).prefix(4).reduce(0) { $0 * 256 + Double($1) }
        }
        return (bigEndian32(16), bigEndian32(20))
    }
}

extension EditorQmlBootstrap {
    /// Records one pane's capture and fails it when the observed facts are not the
    /// requested profile: the metadata beside the PNG is the evidence the parent
    /// verifies, and a DPR, font, pane, theme, palette or fixture mismatch never
    /// passes silently. The record carries the pane's production component and
    /// drawn root, the theme and the palette the capture rendered under, the
    /// staged fixture identity, and the exact logical size it covered.
    func writeProfileMetadataImpl(
        pane: String, observedDpr: Double, observedFontPx: Double,
        drawnRoot: String, logicalWidth: Double, logicalHeight: Double,
        regionX: Int, regionY: Int,
        regionWidth: Int, regionHeight: Int
    ) -> Bool {
        guard profileActive, !pane.isEmpty, logicalWidth > 0, logicalHeight > 0 else { return false }
        let requestedDpr = EditorQmlBootstrap.stagedProfileDpr
        let requestedFont = Double(EditorQmlBootstrap.stagedProfileFontPx)
        guard abs(observedDpr - requestedDpr) < 0.001,
            abs(observedFontPx - requestedFont) < 0.001
        else { return false }
        // The palette the captured pages were attached to — the production grid's
        // own role table, read live rather than copied from a constant — and the
        // fixture identity of the project this process staged and opened.
        let stagedPalette = session.flatMap { $0.songOpen ? $0.gridPresenter().palette : nil }
        let stagedFixture = EditorQmlLane.fixtureIdentity(
            root: projectRoot,
            label: EditorQmlBootstrap.stagedSongLabel)
        guard let identity = EditorQmlLane.paneIdentities[pane], identity.drawnRoot == drawnRoot,
            let palette = stagedPalette, let fixture = stagedFixture
        else {
            reportProfileRefusal(
                pane: pane, drawnRoot: drawnRoot, palette: stagedPalette != nil,
                fixture: stagedFixture)
            return false
        }
        let paletteRecord: [String: Any] = [
            "source": EditorQmlLane.profilePaletteSource,
            "windowBackground": palette.windowBackground,
            "chromeBackground": palette.chromeBackground,
            "rollBackground": palette.rollBackground,
            "keyboardLabel": palette.keyboardLabel,
            "selectionRing": palette.selectionRing,
        ]
        let metadata: [String: Any] = [
            "profile": EditorQmlBootstrap.stagedProfile,
            "pane": pane,
            "component": identity.component,
            "drawnRoot": drawnRoot,
            "theme": EditorQmlLane.profileTheme,
            "palette": paletteRecord,
            "fixture": fixture,
            "requestedDpr": requestedDpr,
            "requestedFontPx": requestedFont,
            "observedDpr": observedDpr,
            "observedFontPx": observedFontPx,
            "logicalWidth": logicalWidth,
            "logicalHeight": logicalHeight,
            "region": ["x": regionX, "y": regionY, "width": regionWidth, "height": regionHeight],
            "capture": EditorQmlLane.profileCaptureLabel,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: metadata,
                options: [.sortedKeys])
        else { return false }
        let path =
            EditorQmlBootstrap.profileArtifactPath(
                scratch: projectRoot, profile: EditorQmlBootstrap.stagedProfile, pane: pane) + ".json"
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// A refused record names itself in the child's own output: the parent prints
    /// that output when the child fails, so a missing pane identity, palette or
    /// fixture is a named refusal instead of a silent `false`.
    private func reportProfileRefusal(
        pane: String, drawnRoot: String, palette: Bool,
        fixture: String?
    ) {
        let line =
            "editorqml-drawer: refused \(pane) profile metadata (drawnRoot=\"\(drawnRoot)\","
            + " knownPane=\(EditorQmlLane.paneIdentities[pane] != nil), palette=\(palette),"
            + " fixture=\"\(fixture ?? "")\", profile=\"\(profileName)\")\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
