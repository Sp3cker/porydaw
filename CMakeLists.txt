cmake_minimum_required(VERSION 3.24)
project(porydaw VERSION 1.0.3 LANGUAGES C CXX)

find_package(Git QUIET)
if(Git_FOUND)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${CMAKE_CURRENT_SOURCE_DIR}"
                rev-parse --is-inside-work-tree
        OUTPUT_VARIABLE PORYDAW_IS_GIT_WORKTREE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(PORYDAW_IS_GIT_WORKTREE STREQUAL "true")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${CMAKE_CURRENT_SOURCE_DIR}"
                    config --local core.hooksPath .githooks
            RESULT_VARIABLE PORYDAW_HOOK_CONFIG_RESULT
            ERROR_VARIABLE PORYDAW_HOOK_CONFIG_ERROR
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_STRIP_TRAILING_WHITESPACE
        )
        if(PORYDAW_HOOK_CONFIG_RESULT)
            message(WARNING "Could not configure repository Git hooks: ${PORYDAW_HOOK_CONFIG_ERROR}")
        else()
            message(STATUS "Configured repository Git hooks from .githooks")
        endif()
    endif()
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(APPLE)
    enable_language(OBJCXX)
    set(CMAKE_OBJCXX_STANDARD 20)
    set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
endif()
set(CMAKE_AUTORCC ON)

# Strict diagnostics apply only to project C++ translation units. Vendored C
# implementation units are excluded, and third-party headers are SYSTEM
# includes. -Wold-style-cast stays off because the codebase idiomatically uses
# C-style casts.
function(porydaw_enable_project_warnings target)
    target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wformat=2>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wformat=2>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wnull-dereference>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wnull-dereference>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wdouble-promotion>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wdouble-promotion>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wcast-align>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wcast-align>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wcast-qual>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wcast-qual>
        $<$<COMPILE_LANG_AND_ID:CXX,Clang,AppleClang>:-Wextra-semi;-Wrange-loop-analysis>
        $<$<COMPILE_LANG_AND_ID:OBJCXX,Clang,AppleClang>:-Wextra-semi;-Wrange-loop-analysis>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU>:-Wduplicated-cond;-Wduplicated-branches;-Wlogical-op>
    )
endfunction()

# Optimize the audio path even in debug builds: the miniaudio converter and
# engine callbacks dominate audio-thread cost, and profile/listening sessions
# with a debug app must not measure inflated audio DSP. -g stays on.
set(PORYDAW_AUDIO_ALWAYS_OPTIMIZE_SRCS
    src/audio/miniaudio_impl.c
    src/audio/stb_vorbis_impl.c
    src/audio/audioengine.cpp)
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    foreach(PORYDAW_AUDIO_SRC IN LISTS PORYDAW_AUDIO_ALWAYS_OPTIMIZE_SRCS)
        set_source_files_properties(
            "${PORYDAW_AUDIO_SRC}"
            PROPERTIES COMPILE_OPTIONS "-O2"
                       SKIP_PRECOMPILE_HEADERS ON)
    endforeach()
endif()

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Optimize through the static porydaw/poryaaaa library boundaries in Release builds.
include(CheckIPOSupported)
check_ipo_supported(RESULT PORYDAW_IPO_SUPPORTED OUTPUT PORYDAW_IPO_ERROR)
if(PORYDAW_IPO_SUPPORTED)
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION_RELEASE ON)
else()
    message(WARNING "Release IPO/LTO disabled: ${PORYDAW_IPO_ERROR}")
endif()

# AddressSanitizer build for the harness sweep (deno task checks): memory
# bugs abort with a stack trace instead of corrupting silently. GCC/Clang
# only. Use a separate build dir, e.g.:
#   cmake -B build-asan -DPORYDAW_ASAN=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo
option(PORYDAW_ASAN "Build with AddressSanitizer" OFF)
option(PORYDAW_COVERAGE "Build with Clang source-based code coverage" OFF)
option(PORYDAW_BUILD_CHECKS "Build the porydaw check executable" ON)
if(PORYDAW_ASAN AND PORYDAW_COVERAGE)
    message(FATAL_ERROR "PORYDAW_ASAN and PORYDAW_COVERAGE are mutually exclusive")
