extension ApplicationSession {
    func connectVoiceSamples() {
        voiceList.onNewSampleRequested = { [weak self] slot in
            self?.sampleStudio().requestImport(slot: slot)
        }
        voiceList.onEditSampleRequested = { [weak self] slot in
            self?.sampleStudio().requestEdit(slot: slot)
        }
    }
}
