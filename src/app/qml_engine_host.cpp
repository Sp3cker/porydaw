#include "qml_engine_host.h"

#include <QtCore/qthread.h>
#include <QtQml/qqmlapplicationengine.h>

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

bool pd_qml_add_import_path(const char *path)
{
    QQmlApplicationEngine *engine = pd_qml_engine();
    if (!engine || !path)
        return false;
    engine->addImportPath(QString::fromUtf8(path));
    return true;
}
