// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include "callbackbase.h"

#include <QtCore/qabstractitemmodel.h>

#include <memory>

#include <swift/bridging>

inline void qhashInsert(QHash<int, QByteArray> &hash, int key, const std::string &val) {
    hash.insert(key, QByteArray::fromStdString(val));
}

class QAbstractItemModelCpp
{
public:
    explicit QAbstractItemModelCpp(void *swiftModel);
    ~QAbstractItemModelCpp();

    QAbstractItemModelCpp(const QAbstractItemModelCpp&) = delete;
    QAbstractItemModelCpp& operator=(const QAbstractItemModelCpp&) = delete;
    QAbstractItemModelCpp(QAbstractItemModelCpp&&) = delete;
    QAbstractItemModelCpp& operator=(QAbstractItemModelCpp&&) = delete;

    static QAbstractItemModelCpp* create(void* swiftModel) {
        return new QAbstractItemModelCpp(swiftModel);
    }
    static void destroy(QAbstractItemModelCpp* ptr) {
        delete ptr;
    }

    QAbstractItemModel* getModel() const;

    using IndexFunc = QModelIndex(*)(void*, int, int, const QModelIndex*);
    void registerIndex(IndexFunc indexCallback);

    using ParentFunc = QModelIndex(*)(void*, const QModelIndex*);
    void registerParent(ParentFunc parentCallback);

    void registerRowCount(CallbackBase::RowCountFunc rowCountCallback);
    void registerColumnCount(CallbackBase::RowCountFunc columnCountCallback);

    void registerData(CallbackBase::DataFunc dataCallback);
    void registerSetData(CallbackBase::SetDataFunc setDataCallback);

    void registerRoleNames(CallbackBase::RoleNamesFunc roleNamesCallback);

    void registerInsertRows(CallbackBase::InsertFunc insertRowsCallback);
    void registerInsertColumns(CallbackBase::InsertFunc insertColumnsCallback);

    void registerMoveRows(CallbackBase::MoveFunc moveRowsCallback);
    void registerMoveColumns(CallbackBase::MoveFunc moveColumnsCallback);

    void registerRemoveRows(CallbackBase::RemoveFunc removeRowsCallback);
    void registerRemoveColumns(CallbackBase::RemoveFunc removeColumnsCallback);

    QModelIndex createIndex(int row, int column, quintptr id) const SWIFT_RETURNS_INDEPENDENT_VALUE;

    void beginInsertRows(const QModelIndex parent, int first, int last);
    void endInsertRows();
    void beginRemoveRows(const QModelIndex &parent, int first, int last);
    void endRemoveRows();
    bool beginMoveRows(const QModelIndex sourceParent, int sourceFirst, int sourceLast,
                       const QModelIndex destinationParent, int destinationRow);
    void endMoveRows();

    void beginInsertColumns(const QModelIndex &parent, int first, int last);
    void endInsertColumns();
    void beginRemoveColumns(const QModelIndex &parent, int first, int last);
    void endRemoveColumns();
    bool beginMoveColumns(const QModelIndex &sourceParent, int sourceFirst, int sourceLast,
                          const QModelIndex &destinationParent, int destinationColumn);
    void endMoveColumns();

    void beginResetModel();
    void endResetModel();

    void emitDataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                         const int *roles, int roleCount);

private:
    void *m_swiftModel;
    class QAbstractItemModelImpl;
    std::unique_ptr<QAbstractItemModelImpl> m_impl;
} SWIFT_IMMORTAL_REFERENCE;
