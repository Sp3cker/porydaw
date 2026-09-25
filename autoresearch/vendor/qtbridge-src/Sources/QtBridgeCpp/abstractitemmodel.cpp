// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "abstractitemmodel.h"

#include <QtCore/qobject.h>



class QAbstractItemModelCpp::QAbstractItemModelImpl : public QAbstractItemModel
                                                    , public CallbackBase
{
public:
    void registerIndex(IndexFunc indexCallback) {
        m_props.m_index = [=](int row, int column, const QModelIndex &parent) {
            return indexCallback(m_swiftModel, row, column, &parent);
        };
    }
    void registerParent(ParentFunc parentCallback) {
        m_props.m_parent = [=](const QModelIndex &child) {
            return parentCallback(m_swiftModel, &child);
        };
    }
    void registerColumnCount(ColumnCountFunc columnCountCallback) {
        m_props.m_columnCount = [=](const QModelIndex &index) {
            return columnCountCallback(m_swiftModel, &index);
        };
    }
    void registerInsertColumns(InsertFunc insertColumnsCallback) {
        m_props.m_insertColumns = [=](int column, int count, const QModelIndex &index) {
            return insertColumnsCallback(m_swiftModel, column, count, &index);
        };
    }
    void registerMoveColumns(MoveFunc moveColumnsCallback) {
        m_props.m_moveColumns = [=](const QModelIndex &sourceParent, int sourceColumn, int count,
                                        const QModelIndex &destinationParent, int destinationChild) {
            return moveColumnsCallback(m_swiftModel, &sourceParent, sourceColumn, count,
                                    &destinationParent, destinationChild);
        };
    }
    void registerRemoveColumns(RemoveFunc removeColumnsCallback) {
        m_props.m_removeColumns = [=](int column, int count, const QModelIndex &parent) {
            return removeColumnsCallback(m_swiftModel, column, count, &parent);
        };
    }

    // QAbstractItemModel interface
    QAbstractItemModelImpl(void* swiftModel, QObject* parent = nullptr)
        : QAbstractItemModel(parent), CallbackBase(swiftModel) {}
    ~QAbstractItemModelImpl() = default;

    QModelIndex index(int row, int column, const QModelIndex &parent) const override {
        if (!hasIndex(row, column, parent))
            return QModelIndex();
        if (!m_props.m_index) {
            qWarning() << "No callback registered for index()";
            return QModelIndex();
        }
        return m_props.m_index(row, column, parent);
    }

    QModelIndex parent(const QModelIndex &child) const override {
        if (!child.isValid())
            return {};
        if (!m_props.m_parent) {
            qWarning() << "No callback registered for parent()";
            return {};
        }
        return  m_props.m_parent(child);
    }

    int rowCount(const QModelIndex &parent) const override {
        if (!m_basicProps.m_rowCount) {
            qWarning() << "No callback registered for rowCount()";
            return 0;
        }
        return m_basicProps.m_rowCount(parent);
    }

    int columnCount(const QModelIndex &parent) const override {
        if (!m_props.m_columnCount) {
            qWarning() << "No callback registered for columnCount()";
            return 0;
        }
        return m_props.m_columnCount(parent);
    }

    QVariant data(const QModelIndex &index, int role) const override {
        if (!index.isValid()) {
            qWarning() << "data() called with invalid index";
            return {};
        }
        if (!m_basicProps.m_data) {
            qWarning() << "No callback registered for data()";
            return {};
        }
        return m_basicProps.m_data(index, role);
    }

    bool setData(const QModelIndex &index, const QVariant &value, int role) override {
        if (!index.isValid()) {
            qWarning() << "setData() called with invalid index";
            return false;
        }
        if (!m_basicProps.m_setData) {
            qWarning() << "No callback registered for setData()";
            return false;
        }
        return m_basicProps.m_setData(index, value, role);
    }

    QHashIntToByteArray roleNames() const override {
        if (!m_basicProps.m_roleNames) {
            qWarning() << "No callback registered for roleNames()";
            return QHashIntToByteArray{};
        }
        return m_basicProps.m_roleNames();
    }

    bool insertRows(int row, int count, const QModelIndex &parent) override {
        if (parent.isValid())
            return false;
        if (!m_basicProps.m_insertRows) {
            qWarning() << "No callback registered for insertRows()";
            return false;
        }
        return m_basicProps.m_insertRows(row, count, parent);
    }

    bool insertColumns(int column, int count, const QModelIndex &parent) override {
        if (parent.isValid())
            return false;
        if (!m_props.m_insertColumns) {
            qWarning() << "No callback registered for insertColumns()";
            return false;
        }
        return m_props.m_insertColumns(column, count, parent);
    }

    bool moveRows(const QModelIndex &sourceParent, int sourceRow, int count,
                  const QModelIndex &destinationParent, int destinationChild) override {
        if (sourceParent.isValid() || destinationParent.isValid())
            return false;
        if (!m_basicProps.m_moveRows) {
            qWarning() << "No callback registered for moveRows()";
        }
        return m_basicProps.m_moveRows(sourceParent, sourceRow, count,
                                  destinationParent, destinationChild);
    }

    bool moveColumns(const QModelIndex &sourceParent, int sourceColumn, int count,
                     const QModelIndex &destinationParent, int destinationChild) override {
        if (sourceParent.isValid() || destinationParent.isValid())
            return false;
        if (!m_props.m_moveColumns) {
            qWarning() << "No callback registered for moveColumns()";
        }
        return m_props.m_moveColumns(sourceParent, sourceColumn, count,
                                  destinationParent, destinationChild);
    }

    bool removeRows(int row, int count, const QModelIndex &parent) override {
        if (parent.isValid())
            return false;
        if (!m_basicProps.m_removeRows) {
            qWarning() << "No callback registered for removeRows()";
        }
        return m_basicProps.m_removeRows(row, count, parent);
    }

    bool removeColumns(int column, int count, const QModelIndex &parent) override {
        if (parent.isValid())
            return false;
        if (!m_props.m_removeColumns) {
            qWarning() << "No callback registered for removeRows()";
        }
        return m_props.m_removeColumns(column, count, parent);
    }

    QModelIndex createIndex(int row, int column, quintptr id) const {
        return QAbstractItemModel::createIndex(row, column, id);
    }

    void beginInsertRows(const QModelIndex &parent, int first, int last) {
        QAbstractItemModel::beginInsertRows(parent, first, last);
    }

    void endInsertRows() { QAbstractItemModel::endInsertRows(); }

    void beginRemoveRows(const QModelIndex &parent, int first, int last) {
        QAbstractItemModel::beginRemoveRows(parent, first, last);
    }

    void endRemoveRows() { QAbstractItemModel::endRemoveRows(); }

    bool beginMoveRows(const QModelIndex &sourceParent, int sourceFirst, int sourceLast,
                                   const QModelIndex &destinationParent, int destinationRow) {
        return QAbstractItemModel::beginMoveRows(sourceParent, sourceFirst, sourceLast,
                                                 destinationParent, destinationRow);
    }

    void endMoveRows() { QAbstractItemModel::endMoveRows(); }

    void beginInsertColumns(const QModelIndex &parent, int first, int last) {
        QAbstractItemModel::beginInsertColumns(parent, first, last);
    }

    void endInsertColumns() { QAbstractItemModel::endInsertColumns(); }

    void beginRemoveColumns(const QModelIndex &parent, int first, int last) {
        QAbstractItemModel::beginRemoveColumns(parent, first, last);
    }

    void endRemoveColumns() { QAbstractItemModel::endRemoveColumns(); }

    bool beginMoveColumns(const QModelIndex &sourceParent, int sourceFirst, int sourceLast,
                          const QModelIndex &destinationParent, int destinationColumn) {
        return QAbstractItemModel::beginMoveColumns(sourceParent, sourceFirst, sourceLast,
                                             destinationParent, destinationColumn);
    }

    void endMoveColumns() { QAbstractItemModel::endMoveColumns(); }

    void beginResetModel() { QAbstractItemModel::beginResetModel(); }

    void endResetModel() { QAbstractItemModel::endResetModel(); }

    void emitDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                         const int *roles, int roleCount) {
        if (!roles || roleCount <= 0) {
            emit dataChanged(topLeft, bottomRight, {});
            return;
        }
        QList<int> rolesList;
        rolesList.reserve(roleCount);
        for (int i = 0; i < roleCount; ++i)
            rolesList.append(roles[i]);
        emit dataChanged(topLeft, bottomRight, rolesList);
    }

