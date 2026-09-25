// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qobject.h>
#include <QtCore/qvariant.h>

#include <memory>

#include <swift/bridging>

#include "metaparamslist.h"
#include "qobjectproxy.h"

class SwiftMetaObjectBuilder
{
public:
    SwiftMetaObjectBuilder(const char *className);
    ~SwiftMetaObjectBuilder();

    void setMetaObjectTo(QObjectProxy dst) const;
    const QMetaObject* metaObject() const;

    using SlotFunc = QVariant(*)(int, void *, void *, MetaParamsList);
    void registerSlot(const char *name, void *builderPtr, int propertyId,
                      int returnTypeId, const std::vector<int> &argTypeIds,
                      SlotFunc callback);

    void registerSignal(const char *name, const std::vector<int> &argTypeIds);
    void emitSignal(QObjectProxy sender, const char *name, const std::vector<QVariant> &args);

    using ReadFunc = QVariant(*)(int, void *, void *);
    using WriteFunc = bool(*)(int, void *, void *, const QVariant*);
    void registerProperty(const char *name, void *builderPtr,
                          int propertyId, int typeId,
                          ReadFunc readCallback, WriteFunc writeCallback);

    void endMetaRegistration();

private:
    class BuilderImpl;
    std::shared_ptr<BuilderImpl> m_impl;
};
