# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

set(QTBRIDGE_CPP_SOURCES
    abstractitemmodel.cpp
    abstractlistmodel.cpp
    abstracttablemodel.cpp
    callbackbase.cpp
    metaparamslist.cpp
    qappcpp.cpp
    include/quickdisplaylistitem.h
    quickdisplaylistitem.cpp
    qobjectproxy.cpp
    qobjectproxyimpl.cpp
    qtestappcpp.cpp
    swiftmetaobjectbuilder.cpp
    swiftqmlelementbuilder.cpp
)

add_library(QtBridgeCpp STATIC ${QTBRIDGE_CPP_SOURCES})

target_link_libraries(QtBridgeCpp
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
    PRIVATE
        Qt6::CorePrivate
)

target_include_directories(QtBridgeCpp
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        ${QTBRIDGE_SWIFT_BRIDGING_INCLUDE}
)
