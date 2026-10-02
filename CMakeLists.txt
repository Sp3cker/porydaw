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
set(CMAKE_AUTORCC ON)

# Strict diagnostics apply only to project C++ translation units. Vendored C
# implementation units are excluded, and third-party headers are SYSTEM
# includes. -Wold-style-cast stays off because the codebase idiomatically uses
# C-style casts.
function(porydaw_enable_project_warnings target)
    target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wformat=2>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wnull-dereference>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wdouble-promotion>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wcast-align>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-Wcast-qual>
        $<$<COMPILE_LANG_AND_ID:CXX,Clang,AppleClang>:-Wextra-semi;-Wrange-loop-analysis>
        $<$<COMPILE_LANG_AND_ID:CXX,GNU>:-Wduplicated-cond;-Wduplicated-branches;-Wlogical-op>
    )
endfunction()

# Batch mode keeps one frontend process per batch of sources, so C++ interop's
# per-process ClangImporter startup is paid once per batch instead of once per
# source file. The driver ignores the flag outside incremental compilation, so
# it stays gated on Debug — the only incremental configuration here.
function(porydaw_enable_swift_batch_mode target)
    target_compile_options(${target} PRIVATE
        "$<$<AND:$<COMPILE_LANGUAGE:Swift>,$<CONFIG:Debug>>:-enable-batch-mode>")
endfunction()

# Optimize the native audio path even in debug builds: the miniaudio converter
# dominates audio-thread cost and the sample codec dominates import decode time.
set(PORYDAW_AUDIO_ALWAYS_OPTIMIZE_SRCS
    src/audio/miniaudio_impl.c
    src/audio/sample_codec.c)
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    foreach(PORYDAW_AUDIO_SRC IN LISTS PORYDAW_AUDIO_ALWAYS_OPTIMIZE_SRCS)
        set_source_files_properties(
            "${PORYDAW_AUDIO_SRC}"
            PROPERTIES COMPILE_OPTIONS "-O2")
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

# AddressSanitizer instruments both Swift and native code in an isolated tree.
# Configure and build with: deno task build:checks --asan
option(PORYDAW_ASAN "Build with AddressSanitizer" OFF)
option(PORYDAW_BUILD_CHECKS "Build the porydaw check executable" ON)
if(PORYDAW_ASAN)
    add_compile_options(
        "$<$<COMPILE_LANGUAGE:C,CXX>:-fsanitize=address;-fno-omit-frame-pointer>"
        "$<$<COMPILE_LANGUAGE:Swift>:-sanitize=address>")
    add_link_options(
        "$<$<LINK_LANGUAGE:C,CXX>:-fsanitize=address>"
        "$<$<LINK_LANGUAGE:Swift>:-sanitize=address>")
endif()

find_package(Qt6 6.11 REQUIRED COMPONENTS Qml Quick QuickControls2 Widgets)
qt_standard_project_setup()
qt_policy(SET QTP0004 NEW)

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
    foreach(qt_target IN ITEMS Core Gui Qml Quick QuickControls2 Widgets)
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

if(POLICY CMP0157)
    cmake_policy(SET CMP0157 NEW)
    set(CMAKE_Swift_COMPILATION_MODE
        "$<IF:$<CONFIG:Debug>,incremental,wholemodule>")
endif()
enable_language(Swift)
if(NOT APPLE AND CMAKE_Swift_COMPILER_VERSION VERSION_LESS 6.4)
    message(FATAL_ERROR "The Qt main executor requires Swift 6.4 or newer on Linux and Windows")
endif()
include(cmake/BinaryParsing.cmake)
add_subdirectory(src/swift/core)
add_subdirectory(src/swift/playback)
add_subdirectory(src/swift/sample)
add_subdirectory(src/swift/project)
include(cmake/QtBridge.cmake)
add_subdirectory(src/swift/app)


