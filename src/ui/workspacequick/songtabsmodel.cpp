#include "ui/workspacequick/songtabsmodel.h"

#include "ui/songtab.h"

#include <QQmlEngine>

namespace {

// The strip label: the document label when present, else the song name,
// with the same dirty asterisk the workspace strip shows.
QString tabTitle(const SongTab &tab)
{
    QString label = tab.document().label();
    if (label.isEmpty())
        label = tab.name().value();
    return tab.document().isDirty() ? label + QLatin1Char('*') : label;
}

} // namespace

SongTabsModel::SongTabsModel(std::vector<std::unique_ptr<SongTab>> &pages,
                             SongTab *const &selectedTab, QObject *parent)
    : QAbstractListModel(parent)
    , m_pages(pages)
    , m_selectedTab(selectedTab)
{
    for (const auto &page : m_pages) {
        if (!page)
            continue;
        observeTab(*page);
        // Once-per-session QML exposure: the session stays owned by the
        // borrowed C++ collection, so the engine must never delete it —
        // in particular across Q_INVOKABLE returns, which default to
        // JavaScriptOwnership without this override.
        QQmlEngine::setObjectOwnership(page.get(), QQmlEngine::CppOwnership);
    }
}

QObject *SongTabsModel::selectedSession() const
{
    return m_selectedTab;
}

int SongTabsModel::selectedIndex() const
{
    return rowFor(m_selectedTab);
}

void SongTabsModel::notifySelectionChanged()
{
    // The borrowed slot is the only selection state; both derived
    // properties re-read it.
    emit selectionChanged();
    emit selectedIndexChanged();
}

SongTab *SongTabsModel::append(std::unique_ptr<SongTab> page)
{
    if (!page)
        return nullptr;
    SongTab *const tab = page.get();
    const int row = int(m_pages.size());
    beginInsertRows(QModelIndex(), row, row);
    m_pages.push_back(std::move(page));
    endInsertRows();
    observeTab(*tab);
    QQmlEngine::setObjectOwnership(tab, QQmlEngine::CppOwnership);
    return tab;
}

std::unique_ptr<SongTab> SongTabsModel::take(SongTab &tab)
{
    const int row = rowFor(&tab);
    if (row < 0)
        return nullptr;
    const int previousSelectedIndex = selectedIndex();
    beginRemoveRows(QModelIndex(), row, row);
    std::unique_ptr<SongTab> removed = std::move(m_pages[size_t(row)]);
    m_pages.erase(m_pages.begin() + row);
    // `removed` keeps the session alive through endRemoveRows so views still
    // see valid rows while the removal settles.
    endRemoveRows();
    unobserveTab(*removed);
    notifySelectedIndexIfChanged(previousSelectedIndex);
    return removed;
}

std::vector<std::unique_ptr<SongTab>> SongTabsModel::takeAll()
{
    if (m_pages.empty())
        return {};
    const int previousSelectedIndex = selectedIndex();
    beginRemoveRows(QModelIndex(), 0, int(m_pages.size()) - 1);
    // The whole storage moves out at once: no session is destroyed while
    // the removal bracket is open.
    std::vector<std::unique_ptr<SongTab>> removed = std::move(m_pages);
    m_pages.clear(); // a moved-from vector's emptiness is unspecified; make it exact
    endRemoveRows();
    for (const auto &page : removed)
        unobserveTab(*page);
    notifySelectedIndexIfChanged(previousSelectedIndex);
    return removed;
}

bool SongTabsModel::move(SongTab &tab, int destinationIndex)
{
    const int source = rowFor(&tab);
    const int count = int(m_pages.size());
    if (source < 0 || destinationIndex < 0 || destinationIndex >= count ||
        destinationIndex == source)
        return false;
    // beginMoveRows wants the position before which the row lands, so a
    // final-index destination on a forward move is one past that.
    const int destinationChild =
        destinationIndex > source ? destinationIndex + 1 : destinationIndex;
    const int previousSelectedIndex = selectedIndex();
    if (!beginMoveRows(QModelIndex(), source, source, QModelIndex(), destinationChild))
        return false;
    std::unique_ptr<SongTab> page = std::move(m_pages[size_t(source)]);
    m_pages.erase(m_pages.begin() + source);
    m_pages.insert(m_pages.begin() + destinationIndex, std::move(page));
    endMoveRows();
    // The selection identity cannot change here; only its derived index can.
    notifySelectedIndexIfChanged(previousSelectedIndex);
    return true;
}

SongTab *SongTabsModel::songAt(int row) const
{
    if (row < 0 || row >= int(m_pages.size()))
        return nullptr;
    return m_pages[size_t(row)].get();
}

int SongTabsModel::rowFor(const SongTab *tab) const
{
    if (!tab)
        return -1;
    for (size_t row = 0; row < m_pages.size(); ++row) {
        if (m_pages[row].get() == tab)
            return int(row);
    }
    return -1;
}

void SongTabsModel::refresh(SongTab &tab)
{
    const int row = rowFor(&tab);
    if (row < 0)
        return;
    const QModelIndex modelIndex = index(row);
    // Saved-state changes (label, path, dirty flags) arrive without a tab
    // signal; every role re-reads the borrowed tab.
    emit dataChanged(modelIndex, modelIndex);
}

int SongTabsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_pages.size());
}

QVariant SongTabsModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.column() != 0 || index.parent().isValid())
        return {};
    const int row = index.row();
    if (row < 0 || row >= int(m_pages.size()))
        return {};
    SongTab &tab = *m_pages[size_t(row)];
    switch (role) {
    case Qt::DisplayRole:
    case TitleRole:
        return tabTitle(tab);
    case Qt::ToolTipRole:
    case TooltipRole:
        return tab.document().midPath();
    case SongKeyRole:
        return tab.name().value();
    case SessionRole:
        return QVariant::fromValue(static_cast<QObject *>(&tab));
    case ReadyRole:
        return tab.isReady();
    default:
        return {};
    }
}

QHash<int, QByteArray> SongTabsModel::roleNames() const
{
    return {
        {Qt::DisplayRole, "display"}, {SongKeyRole, "songKey"}, {SessionRole, "session"},
        {TitleRole, "title"},         {TooltipRole, "tooltip"}, {ReadyRole, "ready"},
    };
}

void SongTabsModel::observeTab(SongTab &tab)
{
    // Capture the pointer: a by-value capture of the reference parameter
    // would copy the SongTab itself, and the connection dies with the sender
    // so the pointer can never dangle.
    SongTab *const observed = &tab;
    connect(observed, &SongTab::edited, this,
            [this, observed] { emitRowRolesChanged(*observed, {TitleRole}); });
    connect(observed, &SongTab::readinessChanged, this,
            [this, observed] { emitRowRolesChanged(*observed, {ReadyRole}); });
}

void SongTabsModel::unobserveTab(SongTab &tab)
{
    disconnect(&tab, &SongTab::edited, this, nullptr);
    disconnect(&tab, &SongTab::readinessChanged, this, nullptr);
}

void SongTabsModel::emitRowRolesChanged(const SongTab &tab, const QList<int> &roles)
{
    const int row = rowFor(&tab);
    if (row < 0)
        return; // a removed session may outlive its membership
    const QModelIndex modelIndex = index(row);
    emit dataChanged(modelIndex, modelIndex, roles);
}

void SongTabsModel::notifySelectedIndexIfChanged(int previousIndex)
{
    if (selectedIndex() != previousIndex)
        emit selectedIndexChanged();
}
