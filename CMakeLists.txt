cmake_minimum_required(VERSION 3.21)
project(porydaw VERSION 1.0.0 LANGUAGES C CXX)

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
    add_compile_options(-fprofile-instr-generate -fcoverage-mapping -O0 -fno-inline)
    add_link_options(-fprofile-instr-generate)
endif()

find_package(Qt6 REQUIRED COMPONENTS Svg Widgets)

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
add_subdirectory(
    "${PORYAAAA_DIR}/plugin/porydaw"
    "${CMAKE_CURRENT_BINARY_DIR}/poryaaaa-engine")

# ---- In-tree m4a converter required by the harness sweep ----
if(PORYDAW_BUILD_CHECKS)
    set(MID2AGB_SOURCE_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/external/poryaaaa/packages/ccomidi/mid2agb")
    # The preserved upstream source includes these otherwise-unused expansion
    # configuration headers. Keep their empty declarations in the build tree rather
    # than adding a stale expansion dependency to this repository.
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
endif()

# ---- porydaw application ----
qt_add_library(porydaw_app STATIC
    src/mainwindow.cpp
    src/mainwindow.h
    src/songsession.h
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
    src/ui/theme/oklchpicker.cpp
    src/ui/theme/oklchpicker.h
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
    src/ui/activity/trackactivitymeter.cpp
    src/ui/activity/trackactivitymeter.h
    src/core/mid2agbtables.cpp
    src/core/mid2agbtables.h
    src/core/miditimeline.cpp
    src/core/miditimeline.h
    src/core/smf.cpp
    src/core/smf.h
    src/core/songdocument.cpp
    src/core/songdocument_range.cpp
    src/core/songdocument_timeeditor.cpp
    src/core/songdocument_timeeditor_insert.cpp
    src/core/songdocument_tempo.cpp
    src/core/songdocument.h
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
    src/project/voicegroupeditcommand.cpp
    src/project/voicegroupeditcommand.h
    src/ui/dragspinbox.cpp
    src/ui/dragspinbox.h
    src/ui/m4asemantics.cpp
    src/ui/m4asemantics.h
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
    src/ui/keymap.cpp
    src/ui/keymap.h
    src/ui/keyboardshortcutsdialog.cpp
    src/ui/keyboardshortcutsdialog.h
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
    src/ui/selectionreticle.cpp
    src/ui/selectionreticle.h
    src/ui/transportbar.cpp
    src/ui/transportbar.h
    src/ui/timelinesurface.cpp
    src/ui/timelinesurface.h
    src/ui/contextmenu.cpp
    src/ui/contextmenu.h
    src/ui/pitchprojection.cpp
    src/ui/pitchprojection.h
    src/ui/songview.cpp
    src/ui/songview.h
    src/ui/songview/otherstrip.cpp
    src/ui/songview/otherstrip.h
    src/ui/songview/voicepicker.cpp
    src/ui/songview/voicepicker.h
    src/ui/songview/trackheaderrow.cpp
    src/ui/songview/trackheaderrow.h
    src/ui/songview/trackheaderpanel.cpp
    src/ui/songview/trackheaderpanel.h
    src/ui/songview/editorselectionmodel.cpp
    src/ui/songview/editorselectionmodel.h
    src/ui/songview/detail.cpp
    src/ui/songview/detail.h
    src/ui/songview/camera.cpp
    src/ui/songview/grid.cpp
    src/ui/songview/rangeedit.cpp
    src/ui/songview/scalecontroller.cpp
    src/ui/songview/scalecontroller.h
    src/ui/songview/clipmime.cpp
    src/ui/songview/trackvoiceops.cpp
    src/ui/songview/viewstate.cpp
    src/ui/songview/drawercoordination.cpp
    src/ui/songview/timeruler.cpp
    src/ui/songview/timeruler.h
    src/ui/songview/timeruler_paint.cpp
    src/ui/songview/timeruler_interaction.cpp
    src/ui/songview/pianoroll.cpp
    src/ui/songview/pianoroll.h
    src/ui/songview/pianoroll_geometry.cpp
    src/ui/songview/pianoroll_paint.cpp
    src/ui/songview/pianoroll_interaction.cpp
    src/ui/songview/pianoroll_commands.cpp
    src/ui/pitchbendeditor.cpp
    src/ui/pitchbendeditor.hpp
    src/ui/pitchbendgraph.cpp
    src/ui/pitchbendgraph.hpp
    src/ui/playheadoverlay.cpp
    src/ui/playheadoverlay.h
    src/ui/eventlistview.cpp
    src/ui/eventlistview.h
    src/ui/eventtablemodel.cpp
    src/ui/eventtablemodeledit.cpp
    src/ui/eventtablemodel.h
    src/ui/eventtabletypes.cpp
    src/ui/eventtabletypes.h
    src/ui/eventlistviewactions.cpp
    src/ui/viewsidecar.cpp
    src/ui/viewsidecar.h
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
    src/ui/editordrawer/drawersections.cpp
    src/ui/editordrawer/drawersections.h
    src/ui/editordrawer/automationcanvas.cpp
    src/ui/editordrawer/automationcanvas_gesture.cpp
    src/ui/editordrawer/automationcanvas_input.cpp
    src/ui/editordrawer/automationcanvas_menu.cpp
    src/ui/editordrawer/automationcanvas_paint.cpp
    src/ui/editordrawer/automationcanvas.h
    src/ui/editordrawer/nodelane/gesture.cpp
    src/ui/editordrawer/nodelane/gesture.h
    src/ui/editordrawer/nodelane/hover.cpp
    src/ui/editordrawer/nodelane/hover.h
    src/ui/editordrawer/cclanes.cpp
    src/ui/editordrawer/cclanes.h
    src/ui/editordrawer/voicechangelane.cpp
    src/ui/editordrawer/voicechangelane.h
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
    src/ui/editordrawer/nodelane/paint.cpp
    src/ui/editordrawer/nodelane/paint.h
    src/ui/editordrawer/nodelane/tempoadapter.cpp
    src/ui/editordrawer/tempolane.cpp
    src/ui/editordrawer/tempolane.h
    src/ui/editordrawer/velocityarea.cpp
    src/ui/editordrawer/velocityarea.h
    src/ui/editordrawer/linearramp.h
    src/ui/editordrawer/velocityaxis.cpp
    src/ui/editordrawer/velocityaxis.h
)
if(APPLE)
    target_sources(porydaw_app PRIVATE
        src/ui/playheadrenderer_macos.mm
    )
    target_compile_definitions(porydaw_app PUBLIC PORYDAW_USE_DIRECT_PLAYHEAD)
    find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
    find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
    target_link_libraries(porydaw_app PRIVATE
        ${APPKIT_FRAMEWORK}
        ${QUARTZCORE_FRAMEWORK}
    )
endif()
target_include_directories(porydaw_app PUBLIC
    src
    ${PORYAAAA_DIR}/third_party
    external/dr_libs
    external/stb
)
# The project() version is the single source of truth (docs/RELEASING.md);
# release CI refuses a tag that doesn't match it.
target_compile_definitions(porydaw_app PUBLIC
    PORYDAW_VERSION="${PROJECT_VERSION}")
target_link_libraries(porydaw_app PUBLIC Qt6::Svg Qt6::Widgets poryaaaa_engine)
target_precompile_headers(porydaw_app PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/src/porydaw_pch.hpp>")
if(WIN32)
    target_sources(porydaw_app PRIVATE src/ui/playheadrenderer_dcomp.cpp)
    target_compile_definitions(porydaw_app PUBLIC PORYDAW_USE_DIRECT_PLAYHEAD)
    target_link_libraries(porydaw_app PRIVATE d2d1 d3d11 dcomp dxgi)
endif()
if(UNIX AND NOT APPLE)
    find_package(Threads REQUIRED)
    target_link_libraries(porydaw_app PRIVATE Threads::Threads ${CMAKE_DL_LIBS})
endif()

qt_add_executable(porydaw
    src/main.cpp
    resources/fonts.qrc
)
target_link_libraries(porydaw PRIVATE porydaw_app)

if(PORYDAW_BUILD_CHECKS)
    qt_add_executable(porydaw_checks
        src/checks/checks_main.cpp
        src/checks/checkregistry.cpp
        src/checks/checkregistry.hpp
        src/checks/checkcatalog.cpp
        src/checks/checkcatalog.h
        src/checks/fixturecatalog.cpp
        src/checks/fixturecatalog.hpp
        src/checks/fwd.hpp
        src/checks/selectioncheck.cpp
        src/checks/clipmimecheck.cpp
        src/checks/clipcheck.cpp
        src/checks/selftest.cpp
        src/checks/tabcheck.cpp
        src/checks/eventviewcheck.cpp
        src/checks/pitchbendcheck.cpp
        src/checks/pitchbendcheck.hpp
        src/checks/rollcheck.cpp
        src/checks/rollcheckwindowing.cpp
        src/checks/rollcheckplayhead.cpp
        src/checks/rollcheckplayhead.h
        src/checks/rollcheckrendering.cpp
        src/checks/rollcheckrendering.h
        src/checks/viewcheck.cpp
        src/checks/roundtrip.cpp
        src/checks/editcheck.cpp
        src/checks/scalecheck.cpp
        src/checks/savecheck.cpp
        src/checks/onboardcheck.cpp
        src/checks/onboardcheck/pipeline.h
        src/checks/onboardcheck/registration.cpp
        src/checks/onboardcheck/debuglayout.cpp
        src/checks/onboardcheck/regionedlayout.cpp
        src/checks/onboardcheck/import.cpp
        src/checks/onboardcheck/deletion.cpp
        src/checks/vgcheck.cpp
        src/checks/vgsavecheck.cpp
        src/checks/exportcheck.cpp
        src/checks/loopcheck.cpp
        src/checks/clickcheck.cpp
        src/checks/polycheck.cpp
        src/checks/primecheck.cpp
        src/checks/xcmdcheck.cpp
        src/checks/smfcheck.cpp
        src/checks/smfcheckfixtures.cpp
        src/checks/smfcheckfixtures.h
        src/checks/transportcheck.cpp
        src/checks/trackactivitycheck.cpp
        src/checks/trackactivitymetercheck.cpp
        src/checks/audiocheck.cpp
        src/checks/resonancecheck.cpp
        src/checks/mkcheck.cpp
        src/checks/ignorecheck.cpp
        src/checks/samplecheck.cpp
        src/checks/sessioncheck.cpp
        src/checks/keymapcheck.cpp
        src/checks/hostcheck.cpp
        src/checks/mainwindowroutingcheck.cpp
        src/checks/noteidcheck.cpp
        src/checks/renderingplayheadcheck.cpp
        src/checks/rollcheckautomation.cpp
        src/checks/rollcheckautomation_tempo.cpp
        src/checks/rollcheckautomation_paint.cpp
        src/checks/rollcheckautomation_tempo_paint.cpp
        src/checks/rollcheckautomation_popup.cpp
        src/checks/automationgesturecheck/rig.cpp
        src/checks/automationgesturecheck/runner.cpp
        src/checks/automationgesturecheck/action.cpp
        src/checks/automationgesturecheck/mapping.cpp
        src/checks/automationgesturecheck/stroke.cpp
        src/checks/automationgesturecheck/ownership.cpp
        src/checks/automationgesturecheck/transactions.cpp
        src/checks/automationgesturecheck/parity.cpp
        src/checks/automationgesturecheck/crosslane.cpp
        src/checks/automationgesturecheck/contract.cpp
        src/checks/automationgesturecheck/hover.cpp
        src/checks/automationgesturecheck/lifecycle.cpp
        src/checks/rollcheckdrawer.cpp
        src/checks/rollcheckpsgvelocity.cpp
        src/checks/themechecks.cpp
        src/checks/fontcheck.cpp
        src/ui/theme/themecheck.cpp
        src/ui/theme/themecheck.h
        src/checks/editorlayoutcheck.cpp
        resources/fonts.qrc
    )
    if(APPLE)
        target_sources(porydaw_checks PRIVATE
            src/checks/rollcheckplayhead_macos.mm
        )
    endif()
    target_link_libraries(porydaw_checks PRIVATE porydaw_app)
    target_precompile_headers(porydaw_checks PRIVATE
        "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/src/porydaw_pch.hpp>")
    add_dependencies(porydaw_checks mid2agb)
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
if(PORYDAW_BUILD_CHECKS)
    qt_add_resources(porydaw_checks "checks_app_icon"
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
    )
    qt_add_resources(porydaw_checks "checks_cursor_images"
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
    qt_add_resources(porydaw_checks "smf_check_fixtures"
        PREFIX "/checks"
        BASE "${CMAKE_CURRENT_SOURCE_DIR}/src/checks/fixtures/decompproject"
        FILES
            src/checks/fixtures/decompproject/test_midis/smf/valid/opaque_sysex.mid
            src/checks/fixtures/decompproject/test_midis/smf/valid/vlq_running_status.mid
            src/checks/fixtures/decompproject/test_midis/smf/valid/note_lifecycle.mid
            src/checks/fixtures/decompproject/test_midis/smf/malformed/duplicate_eot.mid
            src/checks/fixtures/decompproject/test_midis/smf/stress/automation_burst.mid
    )
endif()
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
        MACOSX_BUNDLE_GUI_IDENTIFIER com.huderlem.porydaw
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
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_link_options(porydaw_render_cli PRIVATE -static)
endif()
