import Foundation
import PorydawCore
import QtBridge
import PorydawAppEventList

@MainActor
@QtBridgeable
public final class EventListMenuItem {
    public let actionId: Int
    public let text: String
    public let enabled: Bool
    public let checkable: Bool
    public let checked: Bool

    init(_ id: Int, _ text: String, enabled: Bool = true,
         checkable: Bool = false, checked: Bool = false) {
        actionId = id
        self.text = text
        self.enabled = enabled
        self.checkable = checkable
        self.checked = checked
    }
}

enum EventListMenuKind {
    case chunk, filter, row, type
    static let categories: [(bit: Int, label: String)] = [
        (1, "Notes"), (2, "Control changes"), (4, "Program changes"),
        (8, "Pitch bends"), (16, "Aftertouch"), (32, "SysEx"), (64, "Meta"),
    ]
}

@MainActor
enum EventListAppearance {
    static func roles(palette: GridPalette, baseFontPx: Double)
        -> [String: QVariantSettable]
    {
        let bodyPx = Int(fontPx(baseFontPx, 1.125))
        let body = GridFontSpec(family: gridBodyFamily, pixelSize: bodyPx,
                                weight: 400, letterSpacing: 0).map
        let table = GridFontSpec(family: gridMonoFamily, pixelSize: bodyPx,
                                 weight: 400, letterSpacing: baseFontPx * (-1.0 / 26.0)).map
        let header = GridFontSpec(family: gridBodyFamily,
                                  pixelSize: Int(fontPx(baseFontPx, 1.0)),
                                  weight: 400, letterSpacing: 0).map
        return ["bodyFont": body,
         "controlFont": body,
         "tableFont": table,
         "headerFont": header,
         "tableBackground": palette.menuBackground,
         "tableAlternateBackground": palette.alternateBackground,
         "tableText": palette.windowText,
         "tableSecondaryText": palette.secondaryText,
         "tableSelectedBackground": palette.tabSelectedBackground,
         "tableSelectedText": palette.selectionText,
         "disabledText": palette.disabledText,
         "tableOutline": palette.outline,
         "playheadTint": EventListModel.playheadTint,
         "headerBackground": palette.chromeBackground,
         "headerText": palette.windowText,
         "headerOutline": palette.outline,
         "buttonBackground": palette.buttonBackground,
         "buttonText": palette.buttonText,
         "buttonHoverBackground": palette.buttonHoverBackground,
         "buttonPressedBackground": palette.buttonPressedBackground,
         "buttonPressedText": palette.buttonPressedText,
         "buttonOutline": palette.outline,
         "scrollbarHandle": palette.scrollbarHandle,
         "scrollbarHandleHover": palette.outline,
         "toolTipBackground": palette.inputBackground,
         "toolTipText": palette.windowText,
         "toolTipOutline": palette.outline,
         "inputBackground": palette.buttonHoverBackground,
         "inputText": palette.windowText,
         "inputOutline": palette.outline,
         "focusOutline": palette.focusOutline]
    }
}

@MainActor
extension EventListPresenter {
    func dispatchOpenChunkMenu(x: Double, y: Double) {
        guard visible else { return }
        menuKind = .chunk
        openMenu(x: x, y: y, items: chunkLabels.enumerated().map {
            EventListMenuItem($0.offset, $0.element, checkable: true,
                              checked: $0.offset == chunkIndex)
        })
    }

    func dispatchOpenFilterMenu(x: Double, y: Double) {
        guard visible else { return }
        menuKind = .filter
        openMenu(x: x, y: y, items: EventListMenuKind.categories.map {
            EventListMenuItem($0.bit, $0.label, checkable: true,
                              checked: filterMask & $0.bit != 0)
        })
    }

    func dispatchOpenRowMenu(x: Double, y: Double) {
        guard visible else { return }
        menuKind = .row
        menuRow = currentRow
        let row = model.row(at: currentRow)
        let movable = row?.eventIndex.flatMap { index in
            session?.document.rawMoveBounds(chunk: chunkIndex, index: index)
        }
        openMenu(x: x, y: y, items: [
            EventListMenuItem(1, "Insert event", enabled: chunkIndex >= 0),
            EventListMenuItem(2, "Move up", enabled: movable.map {
                (row?.eventIndex ?? -1) > $0.lowerBound } ?? false),
            EventListMenuItem(3, "Move down", enabled: movable.map {
                (row?.eventIndex ?? -1) < $0.upperBound } ?? false),
            EventListMenuItem(4, "Delete", enabled: !selectedRows.isEmpty),
        ])
    }

    func dispatchOpenTypeMenu(x: Double, y: Double) {
        guard visible, model.isCellEditable(row: currentRow, column: 1) else { return }
        menuRow = currentRow
        menuKind = .type
        let names = ["Note off", "Note on", "Poly aftertouch", "Control change",
                     "Program change", "Channel aftertouch", "Pitch bend",
                     "SysEx (F0)", "SysEx (F7)", "Tempo", "Meta"]
        openMenu(x: x, y: y, items: names.enumerated().map {
            EventListMenuItem($0.offset, $0.element,
                              enabled: $0.offset != 9 || chunkIndex == 0,
                              checkable: true, checked: $0.offset == model.rowType(row: menuRow))
        })
    }

    private func openMenu(x: Double, y: Double, items: [EventListMenuItem]) {
        menuX = x
        menuY = y
        menuItems.reset(to: items)
        menuOpen = true
    }

    func dispatchDismissMenu() {
        menuOpen = false
        menuKind = nil
        menuRow = -1
        menuItems.reset(to: [])
    }

    func dispatchActivateMenuAction(actionId: Int) {
        guard menuOpen, menuItems.asArray.contains(where: {
            $0.actionId == actionId && $0.enabled
        }),
              let kind = menuKind else { return }
        switch kind {
        case .chunk: setChunk(index: actionId, followTrack: true)
        case .filter: toggleFilter(bit: actionId)
        case .type: _ = commitCellEdit(row: menuRow, column: 1, text: String(actionId))
        case .row:
            switch actionId {
            case 1: addEvent()
            case 2, 3:
                guard let index = model.row(at: menuRow)?.eventIndex, let session else { break }
                session.document.moveRawEvent(chunk: chunkIndex, index: index,
                                              to: index + (actionId == 2 ? -1 : 1))
            case 4: deleteSelected()
            default: break
            }
        }
        if kind == .filter {
            openFilterMenu(x: menuX, y: menuY)
        } else {
            dismissMenu()
        }
    }
}
