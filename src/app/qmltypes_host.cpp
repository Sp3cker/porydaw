#include "qmltypes_host.h"

#include <QtCore/qcoreapplication.h>
#include <QtCore/qmetaobject.h>
#include <QtCore/qmetatype.h>
#include <QtCore/qtyperevision.h>

#include <new>

struct PdQmlTypesApplication {
    int argc;
    QCoreApplication application;

    PdQmlTypesApplication(int count, char **arguments)
        : argc(count), application(argc, arguments)
    {
    }
};

PdQmlTypesApplication *pd_qmltypes_application_create(int argc, char **argv)
{
    return new (std::nothrow) PdQmlTypesApplication(argc, argv);
}

void pd_qmltypes_application_destroy(PdQmlTypesApplication *application)
{
    delete application;
}

int pd_qmltypes_metatype_id(const char *name)
{
    return QMetaType::fromName(name).id();
}

int pd_qmltypes_method_kind_method(void)
{
    return static_cast<int>(QMetaMethod::Method);
}

int pd_qmltypes_method_kind_signal(void)
{
    return static_cast<int>(QMetaMethod::Signal);
}

int pd_qmltypes_method_kind_slot(void)
{
    return static_cast<int>(QMetaMethod::Slot);
}

int pd_qmltypes_method_access_public(void)
{
    return static_cast<int>(QMetaMethod::Public);
}

int pd_qmltypes_export_revision(void)
{
    return QTypeRevision::fromVersion(1, 0).toEncodedVersion<int>();
}
