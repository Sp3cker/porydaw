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
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

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

# ---- porydaw application ----
qt_add_library(porydaw_app STATIC
    src/mainwindow.cpp
    src/mainwindow.h
    src/ui/layout.cpp
    src/ui/layout.h
    src/ui/typography.cpp
    src/ui/typography.h
    # Editable swatches and color policy stay separate from Qt runtime mapping;
    # paint code consumes only fully resolved roles.
    src/ui/theme/theme.h
    src/ui/theme/themeruntime.cpp
    src/ui/theme/themeruntime.h
    src/ui/theme/theme_roles.h
    src/ui/theme/color_math.cpp
    src/ui/theme/color_math.h
    src/ui/theme/presetcolors.h
    src/ui/theme/trackidentitycolors.h
    src/ui/theme/trackidentitycolors.cpp
    src/ui/theme/themeresolver.cpp
    src/ui/theme/themeresolver.h
    src/ui/theme/themecontroller.cpp
    src/ui/theme/themecontroller.h
    src/ui/theme/themedialog.cpp
    src/ui/theme/themedialog.h

    src/audio/audioengine.cpp
    src/audio/audioengine.h
    src/audio/resonance_suppressor.cpp
    src/audio/resonance_suppressor.h
    src/audio/auditionslots.cpp
    src/audio/auditionslots.h
    src/audio/miniaudio_impl.c
    src/audio/stb_vorbis_impl.c
    src/audio/wavexport.cpp
    src/audio/wavexport.h
    src/audio/sampledata.h
    src/audio/sampledsp.cpp
    src/audio/sampledsp.h
    src/audio/sampleimport.cpp
    src/audio/sampleimport.h
    src/audio/sampledoc.cpp
    src/audio/sampledoc.h
    src/audio/samplewav.cpp
    src/audio/samplewav.h
    src/audio/sf2reader.cpp
    src/audio/sf2reader.h
    src/ui/activity/trackactivity.cpp
    src/ui/activity/trackactivity.h
    src/ui/activity/trackactivityrender.cpp
    src/ui/activity/trackactivityrender.h
    src/core/mid2agbtables.cpp
    src/core/mid2agbtables.h
    src/core/miditimeline.cpp
    src/core/miditimeline.h
    src/core/smf.cpp
    src/core/smf.h
    src/core/xcmd.cpp
    src/core/xcmd.h
    src/core/songdocument.cpp
    src/core/songdocument_range.cpp
    src/core/songdocument_timeeditor.cpp
    src/core/songdocument_timeeditor_insert.cpp
    src/core/songdocument_timeeditor_xcmd.cpp
    src/core/songdocument_tempo.cpp
    src/core/songdocument_xcmd.cpp
    src/core/songdocument.h
    src/core/songhistory.cpp
    src/core/songhistory.h
    src/core/lanemoveplan.cpp
    src/core/lanemoveplan.h
    src/porydaw_scale.cpp
    src/porydaw_scale.h
    src/core/timelineplayer.cpp
    src/core/timelineplayer.h
    src/core/midiimport.cpp
    src/core/midiimport.h
    src/project/decompproject.cpp
    src/project/decompproject.h
    src/project/voicegroupprojectcontext.cpp
    src/project/voicegroupprojectcontext.h
    src/project/projectidentity.cpp
    src/project/projectidentity.h
    src/project/projectworkspace.cpp
    src/project/projectworkspace.h
    src/project/projectio.cpp
    src/project/projectio.h
    src/project/songregistry.cpp
    src/project/songregistry.h
    src/project/songsmk.cpp
    src/project/songsmk.h
    src/project/samplereg.cpp
    src/project/samplereg.h
    src/project/sidecar.cpp
    src/project/sidecar.h
    src/project/voicegroupsource.cpp
    src/project/voicegroupsource.h
    src/ui/dragspinbox.cpp
    src/ui/dragspinbox.h
    src/core/m4asemantics.cpp
    src/core/m4asemantics.h
    src/ui/applicationstartup.cpp
    src/ui/applicationstartup.h
    src/ui/newsongwizard.cpp
    src/ui/newsongwizard.h
    src/ui/sampleeditordialog.cpp
    src/ui/sampleeditordialog.h
    src/ui/sf2zonepicker.cpp
    src/ui/sf2zonepicker.h
    src/ui/waveformview.cpp
    src/ui/waveformview.h
    src/ui/samplepicker.cpp
    src/ui/samplepicker.h
    src/ui/voicegroupbrowser.cpp
    src/ui/voicegroupbrowser.h
    src/ui/voicetypeicons.cpp
    src/ui/keymap.cpp
    src/ui/keymap.h
    src/ui/enginesettingsdialog.cpp
    src/ui/enginesettingsdialog.h
    src/ui/songsettingsdialog.cpp
    src/ui/songsettingsdialog.h
    src/ui/settingsdialog.cpp
    src/ui/settingsdialog.h
    src/ui/polyphonypanel.cpp
    src/ui/polyphonypanel.h
    src/ui/songlistpanel.cpp
    src/ui/songlistpanel.h
    src/ui/songviewmodel.cpp
    src/ui/songviewmodel.h
    src/ui/transportbar.cpp
    src/ui/transportbar.h
    src/ui/fastlabel.cpp
    src/ui/fastlabel.h
    src/ui/mousehints/hintprofiles.cpp
    src/ui/mousehints/hintprofiles.h
    src/ui/mousehints/mousehints.cpp
    src/ui/mousehints/mousehints.h
    src/ui/mousehints/widgethints.cpp
    src/ui/workspaceui.cpp
    src/ui/workspaceui_tabs.cpp
    src/ui/workspaceui_project.cpp
    src/ui/workspaceui_voicegroup.cpp
    src/ui/workspaceui_samples.cpp
    src/ui/workspaceui.h
    src/ui/songtab.cpp
    src/ui/songtab.h
    src/ui/songtabquickhost.cpp
    src/ui/songtabquickhost.h
    src/ui/voicegroupviewcache.cpp
    src/ui/voicegroupviewcache.h
    src/ui/pitchprojection.cpp
    src/ui/pitchprojection.h
    src/ui/songview.cpp
    src/ui/songview.h
    src/ui/playheadoverlay.cpp
    src/ui/playheadoverlay.h
    src/ui/songview/otherstrip.cpp
    src/ui/songview/otherstrip.h
    src/ui/songview/voicepicker.cpp
    src/ui/songview/voicepicker.h
    src/ui/songview/trackheadermodel.cpp
    src/ui/songview/trackheadermodel.h
    src/ui/songview/trackheadermenu.cpp
    src/ui/songview/editorselectionmodel.cpp
    src/ui/songview/editorselectionmodel.h
    src/ui/songview/detail.cpp
    src/ui/songview/detail.h
    src/ui/songview/camera.cpp
    src/ui/songview/grid.cpp
    src/ui/songview/grid.h
    src/ui/songview/timeaxis.cpp
    src/ui/songview/timeaxis.h
    src/ui/songview/timecamera.cpp
    src/ui/songview/timecamera.h
    src/ui/songview/rangeedit.cpp
    src/ui/songview/editkeyrouting.cpp
    src/ui/songview/editactions.cpp
    src/ui/songview/editactions.h
    src/ui/songview/scalecontroller.cpp
    src/ui/songview/scalecontroller.h
    src/ui/songview/clipmime.cpp
    src/ui/songview/trackvoiceops.cpp
    src/ui/songview/viewstate.cpp
    src/ui/songview/drawercoordination.cpp
    src/ui/songview/timeruler.cpp
    src/ui/songview/timeruler.h
    src/ui/songview/timeruler_interaction.cpp
    src/ui/songview/pianoroll.cpp
    src/ui/songview/pianoroll.h
    src/ui/songview/pianoroll_geometry.cpp
    src/ui/songview/pianoroll_interaction.cpp
    src/ui/songview/pianoroll_gestures.cpp
    src/ui/songview/pianoroll_gestures_active.cpp
    src/ui/songview/pianoroll_commands.cpp
    src/ui/songview/quick/eventlistcontroller.cpp
    src/ui/songview/quick/eventlistcontroller.h
    src/ui/songview/quick/quickmenumodel.cpp
    src/ui/songview/quick/quickmenuhost.cpp
    src/ui/songview/quick/quickpopupsession.cpp
    src/ui/songview/quick/quickpopupsession.h
    src/ui/songview/quick/quickmenulayout.cpp
    src/ui/songview/quick/quickmenulayout.h
    src/ui/songview/quick/promptappearance.cpp
    src/ui/songview/quick/promptappearance.h
    src/ui/songview/quick/quickmenumodel.h
    src/ui/songview/quick/otherstripquick.cpp
    src/ui/songview/quick/automationnodelanequick.cpp
    src/ui/songview/quick/automationnodelanequick.h
    src/ui/songview/quick/automationquick.cpp
    src/ui/songview/quick/velocityquick.cpp
    src/ui/songview/quick/voicechangequick.cpp
    src/ui/songview/quick/pianorollquick.h
    src/ui/songview/quick/timelineinput.h
    src/ui/songview/quick/timelineinputitem.cpp
    src/ui/songview/quick/timelineinputitem.h
    src/ui/songview/quick/timelinequickscene.cpp
    src/ui/songview/quick/timelinequickchrome.cpp
    src/ui/songview/quick/timelinequickchrome.h
    src/ui/songview/quick/playheadquick.cpp
    src/ui/songview/quick/playheadquick.h
    src/ui/songview/quick/timelinequicklayer.h
    src/ui/songview/quick/timelinequickscene.h
    src/ui/songview/quick/timelinequickview.cpp
    src/ui/songview/quick/timelinequickview.h
    src/ui/songview/quick/timelinequickview_pianoroll.cpp
    src/ui/songview/quick/timelinequickview_keyrouting.cpp
    src/ui/songview/quick/timelinequickview_window.cpp
    src/ui/songview/quick/timerulerquick.cpp
    src/ui/pitchbendeditor.cpp
    src/ui/pitchbendeditor.hpp
    src/ui/pitchbendgraph.cpp
    src/ui/pitchbendgraph.hpp
    src/ui/pitchbendgraph_render.cpp
    src/ui/eventtablemodel.cpp
    src/ui/eventtablemodeledit.cpp
    src/ui/eventtablemodel.h
    src/ui/eventtabletypes.cpp
    src/ui/eventtabletypes.h
    src/core/noteid.h
    src/core/velocitymodel.cpp
    src/core/velocitymodel.h
    src/ui/velocitygesturemodel.cpp
    src/ui/velocitygesturemodel.h
    src/ui/editordrawer/drawerpage.h
    src/ui/editorviewstate.cpp
    src/ui/editorviewstate.h
    src/ui/editordrawer/editordrawer.cpp
    src/ui/editordrawer/editordrawer.h
    src/ui/editordrawer/taptempo.h
    src/ui/editordrawer/drawersections.cpp
    src/ui/editordrawer/drawersections.h
    src/ui/editordrawer/drawerchrome.cpp
    src/ui/editordrawer/drawerchrome.h
    src/ui/editordrawer/automationcanvas.cpp
    src/ui/editordrawer/automationcanvas_tabs.cpp
    src/ui/editordrawer/automationcanvas_gesture.cpp
    src/ui/editordrawer/automationcanvas_input.cpp
    src/ui/editordrawer/automationcanvas_menu.cpp
    src/ui/editordrawer/automationcanvas_pointmenu.cpp
    src/ui/editordrawer/automationcanvas_deleteprompt.cpp
    src/ui/editordrawer/automationcanvas_taptempo.cpp
    src/ui/editordrawer/automationviewmodel.cpp
    src/ui/editordrawer/automationviewmodel.h
    src/ui/editordrawer/nodelane/gesture.cpp
    src/ui/editordrawer/nodelane/gesture.h
    src/ui/editordrawer/nodelane/hover.cpp
    src/ui/editordrawer/nodelane/hover.h
    src/ui/editordrawer/cclanes.cpp
    src/ui/editordrawer/cclanes.h
    src/ui/editordrawer/voicechangearea/voicechangearea.cpp
    src/ui/editordrawer/voicechangearea/voicechangearea.h
    src/ui/editordrawer/voicechangearea/voicechangemenu.cpp
    src/ui/editordrawer/nodelane/pencilgesture.cpp
    src/ui/editordrawer/nodelane/pencilgesture.h
    src/ui/editordrawer/automationprojection.cpp
    src/ui/editordrawer/automationprojection.h
    src/ui/editordrawer/automationpage.cpp
    src/ui/editordrawer/automationpage.h
    src/ui/editordrawer/nodelane/nodelane.cpp
    src/ui/editordrawer/nodelane/nodelane.h
    src/ui/editordrawer/nodelane/batchcommit.cpp
    src/ui/editordrawer/nodelane/batchcommit.h
    src/ui/editordrawer/nodelane/tempoadapter.cpp
    src/ui/editordrawer/tempolane.cpp
    src/ui/editordrawer/tempolane.h
    src/ui/editordrawer/velocityarea/velocityarea.cpp
    src/ui/editordrawer/velocityarea/velocityarea.h
    src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp
    src/ui/editordrawer/velocityarea/detail.h
    src/ui/editordrawer/linearramp.h
    src/ui/editordrawer/velocityaxis.cpp
    src/ui/editordrawer/velocityaxis.h
)
if(APPLE)
    target_sources(porydaw_app PRIVATE
        src/ui/nativelayerutils_macos_p.h
        src/ui/playheadrenderer_macos.mm
    )
    # Qt's qdebug.h UInt alias collides with macOS OSTypes.h only in this
    # Objective-C++ bridge; keep project -Wshadow enabled everywhere else.
    set_property(SOURCE src/ui/playheadrenderer_macos.mm APPEND PROPERTY
        COMPILE_OPTIONS -Wno-shadow)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
    find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
    target_link_libraries(porydaw_app PRIVATE
        ${APPKIT_FRAMEWORK}
        ${QUARTZCORE_FRAMEWORK}
    )
