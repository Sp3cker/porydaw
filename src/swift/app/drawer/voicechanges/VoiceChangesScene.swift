import PorydawCore

struct VoiceScenePalette: Sendable {
    var primaryText: String
    var secondaryText: String
    var gridLineSub1: String
    var gridLineSub2: String
    var gridLineSub3: String
    var gridLineBar: String
    var gridLineBeat: String
    var gridLineBeatFine: String
    var heldSpan: String
    var markerLine: String
}

struct VoiceChangesSceneInput: Sendable {
    var state: VoiceChangesState
    var entries: [VoiceProjectionEntry]
    var palette: VoiceScenePalette
    var typography: VoiceTypographyValues
    var gutterTitle: String
}

struct VoiceHoverValue: Equatable, Sendable {
    var visible = false
    var text = ""
    var rect = DrawerRectValue()
    var tick: Tick = 0
    var marker = false
}

struct VoiceTransientValue: Equatable, Sendable {
    var visible = false
    var x: Double = 0
    var tick: Tick = 0
}

struct VoiceModalValues: Equatable, Sendable {
    var pickerOpen = false
    var pickerTitle = ""
    var pickerFilter = ""
    var pickerIndex = -1
    var pickerHasMatch = false
    var pickerRows: [VoicePickerRowValue] = []
    var menuOpen = false
    var menuX: Double = 0
    var menuY: Double = 0
    var menuRows: [VoiceMenuRowValue] = []
}

/// Complete derived Voice Changes scene. Every member is a plain Swift value.
struct VoiceChangesScene: Sendable {
    var trackAvailable = false
    var entries: [VoiceProjectionEntry] = []
    var markers: [VoiceMarkerValue] = []
    var gutterTexts: [DrawerTextValue] = []
    var spans: [DrawerRectValue] = []
    var gridLines: [DrawerRectValue] = []
    var readout = VoiceReadoutValue()
    var hover = VoiceHoverValue()
    var transient = VoiceTransientValue()
    var modal = VoiceModalValues()

    static let detached = Self()

    static func build(_ input: borrowing VoiceChangesSceneInput) -> Self {
        let entries = projectedEntries(input.entries, state: input.state)
        return Self(
            trackAvailable: input.state.attached && input.state.lane.track != nil,
            entries: entries,
            markers: markerValues(input, entries: entries),
            gutterTexts: gutterValues(input),
            spans: spanValues(input, entries: entries),
            gridLines: gridValues(input),
            readout: readoutValue(input.state),
            hover: hoverValue(input.state),
            transient: transientValue(input.state),
            modal: modalValues(input.state))
    }

    static func projectedEntries(_ entries: [VoiceProjectionEntry],
                                 state: borrowing VoiceChangesState) -> [VoiceProjectionEntry] {
        VoiceChangesProjection.moving(entries, drag: state.pointerMode.activeDrag)
    }

    static func measurementLabels(entries: borrowing [VoiceProjectionEntry],
                                  bank: borrowing [BankSlotView]) -> [String] {
        var labels: [String] = ["No voice"]
        labels.reserveCapacity(entries.count + 1)
        for index in entries.indices {
            let entry = entries[index]
            let view = bank.indices.contains(entry.value) ? bank[entry.value] : nil
            let label = VoiceLanePolicy.label(slot: entry.value, view: view)
            labels.append(label.isEmpty ? "No voice" : label)
        }
        return labels
    }

    static func xForTick(_ tick: Tick, view: borrowing VoiceViewFacts) -> Double {
        view.camera.displayX(tick: Double(tick), origin: 0, dpr: view.devicePixelRatio)
    }

    static func snapTick(at x: Double, fine: Bool,
                         state: borrowing VoiceChangesState) -> Tick {
        guard let view = state.view else { return 0 }
        let raw = max(0, view.camera.tickAtContentX(max(0, x)))
        if fine {
            return TimelineSnapPolicy.fineSnap(
                raw, clockTicks: TimelineSnapPolicy.clockTicks(
                    division: state.lane.division,
                    extendedClocks: state.lane.extendedClocks))
        }
        return Tick(max(0, view.metrics.snapTick(raw, camera: view.camera)))
    }