# ---- porydaw application ----
qt_add_library(porydaw_app STATIC
    src/app/native_host.h
    src/app/clipboard_host.cpp
    src/app/qml_engine_host.h
    src/app/qml_engine_host.cpp
    src/app/item_cursor.h
    src/app/item_cursor.cpp
    src/render/display_list.h
    src/render/display_list.c
    src/render/display_list_item.h
    src/render/display_list_item.cpp
    src/ui/songview/quick/swiftroll/native/font_metrics.cpp
    src/ui/songview/quick/swiftroll/native/font_metrics.h
    src/audio/miniaudio_impl.c
    src/audio/sample_codec.h
    src/audio/sample_codec.c
    src/project/banklease.cpp
    src/project/banklease.h
    src/project/projectidentity.cpp
    src/project/projectidentity.h
)

# Icons stand alone so the Controls style and Porydaw.Ui both import them.
qt_add_library(porydaw_icons STATIC)
set_source_files_properties(src/ui/icons/Icons.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(porydaw_icons
    URI Porydaw.Icons
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Porydaw/Icons"
    NO_PLUGIN
    QML_FILES
        src/ui/icons/Icons.qml
        src/ui/icons/AppIcon.qml
)
target_link_libraries(porydaw_icons PRIVATE Qt6::Quick)

# The Controls style (qtquickcontrols2.conf): Fusion, with every image-backed
# indicator drawn as an icon glyph. Its version is forwarded to Fusion, so it
# tracks Qt's.
qt_add_library(porydaw_style STATIC)
qt_add_qml_module(porydaw_style
    URI PorydawStyle
    VERSION ${Qt6_VERSION_MAJOR}.${Qt6_VERSION_MINOR}
    RESOURCE_PREFIX /qt/qml
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/PorydawStyle"
    NO_PLUGIN
    IMPORTS
        QtQuick.Controls.Fusion/auto
    DEPENDENCIES
        Porydaw.Icons
    QML_FILES
        src/ui/style/CheckBox.qml
        src/ui/style/CheckIndicator.qml
        src/ui/style/ComboBox.qml
        src/ui/style/Menu.qml
        src/ui/style/MenuItem.qml
        src/ui/style/ProgressBar.qml
        src/ui/style/SpinBox.qml
)
target_link_libraries(porydaw_style PRIVATE Qt6::Quick porydaw_icons)

qt_add_qml_module(porydaw_app
    URI Porydaw.Ui
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Porydaw/Ui"
    NO_PLUGIN
    QML_FILES
        src/ui/songview/quick/PianoRollCanvas.qml
        src/ui/songview/quick/PromptCard.qml
        src/ui/songview/quick/PromptButton.qml
        src/ui/songview/quick/VelocityPrompt.qml
        src/ui/songview/quick/VoicePickerPrompt.qml
        src/ui/songview/quick/TimeSignaturePrompt.qml
        src/ui/songview/quick/EventListPage.qml
        src/ui/songview/quick/EventListCell.qml
        src/ui/songview/quick/EventListTable.qml
        src/ui/songview/quick/EventListToolbar.qml
        src/ui/songview/quick/EventListMenu.qml
        src/ui/songview/quick/RulerToolTip.qml
        src/ui/songview/quick/InsertTimePrompt.qml
        src/ui/songview/quick/DragInput.qml
        src/ui/songview/quick/PitchBendPopup.qml
        src/ui/songview/quick/HoverHint.qml
        src/ui/songview/quick/MoveCoalescer.qml
        src/ui/songview/quick/TimelineScrollbar.qml
        src/ui/songview/quick/HintProfiles.qml
        src/ui/songview/quick/QuickMenuPanel.qml
        src/ui/songview/quick/AutomationTabs.qml
        src/ui/songview/quick/swiftroll/EditorSurface.qml
        src/ui/songview/quick/swiftroll/EditorRollBand.qml
        src/ui/songview/quick/swiftroll/EditorRulerBand.qml
        src/ui/songview/quick/swiftroll/EditorSurfaceMenus.qml
        src/ui/songview/quick/swiftroll/EditorSurfacePrompts.qml
        src/ui/songview/quick/swiftroll/SongTabs.qml
        src/ui/songview/quick/swiftroll/SongTab.qml
        src/ui/songview/quick/swiftroll/TrackHeaderBand.qml
        src/ui/songview/quick/swiftroll/TrackHeaderRows.qml
        src/ui/songview/quick/swiftroll/TrackHeaderScrollbar.qml
        src/ui/songview/quick/swiftroll/SharedPlayhead.qml
        src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml
        src/ui/songview/quick/swiftroll/MouseHintStatus.qml
        src/ui/songview/quick/docks/SongsPanel.qml
        src/ui/songview/quick/docks/SongsDockColumn.qml
        src/ui/songview/quick/docks/SongConfirmDialog.qml
        src/ui/songview/quick/docks/VoicegroupPanel.qml
        src/ui/songview/quick/docks/VoiceEditor.qml
        src/ui/songview/quick/docks/VoicegroupNewDialog.qml
        src/ui/songview/quick/docks/SamplePicker.qml
        src/ui/songview/quick/drawer/EditorDrawer.qml
        src/ui/songview/quick/drawer/OtherEventsBand.qml
        src/ui/songview/quick/drawer/VelocityPage.qml
        src/ui/songview/quick/drawer/VoiceChangesPage.qml
        src/ui/songview/quick/drawer/VoiceChangeMenu.qml
        src/ui/songview/quick/drawer/AutomationPage.qml
        src/ui/songview/quick/drawer/AutomationPlot.qml
        src/ui/songview/quick/drawer/AutomationPrompt.qml
        src/ui/songview/quick/drawer/AutomationMenu.qml
        src/ui/songview/quick/drawer/VoicePicker.qml
        src/ui/shell/ShellWindow.qml
        src/ui/shell/ShellContent.qml
        src/ui/shell/ShellMenuBar.qml
        src/ui/shell/WavExportSurface.qml
        src/ui/shell/ShellStatusBar.qml
        src/ui/shell/ShellGridContextMenu.qml
        src/ui/shell/ThemedWindow.qml
        src/ui/shell/DialogWindow.qml
        src/ui/shell/DisclosureLabel.qml
        src/ui/shell/AboutDialog.qml
        src/ui/shell/TransportBar.qml
        src/ui/shell/TransportButton.qml
        src/ui/shell/TransportOutputDial.qml
        src/ui/shell/PolyphonyPanel.qml
        src/ui/shell/PolyphonyChannelGroup.qml
        src/ui/shell/settings/SettingsDialog.qml
        src/ui/shell/settings/EngineSettingsPage.qml
        src/ui/shell/settings/SongSettingsPage.qml
        src/ui/shell/midiimport/MidiImportHost.qml
        src/ui/shell/midiimport/MidiImportWizard.qml
        src/ui/shell/midiimport/ImportAnalysisPage.qml
        src/ui/shell/midiimport/ImportIdentityPage.qml
        src/ui/shell/midiimport/ImportSoundPage.qml
        src/ui/shell/newsong/NewSongHost.qml
        src/ui/shell/newsong/NewSongWizard.qml
        src/ui/shell/samplestudio/SampleStudioHost.qml
        src/ui/shell/samplestudio/SampleStudioDialog.qml
        src/ui/shell/samplestudio/Sf2ZonePickerDialog.qml
        src/ui/shell/samplestudio/SampleWaveform.qml
)

qt_add_resources(porydaw_app "cursor_images"
    PREFIX "/cursors"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/left-drag.png
        resources/left-drag@2x.png
        resources/pencil.png
        resources/right-drag.png
        resources/right-drag@2x.png
)

# The application owns its Quick Controls style on every platform: PorydawStyle
# draws entirely from the themed window palette. Platform styles (macOS,
# Windows, FluentWinUI3) follow the OS appearance instead of the theme.
qt_add_resources(porydaw_app "controls_style"
    PREFIX "/"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/qtquickcontrols2.conf
)

target_include_directories(porydaw_app PUBLIC
    src
)
target_include_directories(porydaw_app PRIVATE
    src/app
    src/render
)
target_include_directories(porydaw_app SYSTEM PUBLIC
    ${PORYAAAA_DIR}/third_party
    ${PORYAAAA_DIR}/plugin/porydaw/..
    ${PORYAAAA_DIR}/plugin/m4a
    ${PORYAAAA_DIR}/plugin/m4a/..
    ${PORYAAAA_DIR}/plugin/hw_audio
    ${PORYAAAA_DIR}/plugin/hw_audio/..
)
target_include_directories(porydaw_app SYSTEM PRIVATE
    external/dr_libs
    external/stb
)

porydaw_enable_project_warnings(porydaw_app)
# The project() version is the single source of truth (docs/RELEASING.md);
# release CI refuses a tag that doesn't match it.
target_compile_definitions(porydaw_app PUBLIC
    "$<$<NOT:$<COMPILE_LANGUAGE:Swift>>:PORYDAW_VERSION=\"${PROJECT_VERSION}\">")
target_link_libraries(porydaw_app PUBLIC Qt6::Gui poryaaaa_engine porydaw_icons porydaw_style)
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

file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/PorydawBuildVersion.swift"
    CONTENT "let porydawBuildVersion = \"@PROJECT_VERSION@\"\n" @ONLY)