endif()
if(PORYDAW_ASAN)
    add_compile_options(-fsanitize=address -fno-omit-frame-pointer)
    add_link_options(-fsanitize=address)
endif()
if(PORYDAW_COVERAGE)
    if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang|AppleClang")
        message(WARNING "PORYDAW_COVERAGE is only supported with Clang/AppleClang")
    endif()
    add_compile_options(-fprofile-instr-generate -fcoverage-mapping)
    add_link_options(-fprofile-instr-generate)
endif()

find_package(Qt6 6.11 REQUIRED COMPONENTS Qml Quick QuickControls2 Svg Widgets)
qt_standard_project_setup()

function(porydaw_mark_interface_includes_system dependency)
    get_target_property(dependency_include_dirs ${dependency} INTERFACE_INCLUDE_DIRECTORIES)
    if(dependency_include_dirs)
        set_property(TARGET ${dependency} APPEND PROPERTY
            INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${dependency_include_dirs}")
    endif()
endfunction()

if(APPLE)
    # NO_SYSTEM_FROM_IMPORTED keeps Qt's exact framework-header paths ahead of
    # unrelated non-framework Qt installs. Also classify those same paths as
    # system headers so project warning flags do not diagnose Qt internals.
    foreach(qt_target IN ITEMS Core Gui Qml Quick QuickControls2 Svg Widgets)
        porydaw_mark_interface_includes_system(Qt6::${qt_target})
    endforeach()
endif()

# ---- poryaaaa engine core (MIT, statically linked) ----
set(PORYAAAA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external/poryaaaa/packages/poryaaaa"
    CACHE PATH "Path to the poryaaaa package source tree")
if(NOT EXISTS "${PORYAAAA_DIR}/plugin/porydaw/CMakeLists.txt"
   AND EXISTS "${PORYAAAA_DIR}/packages/poryaaaa/plugin/porydaw/CMakeLists.txt")
    set(PORYAAAA_DIR "${PORYAAAA_DIR}/packages/poryaaaa"
        CACHE PATH "Path to the poryaaaa package source tree" FORCE)
endif()
if(NOT EXISTS "${PORYAAAA_DIR}/plugin/porydaw/CMakeLists.txt")
    message(FATAL_ERROR "PORYAAAA_DIR must point to the poryaaaa package source tree")
endif()
# Keep the engine at Release optimization even when the host is built for debugging.
# Function scope keeps the host's configuration flags and IPO policy unchanged.
function(porydaw_add_release_engine)
    foreach(language IN ITEMS C CXX)
        foreach(config IN ITEMS Debug Release RelWithDebInfo MinSizeRel ${CMAKE_CONFIGURATION_TYPES} ${CMAKE_BUILD_TYPE})
            string(TOUPPER "${config}" config_upper)
            set(CMAKE_${language}_FLAGS_${config_upper} "${CMAKE_${language}_FLAGS_RELEASE}")
        endforeach()
    endforeach()
    set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ${PORYDAW_IPO_SUPPORTED})
    add_subdirectory(
        "${PORYAAAA_DIR}/plugin/porydaw"
        "${CMAKE_CURRENT_BINARY_DIR}/poryaaaa-engine")
endfunction()
porydaw_add_release_engine()

if(PORYDAW_COVERAGE)
    add_compile_options(-O0 -fno-inline)
endif()

if(POLICY CMP0157)
    cmake_policy(SET CMP0157 NEW)
    set(CMAKE_Swift_COMPILATION_MODE
        "$<IF:$<CONFIG:Debug>,incremental,wholemodule>")
