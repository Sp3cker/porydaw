#include "qml_engine_host.h"

#include <QtQml/qqmlapplicationengine.h>
#include <QtQml/qqmlcontext.h>
#include <QtQuick/qquickimageprovider.h>

#include <qappcpp.h>

QQmlApplicationEngine *pd_qml_engine()
{
    return QAppCpp::engine();
}

bool pd_qml_add_image_provider(const QString &id, QQuickImageProvider *provider)
{
    QQmlApplicationEngine *engine = pd_qml_engine();
    if (!engine || !provider)
        return false;
    if (engine->imageProvider(id))
        return false;
    engine->addImageProvider(id, provider);
    return true;
}

bool pd_qml_set_context_property(const char *name, const QVariant &value)
{
    QQmlApplicationEngine *engine = pd_qml_engine();
    if (!engine || !name)
        return false;
    engine->rootContext()->setContextProperty(QString::fromUtf8(name), value);
    return true;
}

bool pd_qml_add_import_path(const char *path)
{
    QQmlApplicationEngine *engine = pd_qml_engine();
    if (!engine || !path)
        return false;
    engine->addImportPath(QString::fromUtf8(path));
    return true;
}

bool pd_qml_clear_component_cache()
{
    QQmlApplicationEngine *engine = pd_qml_engine();
    if (!engine)
        return false;
    engine->clearComponentCache();
    return true;
}
