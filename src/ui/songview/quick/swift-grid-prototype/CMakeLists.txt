cmake_minimum_required(VERSION 3.29)

project(SwiftGridPrototype LANGUAGES C CXX Swift)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.10 REQUIRED COMPONENTS
    Core
    Gui
    Widgets
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
    foreach(qt_target IN ITEMS Core Gui Widgets Qml Quick Test)
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
    "${SWIFT_GRID_ROOT}/src/core/songdocument.cpp"
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
    Qt6::Widgets
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

# Shared seam closure (cmake/SwiftGridFeeds.cmake): compiles the feed TUs and
# carries their include roots identically for this lane and the production
# app target. Lane-specific TUs (the SongView-coupled observer, the mount)
# stay with porydaw_app, which owns those symbols.
include("${SWIFT_GRID_ROOT}/cmake/SwiftGridFeeds.cmake")
set(SWIFT_GRID_FEED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../swiftgrid")
qt_add_library(swift_grid_document_feed STATIC)
target_link_libraries(swift_grid_document_feed PUBLIC swift_grid_feed_closure)

# Production dialog classes and their dependencies, shared by the interactive
# fixture launcher and native window smoke. Fixtures never commit project data.
add_library(swift_grid_widget_interop STATIC
    "${SWIFT_GRID_AUDIO_DIR}/widget_interop.cpp"
    "${SWIFT_GRID_AUDIO_DIR}/widget_window_fixtures.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/settingsdialog.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/enginesettingsdialog.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/songsettingsdialog.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/sampleeditordialog.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/sf2zonepicker.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/waveformview.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/theme/themeruntime.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/typography.cpp"
    "${SWIFT_GRID_ROOT}/src/audio/sampledoc.cpp"
    "${SWIFT_GRID_ROOT}/src/audio/sampledsp.cpp"
    "${SWIFT_GRID_ROOT}/src/audio/samplewav.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/newsongwizard.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/layout.cpp"
    "${SWIFT_GRID_ROOT}/src/core/midiimport.cpp"
    "${SWIFT_GRID_ROOT}/src/core/m4asemantics.cpp"
    "${SWIFT_GRID_ROOT}/src/core/xcmd.cpp"
    "${SWIFT_GRID_ROOT}/src/project/songregistry.cpp"
    "${SWIFT_GRID_ROOT}/src/project/voicegroupsource.cpp"
)
target_include_directories(swift_grid_widget_interop PUBLIC
    "${SWIFT_GRID_AUDIO_DIR}"
    "${SWIFT_GRID_ROOT}/src"
)
target_link_libraries(swift_grid_widget_interop PUBLIC
    Qt6::Core
    Qt6::Widgets
    Qt6::Quick
    swift_grid_audio
)
# The wizard's project-scanning compatibility constructors (the DecompProject
# overloads) are never called by this lane, but they are the only reference to
# the project layer, so a plain link of this closure cannot resolve. One function
# per section plus the toolchain's dead-code elimination drop those unreferenced
# entry points: no stub, no production edit.
#
# Why this cannot mask a missing symbol on the live path: dead-code elimination
# keeps everything reachable from the entry points and the exported symbols. The
# path this lane runs - NewSongWizard(ProjectData) -> buildPages -> IdentityPage
# -> SoundPage, layout::initialize, SongRegistry, the import analysis - is
# reachable, so every symbol it needs stays live and still has to resolve. Only
# the unreferenced DecompProject constructors (and project scans reached solely
# from unreferenced functions) fall away. The widget smoke proves the live path
# end to end: the wizard is populated from the detached in-memory catalog, reads
# and writes no project root, and accepts a real typed label.
if(APPLE)
    target_compile_options(swift_grid_widget_interop PRIVATE
        -ffunction-sections
        -fdata-sections
    )
    target_link_options(swift_grid_widget_interop INTERFACE
        LINKER:-dead_strip
    )
elseif(MSVC)
    target_compile_options(swift_grid_widget_interop PRIVATE
        /Gy
        /Gw
    )
    target_link_options(swift_grid_widget_interop INTERFACE
        "/OPT:REF"
    )
else()
    target_compile_options(swift_grid_widget_interop PRIVATE
        -ffunction-sections
        -fdata-sections
    )
    target_link_options(swift_grid_widget_interop INTERFACE
        LINKER:--gc-sections
    )
endif()
if(APPLE)
    set_target_properties(swift_grid_widget_interop PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)
endif()

# Verification-only native smoke driver (event injection; no UI/model logic).
# Kept as a separate static target so Qt6::Test's QT_TESTCASE_* compile
# definitions stay on C++ and never reach the Swift compilation.
set(SWIFT_GRID_SMOKE_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../../checks/swiftgridprototype"
)

add_library(swift_grid_smoke STATIC
    "${SWIFT_GRID_SMOKE_DIR}/grid_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/document_feed_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/songtabs_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/audio_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/interaction_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/math_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/jurisdiction_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/policy_smoke.cpp"
    "${SWIFT_GRID_ROOT}/src/ui/songview/editcommandtable.cpp"
    "${SWIFT_GRID_AUDIO_DIR}/widget_interop_smoke.cpp"
    "${SWIFT_GRID_SMOKE_DIR}/new_song_wizard_smoke.cpp"
)
target_include_directories(swift_grid_smoke PRIVATE
    "${SWIFT_GRID_SMOKE_DIR}"
)
target_link_libraries(swift_grid_smoke PRIVATE
    Qt6::Quick
    Qt6::Test
    swift_grid_audio
    swift_grid_curve
    swift_grid_widget_interop
)
if(APPLE)
    enable_language(OBJCXX)
    target_sources(swift_grid_smoke PRIVATE
        "${SWIFT_GRID_SMOKE_DIR}/widget_panel_smoke_macos.mm")
    target_link_libraries(swift_grid_smoke PRIVATE "-framework AppKit")
    set_target_properties(swift_grid_smoke PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON)
endif()

file(GLOB SWIFT_GRID_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.swift"
)
file(GLOB SWIFT_GRID_QML_FILES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# Reusable wizard implementation; only the catalog and result observer live in
# this standalone lane. A production host can mount these same sources.
list(APPEND SWIFT_GRID_SOURCES
    "${SWIFT_GRID_ROOT}/src/ui/newsong/NewSongDraft.swift"
    "${SWIFT_GRID_ROOT}/src/ui/newsong/NewSongWizardController.swift"
)
list(APPEND SWIFT_GRID_QML_FILES
    "${SWIFT_GRID_ROOT}/src/ui/newsong/NewSongWizard.qml"
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
    swift_grid_widget_interop
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
target_sources(swift_grid_prototype PRIVATE "${SWIFT_GRID_FONT_QRC}" "tabart.qrc")
if(APPLE)
    qt_add_resources(swift_grid_prototype "swift_grid_qml"
        PREFIX "/swiftgrid"
        BASE "${CMAKE_CURRENT_SOURCE_DIR}"
        FILES
            "${CMAKE_CURRENT_SOURCE_DIR}/SwiftRollOverlay.qml"
            "${CMAKE_CURRENT_SOURCE_DIR}/PianoRollCanvas.qml"
            "${CMAKE_CURRENT_SOURCE_DIR}/TimelineQuickItem.qml"
    )
endif()

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
elseif(WIN32)
    file(COPY ${SWIFT_GRID_QML_FILES}
        DESTINATION "${CMAKE_CURRENT_BINARY_DIR}"
    )
    file(COPY "${SWIFT_GRID_ROOT}/src/checks/fixtures/decompproject/sound"
        DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/AudioFixture"
    )
endif()
