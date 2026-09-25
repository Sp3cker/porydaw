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

# autoresearch harness: build QtBridgeMacros in-tree instead of an
# ExternalProject. On this platform host == target, so the separate
# configure+build EP only adds a serial stamp boundary; a subdirectory puts
# the macro executable in the main Ninja graph.
add_subdirectory(Sources/QtBridgeMacros)

if(CMAKE_HOST_WIN32)
  set(QTBRIDGE_MACROS_PLUGIN_PATH
    "$<TARGET_FILE:QtBridgeMacros>#QtBridgeMacros"
    CACHE STRING "Macro plugin load path"
  )
else()
  set(QTBRIDGE_MACROS_PLUGIN_PATH
    "$<TARGET_FILE:QtBridgeMacros>#QtBridgeMacros"
    CACHE STRING "Macro plugin load path"
  )
endif()



add_subdirectory(Sources/QtBridgeCpp)
add_subdirectory(Sources/QtBridge)

