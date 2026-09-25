// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

class SwiftObjectAccesor {
public:
    virtual ~SwiftObjectAccesor() = default;
    virtual void *swiftObject() const = 0;
};