endif()
enable_language(Swift)
add_subdirectory(src/swift/core)
add_subdirectory(src/swift/playback)
add_subdirectory(src/swift/project)
include(cmake/QtBridge.cmake)
add_subdirectory(src/swift/app)


# ---- porydaw application ----
qt_add_library(porydaw_app STATIC
    src/app/native_host.h
    src/app/clipboard_host.cpp
    src/ui/songview/quick/swiftroll/native/font_metrics.cpp
    src/ui/songview/quick/swiftroll/native/font_metrics.h
    src/audio/audioengine.cpp
    src/audio/audioengine.h
    src/audio/auditionslots.cpp
    src/audio/auditionslots.h
    src/audio/resonance_suppressor.cpp
    src/audio/resonance_suppressor.h
    src/audio/swift_playback.h
    src/audio/timeline_handoff.h
    src/audio/trackactivitylevel.h
    src/audio/wavexport.cpp
    src/audio/wavexport.h
    src/audio/miniaudio_impl.c
    src/audio/stb_vorbis_impl.c
    src/project/banklease.cpp
    src/project/banklease.h
    src/project/projectidentity.cpp
    src/project/projectidentity.h
)

qt_add_resources(porydaw_app "swift_roll_qml"
    PREFIX "/porydaw/swiftroll"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/src/ui/songview/quick/swiftroll"
    FILES
        src/ui/songview/quick/swiftroll/EditorSurface.qml
        src/ui/songview/quick/swiftroll/SongTabs.qml
        src/ui/songview/quick/swiftroll/SongTab.qml
        src/ui/songview/quick/swiftroll/TrackHeaderBand.qml
        src/ui/songview/quick/swiftroll/SharedPlayhead.qml
        src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml
        src/ui/songview/quick/swiftroll/TimelineQuickItem.qml
        src/ui/songview/quick/swiftroll/MouseHintStatus.qml
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-left-disabled.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-left-disabled@2x.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-left-enabled.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-left-enabled@2x.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-right-disabled.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-right-disabled@2x.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-right-enabled.png
        src/ui/songview/quick/swiftroll/tabart/tab-arrow-right-enabled@2x.png
        src/ui/songview/quick/swiftroll/tabart/window-close.svg
)

# Shared original controls retain relative imports from the drawer resources.
qt_add_resources(porydaw_app "drawer_shared_qml"
    PREFIX "/porydaw"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/src/ui/songview/quick"
    FILES
        src/ui/songview/quick/PianoRollCanvas.qml
        src/ui/songview/quick/TrackHeaderBand.qml
        src/ui/songview/quick/PromptCard.qml
        src/ui/songview/quick/PromptButton.qml
        src/ui/songview/quick/VelocityPrompt.qml
        src/ui/songview/quick/VoicePickerPrompt.qml
        src/ui/songview/quick/TimeSignaturePrompt.qml
        src/ui/songview/quick/InsertTimePrompt.qml
        src/ui/songview/quick/DragInput.qml
        src/ui/songview/quick/PitchBendPopup.qml
        src/ui/songview/quick/HoverHint.qml
        src/ui/songview/quick/TimelineScrollbar.qml
        src/ui/songview/quick/HintProfiles.qml
        src/ui/songview/quick/QuickMenuPanel.qml
        src/ui/songview/quick/AutomationTabs.qml
)

# The drawer keeps the swiftroll prefix layout, so EditorSurface's relative
# `import "../drawer"` resolves in both the resource engine and the source tree.
qt_add_resources(porydaw_app "drawer_qml"
    PREFIX "/porydaw/drawer"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/src/ui/songview/quick/drawer"
    FILES
        src/ui/songview/quick/drawer/EditorDrawer.qml
        src/ui/songview/quick/drawer/VelocityPage.qml
        src/ui/songview/quick/drawer/VoiceChangesPage.qml
        src/ui/songview/quick/drawer/VoiceChangeMenu.qml
        src/ui/songview/quick/drawer/AutomationPage.qml
        src/ui/songview/quick/drawer/AutomationPrompt.qml
        src/ui/songview/quick/drawer/AutomationMenu.qml
)

