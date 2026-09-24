#include "qml_engine_host.h"

#include <QtCore/qthread.h>
#include <QtQml/qqmlapplicationengine.h>
#include <QtQml/qqmlcontext.h>

#include <qappcpp.h>

const char *pd_qml_module_prefix()
{
    return "qrc:/qt/qml/Porydaw/Ui/";
}

QQmlApplicationEngine *pd_qml_engine()
{
    QQmlApplicationEngine *engine = QAppCpp::engine();
    Q_ASSERT(!engine || QThread::currentThread() == engine->thread());
    return engine;
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