private:
    struct ItemProperties {
        std::function<QModelIndex(int, int, const QModelIndex&)> m_index;
        std::function<QModelIndex(const QModelIndex&)> m_parent;
        std::function<int(const QModelIndex&)> m_columnCount;
        std::function<bool(int, int, const QModelIndex&)> m_insertColumns;
        std::function<bool(const QModelIndex&, int, int, const QModelIndex&, int)> m_moveColumns;
        std::function<bool(int, int, const QModelIndex&)> m_removeColumns;
    } m_props;
};

QAbstractItemModelCpp::QAbstractItemModelCpp(void* swiftModel)
    : m_swiftModel(swiftModel), m_impl(std::make_unique<QAbstractItemModelImpl>(swiftModel)) {}

QAbstractItemModel* QAbstractItemModelCpp::getModel() const
{
    return m_impl.get();
}

void QAbstractItemModelCpp::registerIndex(IndexFunc indexCallback)
{
    m_impl->registerIndex(indexCallback);
}

void QAbstractItemModelCpp::registerParent(ParentFunc parentCallback)
{
    m_impl->registerParent(parentCallback);
}

void QAbstractItemModelCpp::registerRowCount(CallbackBase::RowCountFunc rowCountCallback)
{
    m_impl->registerRowCount(rowCountCallback);
}