add_library(porydaw_shell_entry STATIC
    src/swift/app/shell/PorydawShellApp.swift
    "${CMAKE_CURRENT_BINARY_DIR}/PorydawBuildVersion.swift")
if(NOT APPLE)
    target_sources(porydaw_shell_entry PRIVATE
        src/swift/app/shell/QtMainExecutor.swift)
endif()
set_target_properties(porydaw_shell_entry PROPERTIES
    Swift_MODULE_NAME PorydawShellEntry
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
porydaw_enable_swift_batch_mode(porydaw_shell_entry)
target_link_libraries(porydaw_shell_entry PRIVATE QtBridge PorydawApp)

set(shell_qml
    src/ui/shell/PorydawApplication.qml
)
# Bundled faces load by file URL from the same resource directory as the shell QML.
set(porydaw_fonts
    "${PROJECT_SOURCE_DIR}/resources/AtkinsonHyperlegibleNext-Regular.ttf"
    "${PROJECT_SOURCE_DIR}/resources/AtkinsonHyperlegibleNext-SemiBold.ttf"
    "${PROJECT_SOURCE_DIR}/resources/AtkinsonHyperlegibleMono-Regular.ttf"
    "${PROJECT_SOURCE_DIR}/resources/icons/PorydawIcons.otf")
set_source_files_properties(${shell_qml} ${porydaw_fonts} PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources)
qt_add_executable(porydaw ${shell_qml} ${porydaw_fonts})
if(NOT APPLE)
    target_sources(porydaw PRIVATE src/app/qt_main_executor.cpp)
endif()
if(NOT APPLE)
    foreach(qml IN LISTS shell_qml)
        get_filename_component(qml_name "${qml}" NAME)
        file(GENERATE OUTPUT "$<TARGET_FILE_DIR:porydaw>/${qml_name}"
            INPUT "${CMAKE_CURRENT_SOURCE_DIR}/${qml}")
    endforeach()
endif()
# Non-bundle executables (the non-Apple app, the QML check hosts) resolve resources
# from their runtime directory; multi-config generators append the config.
if(NOT APPLE OR PORYDAW_BUILD_CHECKS)
    get_property(porydaw_multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
    set(porydaw_runtime_dirs "${PROJECT_BINARY_DIR}")
    if(porydaw_multi_config)
        list(TRANSFORM CMAKE_CONFIGURATION_TYPES PREPEND "${PROJECT_BINARY_DIR}/"
            OUTPUT_VARIABLE porydaw_runtime_dirs)
    endif()
    foreach(runtime_dir IN LISTS porydaw_runtime_dirs)
        foreach(font IN LISTS porydaw_fonts)
            get_filename_component(font_name "${font}" NAME)
            configure_file("${font}" "${runtime_dir}/${font_name}" COPYONLY)
        endforeach()
    endforeach()
endif()
# Retain Swift @main and the original editor qrc from their archives
# while linking native LTO objects with the C++ driver.
set_target_properties(porydaw PROPERTIES LINKER_LANGUAGE CXX
    AUTOMOC OFF AUTOUIC OFF)
target_link_libraries(porydaw PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_shell_entry>"
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
    PorydawApp
)
porydaw_link_linux_swift_runtime(porydaw
    porydaw_shell_entry PorydawApp QtBridge PorydawProject PorydawPlayback PorydawCore
    PorydawSample BinaryParsing)

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
