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

# autoresearch: build QtBridgeMacros as a library plugin linked against the
# toolchain's OWN host swift-syntax dylibs (usr/lib/swift/host). This removes
# the ~34s serial 11-module swift-syntax chain and runs expansion in-process.
# SwiftCompilerPlugin is not shipped to hosts, so the @main tail is guarded
# CMAKE_Swift_COMPILER may be a shim (swiftly). The toolchain root is only
# reliably discoverable from the compiler's own target info.
execute_process(
    COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
    OUTPUT_VARIABLE _qtb_target_info
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(JSON _qtb_rt GET "${_qtb_target_info}" paths runtimeResourcePath)
set(QTBRIDGE_HOST_LIB_DIR "${_qtb_rt}/host")
if(NOT EXISTS "${QTBRIDGE_HOST_LIB_DIR}/libSwiftSyntax.dylib")
    message(FATAL_ERROR "host swift-syntax not found at ${QTBRIDGE_HOST_LIB_DIR}")
endif()
add_library(QtBridgeMacros SHARED
    Sources/QtBridgeMacros/Extensions.swift
    Sources/QtBridgeMacros/QtBridgeableMacro.swift
)
set_target_properties(QtBridgeMacros PROPERTIES
    Swift_MODULE_NAME QtBridgeMacros
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
    BUILD_RPATH "${QTBRIDGE_HOST_LIB_DIR}"
)
target_compile_options(QtBridgeMacros PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-I${QTBRIDGE_HOST_LIB_DIR}>"
)
target_link_directories(QtBridgeMacros PRIVATE "${QTBRIDGE_HOST_LIB_DIR}")
target_link_libraries(QtBridgeMacros PRIVATE
    SwiftSyntax SwiftDiagnostics SwiftBasicFormat SwiftParser
    SwiftParserDiagnostics SwiftOperators SwiftSyntaxBuilder
    SwiftSyntaxMacros SwiftSyntaxMacroExpansion SwiftIfConfig
    SwiftCompilerPluginMessageHandling
)

set(QTBRIDGE_MACROS_PLUGIN_PATH
    "$<TARGET_FILE:QtBridgeMacros>"
    CACHE STRING "Macro plugin load path"
)



add_subdirectory(Sources/QtBridgeCpp)
add_subdirectory(Sources/QtBridge)

