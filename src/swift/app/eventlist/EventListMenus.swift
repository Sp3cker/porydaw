import Foundation
import PorydawCore
import QtBridge
import PorydawAppEventList
import PorydawAppCommands

@MainActor
@QtBridgeable
public final class EventListMenuItem {
    public let actionId: Int
    public let text: String
    public let enabled: Bool
    public let checkable: Bool
    public let checked: Bool
    public let separator: Bool
    public let shortcutText: String

    init(_ id: Int, _ text: String, enabled: Bool = true,
         checkable: Bool = false, checked: Bool = false,
         separator: Bool = false, shortcutText: String = "") {
        actionId = id
        self.text = text
        self.enabled = enabled
        self.checkable = checkable
        self.checked = checked
        self.separator = separator
        self.shortcutText = shortcutText
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
    static func roles(palette: GridPalette, typography: Typography)
        -> [String: QVariantSettable]
    {
        return ["bodyFont": typography.body.map,
         "controlFont": typography.body.map,
         "tableFont": typography.tableMono.map,
         "headerFont": typography.caption.map,
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
        let row = model.row(at: menuRow)
        let keybindings = KeybindingRegistry()
        let deletable = selectedRows.filter {
            guard let selected = model.row(at: $0) else { return false }
            return selected.eventIndex != nil || selected.tempo != nil
        }.count
        var items = [EventListMenuItem(1, "Insert event")]
        if row?.kind == .program, row?.eventIndex != nil {
            items.append(EventListMenuItem(2, "Show voice in voicegroup"))
        }
        if row?.eventIndex != nil {
            items.append(EventListMenuItem(0, "", enabled: false, separator: true))
            items.append(EventListMenuItem(3, "Move Event Up (Same Tick)",
                                           enabled: moveDestination(delta: -1) != nil,
                                           shortcutText: keybindings.sequences("eventlist.move_up")
                                               .first?.nativeText ?? ""))
            items.append(EventListMenuItem(4, "Move Event Down (Same Tick)",
                                           enabled: moveDestination(delta: 1) != nil,
                                           shortcutText: keybindings.sequences("eventlist.move_down")
                                               .first?.nativeText ?? ""))
        }
        items.append(EventListMenuItem(0, "", enabled: false, separator: true))
        items.append(EventListMenuItem(5, deletable > 0 ? "Delete \(deletable) event(s)" : "Delete",
                                       enabled: deletable > 0))
        openMenu(x: x, y: y, items: items)
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
        menuShortcutText = items.max(by: {
            $0.shortcutText.count < $1.shortcutText.count
        })?.shortcutText ?? ""
        menuSeparatorCount = items.filter(\.separator).count
        menuItems.reset(to: items)
        menuOpen = true
    }

    func dispatchDismissMenu() {
        menuOpen = false
        menuKind = nil
        menuRow = -1
        menuItems.reset(to: [])
        menuShortcutText = ""
        menuSeparatorCount = 0
    }

    func dispatchActivateMenuAction(actionId: Int) {
        guard menuOpen, menuItems.asArray.contains(where: {
            $0.actionId == actionId && $0.enabled && !$0.separator
        }),
              let kind = menuKind else { return }
        switch kind {
        case .chunk: setChunk(index: actionId, followTrack: true)
        case .filter: toggleFilter(bit: actionId)
        case .type: _ = commitCellEdit(row: menuRow, column: 1, text: String(actionId))
        case .row:
            switch actionId {
            case 1: insertCopyOfRow(row: menuRow)
            case 2:
                guard let row = model.row(at: menuRow), row.kind == .program,
                      row.eventIndex != nil, let event = row.event,
                      case let .channel(_, program, _) = event.payload,
                      program < 128 else { break }
                onRevealVoiceRequested?(Int(program))
            case 3: onPerformEventListCommand?(EditCommand.moveEventUp.rawValue)
            case 4: onPerformEventListCommand?(EditCommand.moveEventDown.rawValue)
            case 5: deleteSelected()
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
