// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#include <memory>

#include "swiftmetaobjectbuilder.h"

class SwiftQmlElementBuilder
{
public:
    SwiftQmlElementBuilder(const char *moduleName,
                           const char *className);
    ~SwiftQmlElementBuilder();

    void setMetaObjectFrom(SwiftMetaObjectBuilder builder);

    using CreateFn = void (*)(void *builderPtr, void *addr);
    void registerCreateFn(void *builderPtr, CreateFn fn);

    void registerQmlElement();

private:
    class Impl;
    std::shared_ptr<Impl> m_impl;
};
