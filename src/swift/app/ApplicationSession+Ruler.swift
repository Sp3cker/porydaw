import Foundation
import PorydawCore
import PorydawProject
import QtBridge
import PorydawAppAudio
import PorydawAppCommands

@MainActor
extension ApplicationSession {
    struct PendingTimeSignature {
        let session: DocumentSession
        let tick: Tick
        let revision: UInt64
        let numerator: Int
        let denominatorPower: Int
    }
    func openTimeSigPromptImpl(tick: Double) {
        guard let workspace, tick.isFinite, tick >= 0,
            tick < Double(TimeDefaults.noTick)
        else { return }
        workspace.rulerMenu.cancelInsertTimePrompt()
        let session = workspace.session
        let target = TimeDefaults.tick(from: tick)
        let axis = TimeAxis(
            map: TimeMap(
                ticksPerBeat: UInt32(session.document.ticksPerBeat),
                timeSigs: session.document.timeSignatures.map {
                    TimeSigPoint(
                        tick: $0.tick, numerator: $0.numerator,
                        denomPow2: $0.denominatorPower)
                }))
        let signature = axis.signatureAt(target)
        pendingTimeSignature = PendingTimeSignature(
            session: session, tick: target, revision: session.document.revision,
            numerator: signature.numerator, denominatorPower: signature.denomPow2)
        timeSigPromptInitialNumerator = min(32, max(1, signature.numerator))
        timeSigPromptInitialDenominatorPow2 = min(5, max(0, signature.denomPow2))
        var appearance = PromptAppearance.metrics(base: workspace.grid.baseFontPx)
        timeSigPromptFont = PromptAppearance.font(typography: typography)
        appearance["background"] = palette.chromeBackground
        appearance["text"] = palette.primaryText
        appearance["buttonText"] = palette.primaryText
        appearance["buttonBackground"] = palette.chromeBackground
        appearance["pressedBackground"] = palette.hoverChipFill
        appearance["focus"] = palette.editCursor
        appearance["selection"] = palette.tabSelectedBackground
        appearance["selectionText"] = palette.selectionText
        appearance["outline"] = palette.separator
        timeSigPromptAppearance = appearance
        timeSigMenuOpen = false
        timeSigPromptOpen = true
        songTabs.publishTimeSigFlags()
    }

    func openTimeSigPromptAtCursorImpl() {
        guard let session = workspace?.session else { return }
        openTimeSigPrompt(tick: Double(session.editCursor))
    }

    func acceptTimeSigPromptImpl(numerator: Int, denominatorPow2: Int) {
        guard (1...32).contains(numerator), (0...5).contains(denominatorPow2),
            let pending = pendingTimeSignature
        else { return }
        pendingTimeSignature = nil
        timeSigPromptOpen = false
        songTabs.publishTimeSigFlags()
        guard workspace?.session === pending.session,
            pending.session.document.revision == pending.revision,
            numerator != pending.numerator || denominatorPow2 != pending.denominatorPower
        else { return }
        pending.session.document.setTimeSignature(
            tick: pending.tick, numerator: numerator, denominatorPower: denominatorPow2)
    }

    func cancelTimeSigPromptImpl() {
        pendingTimeSignature = nil
        timeSigPromptOpen = false
        songTabs.publishTimeSigFlags()
    }

    func captureTimeSigMenuPressImpl(contentX: Double, pointerY: Double) {
        guard let workspace else { return }
        workspace.rulerMenu.captureRulerPress(contentX: contentX, pointerY: pointerY)
    }

    func openTimeSigMenuImpl() {
        guard let workspace else { return }
        workspace.rulerMenu.cancelInsertTimePrompt()
        cancelTimeSigPrompt()
        workspace.rulerMenu.openRulerAtRelease()
        timeSigMenuOpen = workspace.rulerMenu.isOpen
        songTabs.publishTimeSigFlags()
    }

    func closeTimeSigMenuImpl() {
        workspace?.rulerMenu.close()
        timeSigMenuOpen = false
        songTabs.publishTimeSigFlags()
    }

    func timeSigChipTickImpl(contentX: Double, pointerY: Double) -> Double {
        guard let workspace,
            let tick = workspace.rulerMenu.signatureTick(
                at: contentX, pointerY: pointerY)
        else { return -1 }
        return Double(tick)
    }

    func invalidateTimeSigPrompt(session: DocumentSession, revision: UInt64) {
        if let pending = pendingTimeSignature, pending.session === session,
            pending.revision != revision
        {
            cancelTimeSigPrompt()
        }
    }
}
