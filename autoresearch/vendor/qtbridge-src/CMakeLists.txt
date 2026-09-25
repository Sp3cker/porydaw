# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

cmake_minimum_required(VERSION 3.22)

project(QtBridge
    VERSION 0.2.0
    LANGUAGES CXX Swift
)

if(WIN32)
  set(CMAKE_CXX_STANDARD 20)
else()
  set(CMAKE_CXX_STANDARD 17)
endif()

set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Verify compiler requirements
if("${CMAKE_Swift_COMPILER_VERSION}" VERSION_LESS 6.2)
  message(FATAL_ERROR "QtBridge requires Swift 6.2 or greater. Have ${CMAKE_Swift_COMPILER_VERSION}")
endif()

include(cmake/QtBridgesSwiftHelpers.cmake)
qtbridge_detect_swift_bridging_headers()

# Suppress Qt private module warning
set(QT_NO_PRIVATE_MODULE_WARNING ON)

find_package(Qt6 6.10 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    CorePrivate
)

set(CMAKE_AUTOMOC ON)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

if(WIN32)
  set(CMAKE_STATIC_LIBRARY_PREFIX "lib")
  # This is needed to avoid the MSVC error:
  # "The maximum full path to an object file is 250 characters"
  set(CMAKE_NINJA_FORCE_RESPONSE_FILE ON)
endif()

# Build QtBridgeMacros via ExternalProject (must build for host, not target)
include(ExternalProject)
set(QTBRIDGE_MACROS_EP_ROOT "${CMAKE_BINARY_DIR}/qtbridge_macros_ep")
ExternalProject_Add(QtBridgeMacros_External
    PREFIX "${QTBRIDGE_MACROS_EP_ROOT}"
    BINARY_DIR "${QTBRIDGE_MACROS_EP_ROOT}/build"
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/Sources/QtBridgeMacros"
    CMAKE_ARGS
        -G Ninja
        -DCMAKE_MAKE_PROGRAM:FILEPATH=${CMAKE_MAKE_PROGRAM}
        -DCMAKE_Swift_COMPILER:FILEPATH=${CMAKE_Swift_COMPILER}
        -DCMAKE_Swift_FLAGS:STRING=${CMAKE_Swift_FLAGS}
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DBUILD_SHARED_LIBS=YES
        -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=${QTBRIDGE_MACROS_EP_ROOT}/build/bin
    BUILD_BYPRODUCTS "${QTBRIDGE_MACROS_EP_ROOT}/build/bin/QtBridgeMacros"
    USES_TERMINAL_BUILD TRUE
    INSTALL_COMMAND ""
)
ExternalProject_Get_Property(QtBridgeMacros_External BINARY_DIR)

set(QTBRIDGE_MACROS_BINARY_DIR "${BINARY_DIR}"
  CACHE PATH "Path to QtBridgeMacros build"
)
if(CMAKE_HOST_WIN32)
  set(QTBRIDGE_MACROS_PLUGIN_PATH
    "${BINARY_DIR}/bin/QtBridgeMacros.exe#QtBridgeMacros"
    CACHE STRING "Macro plugin load path"
  )
else()
  set(QTBRIDGE_MACROS_PLUGIN_PATH
    "${BINARY_DIR}/bin/QtBridgeMacros#QtBridgeMacros"
    CACHE STRING "Macro plugin load path"
  )
endif()

add_library(QtBridgeMacros INTERFACE)
add_dependencies(QtBridgeMacros QtBridgeMacros_External)

add_subdirectory(Sources/QtBridgeCpp)
add_subdirectory(Sources/QtBridge)

