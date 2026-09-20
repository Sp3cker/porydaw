# ---- In-tree m4a converter retained by the native-boundary sweep ----
get_filename_component(PORYAAAA_PACKAGES_DIR "${PORYAAAA_DIR}" DIRECTORY)
set(MID2AGB_SOURCE_DIR "${PORYAAAA_PACKAGES_DIR}/ccomidi/mid2agb")
if(NOT EXISTS "${MID2AGB_SOURCE_DIR}/main.cpp")
    message(FATAL_ERROR "PORYAAAA_DIR must belong to the poryaaaa monorepo")
endif()
set(MID2AGB_LEGACY_INCLUDE_ROOT "${CMAKE_CURRENT_BINARY_DIR}/mid2agb-include")
file(MAKE_DIRECTORY "${MID2AGB_LEGACY_INCLUDE_ROOT}/a/b"
                    "${MID2AGB_LEGACY_INCLUDE_ROOT}/include/config")
file(WRITE "${MID2AGB_LEGACY_INCLUDE_ROOT}/include/config/battle.h"
     "#pragma once\n#define B_NUM_LOW_HEALTH_BEEPS 4\n")
file(WRITE "${MID2AGB_LEGACY_INCLUDE_ROOT}/include/config/general.h" "#pragma once\n")
add_executable(mid2agb
    "${MID2AGB_SOURCE_DIR}/main.cpp"
    "${MID2AGB_SOURCE_DIR}/error.cpp"
    "${MID2AGB_SOURCE_DIR}/midi.cpp"
    "${MID2AGB_SOURCE_DIR}/agb.cpp"
    "${MID2AGB_SOURCE_DIR}/tables.cpp"
)
target_include_directories(mid2agb PRIVATE
    "${MID2AGB_SOURCE_DIR}"
    "${MID2AGB_LEGACY_INCLUDE_ROOT}/a/b")
set_target_properties(mid2agb PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")

# ---- Rewrite check executable ----
find_package(Qt6 REQUIRED COMPONENTS Test)
if(APPLE)
    porydaw_mark_interface_includes_system(Qt6::Test)
endif()

qt_add_executable(porydaw_checks
    checks_main.cpp
    checkregistry.cpp
    checkregistry.hpp
    checkcatalog.cpp
    checkcatalog.h
    fixturecatalog.cpp
    fixturecatalog.hpp
    fwd.hpp
    retained/tst_nativeboundaries.cpp
    retained/tst_nativeboundaries.h
    ${PROJECT_SOURCE_DIR}/resources/fonts.qrc
)
set_target_properties(porydaw_checks PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
target_include_directories(porydaw_checks PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
porydaw_enable_project_warnings(porydaw_checks)

if(APPLE)
    add_library(swift_core_check STATIC
        swiftcore/CoreCheckSupport.swift
        swiftcore/MidiChecks.swift
        swiftcore/PlaybackChecks.swift
        swiftcore/NoteChecks.swift
        swiftcore/EventChecks.swift
        swiftcore/TimeChecks.swift
        swiftcore/SessionChecks.swift
    )
    set_target_properties(swift_core_check PROPERTIES
        Swift_MODULE_NAME SwiftCoreCheck
        Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/swift_core_check"
        Swift_LANGUAGE_VERSION 6
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    target_compile_options(swift_core_check PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
    )
    target_link_libraries(swift_core_check PRIVATE PorydawCore PorydawPlayback PorydawApp)
    target_link_libraries(porydaw_checks PRIVATE swift_core_check)
    target_sources(porydaw_checks PRIVATE
        support/corecheck/tst_swiftcore.cpp
        support/corecheck/tst_swiftcore.h
        support/corecheck/core_check.h
        support/corecheck/native_check.cpp
        support/corecheck/native_check.h
    )
    set_target_properties(porydaw_checks PROPERTIES
        LINKER_LANGUAGE CXX
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_GUI_IDENTIFIER com.sp3cker.porydaw.checks
        NO_SYSTEM_FROM_IMPORTED ON
    )
    add_custom_command(TARGET porydaw_checks POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E rm -f "${PROJECT_BINARY_DIR}/porydaw_checks"
        COMMAND ${CMAKE_COMMAND} -E create_symlink
                "$<TARGET_FILE:porydaw_checks>" "${PROJECT_BINARY_DIR}/porydaw_checks"
        VERBATIM
    )
endif()

target_link_libraries(porydaw_checks PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
    Qt6::Test
)
target_precompile_headers(porydaw_checks PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${PROJECT_SOURCE_DIR}/src/porydaw_pch.hpp>")
target_compile_definitions(porydaw_checks PRIVATE
    PORYDAW_CHECK_SOURCE_DIR="${PROJECT_SOURCE_DIR}")
add_dependencies(porydaw_checks mid2agb)
