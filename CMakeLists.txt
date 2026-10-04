cmake_minimum_required(VERSION 3.24)
# Release runners use the newest SDK; without a floor the app would require that macOS.
# InlineArray (core, playback, sample) sets the floor at macOS 26.
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
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
if(WIN32)
    # Swift's Windows archive driver cannot consume Clang LTO objects in mixed targets.
    set(PORYDAW_IPO_SUPPORTED OFF)
elseif(PORYDAW_IPO_SUPPORTED)
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
if(APPLE AND NOT CMAKE_Swift_COMPILER_TARGET)
    # CMake gives only C/C++ the deployment floor; Swift needs it in its target triple.
    if(CMAKE_OSX_ARCHITECTURES)
        set(porydaw_swift_arch "${CMAKE_OSX_ARCHITECTURES}")
    else()
        set(porydaw_swift_arch "${CMAKE_HOST_SYSTEM_PROCESSOR}")
    endif()
    set(CMAKE_Swift_COMPILER_TARGET
        "${porydaw_swift_arch}-apple-macosx${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()
enable_language(Swift)
if(WIN32)
    string(APPEND CMAKE_Swift_FLAGS " -use-ld=lld")
    set(CMAKE_STATIC_LIBRARY_PREFIX_Swift "lib")
endif()
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    string(APPEND CMAKE_Swift_FLAGS_RELEASE " -Xcc -DQT_NO_DEBUG -Xcc -DNDEBUG")
endif()
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
target_sources(PorydawApp PRIVATE src/swift/app/shell/PorydawQmlTypes.swift)

set(porydaw_qmltypes_import_path "${CMAKE_BINARY_DIR}/qmltypes")


# ---- porydaw application ----
qt_add_library(porydaw_native_host STATIC
    src/app/native_host.h
    src/app/clipboard_host.cpp
    src/app/qml_engine_host.h
    src/app/qml_engine_host.cpp
    src/render/display_list.h
    src/render/display_list.c
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
qt_add_library(porydaw_app STATIC
    src/app/item_cursor.h
    src/app/item_cursor.cpp
    src/render/display_list_item.h
    src/render/display_list_item.cpp
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
    IMPORT_PATH "${porydaw_qmltypes_import_path}"
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

set_source_files_properties(src/ui/songview/quick/MenuPlacement.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(porydaw_app
    URI Porydaw.Ui
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Porydaw/Ui"
    NO_PLUGIN
    IMPORT_PATH "${porydaw_qmltypes_import_path}"
    DEPENDENCIES PorydawStyle
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
        src/ui/songview/quick/MenuAppearance.qml
        src/ui/songview/quick/MenuPlacement.qml
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
        src/ui/shell/ShellBody.qml
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
        src/ui/shell/settings/ThemeSettingsPage.qml
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

foreach(native_target IN ITEMS porydaw_app porydaw_native_host)
    target_include_directories(${native_target} PUBLIC src)
    target_include_directories(${native_target} PRIVATE src/app src/render)
    target_include_directories(${native_target} SYSTEM PUBLIC
        ${PORYAAAA_DIR}/third_party
        ${PORYAAAA_DIR}/plugin/porydaw/..
        ${PORYAAAA_DIR}/plugin/m4a
        ${PORYAAAA_DIR}/plugin/m4a/..
        ${PORYAAAA_DIR}/plugin/hw_audio
        ${PORYAAAA_DIR}/plugin/hw_audio/..
    )
    target_include_directories(${native_target} SYSTEM PRIVATE external/dr_libs external/stb)
    porydaw_enable_project_warnings(${native_target})
endforeach()
# The project() version is the single source of truth (docs/RELEASING.md);
# release CI refuses a tag that doesn't match it.
foreach(native_target IN ITEMS porydaw_app porydaw_native_host)
    target_compile_definitions(${native_target} PUBLIC
        "$<$<NOT:$<COMPILE_LANGUAGE:Swift>>:PORYDAW_VERSION=\"${PROJECT_VERSION}\">")
    target_link_libraries(${native_target} PUBLIC Qt6::Gui poryaaaa_engine)
    target_link_libraries(${native_target} PRIVATE Qt6::Qml Qt6::Quick QtBridge)
    set_target_properties(${native_target} PROPERTIES LINKER_LANGUAGE CXX)
    if(APPLE)
        set_target_properties(${native_target} PROPERTIES NO_SYSTEM_FROM_IMPORTED ON)
    endif()
    target_precompile_headers(${native_target} PRIVATE
        "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/src/porydaw_pch.hpp>")
    if(UNIX AND NOT APPLE)
        find_package(Threads REQUIRED)
        target_link_libraries(${native_target} PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
    endif()
endforeach()
target_link_libraries(porydaw_app PUBLIC porydaw_native_host porydaw_icons porydaw_style)
if(WIN32)
    target_link_libraries(porydaw_native_host PRIVATE dwmapi)
endif()

# The dumper must not link porydaw_app: that module's QML compilation consumes its output.
set(porydaw_qmltypes_modulemap "${CMAKE_CURRENT_BINARY_DIR}/qmltypes-interop/module.modulemap")
file(CONFIGURE OUTPUT "${porydaw_qmltypes_modulemap}"
    CONTENT "module PorydawQmlTypesQt {\n    header \"@CMAKE_CURRENT_SOURCE_DIR@/src/app/qmltypes_host.h\"\n    export *\n}\n"
    @ONLY)
qt_add_executable(porydaw_qmltypes
    src/swift/qmltypes/main.swift
    src/app/qmltypes_host.h
    src/app/qmltypes_host.cpp
)
set_target_properties(porydaw_qmltypes PROPERTIES
    Swift_MODULE_NAME PorydawQmlTypesCommand
    Swift_LANGUAGE_VERSION 6
    LINKER_LANGUAGE CXX
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
porydaw_enable_swift_batch_mode(porydaw_qmltypes)
target_compile_options(porydaw_qmltypes PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-parse-as-library>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${porydaw_qmltypes_modulemap}>"
)
target_link_libraries(porydaw_qmltypes PRIVATE PorydawApp QtBridge porydaw_native_host)
if(APPLE)
    set_target_properties(porydaw_qmltypes PROPERTIES NO_SYSTEM_FROM_IMPORTED ON)
endif()
if(WIN32)
    target_sources(porydaw_qmltypes PRIVATE
        "$ENV{SDKROOT}/usr/lib/swift/windows/x86_64/swiftrt.obj")
    target_link_directories(porydaw_qmltypes PRIVATE
        "$ENV{SDKROOT}/usr/lib/swift/windows/x86_64"
        "$<TARGET_FILE_DIR:PorydawApp>"
        "$<TARGET_FILE_DIR:PorydawProject>"
        "$<TARGET_FILE_DIR:PorydawPlayback>"
        "$<TARGET_FILE_DIR:PorydawCore>"
        "$<TARGET_FILE_DIR:PorydawSample>"
        "$<TARGET_FILE_DIR:BinaryParsing>"
    )
endif()
porydaw_link_linux_swift_runtime(porydaw_qmltypes
    PorydawApp QtBridge PorydawAppCommands PorydawAppAudio PorydawAppEventList
    PorydawProject PorydawPlayback PorydawCore PorydawSample BinaryParsing)
set(porydaw_qmltypes_files
    "${porydaw_qmltypes_import_path}/PorydawApp/qmldir"
    "${porydaw_qmltypes_import_path}/PorydawApp/PorydawApp.qmltypes"
)
add_custom_command(
    OUTPUT ${porydaw_qmltypes_files}
    COMMAND "$<TARGET_FILE:porydaw_qmltypes>" "${porydaw_qmltypes_import_path}"
    DEPENDS porydaw_qmltypes PorydawApp
    VERBATIM
)
add_custom_target(porydaw_qmltypes_generate DEPENDS ${porydaw_qmltypes_files})
foreach(qml_target IN ITEMS porydaw_app porydaw_style)
    add_dependencies(${qml_target} porydaw_qmltypes_generate)
    foreach(lint_suffix IN ITEMS qmllint qmllint_json qmllint_module)
        if(TARGET ${qml_target}_${lint_suffix})
            add_dependencies(${qml_target}_${lint_suffix} porydaw_qmltypes_generate)
        endif()
    endforeach()
    get_target_property(qml_target_sources ${qml_target} SOURCES)
    foreach(qml_source IN LISTS qml_target_sources)
        if(qml_source MATCHES "(^|/)\\.rcc/qmlcache/.*_qml\\.cpp$")
            set(qml_type_dependencies ${porydaw_qmltypes_files})
            if(qml_target STREQUAL "porydaw_app")
                list(APPEND qml_type_dependencies
                    "${CMAKE_CURRENT_BINARY_DIR}/PorydawStyle/porydaw_style.qmltypes")
            endif()
            add_custom_command(OUTPUT "${qml_source}" APPEND DEPENDS ${qml_type_dependencies})
        endif()
    endforeach()
endforeach()

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
if(WIN32)
    # The C++ link driver does not add Swift's COFF image registration object.
    # Without it, runtime lookup of generic Swift types returns null.
    target_sources(porydaw PRIVATE
        "$ENV{SDKROOT}/usr/lib/swift/windows/x86_64/swiftrt.obj")
    target_link_directories(porydaw PRIVATE
        "$ENV{SDKROOT}/usr/lib/swift/windows/x86_64"
        "$<TARGET_FILE_DIR:PorydawApp>"
        "$<TARGET_FILE_DIR:PorydawProject>"
        "$<TARGET_FILE_DIR:PorydawPlayback>"
        "$<TARGET_FILE_DIR:PorydawCore>"
        "$<TARGET_FILE_DIR:PorydawSample>"
        "$<TARGET_FILE_DIR:BinaryParsing>")
endif()
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
    # lld-link rewrites the generated requestedExecutionLevel attributes into
    # the wrong XML namespace. Reembed the original manifest after linking.
    find_program(PORYDAW_MT_TOOL mt.exe REQUIRED)
    add_custom_command(TARGET porydaw POST_BUILD
        COMMAND "${PORYDAW_MT_TOOL}" -manifest
                "${CMAKE_CURRENT_BINARY_DIR}/porydaw.exe.manifest"
                "-outputresource:$<TARGET_FILE:porydaw>;#1"
        VERBATIM)
    # Stage the Qt DLLs beside porydaw.exe so the build tree runs directly.
    # Static Qt links everything into the exe, leaving windeployqt nothing
    # to stage — it fails with "does not seem to be a Qt executable" — so
    # the step only runs against a shared Qt. The imported windeployqt
    # target ships with Qt 6.3+; without it the build still succeeds and
    # the DLLs must come from PATH.
    get_target_property(porydaw_qt_core_type Qt6::Core TYPE)
    set(porydaw_windeployqt_args
        --qmldir "${PROJECT_SOURCE_DIR}/src/ui"
        --no-translations
        --no-opengl-sw
        --no-system-d3d-compiler
        --no-system-dxc-compiler)
    if(porydaw_qt_core_type STREQUAL "STATIC_LIBRARY")
        # Nothing to deploy.
    elseif(TARGET Qt6::windeployqt)
        add_custom_command(TARGET porydaw POST_BUILD
            COMMAND Qt6::windeployqt ${porydaw_windeployqt_args} "$<TARGET_FILE:porydaw>"
            VERBATIM
        )
    else()
        message(WARNING "Qt6::windeployqt not available (needs Qt >= 6.3); "
                        "porydaw.exe will need the Qt DLLs on PATH")
    endif()
    # The Swift Windows runtime is not deployed by windeployqt. Keep the
    # compiler-matched DLLs beside the executable for direct build-tree launch.
    execute_process(COMMAND "${CMAKE_Swift_COMPILER}" -print-target-info
        OUTPUT_VARIABLE porydaw_swift_target_info COMMAND_ERROR_IS_FATAL ANY)
    string(JSON porydaw_runtime_count LENGTH
        "${porydaw_swift_target_info}" paths runtimeLibraryPaths)
    math(EXPR porydaw_runtime_last "${porydaw_runtime_count} - 1")
    set(porydaw_swift_runtime_dlls "")
    foreach(index RANGE ${porydaw_runtime_last})
        string(JSON runtime_path GET "${porydaw_swift_target_info}"
            paths runtimeLibraryPaths ${index})
        file(TO_CMAKE_PATH "${runtime_path}" runtime_path)
        if(EXISTS "${runtime_path}/swiftCore.dll")
            file(GLOB porydaw_swift_runtime_dlls "${runtime_path}/*.dll")
            break()
        endif()
    endforeach()
    if(NOT porydaw_swift_runtime_dlls)
        message(FATAL_ERROR "Swift Windows runtime DLLs were not found")
    endif()
    foreach(swift_host IN ITEMS porydaw porydaw_qmltypes)
        add_custom_command(TARGET ${swift_host} POST_BUILD
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
                    ${porydaw_swift_runtime_dlls} "$<TARGET_FILE_DIR:${swift_host}>"
            COMMAND_EXPAND_LISTS VERBATIM)
    endforeach()
    if(TARGET Qt6::windeployqt AND NOT porydaw_qt_core_type STREQUAL "STATIC_LIBRARY")
        add_custom_command(TARGET porydaw_qmltypes POST_BUILD
            COMMAND Qt6::windeployqt --no-translations --no-opengl-sw
                    "$<TARGET_FILE:porydaw_qmltypes>"
            VERBATIM)
    endif()
    # `cmake --install` stages the release folder from runtime files only, not the build tree.
    install(TARGETS porydaw RUNTIME DESTINATION .)
    install(FILES ${shell_qml} ${porydaw_fonts} ${porydaw_swift_runtime_dlls} DESTINATION .)
    if(TARGET Qt6::windeployqt AND NOT porydaw_qt_core_type STREQUAL "STATIC_LIBRARY")
        set(porydaw_install_deploy_args "")
        foreach(arg IN LISTS porydaw_windeployqt_args)
            string(APPEND porydaw_install_deploy_args " \"${arg}\"")
        endforeach()
        install(CODE "execute_process(COMMAND \"$<TARGET_FILE:Qt6::windeployqt>\"${porydaw_install_deploy_args} --skip-plugin-types qmltooling,generic \"\${CMAKE_INSTALL_PREFIX}/porydaw.exe\" COMMAND_ERROR_IS_FATAL ANY)")
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
if(NOT WIN32)
    # PorydawPlayback is a Swift archive, but this executable has only native,
    # possibly LTO, objects: the C++ driver links, as for the application target.
    set_target_properties(porydaw_render_cli PROPERTIES LINKER_LANGUAGE CXX)
    porydaw_link_linux_swift_runtime(porydaw_render_cli
        PorydawPlayback PorydawCore BinaryParsing)
endif()
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_link_options(porydaw_render_cli PRIVATE -static)
endif()
