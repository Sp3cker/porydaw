// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#include "swiftqmlelementbuilder.h"

#include <QtCore/qmetaobject.h>

#include <QtQml/qqml.h>
#include <QtQml/qqmlprivate.h>

#include "qobjectproxy.h"
#include "qobjectproxyimpl.h"

class SwiftQmlElementBuilder::Impl
{
public:
    Impl(const char *moduleName,
         const char *className)
        : m_moduleName(moduleName),
          m_className(className)
    {
    }

    void setMetaObject(const QMetaObject *metaObject)
    {
        m_metaObject = metaObject;
    }

    void registerCreateFn(void *builderPtr, CreateFn createFn)
    {
        m_builderPtr = builderPtr;
        m_createFn = createFn;
    }

    void registerQmlElement()
    {
        registerMetaTypeInterface();

        QQmlPrivate::RegisterType rt = {};
        rt.structVersion = QQmlPrivate::RegisterType::CurrentVersion;
        rt.typeId = QMetaType(m_metaTypeInterface);
        rt.listId = QMetaType::fromType<QQmlListProperty<QObjectProxyImpl>>();
        rt.objectSize = sizeof(QObjectProxyImpl);
        rt.create = Impl::createFn;
        rt.userdata = this;
        rt.noCreationReason = QString();
        rt.createValueType = nullptr;
        rt.uri = m_moduleName.data();
        rt.version = QTypeRevision::fromVersion(1, 0);
        rt.elementName = m_className.data();
        rt.metaObject = m_metaObject;
        rt.attachedPropertiesFunction = qmlAttachedPropertiesFunction(nullptr, m_metaObject),
        rt.attachedPropertiesMetaObject = m_metaObject;
        rt.parserStatusCast = QQmlPrivate::StaticCastSelector<QObjectProxyImpl, QQmlParserStatus>::cast();
        rt.valueSourceCast =  QQmlPrivate::StaticCastSelector<QObjectProxyImpl, QQmlPropertyValueSource>::cast();
        rt.valueInterceptorCast = QQmlPrivate::StaticCastSelector<QObjectProxyImpl, QQmlPropertyValueInterceptor>::cast();
        rt.extensionObjectCreate = nullptr;
        rt.extensionMetaObject = nullptr;
        rt.customParser = nullptr;
        rt.revision = QTypeRevision::fromVersion(0, 0);
        rt.finalizerCast = QQmlPrivate::StaticCastSelector<QObjectProxyImpl, QQmlFinalizerHook>::cast();
        rt.creationMethod = QQmlPrivate::ValueTypeCreationMethod::None;
        QQmlPrivate::qmlregister(QQmlPrivate::TypeRegistration, &rt);
    }

    void registerMetaTypeInterface()
    {
        auto d = MetaData();
        d.self = this;

        d.metaTypeInterface = std::make_unique<QtPrivate::QMetaTypeInterface>();
        d.metaTypeInterface->alignment = alignof(QObjectProxyImpl);
        d.metaTypeInterface->size = sizeof(QObjectProxyImpl);
        d.metaTypeInterface->flags = QMetaType::NeedsConstruction
                                    | QMetaType::NeedsDestruction
                                    | QMetaType::NeedsCopyConstruction
                                    | QMetaType::NeedsMoveConstruction
                                    | QMetaType::PointerToQObject;
        d.metaTypeInterface->name = m_className.data();
        d.metaTypeInterface->defaultCtr = Impl::defaultCtrFn;
        d.metaTypeInterface->dtor = Impl::dtorFn;
        d.metaTypeInterface->metaObjectFn = Impl::metaObject;

        m_metaTypeInterface = d.metaTypeInterface.get();
        m_metaData.push_back(std::move(d));
    }

private:
    struct MetaData {
        std::unique_ptr<QtPrivate::QMetaTypeInterface> metaTypeInterface;
        const Impl * self = nullptr;
    };
    static std::vector<MetaData> m_metaData;

    static const MetaData* findMetaData(const QtPrivate::QMetaTypeInterface *iface)
    {
        if (!iface) {
            return nullptr;
        }

        for (const MetaData &md : m_metaData) {
            if (md.metaTypeInterface.get() == iface)
                return &md;
        }
        return nullptr;
    }

    static void createFn(void *addr, void *userdata)
    {
        Impl* self = static_cast<Impl*>(userdata);

        if (!self || !self->m_createFn)
            return;

        self->m_createFn(self->m_builderPtr, addr);
    }

    static void defaultCtrFn(const QtPrivate::QMetaTypeInterface *iface,
                             void *addr)
    {
        if (auto md = findMetaData(iface)) {
            if (!md->self || !md->self->m_createFn)
                throw std::runtime_error("Invalid MetaData");

            md->self->m_createFn(md->self->m_builderPtr, addr);
        }
    }

    static void dtorFn(const QtPrivate::QMetaTypeInterface *,
                       void *addr)
    {
        auto p = static_cast<const QObject*>(addr);
        if (!p)
            throw std::runtime_error("Invalid QObject pointer");
        p->~QObject();
    }

    static const QMetaObject * metaObject(
                    const QtPrivate::QMetaTypeInterface *iface)
    {
        if (auto md = findMetaData(iface)) {
            if (!md->self)
                return nullptr;

            return md->self->m_metaObject;
        }
        return nullptr;
    }

    std::string m_moduleName;
    std::string m_className;
    const QMetaObject * m_metaObject = nullptr;
    void *m_builderPtr = nullptr;
    CreateFn m_createFn;
    const QtPrivate::QMetaTypeInterface * m_metaTypeInterface = nullptr;
};

std::vector<SwiftQmlElementBuilder::Impl::MetaData> SwiftQmlElementBuilder::Impl::m_metaData;

SwiftQmlElementBuilder::SwiftQmlElementBuilder(const char *moduleName,
                                               const char *className)
{
    m_impl = std::make_shared<SwiftQmlElementBuilder::Impl>(moduleName,
                                                            className);
}

SwiftQmlElementBuilder::~SwiftQmlElementBuilder()
{
}

void SwiftQmlElementBuilder::setMetaObjectFrom(SwiftMetaObjectBuilder builder)
{
    m_impl->setMetaObject(builder.metaObject());
}

void SwiftQmlElementBuilder::registerCreateFn(void *builderPtr, CreateFn fn)
{
    m_impl->registerCreateFn(builderPtr, fn);
}

void SwiftQmlElementBuilder::registerQmlElement()
{
    m_impl->registerQmlElement();
}
