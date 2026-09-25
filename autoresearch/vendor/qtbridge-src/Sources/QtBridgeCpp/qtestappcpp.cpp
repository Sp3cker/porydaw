// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

#include "qtestappcpp.h"
#include "quickdisplaylistitem.h"

#include <QtQuickTest/quicktest.h>
#include <QtQml/QQmlEngine>
#include <QtCore/qobject.h>

QTestAppCpp::QTestAppCpp()
{
    registerQuickDisplayListQmlType();
}

void QTestAppCpp::setImportPath(const char *path)
{
    m_importPath = std::string(path);
}

void QTestAppCpp::setPluginsPath(const char *path)
{
    m_pluginsPath = std::string(path);
}

void QTestAppCpp::setInputDir(const char *dir) {
    m_inputDir = dir ? dir : "";
}

void QTestAppCpp::setTestName(const char *name) {
    m_testName = name ? name : "";
}

void QTestAppCpp::registerQmlSingleton(const char* uri, int major, int minor,
                                       const char* name, QObjectProxy proxy)
{
    auto obj = proxy.toObject();
    qmlRegisterSingletonInstance(uri, major, minor, name, obj);
}

int QTestAppCpp::runQtQuickTests(int argc, char** argv)
{
    qputenv("QT_PLUGIN_PATH", m_pluginsPath);
    qputenv("QML2_IMPORT_PATH", m_importPath);

    const char* dir = m_inputDir.empty() ? nullptr : m_inputDir.c_str();
    const char* testName = m_testName.empty() ? nullptr : m_testName.c_str();

    return quick_test_main(argc, argv, testName, dir);
}
