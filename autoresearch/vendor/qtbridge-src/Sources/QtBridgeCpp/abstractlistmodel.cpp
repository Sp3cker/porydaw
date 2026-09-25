// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "abstractlistmodel.h"

#include <QtCore/qabstractitemmodel.h>
#include <QtCore/qobject.h>

class QAbstractListModelCpp::QAbstractListModelImpl : public QAbstractListModel
                                                    , public CallbackBase
{
public:
    // QAbstractListModel interface
    QAbstractListModelImpl(void* swiftModel, QObject* parent = nullptr)
        : QAbstractListModel(parent), CallbackBase(swiftModel) {}

    ~QAbstractListModelImpl() = default;

    int rowCount(const QModelIndex &parent) const override {
        if (parent.isValid())
            return 0;
        if (!m_basicProps.m_rowCount) {
            qWarning() << "No callback registered for rowCount()";
            return 0;
        }
        return m_basicProps.m_rowCount(parent);
    }

    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override {
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
            return 0;
        }
        if (!m_basicProps.m_setData) {
            qWarning() << "No callback registered for setData()";
            return 0;
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

    void beginInsertRows(const QModelIndex &parent, int first, int last) {
        QAbstractListModel::beginInsertRows(parent, first, last);
    }

    void endInsertRows() { QAbstractListModel::endInsertRows(); }

    bool beginMoveRows(const QModelIndex &sourceParent, int sourceFirst, int sourceLast,
                       const QModelIndex &destinationParent, int destinationRow) {
        return QAbstractListModel::beginMoveRows(sourceParent, sourceFirst, sourceLast,
                                                 destinationParent, destinationRow);
    }

    void endMoveRows() { QAbstractListModel::endMoveRows(); }

    void beginRemoveRows(const QModelIndex &parent, int first, int last) {
        QAbstractListModel::beginRemoveRows(parent, first, last);
    }

    void endRemoveRows() { QAbstractListModel::endRemoveRows(); }

    void beginResetModel() { QAbstractItemModel::beginResetModel(); }

    void endResetModel() { QAbstractItemModel::endResetModel(); }

    void emitDataChanged(int topLeft, int bottomRight, const int *roles, int roleCount) {
        const int rowCnt = rowCount(QModelIndex());
        if (topLeft > bottomRight)
            return;
        if (topLeft < 0)
            topLeft = 0;
        if (bottomRight >= rowCnt)
            bottomRight = rowCnt - 1;

        const QModelIndex tl = index(topLeft, 0);
        const QModelIndex br = index(bottomRight, 0);

        if (!roles || roleCount <= 0) {
            emit dataChanged(tl, br, {});
        } else {
            QList<int> rolesList;
            rolesList.reserve(roleCount);
            for (int i = 0; i < roleCount; ++i)
            rolesList.append(roles[i]);
            emit dataChanged(tl, br, rolesList);
        }
    }
};

QAbstractListModelCpp::QAbstractListModelCpp(void* swiftModel)
    : m_swiftModel(swiftModel), m_impl(std::make_unique<QAbstractListModelImpl>(swiftModel))
{
    if (s_rowCountFunc)
        m_impl->CallbackBase::registerRowCount(s_rowCountFunc);
    if (s_dataFunc)
        m_impl->CallbackBase::registerData(s_dataFunc);
    if (s_setDataFunc)
        m_impl->CallbackBase::registerSetData(s_setDataFunc);
    if (s_roleNamesFunc)
        m_impl->CallbackBase::registerRoleNames(s_roleNamesFunc);
}

QAbstractListModel* QAbstractListModelCpp::getModel() const
{
    return m_impl.get();
}

QVariant QAbstractListModelCpp::toVariant() const
{
    return QVariant::fromValue(m_impl.get());
}

void QAbstractListModelCpp::registerRowCount(CallbackBase::RowCountFunc rowCountCallback)
{
    s_rowCountFunc = rowCountCallback;
}

void QAbstractListModelCpp::registerData(CallbackBase::DataFunc dataCallback)
{
    s_dataFunc = dataCallback;
}

void QAbstractListModelCpp::registerSetData(CallbackBase::SetDataFunc setDataCallback)
{
    s_setDataFunc = setDataCallback;
}

void QAbstractListModelCpp::registerRoleNames(CallbackBase::RoleNamesFunc roleNamesCallback)
{
    s_roleNamesFunc = roleNamesCallback;
}

void QAbstractListModelCpp::beginInsertRows(const QModelIndex parent, int first, int last) {
    m_impl->beginInsertRows(parent, first, last);
}

void QAbstractListModelCpp::endInsertRows() { m_impl->endInsertRows(); }

bool QAbstractListModelCpp::beginMoveRows(const QModelIndex &sourceParent, int sourceFirst,
                                          int sourceLast, const QModelIndex &destinationParent,
                                          int destinationRow) {
    return m_impl->beginMoveRows(sourceParent, sourceFirst, sourceLast, destinationParent,
                                 destinationRow);
}

void QAbstractListModelCpp::endMoveRows() { m_impl->endMoveRows(); }

void QAbstractListModelCpp::beginRemoveRows(const QModelIndex &parent, int first, int last) {
    m_impl->beginRemoveRows(parent, first, last);
}

void QAbstractListModelCpp::endRemoveRows() { m_impl->endRemoveRows(); }

void QAbstractListModelCpp::beginResetModel() { m_impl->beginResetModel(); }

void QAbstractListModelCpp::endResetModel() { m_impl->endResetModel(); }

void QAbstractListModelCpp::emitDataChanged(int topLeft, int bottomRight,
                                            const int *roles,int roleCount) {
    m_impl->emitDataChanged(topLeft, bottomRight, roles, roleCount);
}

QAbstractListModelCpp::~QAbstractListModelCpp() = default;
