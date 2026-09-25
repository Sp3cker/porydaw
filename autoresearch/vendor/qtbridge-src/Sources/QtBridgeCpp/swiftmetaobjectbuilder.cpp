// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "swiftmetaobjectbuilder.h"

#include <QtCore/qmetaobject.h>
#include <QtCore/private/qmetaobjectbuilder_p.h>

#include "qobjectproxyimpl.h"

using namespace std::string_literals;

static QByteArray generateFuncSignature(const std::string &name, const std::vector<QMetaType> &paramTypes)
{
    std::string paramStr;
    for (const auto& type : paramTypes)
    {
        if (!type.isValid())
            throw std::runtime_error("Unspecified argument type");

        if (!paramStr.empty())
            paramStr += ',';
        paramStr += type.name();
    }

    std::string sign = name + '(' + paramStr + ')';
    return QMetaObject::normalizedSignature(sign.c_str());
}

// BuilderImpl

class SwiftMetaObjectBuilder::BuilderImpl : public QDynamicMetaObjectData
{
public:
    BuilderImpl(const QMetaObject* staticMetaObj, const char *className)
        : m_metaObjectBuilder(std::make_unique<QMetaObjectBuilder>())
    {
        m_metaObjectBuilder->setSuperClass(staticMetaObj);
        m_metaObjectBuilder->setClassName(QByteArray(className));
    }

    QMetaObject* toDynamicMetaObject(QObject*) override
    {
        if (!m_metaObject)
            endMetaRegistration();

        return m_metaObject.get();
    }

    void objectDestroyed(QObject *) override
    {
        // Do nothing here unlike QDynamicMetaObjectData
        // to avoid double deletion
    }

    int metaCall(QObject* o, QMetaObject::Call call, int id, void** argv) override
    {
        if (!m_metaObject)
            throw std::logic_error(__func__ + " called before endMetaRegistration()"s);

        auto swiftObjectAccessor = dynamic_cast<const SwiftObjectAccesor*>(o);
        if (!swiftObjectAccessor)
            throw std::runtime_error("Failed to get pointer to Swift object");
        void* swiftObject = swiftObjectAccessor->swiftObject();

        switch (call)
        {
        case QMetaObject::InvokeMetaMethod:
            if (handleMetaCallInvoke(o, swiftObject, id, argv))
                return -1;
            break;
        case QMetaObject::ReadProperty:
            if (handleMetaCallReadProperty(swiftObject, id, argv))
                return -1;
            break;
        case QMetaObject::WriteProperty:
            if (handleMetaCallWriteProperty(swiftObject, id, argv))
                return -1;
            break;
        default:
            break;
        }

        return o->qt_metacall(call, id, argv);
    }

    bool handleMetaCallInvoke(QObject* o, void* swiftObject, int id, void** argv)
    {
        const int methodId = id - m_metaObject->methodOffset();
        if (methodId < 0 || methodId >= m_metaObject->methodCount())
            return false;

        QMetaMethod method = m_metaObject->method(id);
        switch (method.methodType())
        {
        case QMetaMethod::Signal:
        {
            QMetaObject::activate(o, id, argv);
            return true;
        }
        break;
        case QMetaMethod::Slot:
        {
            auto slotIt = m_slots.find(methodId);
            if (slotIt == m_slots.end())
                return false;

            if (auto& callback = slotIt->second.m_callback)
            {
                const MetaParamsList params(method, argv);
                QVariant result = callback(swiftObject, params);
                if (argv[0] && method.returnType() != QMetaType::Void
                    && result.metaType().id() == method.returnType()) {
                    QMetaType(method.returnType()).construct(argv[0], result.constData());
                }
                return true;
            }
        }
        break;
        default:
            break;
        }

        return false;
    }

    bool handleMetaCallReadProperty(void* swiftObject, int id, void** argv)
    {
        const int propId = id - m_metaObject->propertyOffset();
        if (propId < 0 || propId >= m_metaObject->propertyCount())
            return false;

        void* dstArg = argv[0];
        if (!dstArg)
            return false;

        auto propIt = m_properties.find(propId);
        if (propIt == m_properties.end())
            return false;

        auto& getterFunc = propIt->second.m_readCallback;
        if (!getterFunc)
            return false;

        const QMetaProperty property = m_metaObject->property(id);
        QVariant result = getterFunc(swiftObject);
        if (!QMetaType::convert(result.metaType(), result.data(), property.metaType(), dstArg))
            throw std::logic_error("Property type mismatch");

        return true;
    }

