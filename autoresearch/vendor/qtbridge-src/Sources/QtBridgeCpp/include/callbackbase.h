// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qabstractitemmodel.h>

#include <memory>

#include <swift/bridging>

class CallbackBase {
public:
    explicit CallbackBase(void* swiftModel);
    ~CallbackBase() = default;

    using RowCountFunc = int(*)(void*, const QModelIndex*);
    void registerRowCount(RowCountFunc rowCountCallback);

    using ColumnCountFunc = int(*)(void*, const QModelIndex*);
    void registerColumnCount(ColumnCountFunc columnCountCallback);

    using DataFunc = QVariant(*)(void*, const QModelIndex*, int);
    void registerData(DataFunc dataCallback);

    using SetDataFunc = bool(*)(void*, const QModelIndex*, const QVariant*, int);
    void registerSetData(SetDataFunc setDataCallback);

    using QHashIntToByteArray = QHash<int, QByteArray>;
    using RoleNamesFunc = QHashIntToByteArray(*)(void*);
    void registerRoleNames(RoleNamesFunc roleNamesCallback);

    using HeaderDataFunc = QVariant(*)(void*, int, Qt::Orientation, int);
    void registerHeaderData(HeaderDataFunc headerDataCallback);

    using InsertFunc = bool(*)(void*, int, int, const QModelIndex*);
    void registerInsertRows(InsertFunc insertRowsCallback);

    using MoveFunc = bool(*)(void*, const QModelIndex*, int, int, const QModelIndex*, int);
    void registerMoveRows(MoveFunc moveRowsCallback);

    using RemoveFunc = bool(*)(void*, int, int, const QModelIndex*);
    void registerRemoveRows(RemoveFunc removeRowsCallback);

protected:
    void* m_swiftModel;
    struct BasicProps {
        std::function<int(const QModelIndex&)> m_rowCount;
        std::function<int(const QModelIndex&)> m_columnCount;
        std::function<QVariant(const QModelIndex&, int)> m_data;
        std::function<bool(const QModelIndex&, const QVariant&, int)> m_setData;
        std::function<QHash<int,QByteArray>()> m_roleNames;
        std::function<QVariant(int, Qt::Orientation, int)> m_headerData;
        std::function<bool(int,int,const QModelIndex&)> m_insertRows;
        std::function<bool(const QModelIndex&,int,int,const QModelIndex&,int)> m_moveRows;
        std::function<bool(int,int,const QModelIndex&)> m_removeRows;
    } m_basicProps;
};
