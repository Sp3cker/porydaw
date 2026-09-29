import PorydawSample
import QtBridge

@MainActor
@QtBridgeable
public final class Sf2ZonePickerRow {
    public let group: Bool
    public let zoneIndex: Int
    public let sample: String
    public let key: String
    public let rate: String
    public let frames: String
    public let loop: String
    public let notes: String
    public let selected: Bool

    init(group: Bool, zoneIndex: Int, columns: [String], selected: Bool = false) {
        self.group = group
        self.zoneIndex = zoneIndex
        sample = columns[0]
        key = columns[1]
        rate = columns[2]
        frames = columns[3]
        loop = columns[4]
        notes = columns[5]
        self.selected = selected
    }
}

@MainActor
@QtBridgeable
public final class Sf2ZonePickerPresenter {
    private var model: Sf2ZonePickerModel
    public var rows: QListModel<Sf2ZonePickerRow> = QListModel()
    /// QML changes this through setFilter(text:) so the published rows stay in sync.
    @QtTracked public private(set) var filter = "" {
        didSet { model.filter = filter; publish() }
    }
    public func setFilter(text: String) { filter = text }
    @QtTracked public var canAccept = false
    public let title: String = Sf2ZonePickerModel.title
    public let searchPlaceholder: String = Sf2ZonePickerModel.searchPlaceholder
    public let columnTitles: [String] = Sf2ZonePickerModel.columnTitles
    @QtIgnored public var selectedZone: Int { model.selectedZone }

    public init(file: Sf2File) {
        model = Sf2ZonePickerModel(file: file)
        publish()
    }

    public func select(row: Int) {
        guard row >= 0 && row < rows.count else { return }
        let choice = rows[row]
        if choice.group { model.selectGroup(title: choice.sample) }
        else { model.select(zoneIndex: choice.zoneIndex) }
        publish()
    }

    private func publish() {
        var result: [Sf2ZonePickerRow] = []
        for group in model.groups {
            result.append(Sf2ZonePickerRow(group: true, zoneIndex: -1,
                                           columns: [group.title, "", "", "", "", ""]))
            for row in group.rows {
                result.append(Sf2ZonePickerRow(group: false, zoneIndex: row.zoneIndex,
                                               columns: row.columns,
                                               selected: row.zoneIndex == model.selectedZone))
            }
        }
        rows.reset(to: result)
        canAccept = model.canAccept
    }
}