    static func markerHit(at x: Double, markers: borrowing [VoiceMarkerValue],
                          baseFontPx: Double) -> VoiceOccurrence? {
        VoiceChangesProjection.marker(
            at: x, in: markers,
            hitRadius: fontPx(baseFontPx, VoiceChangesPagePolicy.markerHitRadiusFactor))
    }

    static func contextLabel(slot: Int, bank: borrowing [BankSlotView]) -> String {
        guard bank.indices.contains(slot) else { return "" }
        return VoiceLanePolicy.label(slot: slot, view: bank[slot])
    }

    static func markerValues(_ input: borrowing VoiceChangesSceneInput,
                             entries: [VoiceProjectionEntry]) -> [VoiceMarkerValue] {
        let state = input.state
        guard let view = state.view, view.plotWidth > 0, view.plotHeight > 0,
              state.attached, state.lane.track != nil else { return [] }
        let pad = fontPx(view.baseFontPx, VoiceChangesPagePolicy.spaceOneFactor)
        let gap = max(fontPx(view.baseFontPx, VoiceChangesPagePolicy.hoverPaintPaddingFactor), pad)
        let selected = state.pointerMode.drag?.identity ?? state.selectedOccurrence?.text
        return VoiceChangesProjection.markers(VoiceMarkerProjectionInput(
            entries: entries,
            slots: state.bank,
            plotWidth: view.plotWidth,
            plotHeight: view.plotHeight,
            pad: pad,
            gap: gap,
            stairLimit: fontPx(view.baseFontPx, VoiceChangesPagePolicy.spaceFourFactor),
            physicalPixel: physicalPixel(view.devicePixelRatio),
            labelColor: input.palette.primaryText,
            lineColor: input.palette.markerLine,
            selectedIdentity: selected,
            hoverIdentity: state.hoveredOccurrence?.text,
            previewIdentity: state.pointerMode.activeDrag?.identity,
            typography: input.typography,
            camera: view.camera,
            devicePixelRatio: view.devicePixelRatio))
    }

    static func gutterValues(_ input: borrowing VoiceChangesSceneInput) -> [DrawerTextValue] {
        guard let view = input.state.view else { return [] }
        return VoiceChangesProjection.gutterTexts(VoiceGutterProjectionInput(
            plotHeight: view.plotHeight,
            plotOrigin: view.plotOrigin,
            title: input.gutterTitle,
            summary: input.state.lane.track == nil ? nil : countSummary(input.state.lane.points),
            titleFont: input.typography.titleFont,
            captionFont: input.typography.captionFont,
            titleHeight: input.typography.titleHeight,
            captionHeight: input.typography.captionHeight,
            titleColor: input.palette.primaryText,
            captionColor: input.palette.secondaryText))
    }

    static func spanValues(_ input: borrowing VoiceChangesSceneInput,
                           entries: [VoiceProjectionEntry]) -> [DrawerRectValue] {
        let state = input.state
        guard let view = state.view, view.plotHeight > 0, view.plotWidth > 0,
              state.lane.track != nil else { return [] }
        return VoiceChangesProjection.spans(VoiceSpanProjectionInput(
            entries: entries,
            firstProgram: state.lane.firstProgram,
            lengthTicks: state.lane.lengthTicks,
            plotWidth: view.plotWidth,
            plotHeight: view.plotHeight,
            color: input.palette.heldSpan,
            camera: view.camera,
            devicePixelRatio: view.devicePixelRatio))
    }

