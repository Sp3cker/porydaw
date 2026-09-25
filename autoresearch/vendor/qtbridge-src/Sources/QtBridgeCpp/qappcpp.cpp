// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "qappcpp.h"
#include "quickdisplaylistitem.h"

#include <QtGui/qguiapplication.h>
#include <QtQml/qqmlapplicationengine.h>

static QQmlApplicationEngine *s_engine = nullptr;

QQmlApplicationEngine *QAppCpp::engine()
{
    return s_engine;
}

QAppCpp::QAppCpp()
{
    registerQuickDisplayListQmlType();
}

QAppCpp::~QAppCpp()
{
}

void QAppCpp::addImportPath(const char *path)
{
    m_importPaths.push_back(QString(path));
}

void QAppCpp::setPluginsPath(const char *path)
{
    m_pluginsPath = QString(path);
}

void QAppCpp::addInitialProperty(const char *name, QVariant value)
{
    m_map.insert(QString::fromUtf8(name), value);
}

void QAppCpp::setRootQml(const char *path)
{
    m_root = QUrl::fromLocalFile(QString::fromUtf8(path));
}

int QAppCpp::run(int argc, char **argv)
{
    qputenv("QT_PLUGIN_PATH", m_pluginsPath.toUtf8());

    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    for (const auto &path: m_importPaths)
        engine.addImportPath(path);

    engine.setInitialProperties(m_map);
    s_engine = &engine;
    engine.load(m_root);

    const int rc = app.exec();
    s_engine = nullptr;
    return rc;
}
