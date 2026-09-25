// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qobject.h>
#include <QtQml/qqmllist.h>
#include <QtQml/qqmlparserstatus.h>
#include <QtQml/qqmlengine.h>

#include "swiftobjectaccesor.h"

class QObjectProxyImpl : public QObject,
                         public SwiftObjectAccesor,
                         public QQmlParserStatus
{
    Q_OBJECT
    Q_CLASSINFO("DefaultProperty", "children")
    Q_PROPERTY(QQmlListProperty<QObject> children READ children CONSTANT)
    Q_INTERFACES(QQmlParserStatus)

public:
    QObjectProxyImpl(void *swiftObj)
    : m_swiftObj(swiftObj)
    {
        // A Swift-created proxy is owned by its Swift owner, never by QML.
        // Pin CppOwnership so the engine cannot garbage-collect it while the
        // Swift object still publishes through it.
        QQmlEngine::setObjectOwnership(this, QQmlEngine::CppOwnership);
    }

    using DeleterFn = void(*)(void *swiftObj);
    QObjectProxyImpl(void *swiftObj, DeleterFn deleter)
        : m_swiftObj(swiftObj),
          m_deleter(deleter)
    {}

    ~QObjectProxyImpl();

    void* swiftObject() const final;

    QQmlListProperty<QObject> children();
    QList<void*> swiftChildren() const;

    using CompleteFn = void(*)(void *);
    void registerComponentComplete(void *holderPtr, CompleteFn callback);

    void classBegin() override;
    void componentComplete() override;

private:
    QList<QObject *> m_children;

    void* m_swiftObj = nullptr;
    DeleterFn m_deleter = nullptr;

    std::function<void()> m_completeCallback = nullptr;
};
