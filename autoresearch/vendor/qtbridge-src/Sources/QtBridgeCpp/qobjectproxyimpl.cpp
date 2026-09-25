// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "qobjectproxyimpl.h"

QObjectProxyImpl::~QObjectProxyImpl()
{
    if (m_deleter)
        m_deleter(m_swiftObj);
}

void* QObjectProxyImpl::swiftObject() const
{
    return m_swiftObj;
}

QQmlListProperty<QObject> QObjectProxyImpl::children()
{
    return QQmlListProperty<QObject>(this, &m_children);
}

QList<void*> QObjectProxyImpl::swiftChildren() const
{
    QList<void*> children;
    children.reserve(m_children.size());

    for (auto *child : m_children) {
        QObjectProxyImpl *proxy = qobject_cast<QObjectProxyImpl *>(child);
        if (!proxy)
            continue;

        void* ptr = proxy->swiftObject();
        if (!ptr)
            continue;

        children << ptr;
    }

    return children;
}

void QObjectProxyImpl::registerComponentComplete(void *holderPtr, CompleteFn callback)
{
    m_completeCallback = [holderPtr, callback]() {
        callback(holderPtr);
    };
}

void QObjectProxyImpl::classBegin()
{
}

void QObjectProxyImpl::componentComplete()
{
   if (m_completeCallback)
        m_completeCallback();
}

/****************************************************************************
** Meta object code from reading C++ file 'qobjectproxyimpl.h'
**
** Created by: The Qt Meta Object Compiler version 69 (Qt 6.10.0)
**
** WARNING! All changes made in this file will be lost!
*****************************************************************************/

#include <QtCore/qmetatype.h>

#include <QtCore/qtmochelpers.h>

#include <memory>


#include <QtCore/qxptype_traits.h>
#if !defined(Q_MOC_OUTPUT_REVISION)
#error "The header file 'qobjectproxyimpl.h' doesn't include <QObject>."
#elif Q_MOC_OUTPUT_REVISION != 69
#error "This file was generated using the moc from 6.10.0. It"
#error "cannot be used with the include files from this version of Qt."
#error "(The moc has changed too much.)"
#endif

#ifndef Q_CONSTINIT
#define Q_CONSTINIT
#endif

QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
QT_WARNING_DISABLE_GCC("-Wuseless-cast")
namespace {
struct qt_meta_tag_ZN16QObjectProxyImplE_t {};
} // unnamed namespace

template <> constexpr inline auto QObjectProxyImpl::qt_create_metaobjectdata<qt_meta_tag_ZN16QObjectProxyImplE_t>()
{
    namespace QMC = QtMocConstants;
    QtMocHelpers::StringRefStorage qt_stringData {
        "QObjectProxyImpl",
        "DefaultProperty",
        "children",
        "QQmlListProperty<QObject>"
    };

    QtMocHelpers::UintData qt_methods {
    };
    QtMocHelpers::UintData qt_properties {
        // property 'children'
        QtMocHelpers::PropertyData<QQmlListProperty<QObject>>(2, 0x80000000 | 3, QMC::DefaultPropertyFlags | QMC::EnumOrFlag | QMC::Constant),
    };
    QtMocHelpers::UintData qt_enums {
    };
    QtMocHelpers::UintData qt_constructors {};
    QtMocHelpers::ClassInfos qt_classinfo({
            {    1,    2 },
    });
    return QtMocHelpers::metaObjectData<QObjectProxyImpl, qt_meta_tag_ZN16QObjectProxyImplE_t>(QMC::MetaObjectFlag{}, qt_stringData,
            qt_methods, qt_properties, qt_enums, qt_constructors, qt_classinfo);
}
Q_CONSTINIT const QMetaObject QObjectProxyImpl::staticMetaObject = { {
    QMetaObject::SuperData::link<QObject::staticMetaObject>(),
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN16QObjectProxyImplE_t>.stringdata,
    qt_staticMetaObjectStaticContent<qt_meta_tag_ZN16QObjectProxyImplE_t>.data,
    qt_static_metacall,
    nullptr,
    qt_staticMetaObjectRelocatingContent<qt_meta_tag_ZN16QObjectProxyImplE_t>.metaTypes,
    nullptr
} };

void QObjectProxyImpl::qt_static_metacall(QObject *_o, QMetaObject::Call _c, int _id, void **_a)
{
    auto *_t = static_cast<QObjectProxyImpl *>(_o);
    if (_c == QMetaObject::ReadProperty) {
        void *_v = _a[0];
        switch (_id) {
        case 0: *reinterpret_cast<QQmlListProperty<QObject>*>(_v) = _t->children(); break;
        default: break;
        }
    }
}

const QMetaObject *QObjectProxyImpl::metaObject() const
{
    return QObject::d_ptr->metaObject ? QObject::d_ptr->dynamicMetaObject() : &staticMetaObject;
}

void *QObjectProxyImpl::qt_metacast(const char *_clname)
{
    if (!_clname) return nullptr;
    if (!strcmp(_clname, qt_staticMetaObjectStaticContent<qt_meta_tag_ZN16QObjectProxyImplE_t>.strings))
        return static_cast<void*>(this);
    if (!strcmp(_clname, "SwiftObjectAccesor"))
        return static_cast< SwiftObjectAccesor*>(this);
    if (!strcmp(_clname, "QQmlParserStatus"))
        return static_cast< QQmlParserStatus*>(this);
    if (!strcmp(_clname, "org.qt-project.Qt.QQmlParserStatus"))
        return static_cast< QQmlParserStatus*>(this);
    return QObject::qt_metacast(_clname);
}

int QObjectProxyImpl::qt_metacall(QMetaObject::Call _c, int _id, void **_a)
{
    _id = QObject::qt_metacall(_c, _id, _a);
    if (_id < 0)
        return _id;
    if (_c == QMetaObject::ReadProperty || _c == QMetaObject::WriteProperty
            || _c == QMetaObject::ResetProperty || _c == QMetaObject::BindableProperty
            || _c == QMetaObject::RegisterPropertyMetaType) {
        qt_static_metacall(this, _c, _id, _a);
        _id -= 1;
    }
    return _id;
}
QT_WARNING_POP