qt_add_resources(porydaw_app "voicegroup_dock_qml"
    PREFIX "/porydaw/docks"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/src/ui/songview/quick/docks"
    FILES
        src/ui/songview/quick/docks/VoicegroupPanel.qml
        src/ui/songview/quick/docks/VoiceEditor.qml
        src/ui/songview/quick/docks/SamplePicker.qml
)

qt_add_resources(porydaw_app "voicegroup_type_icons"
    PREFIX "/porydaw/voiceicons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/waveform.svg
        resources/wave-square.svg
        resources/wave-triangle.svg
        resources/wave-sine.svg
        resources/waveform-path.svg
        resources/piano-keyboard.svg
        resources/drum.svg
)

qt_add_resources(porydaw_app "drawer_icons"
    PREFIX "/icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/velocity.svg
        resources/velocity_labels.svg
        resources/automation.svg
        resources/flat-music.svg
)

qt_add_resources(porydaw_app "transport_icons"
    PREFIX "/icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/transport-play.svg
        resources/transport-pause.svg
)

qt_add_resources(porydaw_app "drawer_cursors"
    PREFIX "/cursors"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/pencil.png
)

target_include_directories(porydaw_app PUBLIC
    src
)
target_include_directories(porydaw_app SYSTEM PUBLIC
    ${PORYAAAA_DIR}/third_party
    external/dr_libs
    external/stb
    ${PORYAAAA_DIR}/plugin/porydaw/..
    ${PORYAAAA_DIR}/plugin/m4a
    ${PORYAAAA_DIR}/plugin/m4a/..
    ${PORYAAAA_DIR}/plugin/hw_audio
    ${PORYAAAA_DIR}/plugin/hw_audio/..
)

porydaw_enable_project_warnings(porydaw_app)
# The project() version is the single source of truth (docs/RELEASING.md);
# release CI refuses a tag that doesn't match it.
target_compile_definitions(porydaw_app PUBLIC
    "$<$<NOT:$<COMPILE_LANGUAGE:Swift>>:PORYDAW_VERSION=\"${PROJECT_VERSION}\">")
target_link_libraries(porydaw_app PUBLIC Qt6::Widgets poryaaaa_engine PorydawApp
    PorydawPlayback)
target_link_libraries(porydaw_app PRIVATE Qt6::Qml Qt6::Quick QtBridge)
if(APPLE)
    # Keep framework headers ahead of stale non-framework Qt installs such
    # as /usr/local/include/Qt*. Treating imported frameworks as system
    # headers lets Clang select the unrelated include tree first.
    # This archive contains only native objects; Swift's archive rule would
    # incorrectly treat the C++ precompiled header as a Swift input.
    set_target_properties(porydaw_app PROPERTIES
        NO_SYSTEM_FROM_IMPORTED ON
        LINKER_LANGUAGE CXX
    )
