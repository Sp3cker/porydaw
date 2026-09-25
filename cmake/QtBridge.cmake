include_guard(GLOBAL)

# Declare QtBridge's private Qt dependency in the host directory scope too,
# where Qt finalizes the application and check executables.
# QtBridge already opts out of this warning in its subdirectory; this
# host-scope lookup needs the same acknowledgement of its private Qt dependency.
set(QT_NO_PRIVATE_MODULE_WARNING ON)
find_package(Qt6 6.10 REQUIRED COMPONENTS CorePrivate)

include(FetchContent)
set(QTBRIDGE_PATCH_DIR
    "${CMAKE_CURRENT_LIST_DIR}/patches/qtbridge")
# Reconfigure when either input changes, then invalidate FetchContent's patch
# stamp through its recorded command: paths alone leave that stamp unchanged.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${QTBRIDGE_PATCH_DIR}/qtbridge-object-return.patch"
    "${QTBRIDGE_PATCH_DIR}/PatchQtBridge.cmake"
)
file(SHA256 "${QTBRIDGE_PATCH_DIR}/qtbridge-object-return.patch" QTBRIDGE_PATCH_SHA256)
file(SHA256 "${QTBRIDGE_PATCH_DIR}/PatchQtBridge.cmake" QTBRIDGE_PATCH_SCRIPT_SHA256)
FetchContent_Declare(QtBridge
    GIT_REPOSITORY https://github.com/qt/qtbridge-swift.git
    GIT_TAG 407714006dd21107b70db6547ce75e43df0c8a75
    PATCH_COMMAND "${CMAKE_COMMAND}"
        "-DPATCH=${QTBRIDGE_PATCH_DIR}/qtbridge-object-return.patch"
        "-DPATCH_INPUTS_SHA256=${QTBRIDGE_PATCH_SHA256}:${QTBRIDGE_PATCH_SCRIPT_SHA256}"
        -P "${QTBRIDGE_PATCH_DIR}/PatchQtBridge.cmake"
)
FetchContent_MakeAvailable(QtBridge)

if(APPLE)
    # Framework include precedence is per-target, not inherited from consumers.
    set_target_properties(QtBridgeCpp QtBridge PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)

    # Native C++ hosts keep their own linker/LTO driver. Darwin Swift objects
    # carry autolink libraries; publish their compiler's runtime search paths.
    set(qtbridge_sdk "${CMAKE_OSX_SYSROOT}")
    if(NOT qtbridge_sdk)
        set(qtbridge_sdk "${CMAKE_CXX_COMPILER_APPLE_SYSROOT}")
    endif()
    execute_process(
        COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info -sdk "${qtbridge_sdk}"
        OUTPUT_VARIABLE qtbridge_target_info
        COMMAND_ERROR_IS_FATAL ANY
    )
    string(JSON qtbridge_runtime_path_count LENGTH
        "${qtbridge_target_info}" paths runtimeLibraryImportPaths)
    if(qtbridge_runtime_path_count LESS 1)
        message(FATAL_ERROR
            "Swift compiler '${CMAKE_Swift_COMPILER}' reported no runtimeLibraryImportPaths "
            "for SDK '${qtbridge_sdk}'. Verify the selected Swift toolchain and macOS SDK; "
            "native hosts require Swift runtime import paths to link.")
    endif()
    math(EXPR qtbridge_runtime_path_last "${qtbridge_runtime_path_count} - 1")
    foreach(runtime_path_index RANGE ${qtbridge_runtime_path_last})
        string(JSON qtbridge_runtime_path GET
            "${qtbridge_target_info}" paths runtimeLibraryImportPaths ${runtime_path_index})
        target_link_directories(QtBridge INTERFACE "${qtbridge_runtime_path}")
    endforeach()
endif()

function(porydaw_link_linux_swift_runtime target)
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
        return()
    endif()
    execute_process(
        COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
        OUTPUT_VARIABLE swift_target_info
        COMMAND_ERROR_IS_FATAL ANY
    )
    string(JSON runtime_path_count LENGTH "${swift_target_info}" paths runtimeLibraryPaths)
    math(EXPR runtime_path_last "${runtime_path_count} - 1")
    foreach(index RANGE ${runtime_path_last})
        string(JSON runtime_path GET "${swift_target_info}" paths runtimeLibraryPaths ${index})
        target_link_directories(${target} PRIVATE "${runtime_path}")
        set_property(TARGET ${target} APPEND PROPERTY BUILD_RPATH "${runtime_path}")
    endforeach()
    string(JSON resource_path GET "${swift_target_info}" paths runtimeResourcePath)
    string(JSON swift_arch GET "${swift_target_info}" target arch)
    target_sources(${target} PRIVATE "${resource_path}/linux/${swift_arch}/swiftrt.o")
    get_filename_component(swift_bin "${CMAKE_Swift_COMPILER}" DIRECTORY)
    find_program(swift_autolink_extract swift-autolink-extract HINTS "${swift_bin}" REQUIRED)
    set(archives "")
    foreach(library IN LISTS ARGN)
        list(APPEND archives "$<TARGET_FILE:${library}>")
        target_link_directories(${target} PRIVATE "$<TARGET_FILE_DIR:${library}>")
    endforeach()
    set(autolink_file "${CMAKE_CURRENT_BINARY_DIR}/${target}-swift-autolink.rsp")
    add_custom_command(
        OUTPUT "${autolink_file}"
        COMMAND "${swift_autolink_extract}" ${archives} -o "${autolink_file}"
        DEPENDS ${ARGN}
        VERBATIM
    )
    add_custom_target(${target}_swift_autolink DEPENDS "${autolink_file}")
    add_dependencies(${target} ${target}_swift_autolink)
    set_property(TARGET ${target} APPEND PROPERTY LINK_DEPENDS "${autolink_file}")
    target_link_libraries(${target} PRIVATE "-Wl,@${autolink_file}")
endfunction()
