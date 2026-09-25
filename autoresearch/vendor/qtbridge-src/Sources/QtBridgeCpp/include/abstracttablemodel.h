// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qabstractitemmodel.h>

#include <memory>

#include <swift/bridging>

#include "callbackbase.h"
#include "swiftinterop.h"

class QAbstractTableModelCpp
{
public:
    QAbstractTableModelCpp(const QAbstractTableModelCpp&) = delete;
    QAbstractTableModelCpp& operator=(const QAbstractTableModelCpp&) = delete;
    QAbstractTableModelCpp(QAbstractTableModelCpp&&) = delete;
    QAbstractTableModelCpp& operator=(QAbstractTableModelCpp&&) = delete;

    static QAbstractTableModelCpp* create(void* swiftModel) {
        return new QAbstractTableModelCpp(swiftModel);
    }

    static void destroy(QAbstractTableModelCpp* ptr) {
        delete ptr;
    }

    QAbstractTableModel* getModel() const;
    QVariant toVariant() const;

    static void registerRowCount(SWIFT_MAIN_ACTOR CallbackBase::RowCountFunc rowCountCallback);
    static void registerColumnCount(SWIFT_MAIN_ACTOR CallbackBase::ColumnCountFunc columnCountCallback);
    static void registerData(SWIFT_MAIN_ACTOR CallbackBase::DataFunc dataCallback);
    static void registerSetData(SWIFT_MAIN_ACTOR CallbackBase::SetDataFunc setDataCallback);
    static void registerHeaderData(SWIFT_MAIN_ACTOR CallbackBase::HeaderDataFunc headerDataCallback);

    void beginInsertRows(const QModelIndex parent, int first, int last);
    void endInsertRows();

    bool beginMoveRows(const QModelIndex &sourceParent, int sourceFirst,
                       int sourceLast, const QModelIndex &destinationParent,
                       int destinationRow);
    void endMoveRows();

    void beginRemoveRows(const QModelIndex &parent, int first, int last);
    void endRemoveRows();

    void beginInsertColumns(const QModelIndex parent, int first, int last);
    void endInsertColumns();

    void beginRemoveColumns(const QModelIndex &parent, int first, int last);
    void endRemoveColumns();

    void beginResetModel();
    void endResetModel();

    void layoutChanged();
    void layoutAboutToBeChanged();

    void emitDataChanged(int topRow, int leftColumn, int bottomRow,int rightColumn,
                         const int *roles = nullptr, int roleCount = 0);

private:
    explicit QAbstractTableModelCpp(void* swiftModel);
    ~QAbstractTableModelCpp();

    void *m_swiftModel;
    class QAbstractTableModelImpl;
    std::unique_ptr<QAbstractTableModelImpl> m_impl;

    inline static CallbackBase::RowCountFunc s_rowCountFunc = nullptr;
    inline static CallbackBase::RowCountFunc s_columnCountFunc = nullptr;
    inline static CallbackBase::DataFunc s_dataFunc = nullptr;
    inline static CallbackBase::SetDataFunc s_setDataFunc = nullptr;
    inline static CallbackBase::HeaderDataFunc s_headerDataFunc = nullptr;
} SWIFT_IMMORTAL_REFERENCE;
