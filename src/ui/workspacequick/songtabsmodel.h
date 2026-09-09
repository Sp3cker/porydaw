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

// Read-only QML projection over the borrowed session collection and selection.
// Mutation brackets preserve C++ ownership and publish explicit CppOwnership.
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
        QuickViewRole,
        TitleRole,
        TooltipRole,
        ReadyRole,
    };
    Q_ENUM(Roles)

    // Borrows storage that must outlive the model.
    SongTabsModel(std::vector<std::unique_ptr<SongTab>> &pages, SongTab *const &selectedTab,
                  QObject *parent = nullptr);

    QObject *selectedSession() const;
    int selectedIndex() const;
    // Re-publishes both selected properties after the owner changes selection.
    void notifySelectionChanged();

    // Adds the page as the last row and returns it. Null input adds nothing.
    SongTab *append(std::unique_ptr<SongTab> page);
    // Removes the tab's row and hands the session back; null when the tab is
    // not in the model. The session stays alive until the caller destroys it.
    std::unique_ptr<SongTab> take(SongTab &tab);
    // Empties the collection and hands every session back alive, in order.
    std::vector<std::unique_ptr<SongTab>> takeAll();
    Q_INVOKABLE SongTab *songAt(int row) const;
    // The tab's row, or -1 when it is not in the borrowed collection.
    int rowFor(const SongTab *tab) const;
    // Re-publishes title and tooltip after a saved-state change that emits no
    // tab signal (label, path, dirty flags).
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
