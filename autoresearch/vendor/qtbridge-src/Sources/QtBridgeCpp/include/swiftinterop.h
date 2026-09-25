// Copyright (C) 2025 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR GPL-3.0-only

#pragma once

#if defined(__clang__)
  #define SWIFT_MAIN_ACTOR __attribute__((swift_attr("@MainActor")))
#else
  #define SWIFT_MAIN_ACTOR
#endif