    bool handleMetaCallWriteProperty(void* swiftObject, int id, void** argv)
    {
        const int propId = id - m_metaObject->propertyOffset();
        if (propId < 0 || propId >= m_metaObject->propertyCount())
            return false;

        void* arg = argv[0];
        if (!arg)
            return false;

        auto propIt = m_properties.find(propId);
        if (propIt == m_properties.end())
            return false;

        auto& setterFunc = propIt->second.m_writeCallback;
        if (!setterFunc)
            return false;

        const QMetaProperty property = m_metaObject->property(id);
        const QVariant v = QVariant::fromMetaType(property.metaType(), arg);
        if (!v.isValid())
            return false;

        return setterFunc(swiftObject, &v);
    }

    void registerSlot(const std::string &name, int propertyId,
                      int returnTypeId, const std::vector<int> &argTypeIds,
                      void *builderPtr, SlotFunc callback)
    {
        if (!m_metaObjectBuilder)
            throw std::runtime_error("Slot registration must be done before endMetaRegistration() call");

        const std::vector<QMetaType> metaTypes(argTypeIds.begin(), argTypeIds.end());
        QByteArray signature = generateFuncSignature(name, metaTypes);
        QMetaMethodBuilder builder = m_metaObjectBuilder->addSlot(signature);

        QByteArray returnType = QMetaType(returnTypeId).name();
        if (!returnType.isEmpty() && returnTypeId != QMetaType::Void) {
            builder.setReturnType(returnType);
        }
        const int localId = builder.index();

        SlotInfo info;
        info.m_callback = [propertyId, builderPtr, callback](void *receiver, const MetaParamsList& params) -> QVariant {
            return callback(propertyId, builderPtr, receiver, params);
        };

        m_slots.emplace(localId, info);
    }

    void registerSignal(const std::string &name, const std::vector<int> &argTypeIds)
    {
        if (!m_metaObjectBuilder)
            throw std::runtime_error("Signal registration must be done before endMetaRegistration() call");

        const std::vector<QMetaType> metaTypes(argTypeIds.begin(), argTypeIds.end());
        QByteArray signature = generateFuncSignature(name, metaTypes);
        QMetaMethodBuilder builder = m_metaObjectBuilder->addSignal(signature);
        const int localId = builder.index();
        auto [_, added] = m_signalNameToId.emplace(name, localId);

        if (!added)
            throw std::runtime_error("Failed to register signal");
    }

    void registerProperty(const std::string &name, void *builderPtr, int propertyId,
                          int typeId, ReadFunc readCallback, WriteFunc writeCallback)
    {
        if (!m_metaObjectBuilder)
            throw std::runtime_error("Property registration must be done before endMetaRegistration() call");

        QMetaType metaType(typeId);
        if (!metaType.isValid())
            throw std::runtime_error("Invalid property type");

        const bool isWritable = static_cast<bool>(writeCallback);

        const auto it = m_signalNameToId.find(name + "Changed");
        bool hasSignal = it != m_signalNameToId.end();

        QMetaPropertyBuilder builder = m_metaObjectBuilder->addProperty(
                                           QByteArray::fromStdString(name), metaType.name());
        builder.setReadable(true);
        builder.setWritable(isWritable);
        builder.setConstant(!isWritable && !hasSignal);
        if (hasSignal) {
            builder.setNotifySignal(m_metaObjectBuilder->method(it->second));
        }

        const auto localId = builder.index();

        PropertyInfo info;
        info.m_type = metaType;
        info.m_readCallback = [propertyId, builderPtr, readCallback](void* receiver) {
            return readCallback(propertyId, builderPtr, receiver);
        };
        if (isWritable) {
            info.m_writeCallback = [propertyId, builderPtr, writeCallback](void* receiver, const QVariant* value){
                return writeCallback(propertyId, builderPtr, receiver, value);
            };
        }

        auto [_, added] = m_properties.emplace(localId, std::move(info));
        if (!added)
            throw std::runtime_error("Failed to register property");
    }

    void endMetaRegistration()
    {
        if (m_metaObjectBuilder) {
            m_metaObject.reset(m_metaObjectBuilder->toMetaObject());
            m_metaObjectBuilder.reset();
        } else {
            Q_ASSERT_X(false, Q_FUNC_INFO, "Called more than once");
        }
    }

