// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "callbackbase.h"

CallbackBase::CallbackBase(void* swift) : m_swiftModel(swift) {}

void CallbackBase::registerRowCount(RowCountFunc rowCountCallback) {
    m_basicProps.m_rowCount = [=](const QModelIndex &index) {
        return rowCountCallback(m_swiftModel, &index);
    };
}
void CallbackBase::registerColumnCount(ColumnCountFunc columnCountCallback) {
    m_basicProps.m_columnCount = [=](const QModelIndex &index) {
        return columnCountCallback(m_swiftModel, &index);
    };
}
void CallbackBase::registerData(DataFunc dataCallback) {
    m_basicProps.m_data = [=](const QModelIndex &index, int role) {
        return dataCallback(m_swiftModel, &index, role);
    };
}
void CallbackBase::registerSetData(SetDataFunc setDataCallback) {
    m_basicProps.m_setData = [=](const QModelIndex &index, const QVariant &value, int role) {
        return setDataCallback(m_swiftModel, &index, &value, role);
    };
}
void CallbackBase::registerRoleNames(RoleNamesFunc roleNamesCallback) {
    m_basicProps.m_roleNames = [=]() {
        return roleNamesCallback(m_swiftModel);
    };
}
void CallbackBase::registerHeaderData(HeaderDataFunc headerDataCallback) {
    m_basicProps.m_headerData = [=](int section, Qt::Orientation orientation, int role) {
        return headerDataCallback(m_swiftModel, section, orientation, role);
    };
}
void CallbackBase::registerInsertRows(InsertFunc insertRowsCallback) {
    m_basicProps.m_insertRows = [=](int row, int count, const QModelIndex &index) {
        return insertRowsCallback(m_swiftModel, row, count, &index);
    };
}
void CallbackBase::registerMoveRows(MoveFunc moveRowsCallback) {
    m_basicProps.m_moveRows = [=](const QModelIndex &sourceParent, int sourceRow, int count,
                                  const QModelIndex &destinationParent, int destinationChild) {
        return moveRowsCallback(m_swiftModel, &sourceParent, sourceRow, count,
                                &destinationParent, destinationChild);
    };
}
void CallbackBase::registerRemoveRows(RemoveFunc removeRowsCallback) {
    m_basicProps.m_removeRows = [=](int row, int count, const QModelIndex &parent) {
        return removeRowsCallback(m_swiftModel, row, count, &parent);
    };
}
