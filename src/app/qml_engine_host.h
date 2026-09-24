#pragma once

#include <QtCore/qvariant.h>

class QQmlApplicationEngine;
class QQuickImageProvider;
class QString;

// Native boundary for the running QQmlApplicationEngine. QAppCpp::run()
// owns the engine; these functions reach it through QAppCpp::engine() so
// Swift presenters can perform engine-scoped operations (image providers,
// context properties, import paths, cache control) without workarounds.
// All functions are no-ops returning failure while the engine is absent
// (before the root document loads, after exec() returns).

// The live engine, or nullptr outside run(). C++ callers that need the
// raw pointer use this; Swift callers use the operations below since
// QQmlApplicationEngine is a reference type invisible to the importer.
QQmlApplicationEngine *pd_qml_engine();

// Registers a QQuickImageProvider under `id` (image://id/...). The engine
// takes ownership. Returns false if a provider already owns the id or the
// engine is absent.
bool pd_qml_add_image_provider(const QString &id, QQuickImageProvider *provider);

// Sets a root-context property visible to every loaded component.
bool pd_qml_set_context_property(const char *name, const QVariant &value);

// Adds a QML import path at runtime.
bool pd_qml_add_import_path(const char *path);

// Drops the engine's compiled-component cache (e.g. after hot reloads).
bool pd_qml_clear_component_cache();