void QAbstractItemModelCpp::registerColumnCount(CallbackBase::ColumnCountFunc columnCountCallback)
{
    m_impl->registerColumnCount(columnCountCallback);
}

void QAbstractItemModelCpp::registerData(CallbackBase::DataFunc dataCallback)
{
    m_impl->registerData(dataCallback);
}

void QAbstractItemModelCpp::registerSetData(CallbackBase::SetDataFunc setDataCallback)
{
    m_impl->registerSetData(setDataCallback);
}

void QAbstractItemModelCpp::registerRoleNames(CallbackBase::RoleNamesFunc roleNamesCallback)
{
    m_impl->registerRoleNames(roleNamesCallback);
}

void QAbstractItemModelCpp::registerInsertRows(CallbackBase::InsertFunc insertRowsCallback)
{
    m_impl->registerInsertRows(insertRowsCallback);
}

void QAbstractItemModelCpp::registerInsertColumns(CallbackBase::InsertFunc insertColumnsCallback)
{
    m_impl->registerInsertColumns(insertColumnsCallback);
}

void QAbstractItemModelCpp::registerMoveRows(CallbackBase::MoveFunc moveRowsCallback)
{
    m_impl->registerMoveRows(moveRowsCallback);
}

void QAbstractItemModelCpp::registerMoveColumns(CallbackBase::MoveFunc moveColumnsCallback)
{
    m_impl->registerMoveColumns(moveColumnsCallback);
}

void QAbstractItemModelCpp::registerRemoveRows(CallbackBase::RemoveFunc removeRowsCallback)
{
    m_impl->registerRemoveRows(removeRowsCallback);
}

void QAbstractItemModelCpp::registerRemoveColumns(CallbackBase::RemoveFunc removeColumnsCallback)
{
    m_impl->registerRemoveColumns(removeColumnsCallback);
}

QModelIndex QAbstractItemModelCpp::createIndex(int row, int column, quintptr id) const {
    return m_impl->createIndex(row, column, id);
}

void QAbstractItemModelCpp::beginInsertRows(const QModelIndex parent, int first, int last) {
    m_impl->beginInsertRows(parent, first, last);
}

void QAbstractItemModelCpp::endInsertRows() { m_impl->endInsertRows(); }

void QAbstractItemModelCpp::beginRemoveRows(const QModelIndex &parent, int first, int last) {
    m_impl->beginRemoveRows(parent, first, last);
}

void QAbstractItemModelCpp::endRemoveRows() { m_impl->endRemoveRows(); }

bool QAbstractItemModelCpp::beginMoveRows(const QModelIndex sourceParent, int sourceFirst, int sourceLast,
                                          const QModelIndex destinationParent, int destinationRow) {
    return m_impl->beginMoveRows(sourceParent, sourceFirst, sourceLast, destinationParent, destinationRow);
}

void QAbstractItemModelCpp::endMoveRows() { m_impl->endMoveRows(); }

void QAbstractItemModelCpp::beginInsertColumns(const QModelIndex &parent, int first, int last) {
    m_impl->beginInsertColumns(parent, first, last);
}

void QAbstractItemModelCpp::endInsertColumns() { m_impl->endInsertColumns(); }

void QAbstractItemModelCpp::beginRemoveColumns(const QModelIndex &parent, int first, int last) {
    m_impl->beginRemoveColumns(parent, first, last);
}

void QAbstractItemModelCpp::endRemoveColumns() { m_impl->endRemoveColumns(); }

bool QAbstractItemModelCpp::beginMoveColumns(const QModelIndex &sourceParent, int sourceFirst, int sourceLast,
                                             const QModelIndex &destinationParent, int destinationColumn) {
    return m_impl->beginMoveColumns(sourceParent, sourceFirst, sourceLast, destinationParent, destinationColumn);
}

void QAbstractItemModelCpp::endMoveColumns() { m_impl->endMoveColumns(); }

void QAbstractItemModelCpp::beginResetModel() { m_impl->beginResetModel(); }

void QAbstractItemModelCpp::endResetModel() { m_impl->endResetModel(); }

void QAbstractItemModelCpp::emitDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                                            const int *roles, int roleCount) {
    m_impl->emitDataChanged(topLeft, bottomRight, roles, roleCount);
}

QAbstractItemModelCpp::~QAbstractItemModelCpp() = default;
