// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "abstracttablemodel.h"

#include <QtCore/qabstractitemmodel.h>
#include <QtCore/qobject.h>

class QAbstractTableModelCpp::QAbstractTableModelImpl : public QAbstractTableModel
                                                      , public CallbackBase
{
public:
    // QAbstractTableModel interface
    QAbstractTableModelImpl(void* swiftModel, QObject* parent = nullptr)
        : QAbstractTableModel(parent), CallbackBase(swiftModel) {}

    ~QAbstractTableModelImpl() = default;

    int rowCount(const QModelIndex &parent) const override {
        if (parent.isValid())
            return 0;
        if (!m_basicProps.m_rowCount) {
            qWarning() << "No callback registered for rowCount()";
            return 0;
        }
        return m_basicProps.m_rowCount(parent);
    }

    int columnCount(const QModelIndex &parent) const override {
        if (parent.isValid())
            return 0;
        if (!m_basicProps.m_columnCount) {
            qWarning() << "No callback registered for columnCount()";
            return 0;
        }
        return m_basicProps.m_columnCount(parent);
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

    QVariant headerData(int section, Qt::Orientation orientation, int role) const override {
        if (!m_basicProps.m_headerData) {
            qWarning() << "No callback registered for headerData()";
            return QVariant();
        }
        return m_basicProps.m_headerData(section, orientation, role);
    }

    Qt::ItemFlags flags(const QModelIndex &index) const override {
        return Qt::ItemIsEnabled | Qt::ItemIsEditable | Qt::ItemIsSelectable;
    }

    void beginInsertRows(const QModelIndex &parent, int first, int last) {
        QAbstractTableModel::beginInsertRows(parent, first, last);
    }

    void endInsertRows() { QAbstractTableModel::endInsertRows(); }

    bool beginMoveRows(const QModelIndex &sourceParent, int sourceFirst, int sourceLast,
                       const QModelIndex &destinationParent, int destinationRow) {
        return QAbstractTableModel::beginMoveRows(sourceParent, sourceFirst, sourceLast,
                                                  destinationParent, destinationRow);
    }

    void endMoveRows() { QAbstractTableModel::endMoveRows(); }

    void beginRemoveRows(const QModelIndex &parent, int first, int last) {
        QAbstractTableModel::beginRemoveRows(parent, first, last);
    }

    void endRemoveRows() { QAbstractTableModel::endRemoveRows(); }

    void beginInsertColumns(const QModelIndex &parent, int first, int last) {
        QAbstractTableModel::beginInsertColumns(parent, first, last);
    }

    void endInsertColumns() { QAbstractTableModel::endInsertColumns(); }

    void beginRemoveColumns(const QModelIndex &parent, int first, int last) {
        QAbstractTableModel::beginRemoveColumns(parent, first, last);
    }

    void endRemoveColumns() { QAbstractTableModel::endRemoveColumns(); }

    void beginResetModel() { QAbstractItemModel::beginResetModel(); }

    void endResetModel() { QAbstractItemModel::endResetModel(); }

    void layoutChanged() {
        QAbstractItemModel::layoutChanged();
    }

    void layoutAboutToBeChanged() {
        QAbstractItemModel::layoutAboutToBeChanged();
    }

    void emitDataChanged(int topRow, int leftColumn, int bottomRow,
                         int rightColumn, const int *roles, int roleCount) {
        const int rows = rowCount(QModelIndex());
        const int cols = columnCount(QModelIndex());

        if (topRow < 0 || topRow >= rows || bottomRow < 0 || bottomRow >= rows
            || leftColumn < 0 || leftColumn >= cols || rightColumn < 0
            || rightColumn >= cols)
            return;

        const QModelIndex topLeft = index(topRow, leftColumn);
        const QModelIndex bottomRight = index(bottomRow, rightColumn);

        if (!roles || roleCount <= 0) {
            emit dataChanged(topLeft, bottomRight, {});
        } else {
            QList<int> rolesList;
            rolesList.reserve(roleCount);
            for (int i = 0; i < roleCount; ++i)
            rolesList.append(roles[i]);
            emit dataChanged(topLeft, bottomRight, rolesList);
        }
    }
};

QAbstractTableModelCpp::QAbstractTableModelCpp(void* swiftModel)
    : m_swiftModel(swiftModel), m_impl(std::make_unique<QAbstractTableModelImpl>(swiftModel)) {
    if (s_rowCountFunc)
        m_impl->CallbackBase::registerRowCount(s_rowCountFunc);
    if (s_rowCountFunc)
        m_impl->CallbackBase::registerColumnCount(s_columnCountFunc);
    if (s_dataFunc)
        m_impl->CallbackBase::registerData(s_dataFunc);
    if (s_setDataFunc)
        m_impl->CallbackBase::registerSetData(s_setDataFunc);
    if (s_headerDataFunc)
        m_impl->CallbackBase::registerHeaderData(s_headerDataFunc);
}

QAbstractTableModel* QAbstractTableModelCpp::getModel() const {
    return m_impl.get();
}

QVariant QAbstractTableModelCpp::toVariant() const {
    return QVariant::fromValue(m_impl.get());
}

void QAbstractTableModelCpp::registerRowCount(CallbackBase::RowCountFunc rowCountCallback) {
    s_rowCountFunc = rowCountCallback;
}

void QAbstractTableModelCpp::registerColumnCount(CallbackBase::ColumnCountFunc columnCountCallback) {
    s_columnCountFunc = columnCountCallback;
}

void QAbstractTableModelCpp::registerData(CallbackBase::DataFunc dataCallback) {
    s_dataFunc = dataCallback;
}

void QAbstractTableModelCpp::registerSetData(CallbackBase::SetDataFunc setDataCallback) {
    s_setDataFunc = setDataCallback;
}

void QAbstractTableModelCpp::registerHeaderData(CallbackBase::HeaderDataFunc headerDataCallback) {
    s_headerDataFunc = headerDataCallback;
}

void QAbstractTableModelCpp::beginInsertRows(const QModelIndex parent, int first, int last) {
    m_impl->beginInsertRows(parent, first, last);
}

void QAbstractTableModelCpp::endInsertRows() { m_impl->endInsertRows(); }

bool QAbstractTableModelCpp::beginMoveRows(const QModelIndex &sourceParent, int sourceFirst,
                                           int sourceLast, const QModelIndex &destinationParent,
                                           int destinationRow) {
    return m_impl->beginMoveRows(sourceParent, sourceFirst, sourceLast, destinationParent, destinationRow);
}

void QAbstractTableModelCpp::endMoveRows() { m_impl->endMoveRows(); }

void QAbstractTableModelCpp::beginRemoveRows(const QModelIndex &parent, int first, int last) {
    m_impl->beginRemoveRows(parent, first, last);
}

void QAbstractTableModelCpp::endRemoveRows() { m_impl->endRemoveRows(); }

void QAbstractTableModelCpp::beginInsertColumns(const QModelIndex parent, int first, int last) {
    m_impl->beginInsertColumns(parent, first, last);
}

void QAbstractTableModelCpp::endInsertColumns() { m_impl->endInsertColumns(); }

void QAbstractTableModelCpp::beginRemoveColumns(const QModelIndex &parent, int first, int last) {
    m_impl->beginRemoveColumns(parent, first, last);
}

void QAbstractTableModelCpp::endRemoveColumns() { m_impl->endRemoveColumns(); }

void QAbstractTableModelCpp::beginResetModel() { m_impl->beginResetModel(); }

void QAbstractTableModelCpp::endResetModel() { m_impl->endResetModel(); }

void QAbstractTableModelCpp::layoutChanged() { m_impl->layoutChanged(); }

void QAbstractTableModelCpp::layoutAboutToBeChanged() { m_impl->layoutAboutToBeChanged(); }

void QAbstractTableModelCpp::emitDataChanged(int topRow, int leftColumn, int bottomRow,
                                             int rightColumn, const int *roles,int roleCount) {
    m_impl->emitDataChanged(topRow, leftColumn, bottomRow, rightColumn, roles, roleCount);
}

QAbstractTableModelCpp::~QAbstractTableModelCpp() = default;

