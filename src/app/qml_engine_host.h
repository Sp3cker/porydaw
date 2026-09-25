#pragma once

class QQmlApplicationEngine;

const char *pd_qml_module_prefix();

[[nodiscard]] QQmlApplicationEngine *pd_qml_engine();

[[nodiscard]] bool pd_qml_add_import_path(const char *path);
