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
# QuickTest serves the Swift-hosted editor-QML lane at the end of this file.
find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)
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
    audio/tst_audiobackend.cpp
    audio/tst_audiobackend.h
    support/checkstartup.cpp
    support/checkstartup.h
    support/songfixture.cpp
    support/songfixture.h
    ${PROJECT_SOURCE_DIR}/resources/fonts.qrc
)
set_target_properties(porydaw_checks PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")
target_include_directories(porydaw_checks PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
porydaw_enable_project_warnings(porydaw_checks)

if(APPLE)
    add_library(swift_core_check STATIC
        support/corecheck/CoreCheckSupport.swift
        midi/MidiSmfCodecChecks.swift
        midi/MidiSemanticsChecks.swift
        midi/MidiEngineBoundsChecks.swift
        playback/PlaybackChecks.swift
        audio/controllerfixture.swift
        audio/tst_clicktransport.swift
        audio/tst_audiotelemetry.swift
        audio/tst_trackactivity.swift
        playback/publish.swift
        playback/transportfixture.swift
        playback/tst_loop.swift
        playback/tst_prime.swift
        polyphony/polyphonyengine.swift
        polyphony/PolyphonyPanelChecks.swift
        playback/tst_xcmd.swift
        keyboard/tst_velocitymodel.swift
        keyboard/tst_velocityaxis.swift
        keyboard/tst_velocitygesture.swift
        keyboard/KeybindingRegistryChecks.swift
        keyboard/EngineSettingsChecks.swift
        themecolor/ThemeColorChecks.swift
        editcheck/tst_songdocument_songraw.swift
        editcheck/tst_songdocument_runner.swift
        editcheck/tst_songdocument_songranges.swift
        editcheck/tst_songdocument_songnotes.swift
        editcheck/NoteCorpusChecks.swift
        editcheck/NoteMoveTransactionChecks.swift
        editcheck/NoteMoveCorpusChecks.swift
        playback/projection.swift
        playback/rewrites.swift
        playback/opaque.swift
        playback/rawreconciliation.swift
        playback/export.swift
        playback/cgb.swift
        playback/settle.swift
        playback/tails.swift
        audio/resonancefixture.swift
        audio/tst_resonancelaw.swift
        audio/tst_resonancetiming.swift
        audio/AudioControllerChecks.swift
        audio/AudioAuditionChecks.swift
        playback/ResonanceSuppressionChecks.swift
        editcheck/NoteChecks.swift
        editcheck/NoteIdentityChecks.swift
        editcheck/DocumentHistoryChecks.swift
        editcheck/DocumentEditChecks.swift
        editcheck/DocumentTrackChecks.swift
        editcheck/ScaleChecks.swift
        editcheck/EventChecks.swift
        editcheck/EventViewsEditsParity.swift
        editcheck/EventViewsRemapBucketsParity.swift
        editcheck/TrackCorpusChecks.swift
        editcheck/TimeRangeChecks.swift
        editcheck/TimeCorpusChecks.swift
        editcheck/SelectionChecks.swift
        editcheck/TickBoundsChecks.swift
        editcheck/ClipboardCodecChecks.swift
        editcheck/ClipboardEditingChecks.swift
        editcheck/TrackLifecycleChecks.swift
        editcheck/MidiImportChecks.swift
        editcheck/XcmdPlaybackChecks.swift
        editcheck/FormatZeroChecks.swift
        rollcheck/static/camera.swift
        rollcheck/static/geometry.swift
        rollcheck/static/gate.swift
        rollcheck/camera_grid.swift
        support/PageCheckSupport.swift
        scrollbar/ScrollbarChecks.swift
        rollcheck/pencil.swift
        rollcheck/resize.swift
        rollcheck/scale_editing.swift
        rollcheck/note_rendering.swift
        rollcheck/keyboard.swift
        rollcheck/keyboard_parity.swift
        rollcheck/selection.swift
        rollcheck/identity.swift
        rollcheck/interlock.swift
        rollcheck/note_commands.swift
        rollcheck/remap.swift
        rollcheck/presentation.swift
        rollcheck/time_signature_prompt.swift
        rollcheck/pitch_bend.swift
        rollcheck/timemenu.swift
        rollcheck/ruler_loop_menu.swift
        nativegraphics/tst_playhead_quick.swift
        nativegraphics/PlayheadFeatureChecks.swift
        eventviews/EventListPlayheadChecks.swift
        eventviews/EventListPageChecks.swift
        songlist/songlist_checks.swift
        songlist/songlist_service.swift
        voicelist/VoiceListChecks.swift
        voicelist/VoiceListIntentChecks.swift
        voicelist/voicelist_session.swift
        trackheaders/headerfixture.swift
        trackheaders/headerinputfixture.swift
        trackheaders/tst_trackheadermodel.swift
        trackheaders/trackheaderinput.swift
        trackheaders/trackheadermutations.swift
        trackheaders/trackheadermenu.swift
        trackheaders/trackheaderraster.swift
        trackheaders/tst_trackactivitymeter.swift
        automation/domain/tst_automationdomain.swift
        automation/domain/gestureSweep.swift
        automation/domain/gestureNodeDrag.swift
        automation/domain/gesturePointRange.swift
        automation/domain/gesturePencil.swift
        automation/domain/xcmd.swift
        automation/domain/xcmdRanges.swift
        automation/presentation/painting.swift
        automation/presentation/tst_automationpresentation.swift
        automation/automationcanvaslayout.swift
        automation/automationpointmenus.swift
        automation/automationclipboard.swift
        automation/automationcanvasediting.swift
        automation/tst_automationediting.swift
        automation/automationtaptempo.swift
        automation/automationactions.swift
        automation/automationselection.swift
        automation/automationmenus.swift
        selectionkey/localinputtier_text.swift
        drawerpresentation/velocity.swift
        drawerpresentation/voice_projection.swift
        drawerpresentation/voice_picker.swift
        drawerpresentation/voice_interaction.swift
        drawerpresentation/voice_lifecycle.swift
        drawerpresentation/voicemenus.swift
        drawerpresentation/drawer_basics.swift
        drawerpresentation/drawer_resize.swift
        drawerpresentation/drawer_state.swift
        velocity/velocitydetentdragging.swift
        velocity/tst_velocityediting.swift
        velocity/VelocityClickSelectionChecks.swift
        velocity/VelocityPaintDetentChecks.swift
        velocity/VelocityRollCoreChecks.swift
        rollcheck/velocity_prompt.swift
        rollcheck/EditorGridCameraChecks.swift
        drawerpresentation/EditorDrawerChecks.swift
        drawerpresentation/other_events_band.swift
        themelayout/TypographyLayoutChecks.swift
        nativegraphics/SharedPlayheadChecks.swift
        velocity/VelocityPageChecks.swift
        drawerpresentation/VoiceChangesPageChecks.swift
        automation/AutomationPageChecks.swift
        trackheaders/TrackHeadersChecks.swift
        trackheaders/TrackHeadersInputChecks.swift
        workspace/SessionChecks.swift
        projectstore/ProjectIdentityChecks.swift
        projectstore/SongModelChecks.swift
        projectstore/MidiCfgChecks.swift
        projectstore/SongsMkChecks.swift
        projectstore/SongCatalogChecks.swift
        projectstore/SynthCatalogChecks.swift
        projectstore/VoicegroupValueChecks.swift
        projectstore/SaveCoreChecks.swift
        projectstore/VoicegroupEditingChecks.swift
        projectstore/VoicegroupCatalogAbsentChecks.swift
        projectstore/VoicegroupContextChecks.swift
        projectstore/VoicegroupBankLogicChecks.swift
        projectstore/ProjectStoreActorChecks.swift
        projectstore/ProjectStoreCheckSupport.swift
        projectstore/ProjectStoreOpenChecks.swift
        projectstore/ProjectStoreReadChecks.swift
        projectstore/ProjectStoreLoadBankChecks.swift
        projectstore/ProjectStoreEditChecks.swift
        projectstore/ProjectStoreSaveChecks.swift
        projectstore/BankLeasesChecks.swift
        projectstore/ExportChecks.swift
        workspace/session_support.swift
        workspace/editor_view_state_checks.swift
        workspace/transport_checks.swift
        workspace/session_fixtures.swift
        workspace/session_editor_semantics.swift
        workspace/session_time_routing.swift
        workspace/session_io.swift
        workspace/session_playback.swift
        workspace/session_save.swift
        workspace/bank_history_probes.swift
        workspace/bank_edits.swift
        workspace/bank_saves.swift
        workspace/bank_sharing.swift
        workspace/bank_switching.swift
    )
    set_target_properties(swift_core_check PROPERTIES
        Swift_MODULE_NAME SwiftCoreCheck
        Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/swift_core_check"
        Swift_LANGUAGE_VERSION 6
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    porydaw_enable_swift_batch_mode(swift_core_check)
    target_compile_options(swift_core_check PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/project/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
    )
    target_link_libraries(swift_core_check PRIVATE PorydawCore PorydawPlayback PorydawProject PorydawApp)
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
    PorydawApp
    Qt6::Test
)
target_precompile_headers(porydaw_checks PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${PROJECT_SOURCE_DIR}/src/porydaw_pch.hpp>")
target_compile_definitions(porydaw_checks PRIVATE
    PORYDAW_CHECK_SOURCE_DIR="${PROJECT_SOURCE_DIR}")
add_dependencies(porydaw_checks mid2agb)

# ---- Editor drawer Qt Quick Test lane (Swift-hosted, test only) ----
# The drawer container's QML lane is its own Swift executable, so tools/
# run_checks.ts drives it like any other harness: the runner reads this lane's
# manifest and launches it with one entry. Its cases load the production
# composition by relative URL, so the QML input directory is the source
# directory, and the Qt import/plugin paths are read from the pinned Qt
# installation this configure selected — never from the caller's environment.
if(APPLE)
    # Locate qmake through the Qt package this configure selected, so the query
    # answers for that same Qt (verified against the pinned Qt 6.11).
    set(PORYDAW_QMAKE_EXECUTABLE "")
    if(TARGET Qt6::qmake)
        get_target_property(PORYDAW_QMAKE_EXECUTABLE Qt6::qmake IMPORTED_LOCATION)
    endif()
    if(NOT PORYDAW_QMAKE_EXECUTABLE)
        message(FATAL_ERROR
            "Qt6::qmake is unavailable; the editor drawer QML lane cannot "
            "resolve QT_INSTALL_QML/QT_INSTALL_PLUGINS")
    endif()
    foreach(_porydaw_qt_query IN ITEMS QT_INSTALL_QML QT_INSTALL_PLUGINS)
        execute_process(
            COMMAND "${PORYDAW_QMAKE_EXECUTABLE}" -query "${_porydaw_qt_query}"
            OUTPUT_VARIABLE ${_porydaw_qt_query}
            OUTPUT_STRIP_TRAILING_WHITESPACE
            COMMAND_ERROR_IS_FATAL ANY
        )
    endforeach()
    set(EDITOR_QML_TEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/editorqml")
    configure_file(
        "${EDITOR_QML_TEST_DIR}/EditorQmlPaths.swift.in"
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
        @ONLY
    )
    # CMake emits Swift compile rules only for a target that archives or links
    # its sources, so the lane's Swift module is its own static library and the
    # executable below links it instead of compiling Swift itself.
    add_library(editor_qml_lane STATIC
        editorqml/EditorQmlTests.swift
        editorqml/DrawerTestPage.swift
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
    )
    set_target_properties(editor_qml_lane PROPERTIES
        Swift_MODULE_NAME EditorQmlCheck
        Swift_LANGUAGE_VERSION 6
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    porydaw_enable_swift_batch_mode(editor_qml_lane)
    # The Swift module-map compile options the core check sets, so this lane
    # sees the app module's Clang headers through the same contract. QtBridge
    # and PorydawApp also hand their Swift modules to this compile.
    target_compile_options(editor_qml_lane PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
    )
    target_link_libraries(editor_qml_lane PRIVATE QtBridge PorydawApp)

    # A plain executable at the build root: the Deno runner resolves
    # `<build>/editor_qml_tests` as a file, so no bundle or symlink wrapper.
    add_executable(editor_qml_tests
        editorqml/EditorQmlPaths.swift.in
        # Shared waitForNative loop (editorqml/NativeWait.js): the QML lanes run
        # with -input under the source directories themselves, so Qt Quick Test
        # resolves each suite's relative "NativeWait.js" import against the
        # importing file's directory at runtime — no fixture staging or qrc
        # needed. Listed here so the build tracks the helper every suite imports.
        editorqml/NativeWait.js
        "${PROJECT_SOURCE_DIR}/resources/fonts.qrc"
    )
    set_target_properties(editor_qml_tests PROPERTIES
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC ON
        LINKER_LANGUAGE CXX
        RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    )
    target_link_libraries(editor_qml_tests PRIVATE
        editor_qml_lane
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
        PorydawApp
        Qt6::QuickTest
    )
    # run_checks.ts refuses to start without mid2agb beside the build root.
    add_dependencies(editor_qml_tests mid2agb)
    # The Swift roll window's own QML lane: the same Qt Quick Test host shape
    # as the drawer lane, mounting the production SwiftRollOverlay composition
    # against a real ApplicationSession. Its input directory is rollqml/, so
    # the lane gets its own generated paths file and reuses the editor lane's
    # generated Qt import/plugin paths.
    set(ROLL_QML_TEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rollqml")
    configure_file(
        "${ROLL_QML_TEST_DIR}/RollQmlPaths.swift.in"
        "${CMAKE_CURRENT_BINARY_DIR}/rollqml/RollQmlPaths.swift"
        @ONLY
    )
    add_library(roll_qml_lane STATIC
        rollqml/RollQmlTests.swift
        swiftqtml/BridgeProbeCheck.swift
        "${CMAKE_CURRENT_BINARY_DIR}/rollqml/RollQmlPaths.swift"
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
    )
    set_target_properties(roll_qml_lane PROPERTIES
        Swift_MODULE_NAME RollQmlCheck
        Swift_LANGUAGE_VERSION 6
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    porydaw_enable_swift_batch_mode(roll_qml_lane)
    target_compile_options(roll_qml_lane PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
    )
    target_link_libraries(roll_qml_lane PRIVATE QtBridge PorydawApp)

    add_executable(roll_qml_tests
        rollqml/RollQmlPaths.swift.in
        # Same shared waitForNative loop the editor lane lists above; rollqml
        # suites import it as "../editorqml/NativeWait.js", which Qt Quick Test
        # resolves against the importing file's source directory at runtime.
        editorqml/NativeWait.js
        "${PROJECT_SOURCE_DIR}/resources/fonts.qrc"
    )
    set_target_properties(roll_qml_tests PROPERTIES
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC ON
        LINKER_LANGUAGE CXX
        RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    )
    target_link_libraries(roll_qml_tests PRIVATE
        roll_qml_lane
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
        PorydawApp
        Qt6::QuickTest
    )
    add_dependencies(roll_qml_tests mid2agb)

    add_library(shell_qml_lane STATIC
        editorqml/ShellQmlTests.swift
        editorqml/GridInputClipProbe.swift
        editorqml/GatedVisualsProbe.swift
        editorqml/PolyphonyShellProbe.swift
        editorqml/TabsDrawerProbe.swift
        keyboard/KeybindingRegistryChecks.swift
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
    )
    set_target_properties(shell_qml_lane PROPERTIES
        Swift_MODULE_NAME ShellQmlCheck
        Swift_LANGUAGE_VERSION 6
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    porydaw_enable_swift_batch_mode(shell_qml_lane)
    target_compile_options(shell_qml_lane PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
    )
    target_link_libraries(shell_qml_lane PRIVATE QtBridge PorydawApp)

    add_executable(shell_qml_tests
        editorqml/EditorQmlPaths.swift.in
        "${PROJECT_SOURCE_DIR}/resources/fonts.qrc"
    )
    set_target_properties(shell_qml_tests PROPERTIES
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC ON
        LINKER_LANGUAGE CXX
        RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    )
    target_link_libraries(shell_qml_tests PRIVATE
        shell_qml_lane
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
        PorydawApp
        Qt6::QuickTest
    )
    add_dependencies(shell_qml_tests mid2agb)
endif()
