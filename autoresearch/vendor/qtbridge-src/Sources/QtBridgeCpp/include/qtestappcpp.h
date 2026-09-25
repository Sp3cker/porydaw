// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qvariant.h>

#include <string>

#include "qobjectproxy.h"

class QTestAppCpp
{
public:
    QTestAppCpp();
    ~QTestAppCpp() = default;

    void setImportPath(const char *path);
    void setPluginsPath(const char *path);

    void setInputDir(const char* dir);
    void setTestName(const char *name);

    void registerQmlSingleton(const char* uri, int major, int minor,
                              const char* name, QObjectProxy proxy);
    int runQtQuickTests(int argc, char** argv);

private:
    std::string m_importPath;
    std::string m_pluginsPath;
    std::string m_inputDir;
    std::string m_testName;
};
