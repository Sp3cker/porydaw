// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "qobjectproxy.h"

#include "qobjectproxyimpl.h"

#include <QtQml/QJSEngine>

// Impl

class QObjectProxy::Impl
{
public:
    Impl(void *owner) :
        m_ownership(Cpp),
        m_object(new QObjectProxyImpl(owner))
    {
        // ~Impl deletes this object; exclude it from JS garbage collection.
        QJSEngine::setObjectOwnership(m_object, QJSEngine::CppOwnership);
    }

    Impl(void *owner,
         void *addr,
         DeleterFn deleter) :
        m_ownership(Qml),
        m_object(new (addr) QObjectProxyImpl(owner, deleter))
    {
    }

    ~Impl()
    {
        if (m_ownership == Cpp)
            delete m_object;
    }

    QObject * object() { return m_object; }

    QList<void *> swiftChildren() const
    {
        QObjectProxyImpl *obj = qobject_cast<QObjectProxyImpl *>(m_object);
        if (!obj)
            return {};

        return obj->swiftChildren();
    }

    void registerComponentComplete(void *holderPtr, CompleteFn callback)
    {
        QObjectProxyImpl *obj = qobject_cast<QObjectProxyImpl *>(m_object);
        if (obj)
            obj->registerComponentComplete(holderPtr, callback);
    }

private:
    enum Ownership {
        Cpp,
        Qml
    };

    Ownership m_ownership;
    QPointer<QObject> m_object;
};

QObjectProxy::QObjectProxy(void *owner)
{
    m_impl = std::make_shared<QObjectProxy::Impl>(owner);
}

QObjectProxy::QObjectProxy(void *owner,
                           void *addr,
                           DeleterFn deleter)
{
    m_impl = std::make_shared<QObjectProxy::Impl>(owner, addr, deleter);
}

QObjectProxy::~QObjectProxy()
{
}

QObject * QObjectProxy::toObject() const
{
    return m_impl->object();
}

QVariant QObjectProxy::toVariant() const
{
    return QVariant::fromValue(m_impl->object());
}

QList<void *> QObjectProxy::swiftChildren() const
{
    return m_impl->swiftChildren();
}

void QObjectProxy::registerComponentComplete(void *holderPtr, CompleteFn callback)
{
    m_impl->registerComponentComplete(holderPtr, callback);
}