endif()

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
target_include_directories(porydaw_app PRIVATE
    src/ui
    src/ui/mousehints
    src/ui/songview/quick
)

porydaw_enable_project_warnings(porydaw_app)
# The project() version is the single source of truth (docs/RELEASING.md);
# release CI refuses a tag that doesn't match it.
target_compile_definitions(porydaw_app PUBLIC
    PORYDAW_VERSION="${PROJECT_VERSION}")
target_link_libraries(porydaw_app PUBLIC Qt6::Svg Qt6::Widgets poryaaaa_engine)
target_link_libraries(porydaw_app PRIVATE Qt6::Qml Qt6::Quick Qt6::QuickControls2)
if(APPLE)
    # Keep framework headers ahead of stale non-framework Qt installs such
    # as /usr/local/include/Qt*. Treating imported frameworks as system
    # headers lets Clang select the unrelated include tree first.
    set_target_properties(porydaw_app PROPERTIES NO_SYSTEM_FROM_IMPORTED ON)
endif()
set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
# Each Quick file is bundled at its basename; one loop instead of one
# set_source_files_properties block per file.
foreach(qml IN
    ITEMS AutomationTabs TimelineCanvas PianoRollCanvas TimelineScrollbar
          RulerControls RulerToolTip TrackHeaderBand OtherStripToolTip
          DrawerChromeLayer DragInput HoverHint PromptCard PromptButton
          PitchBendPopup VelocityPrompt CcDeleteConfirm TimeSignaturePrompt
          InsertTimePrompt VoicePickerPrompt EventListPage QuickMenuPanel
          QuickPopupLayer)
    set_source_files_properties(
        src/ui/songview/quick/${qml}.qml
        PROPERTIES QT_RESOURCE_ALIAS ${qml}.qml)
