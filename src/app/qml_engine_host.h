#pragma once

#include <QtCore/qvariant.h>

class QQmlApplicationEngine;

const char *pd_qml_module_prefix();

[[nodiscard]] QQmlApplicationEngine *pd_qml_engine();

[[nodiscard]] bool pd_qml_set_context_property(const char *name, const QVariant &value);

[[nodiscard]] bool pd_qml_add_import_path(const char *path);
