# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

cmake_minimum_required(VERSION 3.29)

project(HelloWorld LANGUAGES CXX Swift)

add_executable(HelloWorld
    Sources/MyApp.swift
    Sources/MyModel.swift
)

if(NOT TARGET QtBridge)
    include(FetchContent)
    FetchContent_Declare(QtBridgeLocal
        SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../.."
    )
    FetchContent_MakeAvailable(QtBridgeLocal)
endif()

target_link_libraries(HelloWorld
    PRIVATE
        QtBridge
)

set(HELLO_WORLD_QML_FILE "${CMAKE_CURRENT_SOURCE_DIR}/Resources/main.qml")

if(APPLE)
    # Create an app bundle
    set_target_properties(HelloWorld PROPERTIES
        MACOSX_BUNDLE TRUE
    )
    # Copy QML to Resources
    target_sources(HelloWorld PRIVATE "${HELLO_WORLD_QML_FILE}")
    set_source_files_properties("${HELLO_WORLD_QML_FILE}" PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources
    )
else()
    add_custom_command(
        TARGET HelloWorld POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
            "${HELLO_WORLD_QML_FILE}"
            "$<TARGET_FILE_DIR:HelloWorld>/main.qml"
        COMMENT "Copying QML file next to executable"
    )
endif()
