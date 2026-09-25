// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qobject.h>
#include <QtCore/qvariant.h>
#include <QtCore/qpointer.h>

#include <memory>

class QObjectProxy
{
public:
    QObjectProxy(void *owner);
    using DeleterFn = void (*)(void *swiftObj);
    QObjectProxy(void *owner, void *addr, DeleterFn deleter);
    ~QObjectProxy();

    QObject *toObject() const;
    QVariant toVariant() const;

    QList<void *> swiftChildren() const;

    using CompleteFn = void(*)(void *);
    void registerComponentComplete(void *holderPtr, CompleteFn callback);

private:
    class Impl;
    std::shared_ptr<Impl> m_impl;
};
