#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QList>
#include <QObject>
#include <QString>
#include <QVariant>

#include <memory>
#include <vector>

class SongTab;

// The Quick tab strip's model: a read-only projection of the workspace's
// authoritative open-tab collection and selection. Both are borrowed — the
// model keeps references to the page vector and to the selected-tab slot —
// so the existing collection order and the one selection authority remain
// the only ones: every read (roles, songAt, rowFor, the selectedSession and
// selectedIndex properties) goes straight through the borrowed storage, and
// the model never copies rows, resets, or decides selection.
//
// The controller mutates through append/take/takeAll/move, which own the
// entire Qt notification bracket and preserve the moved unique_ptr values
// and every session's identity. A removed session outlives the bracket:
// take/takeAll hand ownership back only after the rows have settled, so
// callers can tear down pages and borrowed references afterwards. QML sees
// only the roles and the read-only selection properties;
// notifySelectionChanged() is the owner's notification after it reassigns
// the borrowed selection slot, since nothing inside the model can observe
// that write.
//
// QML lifetime: every published session is explicitly CppOwnership — the
// borrowed C++ collection is the sole owner and the engine must never
// delete a tab. Publication happens once per session (construction covers
// initial rows, append covers later rows).
//
// Row content projects the tabs directly: SongTab::edited refreshes the
// title (dirty asterisk), SongTab::readinessChanged refreshes the ready
// flag, and refresh() covers saved-state changes that emit no signal.
class SongTabsModel final : public QAbstractListModel
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(SongTabsModel)

    Q_PROPERTY(QObject *selectedSession READ selectedSession NOTIFY selectionChanged)
    Q_PROPERTY(int selectedIndex READ selectedIndex NOTIFY selectedIndexChanged)

  public:
    enum Roles {
        SongKeyRole = Qt::UserRole + 1,
        SessionRole,
        TitleRole,
        TooltipRole,
        ReadyRole,
    };
    Q_ENUM(Roles)

    // Borrows the authoritative tab collection and the selected-tab slot.
    // Both must outlive the model; neither is copied, and only the mutation
    // API below changes the collection.
    SongTabsModel(std::vector<std::unique_ptr<SongTab>> &pages, SongTab *const &selectedTab,
                  QObject *parent = nullptr);

    QObject *selectedSession() const;
    int selectedIndex() const;
    // The owner calls this after reassigning the borrowed selection slot;
    // both derived properties re-read it. Internal index-only changes
    // (move/remove brackets) emit selectedIndexChanged alone so a moved row
    // never pretends the selection changed.
    void notifySelectionChanged();

    // Adds the page as the last row and returns it. Null input adds nothing.
    SongTab *append(std::unique_ptr<SongTab> page);
    // Removes the tab's row and hands the session back; null when the tab is
    // not in the model. The session stays alive until the caller destroys it.
    std::unique_ptr<SongTab> take(SongTab &tab);
    // Empties the collection and hands every session back alive, in order.
    std::vector<std::unique_ptr<SongTab>> takeAll();
    // Moves the tab so it lands at destinationIndex (final-index semantics);
    // false for unknown tabs, out-of-range destinations, and no-ops.
    bool move(SongTab &tab, int destinationIndex);
    SongTab *songAt(int row) const;
    // The tab's row, or -1 when it is not in the borrowed collection.
    int rowFor(const SongTab *tab) const;
    // Re-publishes every role of the tab's row after a saved-state change
    // that emits no tab signal (label, path, dirty flags).
    void refresh(SongTab &tab);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

  signals:
    void selectionChanged();
    void selectedIndexChanged();

  private:
    void observeTab(SongTab &tab);
    void unobserveTab(SongTab &tab);
    void emitRowRolesChanged(const SongTab &tab, const QList<int> &roles);
    void notifySelectedIndexIfChanged(int previousIndex);

    std::vector<std::unique_ptr<SongTab>> &m_pages;
    SongTab *const &m_selectedTab;
};
