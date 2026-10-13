import Foundation
import PorydawCore
import QtBridge
import PorydawAppEventList
import PorydawAppCommands


enum EventListMenuKind {
    case chunk, filter, row, type
    static let categories: [(bit: Int, label: String)] = [
        (1, "Notes"), (2, "Control changes"), (4, "Program changes"),
        (8, "Pitch bends"), (16, "Aftertouch"), (32, "SysEx"), (64, "Meta"),
    ]
}


@MainActor
extension EventListPresenter {
    func dispatchOpenChunkMenu(x: Double, y: Double) {
        guard visible else { return }
        menuKind = .chunk
        openMenu(
            x: x, y: y,
            items: chunkLabels.enumerated().map { (entry: (offset: Int, element: String)) -> MenuRow in
                MenuRow(
                    actionId: entry.offset, text: entry.element, checkable: true,
                    checked: entry.offset == chunkIndex)
            })
    }

    func dispatchOpenFilterMenu(x: Double, y: Double) {
        guard visible else { return }
        menuKind = .filter
        openMenu(
            x: x, y: y,
            items: EventListMenuKind.categories.map { (category: (bit: Int, label: String)) -> MenuRow in
                MenuRow(
                    actionId: category.bit, text: category.label, checkable: true,
                    checked: filterMask & category.bit != 0)
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
        var items = [MenuRow(actionId: 1, text: "Insert event")]
        if row?.kind == .program, row?.eventIndex != nil {
            items.append(MenuRow(actionId: 2, text: "Show voice in voicegroup"))
        }
        if row?.eventIndex != nil {
            items.append(MenuRow(actionId: 0, enabled: false, separator: true))
            items.append(
                MenuRow(
                    actionId: 3, text: "Move Event Up (Same Tick)",
                    enabled: moveDestination(delta: -1) != nil,
                    shortcutText: keybindings.sequences("eventlist.move_up")
                        .first?.nativeText ?? ""))
            items.append(
                MenuRow(
                    actionId: 4, text: "Move Event Down (Same Tick)",
                    enabled: moveDestination(delta: 1) != nil,
                    shortcutText: keybindings.sequences("eventlist.move_down")
                        .first?.nativeText ?? ""))
        }
        items.append(MenuRow(actionId: 0, enabled: false, separator: true))
        items.append(
            MenuRow(
                actionId: 5, text: deletable > 0 ? "Delete \(deletable) event(s)" : "Delete",
                enabled: deletable > 0))
        openMenu(x: x, y: y, items: items)
    }

    func dispatchOpenTypeMenu(x: Double, y: Double) {
        guard visible, model.isCellEditable(row: currentRow, column: 1) else { return }
        menuRow = currentRow
        menuKind = .type
        let names = [
            "Note off", "Note on", "Poly aftertouch", "Control change",
            "Program change", "Channel aftertouch", "Pitch bend",
            "SysEx (F0)", "SysEx (F7)", "Tempo", "Meta",
        ]
        openMenu(
            x: x, y: y,
            items: names.enumerated().map { (entry: (offset: Int, element: String)) -> MenuRow in
                MenuRow(
                    actionId: entry.offset, text: entry.element,
                    enabled: entry.offset != 9 || chunkIndex == 0,
                    checkable: true, checked: entry.offset == model.rowType(row: menuRow))
            })
    }

    private func openMenu(x: Double, y: Double, items: [MenuRow]) {
        menuX = x
        menuY = y
        menuShortcutText =
            items.max(by: { (lhs: MenuRow, rhs: MenuRow) -> Bool in
                lhs.shortcutText.count < rhs.shortcutText.count
            })?.shortcutText ?? ""
        menuSeparatorCount = items.filter(\.separator).count
        menuItems.reset(to: items)
        setMenuOpen(open: true)
    }

    func dispatchDismissMenu() {
        menuKind = nil
        menuRow = -1
        menuItems.reset(to: [])
        menuShortcutText = ""
        menuSeparatorCount = 0
        setMenuOpen(open: false)
    }

    func invalidateRowMenu() {
        if menuOpen && menuKind == .row {
            dispatchDismissMenu()
        }
    }

    func dispatchActivateMenuAction(actionId: Int) {
        guard menuOpen,
            menuItems.asArray.contains(where: {
                $0.actionId == actionId && $0.enabled && !$0.separator
            }),
            let kind = menuKind
        else { return }
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
                    program < 128
                else { break }
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
