cmake_minimum_required(VERSION 3.29)

project(SwiftGridPrototype LANGUAGES C CXX Swift)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.10 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    Test
)

qt_standard_project_setup()

include("${CMAKE_CURRENT_SOURCE_DIR}/../../../../../cmake/QtBridge.cmake")

if(APPLE)
    # Same framework-header precedence fix as the root build: keep Qt's exact
    # framework-header paths ahead of unrelated non-framework Qt installs such
    # as /usr/local/include/Qt*. Treating imported frameworks as system
    # headers lets Clang select the unrelated include tree first.
    foreach(qt_target IN ITEMS Core Gui Qml Quick Test)
        get_target_property(qt_include_dirs Qt6::${qt_target}
            INTERFACE_INCLUDE_DIRECTORIES)
        if(qt_include_dirs)
            set_property(TARGET Qt6::${qt_target} APPEND PROPERTY
                INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${qt_include_dirs}")
        endif()
    endforeach()
endif()


# The poryaaaa submodule is not checked out in worktrees; the build tool
# passes -DPORYAAAA_DIR from the main checkout (same pattern as Qt).
if(NOT PORYAAAA_DIR)
    set(PORYAAAA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../external/poryaaaa/packages/poryaaaa")
endif()
if(NOT EXISTS "${PORYAAAA_DIR}/plugin/porydaw/CMakeLists.txt")
    message(FATAL_ERROR "PORYAAAA_DIR must point to the poryaaaa package source tree")
endif()
add_subdirectory("${PORYAAAA_DIR}/plugin/porydaw" poryaaaa-engine)
set(SWIFT_GRID_AUDIO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/native")
# Project root (src/, external/, resources/) — five levels above this dir.
set(SWIFT_GRID_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../..")
add_library(swift_grid_audio STATIC
    "${SWIFT_GRID_AUDIO_DIR}/audio_session.cpp"
    "${SWIFT_GRID_AUDIO_DIR}/audio_session_internal.h"
    "${SWIFT_GRID_ROOT}/src/audio/audioengine.cpp"
    "${SWIFT_GRID_ROOT}/src/audio/auditionslots.cpp"
    "${SWIFT_GRID_ROOT}/src/audio/resonance_suppressor.cpp"
    "${SWIFT_GRID_ROOT}/src/audio/miniaudio_impl.c"
    "${SWIFT_GRID_ROOT}/src/core/miditimeline.cpp"
    "${SWIFT_GRID_ROOT}/src/core/timelineplayer.cpp"
    "${SWIFT_GRID_ROOT}/src/core/smf.cpp"
    "${SWIFT_GRID_ROOT}/src/core/mid2agbtables.cpp"
)
set_source_files_properties("${SWIFT_GRID_AUDIO_DIR}/audio_session_internal.h" PROPERTIES
    HEADER_FILE_ONLY ON
)
target_include_directories(swift_grid_audio PUBLIC
    "${SWIFT_GRID_AUDIO_DIR}"
    "${SWIFT_GRID_ROOT}/src"
)
target_include_directories(swift_grid_audio SYSTEM PUBLIC
    "${PORYAAAA_DIR}/third_party"
    "${PORYAAAA_DIR}/plugin/porydaw/.."
    "${PORYAAAA_DIR}/plugin/m4a"
    "${PORYAAAA_DIR}/plugin/m4a/.."
    "${PORYAAAA_DIR}/plugin/hw_audio"
    "${PORYAAAA_DIR}/plugin/hw_audio/.."
)
target_link_libraries(swift_grid_audio PUBLIC
    Qt6::Core
    poryaaaa_engine
)

add_library(swift_grid_curve STATIC
    "${SWIFT_GRID_AUDIO_DIR}/curve_session.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/pitchbendkernel.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/pitchprojection.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/songview/grid.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/songview/timeaxis.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/songview/timecamera.cpp"
)
target_include_directories(swift_grid_curve PUBLIC
    "${SWIFT_GRID_AUDIO_DIR}"
    "${SWIFT_GRID_ROOT}/src"
)
target_link_libraries(swift_grid_curve PUBLIC Qt6::Core)

add_library(swift_grid_typography STATIC "${SWIFT_GRID_AUDIO_DIR}/font_metrics.cpp")
target_include_directories(swift_grid_typography PUBLIC "${SWIFT_GRID_AUDIO_DIR}")
target_link_libraries(swift_grid_typography PUBLIC Qt6::Gui)
add_library(swift_grid_window_cancel STATIC "${SWIFT_GRID_AUDIO_DIR}/window_cancel.cpp")
target_include_directories(swift_grid_window_cancel PUBLIC "${SWIFT_GRID_AUDIO_DIR}")
target_link_libraries(swift_grid_window_cancel PUBLIC Qt6::Quick)

set(SWIFT_GRID_FEED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../swiftgrid")
qt_add_library(swift_grid_document_feed STATIC
    "${SWIFT_GRID_FEED_DIR}/document_feed.cpp"
    "${SWIFT_GRID_FEED_DIR}/document_feed.h"
)
target_include_directories(swift_grid_document_feed PUBLIC "${SWIFT_GRID_FEED_DIR}")

# Verification-only native smoke driver (event injection; no UI/model logic).
# Kept as a separate static target so Qt6::Test's QT_TESTCASE_* compile
# definitions stay on C++ and never reach the Swift compilation.
set(SWIFT_GRID_SMOKE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../checks/swiftgridprototype"
)

add_library(swift_grid_smoke STATIC
    "${SWIFT_GRID_SMOKE_DIR}/grid_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/audio_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/interaction_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/math_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/jurisdiction_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/policy_smoke.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/songview/editcommandtable.cpp"
)
target_include_directories(swift_grid_smoke PRIVATE
    "${SWIFT_GRID_SMOKE_DIR}"
)
target_link_libraries(swift_grid_smoke PRIVATE
    Qt6::Quick
    Qt6::Test
    swift_grid_audio
    swift_grid_curve
)
if(APPLE)
    set_target_properties(swift_grid_smoke PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)
endif()

file(GLOB SWIFT_GRID_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.swift"
)
file(GLOB SWIFT_GRID_QML_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

qt_add_executable(swift_grid_prototype
    ${SWIFT_GRID_SOURCES}
)
set_target_properties(swift_grid_prototype PROPERTIES
    Swift_MODULE_NAME SwiftGrid
    Swift_LANGUAGE_VERSION 6
)

if(APPLE)
    set_target_properties(swift_grid_prototype PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)
endif()

target_compile_options(swift_grid_prototype PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_SMOKE_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_AUDIO_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_FEED_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_AUDIO_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_FEED_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_ROOT}/src>"
)

target_link_libraries(swift_grid_prototype PRIVATE
    QtBridge
    Qt6::Quick
    swift_grid_audio
    swift_grid_curve
    swift_grid_typography
    swift_grid_window_cancel
    swift_grid_document_feed
    "$<LINK_ONLY:swift_grid_smoke>"
)

set(SWIFT_GRID_FONT_QRC
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../resources/fonts.qrc"
)

set_target_properties(swift_grid_prototype PROPERTIES AUTORCC ON)
target_sources(swift_grid_prototype PRIVATE "${SWIFT_GRID_FONT_QRC}")

if(APPLE)
    set_target_properties(swift_grid_prototype PROPERTIES
        MACOSX_BUNDLE TRUE
    )
    target_sources(swift_grid_prototype PRIVATE ${SWIFT_GRID_QML_FILES})
    set_source_files_properties(${SWIFT_GRID_QML_FILES} PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources
    )
    file(GLOB_RECURSE SWIFT_GRID_FIXTURE_FILES RELATIVE
        "${SWIFT_GRID_ROOT}/src/checks/fixtures/decompproject"
        "${SWIFT_GRID_ROOT}/src/checks/fixtures/decompproject/sound/*"
    )
    foreach(fixture_file IN LISTS SWIFT_GRID_FIXTURE_FILES)
        set(SWIFT_GRID_FIXTURE_SRC
            "${SWIFT_GRID_ROOT}/src/checks/fixtures/decompproject/${fixture_file}")
        get_filename_component(SWIFT_GRID_FIXTURE_DIR "${fixture_file}" DIRECTORY)
        set_source_files_properties("${SWIFT_GRID_FIXTURE_SRC}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources/AudioFixture/${SWIFT_GRID_FIXTURE_DIR}"
        )
        target_sources(swift_grid_prototype PRIVATE "${SWIFT_GRID_FIXTURE_SRC}")
    endforeach()
endif()
