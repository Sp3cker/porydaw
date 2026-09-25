# Copyright (C) 2025 The Qt Company Ltd.
# SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only

function(qtbridge_detect_swift_bridging_headers)
    # This is needed due to swift/bridging not being included in the path by default on non-Xcode toolchains
    # Issue can be tracked: https://github.com/swiftlang/swift-package-manager/issues/9010
    # Query Swift compiler for runtime resource path
    execute_process(
        COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
        OUTPUT_VARIABLE SWIFT_TARGET_INFO
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
        RESULT_VARIABLE SWIFT_TARGET_INFO_RESULT
    )

    if(SWIFT_TARGET_INFO_RESULT EQUAL 0)
        # Parse runtimeResourcePath from JSON output
        string(JSON SWIFT_RUNTIME_RESOURCE_PATH ERROR_VARIABLE JSON_ERROR
                GET "${SWIFT_TARGET_INFO}" "paths" "runtimeResourcePath")

        if(NOT JSON_ERROR AND SWIFT_RUNTIME_RESOURCE_PATH)
            # runtimeResourcePath is typically <prefix>/lib/swift
            # bridging headers are at <prefix>/include/swift/bridging
            cmake_path(GET SWIFT_RUNTIME_RESOURCE_PATH PARENT_PATH SWIFT_LIB_DIR)
            cmake_path(GET SWIFT_LIB_DIR PARENT_PATH SWIFT_PREFIX_DIR)
            set(SWIFT_INCLUDE_CANDIDATE "${SWIFT_PREFIX_DIR}/include")

            if(EXISTS "${SWIFT_INCLUDE_CANDIDATE}/swift/bridging")
                set(QTBRIDGE_SWIFT_BRIDGING_INCLUDE "${SWIFT_INCLUDE_CANDIDATE}" CACHE PATH "Swift bridging header include path")
                message(STATUS "Using Swift bridging include: ${QTBRIDGE_SWIFT_BRIDGING_INCLUDE}")
            else()
                message(WARNING "Swift bridging headers not found at ${SWIFT_INCLUDE_CANDIDATE}. Set QTBRIDGE_SWIFT_BRIDGING_INCLUDE manually if needed.")
            endif()
        else()
            message(WARNING "Could not parse Swift target info. Set QTBRIDGE_SWIFT_BRIDGING_INCLUDE manually if needed.")
        endif()
    else()
        message(WARNING "Could not query Swift compiler. Set QTBRIDGE_SWIFT_BRIDGING_INCLUDE manually if needed.")
    endif()
endfunction()
