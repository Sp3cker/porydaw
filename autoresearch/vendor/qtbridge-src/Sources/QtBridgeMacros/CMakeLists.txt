# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

# QtBridgeMacros standalone CMake project
# This is built as an ExternalProject from the main build because:
# 1. Macros must be built for the build machine, not the target
# 2. SwiftSyntax is fetched and built as part of the macro


cmake_minimum_required(VERSION 3.22)

project(QtBridgeMacros LANGUAGES Swift)

# autoresearch harness: CMAKE_CURRENT_SOURCE_DIR works both as an
# ExternalProject root and as an add_subdirectory child.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../Package.swift" PACKAGE_SWIFT_CONTENTS)
string(REGEX MATCH "let[ \t]+swiftSyntaxVersion[ \t]*:[ \t]*Version[ \t]*=[ \t]*\"([0-9]+\\.[0-9]+\\.[0-9]+)\"" _MATCH "${PACKAGE_SWIFT_CONTENTS}")
set(SWIFT_SYNTAX_VERSION "${CMAKE_MATCH_1}")
if(NOT SWIFT_SYNTAX_VERSION)
  message(FATAL_ERROR "Could not extract swift-syntax version from Package.swift!")
endif()
message(STATUS "swift-syntax version: ${SWIFT_SYNTAX_VERSION}")

include(FetchContent)
# autoresearch harness: consume the vendored swift-syntax tree so the
# benchmark configure/build performs no network access. AUTOMOC is
# inherited ON from the vendored QtBridge root; every swift-syntax module is
# pure Swift, so each target pays a useless autogen step + mocs compile.
# Off for the subtree and stay Debug-line-tables-only — full -g DWARF on
# SwiftSyntax's 18s module edge is dead weight nobody debugs.
set(CMAKE_AUTOMOC OFF)
set(CMAKE_AUTOUIC OFF)
set(CMAKE_AUTORCC OFF)
FetchContent_Declare(SwiftSyntax
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../swiftsyntax-src"
)
FetchContent_MakeAvailable(SwiftSyntax)

foreach(syntax_target
        SwiftSyntax SwiftDiagnostics SwiftBasicFormat SwiftParser
        SwiftParserDiagnostics SwiftOperators SwiftSyntaxBuilder
        SwiftSyntaxMacros SwiftSyntaxMacroExpansion
        SwiftCompilerPluginMessageHandling SwiftCompilerPlugin
        _SwiftSyntaxCShims)
    if(TARGET ${syntax_target})
        get_target_property(_st_type ${syntax_target} TYPE)
        if(NOT _st_type STREQUAL "INTERFACE_LIBRARY")
            target_compile_options(${syntax_target} PRIVATE
                "$<$<COMPILE_LANGUAGE:Swift>:-gline-tables-only>"
            )
        endif()
    endif()
endforeach()

add_executable(QtBridgeMacros
    Extensions.swift
    QtBridgeableMacro.swift
)

target_compile_options(QtBridgeMacros PRIVATE
    -parse-as-library
)

target_link_libraries(QtBridgeMacros PRIVATE
    SwiftSyntax
    SwiftSyntaxMacros
    SwiftCompilerPlugin
)
set_target_properties(QtBridgeMacros PROPERTIES
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

install(TARGETS QtBridgeMacros
    RUNTIME DESTINATION bin
)