endforeach()
qt_add_qml_module(porydaw_app
    URI Porydaw.Ui
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    NO_PLUGIN
    SOURCES
        src/ui/mousehints/hintprofiles.h
        src/ui/pitchbendgraph.hpp
        src/ui/songview/quick/playheadquick.h
        src/ui/songview/quick/timelineinputitem.h
        src/ui/songview/quick/timelinequickchrome.h
        src/ui/songview/quick/timelinequickscene.h
    QML_FILES
        src/ui/songview/quick/AutomationTabs.qml
        src/ui/songview/quick/TimelineCanvas.qml
        src/ui/songview/quick/PianoRollCanvas.qml
        src/ui/songview/quick/TimelineScrollbar.qml
        src/ui/songview/quick/RulerControls.qml
        src/ui/songview/quick/RulerToolTip.qml
        src/ui/songview/quick/TrackHeaderBand.qml
        src/ui/songview/quick/DrawerChromeLayer.qml
        src/ui/songview/quick/OtherStripToolTip.qml
        src/ui/songview/quick/QuickMenuPanel.qml
        src/ui/songview/quick/QuickPopupLayer.qml
        src/ui/songview/quick/EventListPage.qml
        src/ui/songview/quick/DragInput.qml
        src/ui/songview/quick/HoverHint.qml
        src/ui/songview/quick/PromptCard.qml
        src/ui/songview/quick/PromptButton.qml
        src/ui/songview/quick/PitchBendPopup.qml
        src/ui/songview/quick/VelocityPrompt.qml
        src/ui/songview/quick/CcDeleteConfirm.qml
        src/ui/songview/quick/TimeSignaturePrompt.qml
        src/ui/songview/quick/InsertTimePrompt.qml
        src/ui/songview/quick/VoicePickerPrompt.qml
)
target_precompile_headers(porydaw_app PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/src/porydaw_pch.hpp>")
if(UNIX AND NOT APPLE)
    find_package(Threads REQUIRED)
    target_link_libraries(porydaw_app PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
endif()

qt_add_executable(porydaw
    src/main.cpp
    resources/fonts.qrc
)
target_link_libraries(porydaw PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>")

if(PORYDAW_BUILD_CHECKS)
    add_subdirectory(src/checks)
endif()
qt_add_resources(porydaw "app_icon"
    PREFIX "/icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/flat-music.svg
        resources/porydaw-16.png
        resources/porydaw-32.png
        resources/porydaw-48.png
        resources/porydaw-128.png
        resources/porydaw-256.png
        resources/velocity.svg
        resources/velocity_labels.svg
        resources/automation.svg
        resources/drum.svg
        resources/piano-keyboard.svg
        resources/wave-sine.svg
        resources/wave-square.svg
        resources/wave-triangle.svg
        resources/waveform-path.svg
        resources/waveform.svg
)
qt_add_resources(porydaw "cursor_images"
    PREFIX "/cursors"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES
        resources/left-drag.png
        resources/left-drag@2x.png
        resources/pencil.png
        resources/pencil@2x.png
        resources/right-drag.png
        resources/right-drag@2x.png
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
    if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        # MinGW: statically link libgcc/libstdc++/winpthread so the exe
        # doesn't depend on libgcc_s_seh-1.dll etc. at runtime.
        target_link_options(porydaw PRIVATE -static)
    endif()
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
    src/core/mid2agbtables.cpp
    src/core/miditimeline.cpp
    src/core/smf.cpp
    src/core/timelineplayer.cpp
)
target_include_directories(porydaw_render_cli PRIVATE src)
target_link_libraries(porydaw_render_cli PRIVATE Qt6::Core poryaaaa_engine)

porydaw_enable_project_warnings(porydaw_render_cli)
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_link_options(porydaw_render_cli PRIVATE -static)
endif()
