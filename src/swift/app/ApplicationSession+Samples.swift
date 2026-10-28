extension ApplicationSession {
    func connectVoiceSamples() {
        voiceList.onNewSampleRequested = { [weak self] slot in
            self?.sampleStudio().requestImport(slot: slot)
        }
        voiceList.onEditSampleRequested = { [weak self] slot in
            self?.sampleStudio().requestEdit(slot: slot)
        }
        voiceList.onEditKitRequested = { [weak self] (slot: Int) in
            self?.kitStudio().requestEdit(slot: slot)
        }
    }
}
