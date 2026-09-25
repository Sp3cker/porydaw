// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qmetaobject.h>
#include <QtCore/qvariant.h>

#include <vector>
#include <string>

#include <swift/bridging>

using CppVectorOfStrings = std::vector<std::string>;
using CppVectorOfInt = std::vector<int>;
using CppVectorOfQVariant = std::vector<QVariant>;

class MetaParamsList
{
public:
    MetaParamsList(const QMetaMethod& method, void** paramData);
    MetaParamsList(const MetaParamsList& other);
    ~MetaParamsList() = default;

    int size() const;

    bool getBool(size_t i) const;
    int getInt(size_t i) const;
    unsigned int getUInt(size_t i) const;
    float getFloat(size_t i) const;
    double getDouble(size_t i) const;
    std::string getString(size_t i) const;
    QStringList getStringList(size_t i) const;
    QVariantMap getVariantMap(size_t i) const;

private:
    template <typename T>
    auto getT(size_t paramNum) const
    {
        const int iParamNum = static_cast<int>(paramNum);
        if (iParamNum >= m_method.parameterCount())
            throw std::logic_error("Wrong argument number");

        const QMetaType srcType(m_method.parameterType(iParamNum));
        if (!srcType.isValid())
            throw std::logic_error("Invalid parameter type");

        const QMetaType dstType = QMetaType::fromType<T>();
        if (!dstType.isValid())
            throw std::logic_error("Invalid result type");

        if (!QMetaType::canConvert(srcType, dstType))
            throw std::logic_error("Type can not be converted");

        T result = {};
        if (!QMetaType::convert(srcType,
                                const_cast<void*>(m_paramData[iParamNum+1]),
                                dstType,
                                &result)) {
            throw std::runtime_error("Failed to perform type conversion");
        }

        return result;
    }

    QMetaMethod m_method;
    void** m_paramData;
} SWIFT_UNSAFE_REFERENCE;
