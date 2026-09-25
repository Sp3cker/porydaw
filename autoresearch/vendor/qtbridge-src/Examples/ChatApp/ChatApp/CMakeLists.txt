# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

cmake_minimum_required(VERSION 3.29)

project(ChatApp LANGUAGES CXX Swift)

add_executable(ChatApp
    Sources/ChatApp.swift
    Sources/ChatModel.swift
)

if(NOT TARGET QtBridge)
    include(FetchContent)
    FetchContent_Declare(QtBridgeLocal
        SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../.."
    )
    FetchContent_MakeAvailable(QtBridgeLocal)
endif()

target_link_libraries(ChatApp
    PRIVATE
        QtBridge
)

set(CHAT_APP_QML_FILE "${CMAKE_CURRENT_SOURCE_DIR}/Resources/chatUI.qml")

if(APPLE)
    # Create an app bundle
    set_target_properties(ChatApp PROPERTIES
        MACOSX_BUNDLE TRUE
    )
    # Copy QML to Resources
    target_sources(ChatApp PRIVATE "${CHAT_APP_QML_FILE}")
    set_source_files_properties("${CHAT_APP_QML_FILE}" PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources
    )
else()
    add_custom_command(
        TARGET ChatApp POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CHAT_APP_QML_FILE}"
            "$<TARGET_FILE_DIR:ChatApp>/chatUI.qml"
        COMMENT "Copying QML file next to executable"
    )
endif()