endif()
target_precompile_headers(porydaw_app PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/src/porydaw_pch.hpp>")
if(UNIX AND NOT APPLE)
    find_package(Threads REQUIRED)
    target_link_libraries(porydaw_app PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
endif()

# The Swift shell owns the only application entry point.
add_library(porydaw_shell_entry STATIC src/swift/app/shell/PorydawShellApp.swift)
set_target_properties(porydaw_shell_entry PROPERTIES
    Swift_MODULE_NAME PorydawShellEntry
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
target_link_libraries(porydaw_shell_entry PRIVATE QtBridge PorydawApp)

set(shell_qml
    src/ui/shell/PorydawApplication.qml
    src/ui/shell/ShellWindow.qml
    src/ui/shell/TransportBar.qml
    src/ui/shell/TransportButton.qml
    src/ui/shell/TransportOutputDial.qml
    src/ui/shell/PolyphonyPanel.qml
    src/ui/shell/PolyphonyChannelGroup.qml
)
set_source_files_properties(${shell_qml} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
qt_add_executable(porydaw ${shell_qml} resources/fonts.qrc)
# Retain Swift @main and the original editor qrc from their archives
# while linking native LTO objects with the C++ driver.
set_target_properties(porydaw PROPERTIES LINKER_LANGUAGE CXX)
target_link_libraries(porydaw PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_shell_entry>"
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
)

if(PORYDAW_BUILD_CHECKS)
    add_subdirectory(src/checks)
endif()
qt_add_resources(porydaw "app_icon"
    PREFIX "/icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/porydaw-16.png
        resources/porydaw-32.png
        resources/porydaw-48.png
        resources/porydaw-128.png
        resources/porydaw-256.png
)
if(WIN32)
    # Stage the Qt DLLs beside porydaw.exe so the build tree runs directly.
    # Static Qt links everything into the exe, leaving windeployqt nothing
    # to stage — it fails with "does not seem to be a Qt executable" — so
    # the step only runs against a shared Qt. The imported windeployqt
    # target ships with Qt 6.3+; without it the build still succeeds and
    # the DLLs must come from PATH.
    get_target_property(porydaw_qt_core_type Qt6::Core TYPE)
    if(porydaw_qt_core_type STREQUAL "STATIC_LIBRARY")
        # Nothing to deploy.
    elseif(TARGET Qt6::windeployqt)
        add_custom_command(TARGET porydaw POST_BUILD
            COMMAND Qt6::windeployqt
                    --qmldir "${PROJECT_SOURCE_DIR}/src/ui"
                    # SVG image/icon plugins are soft dependencies, so force
                    # their deployment rather than relying on executable scanning.
                    --include-plugins qsvg,qsvgicon
                    --no-translations
                    --no-opengl-sw
                    --no-system-d3d-compiler
                    "$<TARGET_FILE:porydaw>"
            VERBATIM
        )
    else()
        message(WARNING "Qt6::windeployqt not available (needs Qt >= 6.3); "
                        "porydaw.exe will need the Qt DLLs on PATH")
    endif()
endif()

if(WIN32)
    set_target_properties(porydaw PROPERTIES WIN32_EXECUTABLE TRUE)
    # Embeds resources/porydaw.ico as the executable's Explorer/taskbar icon.
    target_sources(porydaw PRIVATE resources/porydaw.rc)
    target_link_libraries(porydaw_app PRIVATE dwmapi)
endif()
if(APPLE)
    set_target_properties(porydaw PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_GUI_IDENTIFIER com.sp3cker.porydaw
        MACOSX_BUNDLE_ICON_FILE porydaw.icns)
    target_sources(porydaw PRIVATE resources/porydaw.icns)
    set_source_files_properties(resources/porydaw.icns PROPERTIES
        MACOSX_PACKAGE_LOCATION Resources)
endif()

# ---- Offline render CLI (development/testing: parity vs poryaaaa_render) ----
add_executable(porydaw_render_cli
    tools/porydaw_render_cli.cpp
    src/audio/swift_playback.h
)
target_include_directories(porydaw_render_cli PRIVATE src)
target_link_libraries(porydaw_render_cli PRIVATE PorydawPlayback poryaaaa_engine)
porydaw_enable_project_warnings(porydaw_render_cli)
if(APPLE)
    # PorydawPlayback is a Swift archive, but this executable contains only
    # native objects. Match the application target: let CMake propagate the
    # Swift runtime link items while the C++ driver performs the final link.
    set_target_properties(porydaw_render_cli PROPERTIES LINKER_LANGUAGE CXX)
endif()
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_link_options(porydaw_render_cli PRIVATE -static)
endif()
