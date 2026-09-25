// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <QtCore/qobject.h>
#include <QtCore/qurl.h>
#include <QtCore/qvariant.h>

#include <QtQml/qqmlapplicationengine.h>

#include <swift/bridging>

#include "qobjectproxy.h"

class QAppCpp
{
public:
    QAppCpp();
    ~QAppCpp();

    void addImportPath(const char *path);
    void setPluginsPath(const char *path);

    void addInitialProperty(const char *name, QVariant value);
    void setRootQml(const char *path);

    int run(int argc, char **argv);

    // The application engine while run() is executing; nullptr before load
    // and after exec() returns. Valid to call from slots during exec().
    static QQmlApplicationEngine *engine();

private:
    std::vector<QString> m_importPaths;
    QString m_pluginsPath;
    QVariantMap m_map;
    QUrl m_root;
};
