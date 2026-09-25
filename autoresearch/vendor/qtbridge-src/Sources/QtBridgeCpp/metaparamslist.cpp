// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "metaparamslist.h"

#include <QtCore/qstring.h>

MetaParamsList::MetaParamsList(
    const QMetaMethod &method, void **paramData)
    : m_method(method),
      m_paramData(paramData)
{
}

MetaParamsList::MetaParamsList(const MetaParamsList& other)
    : m_method(other.m_method),
      m_paramData(other.m_paramData)
{
}

int MetaParamsList::size() const
{
    return m_method.parameterCount();
}

bool MetaParamsList::getBool(size_t i) const { return getT<bool>(i); }

int MetaParamsList::getInt(size_t i) const { return getT<int>(i); }

unsigned int MetaParamsList::getUInt(size_t i) const { return getT<unsigned int>(i); }

float MetaParamsList::getFloat(size_t i) const { return getT<float>(i); }

double MetaParamsList::getDouble(size_t i) const { return getT<double>(i); }

std::string MetaParamsList::getString(size_t i) const
{
    return getT<QString>(i).toStdString();
}

QStringList MetaParamsList::getStringList(size_t i) const {
    return getT<QStringList>(i);
}

QVariantMap MetaParamsList::getVariantMap(size_t i) const {
    return getT<QVariantMap>(i);
}
