# Copyright (C) 2026 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

cmake_minimum_required(VERSION 3.29)

project(ColorPalette LANGUAGES CXX Swift)

add_executable(ColorPalette
    Sources/AbstractResource.swift
    Sources/BasicLogin.swift
    Sources/ColorPaletteApp.swift
    Sources/Extensions.swift
    Sources/PaginatedResourceColors.swift
    Sources/PaginatedResourceUsers.swift
    Sources/RestService.swift
    Sources/ServiceApi.swift
)

if(NOT TARGET QtBridge)
    include(FetchContent)
    FetchContent_Declare(QtBridgeLocal
        SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../.."
    )
    FetchContent_MakeAvailable(QtBridgeLocal)
endif()

target_link_libraries(ColorPalette
    PRIVATE
        QtBridge
)

set(QML_FILES
    "Resources/qml/ColorPalette/ColorDialogDelete.qml"
    "Resources/qml/ColorPalette/ColorDialogEditor.qml"
    "Resources/qml/ColorPalette/ColorView.qml"
    "Resources/qml/ColorPalette/Main.qml"
    "Resources/qml/ColorPalette/qmldir"
    "Resources/qml/ColorPalette/ServerSelection.qml"
    "Resources/qml/ColorPalette/UserMenu.qml"
    "Resources/qml/QtExampleStyle/Button.qml"
    "Resources/qml/QtExampleStyle/Label.qml"
    "Resources/qml/QtExampleStyle/Popup.qml"
    "Resources/qml/QtExampleStyle/qmldir"
    "Resources/qml/QtExampleStyle/TextField.qml"
    "Resources/qml/QtExampleStyle/ToolBar.qml"
    "Resources/qml/QtExampleStyle/ToolButton.qml"
    "Resources/qml/QtExampleStyle/UIStyle.qml")

set(RESOURCE_FILES
    ${QML_FILES}
    "Resources/qml/icons/close_dark.svg"
    "Resources/qml/icons/close.svg"
    "Resources/qml/icons/delete_dark.svg"
    "Resources/qml/icons/delete.svg"
    "Resources/qml/icons/dots_dark.svg"
    "Resources/qml/icons/dots.svg"
    "Resources/qml/icons/edit_dark.svg"
    "Resources/qml/icons/edit.svg"
    "Resources/qml/icons/login_dark.svg"
    "Resources/qml/icons/login.svg"
    "Resources/qml/icons/logout_dark.svg"
    "Resources/qml/icons/logout.svg"
    "Resources/qml/icons/ok_dark.svg"
    "Resources/qml/icons/ok.svg"
    "Resources/qml/icons/plus_dark.svg"
    "Resources/qml/icons/plus.svg"
    "Resources/qml/icons/qt_attribution.json"
    "Resources/qml/icons/qt.png"
    "Resources/qml/icons/REUSE.toml"
    "Resources/qml/icons/testserver.png"
    "Resources/qml/icons/update_dark.svg"
    "Resources/qml/icons/update.svg"
    "Resources/qml/icons/user_dark.svg"
    "Resources/qml/icons/user.svg"
    "Resources/qml/icons/userMask.svg"
)

if(APPLE)
    # Create an app bundle
    set_target_properties(ColorPalette PROPERTIES
        MACOSX_BUNDLE TRUE
    )
    foreach(file IN LISTS RESOURCE_FILES)
        file(RELATIVE_PATH rel "${CMAKE_CURRENT_SOURCE_DIR}/Resources/qml" "${CMAKE_CURRENT_SOURCE_DIR}/${file}")
        get_filename_component(dir "${rel}" DIRECTORY)
        set_source_files_properties("${file}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources/${dir}"
        )
    endforeach()
    target_sources(ColorPalette PRIVATE "${QML_FILES}")
else()
    add_custom_command(
        TARGET ColorPalette POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/Resources/qml/ColorPalette"
        "$<TARGET_FILE_DIR:ColorPalette>/ColorPalette"
        COMMENT "Copying ColorPalette resources next to executable"
    )
    add_custom_command(
        TARGET ColorPalette POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/Resources/qml/QtExampleStyle"
        "$<TARGET_FILE_DIR:ColorPalette>/QtExampleStyle"
        COMMENT "Copying QtExampleStyle resources next to executable"
    )
    target_sources(ColorPalette PRIVATE "${QML_FILES}")
endif()

