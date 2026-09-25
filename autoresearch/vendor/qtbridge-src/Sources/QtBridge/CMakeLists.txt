# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

set(QTBRIDGE_SWIFT_SOURCES
    Extensions.swift
    QAbstractItemModel.swift
    QAbstractListModel.swift
    QAbstractTableModel.swift
    QApp.swift
    QListModel.swift
    QMetaObjectBuilder.swift
    QMetaParamsList.swift
    QmlInstantiable.swift
    QmlInstantiableStatus.swift
    QModelIndex.swift
    QNamespace.swift
    QObjectBuildable.swift
    QObjectHolder.swift
    QTableModel.swift
    QtBridgesMacros.swift
    QVariant.swift
)

add_library(QtBridge
    ${QTBRIDGE_SWIFT_SOURCES}
)

target_link_libraries(QtBridge
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        QtBridgeCpp
    PRIVATE
        Qt6::CorePrivate
)

set(package_name "-package-name" "QtBridge")
target_compile_options(QtBridge PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:-cxx-interoperability-mode=default>"
    "$<$<COMPILE_LANGUAGE:Swift>:${package_name}>"
)

if(WIN32)
    target_compile_options(QtBridge PUBLIC
        "$<$<COMPILE_LANGUAGE:Swift>:-Xcc>"
        "$<$<COMPILE_LANGUAGE:Swift>:-std=c++20>"
    )
    target_compile_options(QtBridge PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-DQT_IS_CXX_20>"
    )
endif()

if(DEFINED QTBRIDGE_SWIFT_BRIDGING_INCLUDE)
    target_compile_options(QtBridge PUBLIC
        "$<$<COMPILE_LANGUAGE:Swift>:-Xcc>"
        "$<$<COMPILE_LANGUAGE:Swift>:-I${QTBRIDGE_SWIFT_BRIDGING_INCLUDE}>"
    )
    target_include_directories(QtBridge PUBLIC
        "$<$<COMPILE_LANGUAGE:CXX>:${QTBRIDGE_SWIFT_BRIDGING_INCLUDE}>"
    )
endif()

target_compile_options(QtBridge PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-DQT_IS_CMAKE_BUILD>"
)
# autoresearch harness: QtBridge's own sources only declare the macros —
# they never invoke them — so the library compiles without the plugin dylib.
# INTERFACE scope hands consumers -load-plugin-library (dylib path only, no
# #module). NOTE: TARGET_FILE inside target_compile_options adds NO Ninja
# build edge — each macro-consuming target needs its own add_dependencies
# (see PorydawApp); the leaves are macro-free so they carry none.
if(DEFINED QTBRIDGE_MACROS_PLUGIN_PATH)
    target_compile_options(QtBridge INTERFACE
        "$<$<COMPILE_LANGUAGE:Swift>:-load-plugin-library>"
        "$<$<COMPILE_LANGUAGE:Swift>:${QTBRIDGE_MACROS_PLUGIN_PATH}>"
    )
endif()

# Set Swift version; AUTOMOC off — pure Swift target, the autogen step only
# serializes QtBridge.swiftmodule behind the C++ QtBridgeCpp archive.
set_target_properties(QtBridge PROPERTIES
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