    static func gridValues(_ input: borrowing VoiceChangesSceneInput) -> [DrawerRectValue] {
        let state = input.state
        guard let view = state.view, view.plotHeight > 0, view.plotWidth > 0,
              state.lane.track != nil else { return [] }
        return VoiceChangesProjection.grid(
            metrics: view.metrics,
            camera: view.camera,
            plotWidth: view.plotWidth,
            plotHeight: view.plotHeight,
            colors: VoiceGridProjectionColors(
                subdivision1: input.palette.gridLineSub1,
                subdivision2: input.palette.gridLineSub2,
                subdivision3: input.palette.gridLineSub3,
                bar: input.palette.gridLineBar,
                beat: input.palette.gridLineBeat,
                fineBeat: input.palette.gridLineBeatFine))
    }

    static func readoutValue(_ state: borrowing VoiceChangesState) -> VoiceReadoutValue {
        guard let view = state.view else { return VoiceReadoutValue() }
        return VoiceChangesProjection.readout(
            firstProgram: state.lane.firstProgram,
            tick: state.effectiveContextTick,
            points: state.lane.points,
            slots: state.bank,
            pad: fontPx(view.baseFontPx, VoiceChangesPagePolicy.spaceOneFactor),
            plotWidth: view.plotWidth,
            plotHeight: view.plotHeight)
    }

    static func hoverValue(_ state: borrowing VoiceChangesState) -> VoiceHoverValue {
        guard let view = state.view else { return VoiceHoverValue() }
        if let occurrence = state.hoveredOccurrence {
            let x = xForTick(occurrence.tick, view: view)
            let pad = fontPx(view.baseFontPx, VoiceChangesPagePolicy.spaceOneFactor)
            return VoiceHoverValue(
                visible: false, text: "",
                rect: DrawerRectValue(x: x + pad, y: 0,
                                      width: max(0, view.plotWidth - x),
                                      height: view.plotHeight),
                tick: occurrence.tick, marker: true)
        }
        guard !state.hoverLabel.isEmpty else { return VoiceHoverValue() }
        let x = xForTick(state.hoverTick, view: view)
        let pad = fontPx(view.baseFontPx, VoiceChangesPagePolicy.spaceOneFactor)
        return VoiceHoverValue(
            visible: true, text: state.hoverLabel,
            rect: DrawerRectValue(x: x + pad, y: 0,
                                  width: max(0, view.plotWidth - x),
                                  height: view.plotHeight),
            tick: state.hoverTick, marker: false)
    }

    static func transientValue(_ state: borrowing VoiceChangesState) -> VoiceTransientValue {
        guard let view = state.view, let drag = state.pointerMode.activeDrag else {
            return VoiceTransientValue()
        }
        return VoiceTransientValue(
            visible: true, x: xForTick(drag.previewTick, view: view), tick: drag.previewTick)
    }

    static func modalValues(_ state: borrowing VoiceChangesState) -> VoiceModalValues {
        switch state.modalMode {
        case .none:
            return VoiceModalValues()
        case let .picker(picker):
            let rows = VoiceChangesProjection.pickerRows(
                slots: state.bank, filter: picker.filter, selected: picker.program)
            return VoiceModalValues(
                pickerOpen: true,
                pickerTitle: picker.title,
                pickerFilter: picker.filter,
                pickerIndex: rows.firstIndex(where: { $0.program == picker.program }) ?? -1,
                pickerHasMatch: picker.program >= 0,
                pickerRows: rows)
        case let .menu(menu):
            return VoiceModalValues(
                menuOpen: true, menuX: menu.anchorX, menuY: menu.anchorY,
                menuRows: VoiceChangesProjection.menuRows(for: menu.target))
        }
    }

    private static func fontPx(_ base: Double, _ multiplier: Double) -> Double {
        multiplier == 0 ? 0 : max(1, (base * multiplier).rounded())
    }

    private static func countSummary(_ points: borrowing [LanePoint]) -> String {
        let count = points.count
        return count == 0 ? "no voice set · double-click to add"
            : "\(count) change(s) · double-click to edit"
    }
}
