import Foundation

@MainActor
extension ApplicationSession {
    /// Refreshes the project's catalog without disturbing live banks or song bindings.
    /// - Returns: Whether a successful scan is live or superseded by a newer successful scan.
    @discardableResult
    public func refreshVoicegroupCatalog() async -> Bool {
        guard let service = catalogService else { return false }
        catalogRefreshIssued += 1
        let generation = catalogRefreshIssued
        do {
            let catalog = try await service.voicegroupCatalog()
            guard catalogService === service, !isDisposed else { return false }
            if generation > catalogRefreshApplied {
                installVoicegroupCatalog(catalog)
                catalogRefreshApplied = generation
                voiceList.catalogRevision += 1
                onVoicegroupCatalogChanged?()
            }
            return true
        } catch {
            guard catalogService === service, !isDisposed else { return false }
            if generation > catalogRefreshApplied {
                let message: String
                if case ProjectServiceError.operationFailed(let reason) = error {
                    message = reason
                } else {
                    message = String(describing: error)
                }
                publishStatusMessage(message: message)
            }
            return false
        }
    }

    func resetVoicegroupCatalog() {
        settingsVoicegroups = []
        voiceList.setVoicegroupChoices([])
        voiceList.sampleChoices = []
        voiceList.waveSymbols = []
        voiceList.drumkitSymbols = []
        voiceList.keysplitTables = [:]
        voiceList.synthChoices = []
        voiceList.synthDefinitions = [:]
        voiceList.synthSymbols = []
        voiceList.canMintSynths = false
        voiceList.adsrDefaults = VoiceListAdsrDefaults()
        voiceList.catalogRevision += 1
        onVoicegroupCatalogChanged?()
    }

    private func installVoicegroupCatalog(_ catalog: VoicegroupCatalog) {
        settingsVoicegroups = catalog.groupArgs
        voiceList.setVoicegroupChoices(catalog.groupArgs)
        voiceList.sampleChoices = catalog.samples
        voiceList.waveSymbols = catalog.waves
        voiceList.drumkitSymbols = catalog.drumkits
        voiceList.keysplitTables = catalog.keysplits
        voiceList.synthChoices = catalog.synths
        voiceList.canMintSynths = catalog.canMintSynths
        voiceList.adsrDefaults = catalog.defaults
        voiceList.synthDefinitions.merge(catalog.synthDefinitions) { _, saved in saved }
        voiceList.synthSymbols.formUnion(catalog.synths)
    }
}