    QMetaMethod metaMethod(int id) const
    {
        if (!m_metaObject)
            throw std::logic_error(__func__ + " called before endMetaRegistration()"s);

        const int methodOffset = m_metaObject->methodOffset();
        const QMetaMethod method = m_metaObject->method(id + methodOffset);
        return method;
    }

    void emitSignal(QObject* obj, const std::string &name, const std::vector<QVariant> &args)
    {
        if (!obj)
            return;

        auto it = m_signalNameToId.find(name);
        if (it == m_signalNameToId.end())
            return;

        QMetaMethod signal = metaMethod(it->second);
        const int signalIndex = signal.methodIndex();

        if (signalIndex < 0)
            return;

        QMetaMethod metaMethod = m_metaObject->method(signalIndex);

        if (metaMethod.parameterCount() != int(args.size()))
            throw std::logic_error("Signal argument count mismatch");

        std::vector<QVariant> convertedArgs;
        const size_t argsSize = args.size();
        convertedArgs.reserve(argsSize);

        for (size_t i = 0; i < argsSize; ++i) {
            QMetaType paramMetaType = metaMethod.parameterMetaType(static_cast<int>(i));
            QVariant v = args[i];
            if (v.metaType() != paramMetaType && !v.convert(paramMetaType))
                throw std::runtime_error("Failed to convert signal argument");
            convertedArgs.push_back(std::move(v));
        }

        QMetaObject::invokeMethod(obj, [obj, signalIndex, args = std::move(convertedArgs)]() mutable {
            std::vector<void*> argv;
            argv.reserve(args.size() + 1);
            argv.push_back(nullptr); // Signal return value

            for (auto &arg : args) {
                argv.push_back(arg.data());
            }

            QMetaObject::activate(obj, signalIndex, argv.data());
        }, Qt::QueuedConnection);
    }

private:
    struct SlotInfo
    {
        std::function<QVariant(void *receiver, const MetaParamsList&)> m_callback;
    };
    using SlotId = int;
    std::unordered_map<SlotId, SlotInfo> m_slots;

    struct PropertyInfo
    {
        QMetaType m_type;
        std::function<QVariant(void* receiver)> m_readCallback;
        std::function<bool(void* receiver, const QVariant*)> m_writeCallback;
    };
    using PropertyId = int;
    std::unordered_map<PropertyId, PropertyInfo> m_properties;

    using SignalId = int;
    std::unordered_map<std::string, SignalId> m_signalNameToId;

    std::unique_ptr<QMetaObjectBuilder> m_metaObjectBuilder;
    std::unique_ptr<QMetaObject, QScopedPointerPodDeleter> m_metaObject;
};

SwiftMetaObjectBuilder::SwiftMetaObjectBuilder(const char *className)
{
    m_impl = std::make_shared<SwiftMetaObjectBuilder::BuilderImpl>(
        &QObjectProxyImpl::staticMetaObject,
        className
    );
}

SwiftMetaObjectBuilder::~SwiftMetaObjectBuilder()
{
}

void SwiftMetaObjectBuilder::setMetaObjectTo(QObjectProxy dst) const
{
    QObjectPrivate::get(dst.toObject())->metaObject = m_impl.get();
}

const QMetaObject* SwiftMetaObjectBuilder::metaObject() const
{
    return m_impl->toDynamicMetaObject(nullptr);
}

void SwiftMetaObjectBuilder::registerSlot(const char *name,
                                          void *builderPtr,
                                          int propertyId,
                                          int returnTypeId,
                                          const std::vector<int> &argTypeIds,
                                          SlotFunc callback)
{
    m_impl->registerSlot(name, propertyId, returnTypeId, argTypeIds, builderPtr, callback);
}

void SwiftMetaObjectBuilder::registerSignal(const char *name, const std::vector<int> &argTypeIds)
{
    m_impl->registerSignal(name, argTypeIds);
}

void SwiftMetaObjectBuilder::emitSignal(QObjectProxy sender, const char *name, const std::vector<QVariant> &args)
{
    m_impl->emitSignal(sender.toObject(), name, args);
}

void SwiftMetaObjectBuilder::registerProperty(const char *name, void *builderPtr,
                                              int propertyId, int typeId,
                                              ReadFunc readCallback,
                                              WriteFunc writeCallback)
{
    m_impl->registerProperty(name, builderPtr, propertyId, typeId, readCallback, writeCallback);
}

void SwiftMetaObjectBuilder::endMetaRegistration()
{
    m_impl->endMetaRegistration();
}
