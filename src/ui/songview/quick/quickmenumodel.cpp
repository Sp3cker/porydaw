#include "ui/songview/quick/quickmenumodel.h"

#include <QAction>
#include <QKeySequence>
#include <QStringView>
#include <QVariant>

namespace songview {
namespace {

/// Removes mnemonic markers while preserving an escaped "&&".
QString stripAccelerator(QStringView text)
{
    QString stripped;
    stripped.reserve(text.size());
    for (qsizetype index = 0; index < text.size(); ++index) {
        if (text.at(index) != u'&') {
            stripped += text.at(index);
            continue;
        }
        if (index + 1 < text.size() && text.at(index + 1) == u'&') {
            stripped += u'&';
            ++index;
        }
    }
    return stripped;
}

} // namespace

QuickMenuItem QuickMenuItem::makeSeparator()
{
    QuickMenuItem item;
    item.separator = true;
    return item;
}

QuickMenuItem QuickMenuItem::fromAction(QAction &source, int id)
{
    QuickMenuItem item;
    item.id = id;
    item.enabled = source.isEnabled();
    item.checkable = source.isCheckable();
    item.checked = source.isChecked();
    item.shortcutText = source.shortcut().toString(QKeySequence::NativeText);
    item.backing = Backing::Action;
    item.action = &source;
    item.text = stripAccelerator(source.text());
    return item;
}

QuickMenuModel::QuickMenuModel(QObject *parent) : QAbstractListModel(parent) {}

int QuickMenuModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant QuickMenuModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= int(m_items.size()))
        return {};
    const QuickMenuItem &item = m_items[std::size_t(index.row())];
    switch (role) {
    case IdRole:
        return item.id;
    case TextRole:
        return item.text;
    case ShortcutRole:
        return item.shortcutText;
    case CheckableRole:
        return item.checkable;
    case CheckedRole:
        return item.checked;
    case EnabledRole:
        return item.enabled;
    case SeparatorRole:
        return item.separator;
    case HasSubmenuRole:
        return !item.children.empty();
    default:
        return {};
    }
}

QHash<int, QByteArray> QuickMenuModel::roleNames() const
{
    return {
        {IdRole, "itemId"},
        {TextRole, "text"},
        {ShortcutRole, "shortcutText"},
        {CheckableRole, "checkable"},
        {CheckedRole, "checked"},
        {EnabledRole, "enabled"},
        {SeparatorRole, "separator"},
        {HasSubmenuRole, "hasSubmenu"},
    };
}

int QuickMenuModel::count() const
{
    return int(m_items.size());
}

const QuickMenuItem *QuickMenuModel::itemAt(int row) const
{
    if (row < 0 || row >= int(m_items.size()))
        return nullptr;
    return &m_items[std::size_t(row)];
}

int QuickMenuModel::rowForId(int id) const
{
    for (std::size_t index = 0; index < m_items.size(); ++index) {
        if (m_items[index].id == id)
            return int(index);
    }
    return -1;
}

void QuickMenuModel::setItems(std::vector<QuickMenuItem> items)
{
    const bool countDidChange = items.size() != m_items.size();
    beginResetModel();
    clearSubmenus();
    m_items = std::move(items);
    m_submenus.resize(m_items.size());
    endResetModel();
    if (countDidChange)
        emit countChanged();
}

bool QuickMenuModel::setItemChecked(int row, bool checked)
{
    if (row < 0 || row >= int(m_items.size()))
        return false;
    QuickMenuItem &item = m_items[std::size_t(row)];
    if (item.separator || !item.checkable)
        return false;
    if (item.checked == checked)
        return true;
    item.checked = checked;
    const QModelIndex modelIndex = index(row);
    emit dataChanged(modelIndex, modelIndex, {CheckedRole});
    return true;
}

QuickMenuModel *QuickMenuModel::submenuForRow(int row)
{
    if (row < 0 || row >= int(m_items.size()))
        return nullptr;
    const QuickMenuItem &item = m_items[std::size_t(row)];
    if (item.separator)
        return nullptr;
    QPointer<QuickMenuModel> &cached = m_submenus[std::size_t(row)];
    if (!cached) {
        cached = new QuickMenuModel(this);
        cached->setItems(item.children);
    }
    return cached.data();
}

void QuickMenuModel::clearSubmenus()
{
    for (QPointer<QuickMenuModel> &submenu : m_submenus) {
        if (submenu)
            delete submenu.data();
    }
    m_submenus.clear();
}

} // namespace songview
