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

# Swift check sources need their own archive for CMake to emit compile rules.
function(add_porydaw_check_lane name)
    cmake_parse_arguments(PARSE_ARGV 1 CHECK "" "MODULE_NAME;MODULE_DIRECTORY"
        "SOURCES;COMPILE_OPTIONS;LINK_LIBRARIES")
    add_library(${name} STATIC ${CHECK_SOURCES})
    set_target_properties(${name} PROPERTIES
        Swift_MODULE_NAME "${CHECK_MODULE_NAME}"
        Swift_LANGUAGE_VERSION 6
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    if(CHECK_MODULE_DIRECTORY)
        set_target_properties(${name} PROPERTIES
            Swift_MODULE_DIRECTORY "${CHECK_MODULE_DIRECTORY}")
    endif()
    # Lanes with a module directory publish it so importing lanes find the
    # .swiftmodule; lanes without one (QML hosts) are unaffected.
    if(CHECK_MODULE_DIRECTORY)
        target_include_directories(${name} INTERFACE
            "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:${name},Swift_MODULE_DIRECTORY>>")
    endif()
    porydaw_enable_swift_batch_mode(${name})
    target_compile_options(${name} PRIVATE ${CHECK_COMPILE_OPTIONS})
    target_link_libraries(${name} PRIVATE ${CHECK_LINK_LIBRARIES})
endfunction()

# Keep QML hosts as plain build-root executables for run_checks.ts.
function(add_porydaw_check name)
    cmake_parse_arguments(PARSE_ARGV 1 CHECK "" "SWIFT_LANE;MODULE_NAME;AUTOMOC"
        "SOURCES;SWIFT_SOURCES;SWIFT_COMPILE_OPTIONS;SWIFT_LINK_LIBRARIES")
    add_porydaw_check_lane(${CHECK_SWIFT_LANE}
        MODULE_NAME "${CHECK_MODULE_NAME}"
        SOURCES ${CHECK_SWIFT_SOURCES}
        COMPILE_OPTIONS ${CHECK_SWIFT_COMPILE_OPTIONS}
        LINK_LIBRARIES ${CHECK_SWIFT_LINK_LIBRARIES}
    )
    add_executable(${name} ${CHECK_SOURCES})
    set_target_properties(${name} PROPERTIES
        AUTOMOC "${CHECK_AUTOMOC}"
        AUTOUIC OFF
        AUTORCC ON
        LINKER_LANGUAGE CXX
        RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    )
    target_link_libraries(${name} PRIVATE
        ${CHECK_SWIFT_LANE}
        "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
        PorydawApp
        Qt6::QuickTest
    )
    porydaw_link_linux_swift_runtime(${name}
        ${CHECK_SWIFT_LANE} PorydawApp QtBridge PorydawAppCommands PorydawAppAudio
        PorydawAppEventList PorydawDocument PorydawVoicegroup PorydawBackups PorydawProject PorydawPlayback PorydawCore PorydawSample BinaryParsing)
    # run_checks.ts requires mid2agb beside the build-root harnesses.
    add_dependencies(${name} mid2agb)
endfunction()

qt_add_executable(porydaw_checks
    checks_main.cpp
    checkregistry.cpp
    checkregistry.hpp
    checkcatalog.cpp
    checkcatalog.h
    fixturecatalog.cpp
    fixturecatalog.hpp
    fwd.hpp
    support/checkstartup.cpp
    support/checkstartup.h
)
set_target_properties(porydaw_checks PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
    LINKER_LANGUAGE CXX)
target_include_directories(porydaw_checks PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
porydaw_enable_project_warnings(porydaw_checks)

if(APPLE OR CMAKE_SYSTEM_NAME STREQUAL "Linux")
    # Every core-check module gets these; only SwiftCoreCheck adds the app/render maps
    # and PorydawApp, so Support and Logic stay interop-free and build beside the app.
    set(core_check_swift_options
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/voicegroup/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
    )
    set(core_check_libraries
        PorydawCore PorydawPlayback PorydawProject PorydawVoicegroup PorydawSample PorydawDocument PorydawAppAudio)
    add_porydaw_check_lane(swift_core_check_support
        MODULE_NAME SwiftCoreCheckSupport
        MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/swift_core_check_support"
        COMPILE_OPTIONS ${core_check_swift_options}
        SOURCES
        support/corecheck/CoreCheckSupport.swift
        editcheck/TimeRangeSupport.swift
        support/PageCheckSupport.swift
        support/DocumentSessionFixture.swift
        projectstore/ProjectStoreCheckSupport.swift
        workspace/session_support.swift
        workspace/session_fixtures.swift
        support/NumericCheckSupport.swift
        LINK_LIBRARIES ${core_check_libraries}
    )
    add_porydaw_check_lane(swift_core_check_logic
        MODULE_NAME SwiftCoreCheckLogic
        MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/swift_core_check_logic"
        COMPILE_OPTIONS ${core_check_swift_options} "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>"
        SOURCES
        lanes/SwiftCoreCheckLogicLane.swift
        audio/AudioAuditionChecks.swift
        audio/controllerfixture.swift
        audio/resonancefixture.swift
        audio/tst_audiotelemetry.swift
        audio/tst_clicktransport.swift
        audio/tst_resonancelaw.swift
        audio/tst_resonancetiming.swift
        automation/domain/stagedSnapshot.swift
        automation/domain/xcmdRanges.swift
        editcheck/DocumentEditChecks.swift
        editcheck/DocumentHistoryChecks.swift
        editcheck/DocumentTrackChecks.swift
        editcheck/EventViewsEditsParity.swift
        editcheck/MidiImportChecks.swift
        editcheck/NoteChecks.swift
        editcheck/NoteCorpusChecks.swift
        editcheck/NoteHistoryChecks.swift
        editcheck/NoteIdentityChecks.swift
        editcheck/NoteMoveCorpusChecks.swift
        editcheck/NoteMoveTransactionChecks.swift
        editcheck/ScaleChecks.swift
        editcheck/SelectionTrackChecks.swift
        editcheck/TickBoundsChecks.swift
        editcheck/TimeCorpusChecks.swift
        editcheck/TimeRangeDuplicationAndGlobalsChecks.swift
        editcheck/TimeRangeInsertionAndBoundariesChecks.swift
        editcheck/TimeRangeRangeEditingChecks.swift
        editcheck/TimeRangeRangeMovementChecks.swift
        editcheck/TimeRangeRemovalAndSeamsChecks.swift
        editcheck/TrackLifecycleChecks.swift
        editcheck/tst_songdocument_runner.swift
        editcheck/tst_songdocument_songnotes.swift
        editcheck/tst_songdocument_songranges.swift
        editcheck/tst_songdocument_songraw.swift
        midi/MidiEngineBoundsChecks.swift
        playback/PlaybackChecks.swift
        playback/ResonanceSuppressionChecks.swift
        playback/cgb.swift
        playback/export.swift
        playback/opaque.swift
        playback/projection.swift
        playback/publish.swift
        playback/rawreconciliation.swift
        playback/rewrites.swift
        playback/settle.swift
        playback/tails.swift
        playback/transportfixture.swift
        playback/tst_loop.swift
        playback/tst_prime.swift
        playback/tst_xcmd.swift
        polyphony/polyphonyengine.swift
        projectstore/BankDigest.swift
        projectstore/BankLeasesChecks.swift
        projectstore/BankOwnershipChecks.swift
        projectstore/KeysplitTablesChecks.swift
        projectstore/MidiBackupChecks.swift
        projectstore/MidiCfgChecks.swift
        projectstore/ProjectIdentityChecks.swift
        projectstore/ProjectLayoutChecks.swift
        projectstore/ProjectStoreActorChecks.swift
        projectstore/ProjectStoreEditChecks.swift
        projectstore/ProjectStoreLoadBankChecks.swift
        projectstore/ProjectStoreOpenChecks.swift
        projectstore/ProjectStoreReadChecks.swift
        projectstore/ProjectStoreSaveChecks.swift
        projectstore/SaveCoreChecks.swift
        projectstore/SongCatalogChecks.swift
        projectstore/SongModelChecks.swift
        projectstore/SongsMkChecks.swift
        projectstore/SynthCatalogChecks.swift
        projectstore/VoicegroupBankLogicChecks.swift
        projectstore/VoicegroupContextChecks.swift
        projectstore/VoicegroupEditingChecks.swift
        projectstore/VoicegroupLoaderChecks.swift
        projectstore/VoicegroupLocatorChecks.swift
        projectstore/VoicegroupParityChecks.swift
        projectstore/VoicegroupValueChecks.swift
        projectstore/WriteFailureFixture.swift
        rollcheck/time_signature_prompt.swift
        samplecheck/AnalysisChecks.swift
        samplecheck/CompressedDecoderChecks.swift
        samplecheck/DecoderChecks.swift
        samplecheck/DspKernelChecks.swift
        samplecheck/SampleFixtures.swift
        songlist/SongDebugLayoutChecks.swift
        songlist/SongDeletionChecks.swift
        songlist/SongImportChecks.swift
        songlist/SongRegionRegistrationChecks.swift
        songlist/SongRegistrationChecks.swift
        workspace/bank_edits.swift
        workspace/bank_history_probes.swift
        workspace/bank_saves.swift
        workspace/bank_sharing_history.swift
        workspace/bank_switching.swift
        workspace/history_jump.swift
        workspace/session_save.swift
        workspace/session_save_delta.swift
        workspace/voicegroup_creation.swift
        LINK_LIBRARIES swift_core_check_support ${core_check_libraries}
    )
    add_porydaw_check_lane(swift_core_check
        MODULE_NAME SwiftCoreCheck
        MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/swift_core_check"
        COMPILE_OPTIONS ${core_check_swift_options}
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_SOURCE_DIR}/src/render/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src/render>"
        SOURCES
        support/WorkspacePresenterFixture.swift
        audio/AudioControllerChecks.swift
        audio/tst_trackactivity.swift
        displaylist/DisplayListChecks.swift
        keyboard/EngineSettingsChecks.swift
        keyboard/KeybindingRegistryChecks.swift
        keyboard/tst_velocityaxis.swift
        keyboard/tst_velocitygesture.swift
        keyboard/tst_velocitymodel.swift
        midi/MidiSemanticsChecks.swift
        midi/MidiSemanticsExpected.swift
        midi/MidiSmfCodecChecks.swift
        midi/MidiSmfCodecCompare.swift
        polyphony/PolyphonyPanelChecks.swift
        samplecheck/AuditionStripChecks.swift
        samplecheck/EditorPresenterChecks.swift
        samplecheck/LoopToolsChecks.swift
        samplecheck/ProvenanceChecks.swift
        samplecheck/RegistrationChecks.swift
        samplecheck/RenderPipelineChecks.swift
        samplecheck/SampleChecks.swift
        samplecheck/SoundFontChecks.swift
        samplecheck/WaveformChecks.swift
        themecolor/ThemeColorChecks.swift
        themecolor/ThemeColorPresets.swift
        automation/domain/automationFixture.swift
        automation/domain/gesturePointRange.swift
        automation/domain/xcmd.swift
        editcheck/ClipboardCodecChecks.swift
        editcheck/ClipboardEditingChecks.swift
        editcheck/EventChecks.swift
        editcheck/EventViewsRemapBucketsParity.swift
        editcheck/FormatZeroChecks.swift
        editcheck/MidiImportWizardLawChecks.swift
        editcheck/SelectionChecks.swift
        editcheck/SelectionTransitions.swift
        editcheck/TimeRangeChecks.swift
        editcheck/TrackContractsChecks.swift
        editcheck/TrackCorpusChecks.swift
        editcheck/XcmdPlaybackChecks.swift
        eventviews/EventListPageAppearanceChecks.swift
        eventviews/EventListPageCellCommitChecks.swift
        eventviews/EventListPageChecks.swift
        eventviews/EventListPlayheadChecks.swift
        eventviews/EventListPlayheadContractChecks.swift
        eventviews/EventListPlayheadFocusChecks.swift
        nativegraphics/PlayheadFeatureChecks.swift
        nativegraphics/SharedPlayheadChecks.swift
        nativegraphics/SharedPlayheadPureChecks.swift
        nativegraphics/tst_playhead_quick.swift
        rollcheck/EditorGridCameraChecks.swift
        rollcheck/EditorGridCameraIsolation.swift
        rollcheck/EditorGridLatticeChecks.swift
        rollcheck/EditorGridProjectionChecks.swift
        rollcheck/camera_grid.swift
        rollcheck/identity.swift
        rollcheck/interlock.swift
        rollcheck/keyboard.swift
        rollcheck/keyboard_drum_labels.swift
        rollcheck/keyboard_parity.swift
        rollcheck/keyboard_time_selection.swift
        rollcheck/keyboard_timeline_insert.swift
        rollcheck/note_commands.swift
        rollcheck/note_commands_routing.swift
        rollcheck/note_rendering.swift
        rollcheck/note_rendering_borders.swift
        rollcheck/note_rendering_economy.swift
        rollcheck/note_rendering_ghosts.swift
        rollcheck/note_rendering_names.swift
        rollcheck/note_rendering_support.swift
        rollcheck/note_rendering_velocity.swift
        rollcheck/pencil.swift
        rollcheck/pitch_bend.swift
        rollcheck/pitch_bend_document.swift
        rollcheck/pitch_bend_editing.swift
        rollcheck/pitch_bend_lifecycle.swift
        rollcheck/pitch_bend_support.swift
        rollcheck/presentation.swift
        rollcheck/remap.swift
        rollcheck/resize.swift
        rollcheck/roll_content_probe.swift
        rollcheck/rollheaderfixture.swift
        rollcheck/ruler_loop_menu.swift
        rollcheck/ruler_loop_menu_loop.swift
        rollcheck/ruler_loop_menu_retirement.swift
        rollcheck/ruler_loop_menu_seek.swift
        rollcheck/ruler_loop_menu_sweep.swift
        rollcheck/scale_editing.swift
        rollcheck/selection.swift
        rollcheck/selection_audition.swift
        rollcheck/selection_band.swift
        rollcheck/selection_editing.swift
        rollcheck/static/camera.swift
        rollcheck/static/camera_wheel.swift
        rollcheck/static/gate.swift
        rollcheck/static/geometry.swift
        trackheaders/TrackHeadersChecks.swift
        trackheaders/TrackHeadersInputChecks.swift
        trackheaders/headerfixture.swift
        trackheaders/headerinputfixture.swift
        trackheaders/trackheaderinput.swift
        trackheaders/trackheadermenu.swift
        trackheaders/trackheadermutations.swift
        trackheaders/trackheaderraster.swift
        trackheaders/tst_trackactivitymeter.swift
        trackheaders/tst_trackheadermodel.swift
        automation/AutomationDrawingContentChecks.swift
        automation/AutomationPageChecks.swift
        automation/automationactions.swift
        automation/automationcanvasediting.swift
        automation/automationcanvashover.swift
        automation/automationcanvaslayout.swift
        automation/automationclipboard.swift
        automation/automationmenus.swift
        automation/automationpointmenus.swift
        automation/automationselection.swift
        automation/automationselection_band.swift
        automation/automationselection_mixed.swift
        automation/automationselection_pencil.swift
        automation/automationtaptempo.swift
        automation/domain/gestureNodeContract.swift
        automation/domain/gestureNodeDrag.swift
        automation/domain/gestureNodeDragPhantom.swift
        automation/domain/gesturePencil.swift
        automation/domain/gestureSweep.swift
        automation/domain/tst_automationdomain.swift
        automation/domain/tst_automationdomainLegacy.swift
        automation/presentation/painting.swift
        automation/presentation/painting_raster.swift
        automation/presentation/tst_automationpresentation.swift
        automation/tst_automationediting.swift
        drawerpresentation/EditorDrawerChecks.swift
        drawerpresentation/VoiceChangesPageChecks.swift
        drawerpresentation/drawer_basics.swift
        drawerpresentation/drawer_resize.swift
        drawerpresentation/drawer_state.swift
        drawerpresentation/other_events_band.swift
        drawerpresentation/velocity.swift
        drawerpresentation/velocity_context.swift
        drawerpresentation/voice_interaction.swift
        drawerpresentation/voice_lifecycle.swift
        drawerpresentation/voice_picker.swift
        drawerpresentation/voice_projection.swift
        drawerpresentation/voicemenus.swift
        host/HostBehaviorChecks.swift
        rollcheck/timemenu.swift
        rollcheck/velocity_prompt.swift
        scrollbar/ScrollbarChecks.swift
        selectionkey/localinputtier_text.swift
        selectionkey/localinputtier_window.swift
        songlist/MidiImportWizardChecks.swift
        songlist/NewSongWizardChecks.swift
        songlist/songlist_checks.swift
        songlist/songlist_service.swift
        themelayout/TypographyLayoutChecks.swift
        velocity/VelocityClickCancellationChecks.swift
        velocity/VelocityClickSelectionChecks.swift
        velocity/VelocityContentProbe.swift
        velocity/VelocityPageChecks.swift
        velocity/VelocityPaintDetentChecks.swift
        velocity/VelocityPaintDetentUnlockedChecks.swift
        velocity/VelocityProgramFlowChecks.swift
        velocity/VelocityRollCoreChecks.swift
        velocity/VelocityRollDrawerMirrorChecks.swift
        velocity/WorkspaceRefreshScopeChecks.swift
        velocity/tst_velocityediting.swift
        velocity/velocitydetentdragging.swift
        voicelist/VoiceListChecks.swift
        voicelist/VoiceListIntentChecks.swift
        voicelist/voicelist_session.swift
        projectstore/ExportCaptureChecks.swift
        projectstore/ExportChecks.swift
        workspace/SessionChecks.swift
        workspace/bank_sharing.swift
        workspace/bank_undo_publication.swift
        workspace/editor_view_state_checks.swift
        workspace/sample_commit.swift
        workspace/session_catalog.swift
        workspace/session_edit_routing.swift
        workspace/session_editor_semantics.swift
        workspace/session_io.swift
        workspace/session_playback.swift
        workspace/session_time_routing.swift
        workspace/session_view_state.swift
        workspace/session_view_state_fanout.swift
        workspace/startup_checks.swift
        workspace/transport_checks.swift
        support/corecheck/CoreCheckDispatch.swift
        lanes/SwiftCoreCheckLane.swift
        LINK_LIBRARIES swift_core_check_logic swift_core_check_support ${core_check_libraries} PorydawApp
    )
    target_link_libraries(porydaw_checks PRIVATE swift_core_check swift_core_check_logic swift_core_check_support)
    target_sources(porydaw_checks PRIVATE
        support/corecheck/tst_swiftcore.cpp
        support/corecheck/tst_swiftcore.h
        support/corecheck/core_check.h
        support/corecheck/native_check.cpp
        support/corecheck/native_check.h
    )
    if(APPLE)
        set_target_properties(porydaw_checks PROPERTIES
            MACOSX_BUNDLE TRUE
            MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
            MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
            MACOSX_BUNDLE_GUI_IDENTIFIER com.sp3cker.porydaw.checks
            NO_SYSTEM_FROM_IMPORTED ON
        )
        # The bundle's resources, like the app's: checkstartup loads the staged faces.
        target_sources(porydaw_checks PRIVATE ${porydaw_fonts})
        set_source_files_properties(${porydaw_fonts} PROPERTIES
            MACOSX_PACKAGE_LOCATION Resources)
        add_custom_command(TARGET porydaw_checks POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E rm -f "${PROJECT_BINARY_DIR}/porydaw_checks"
            COMMAND ${CMAKE_COMMAND} -E create_symlink
                    "$<TARGET_FILE:porydaw_checks>" "${PROJECT_BINARY_DIR}/porydaw_checks"
            VERBATIM
        )
    endif()
endif()

target_link_libraries(porydaw_checks PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
    PorydawApp
    Qt6::Test
    Qt6::Widgets
    QtBridgeCpp
)
porydaw_link_linux_swift_runtime(porydaw_checks
    swift_core_check swift_core_check_logic swift_core_check_support PorydawApp QtBridge
    PorydawDocument PorydawVoicegroup PorydawBackups PorydawProject PorydawPlayback PorydawCore PorydawSample BinaryParsing)
target_precompile_headers(porydaw_checks PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${PROJECT_SOURCE_DIR}/src/porydaw_pch.hpp>")
target_compile_definitions(porydaw_checks PRIVATE
    PORYDAW_CHECK_SOURCE_DIR="${PROJECT_SOURCE_DIR}")
add_dependencies(porydaw_checks mid2agb)

if(WIN32)
    # Match the application's manifest embedding for the Windows linker.
    find_program(PORYDAW_MT_TOOL mt.exe REQUIRED)
    add_custom_command(TARGET porydaw_checks POST_BUILD
        COMMAND "${PORYDAW_MT_TOOL}" -manifest
                "${CMAKE_CURRENT_BINARY_DIR}/porydaw_checks.exe.manifest"
                "-outputresource:$<TARGET_FILE:porydaw_checks>;#1"
        VERBATIM)
endif()

# ---- Swift-hosted Qt Quick Test lanes (source-directory inputs) ----
# Qt import/plugin paths come from this configure's pinned Qt installation.
if(APPLE OR CMAKE_SYSTEM_NAME STREQUAL "Linux")
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
    add_porydaw_check(editor_qml_tests
        SWIFT_LANE editor_qml_lane
        MODULE_NAME EditorQmlCheck
        AUTOMOC OFF
        SWIFT_SOURCES
        editorqml/EditorQmlTests.swift
        editorqml/EditorQmlProfileChildren.swift
        editorqml/EditorQmlProfileEvidence.swift
        editorqml/EditorQmlBootstrap.swift
        editorqml/EditorQmlBootstrapSupport.swift
        editorqml/DisplayListProbe.swift
        editorqml/DrawerTestPage.swift
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
        SWIFT_COMPILE_OPTIONS
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
        SWIFT_LINK_LIBRARIES QtBridge PorydawApp
        SOURCES
        editorqml/EditorQmlPaths.swift.in
        # Source-directory inputs resolve NativeWait.js imports without staging.
        editorqml/NativeWait.js
        editorqml/tst_DisplayListSameFrame.qml
        editorqml/tst_EditorDrawerVelocitySameFrame.qml
        editorqml/ShellLaneSupport.qml
        editorqml/EditorDrawerTestSupport.qml
        editorqml/EditorDrawerLayoutSupport.js
        editorqml/EditorDrawerPixelSupport.js
        editorqml/EditorDrawerPageSupport.js
        editorqml/EditorDrawerVelocitySupport.js
        editorqml/EditorDrawerAutomationTabsSupport.js
        editorqml/EditorDrawerAutomationGestureSupport.js
        editorqml/EditorDrawerAutomationMenuSupport.js
        editorqml/EditorDrawerVoiceSupport.js
        editorqml/RollNoteFaces.js
    )
    # The roll host mounts SwiftRollOverlay and reuses the editor's Qt paths.
    set(ROLL_QML_TEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rollqml")
    configure_file(
        "${ROLL_QML_TEST_DIR}/RollQmlPaths.swift.in"
        "${CMAKE_CURRENT_BINARY_DIR}/rollqml/RollQmlPaths.swift"
        @ONLY
    )
    add_porydaw_check(roll_qml_tests
        SWIFT_LANE roll_qml_lane
        MODULE_NAME RollQmlCheck
        AUTOMOC ON
        SWIFT_SOURCES
        rollqml/RollQmlTests.swift
        rollqml/RollQmlStaging.swift
        swiftqtml/BridgeProbeCheck.swift
        "${CMAKE_CURRENT_BINARY_DIR}/rollqml/RollQmlPaths.swift"
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
        SWIFT_COMPILE_OPTIONS
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/support/corecheck>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
        SWIFT_LINK_LIBRARIES QtBridge PorydawApp
        SOURCES
        rollqml/RollQmlPaths.swift.in
        rollqml/cursor_probe.cpp
        rollqml/cursor_probe.h
        # Roll suites resolve "../editorqml/NativeWait.js" from their sources.
        editorqml/NativeWait.js
    )

    add_porydaw_check(shell_qml_tests
        SWIFT_LANE shell_qml_lane
        MODULE_NAME ShellQmlCheck
        AUTOMOC OFF
        SWIFT_SOURCES
        editorqml/ShellQmlTests.swift
        editorqml/ShellQmlEntries.swift
        editorqml/GridInputClipProbe.swift
        editorqml/GatedVisualsProbe.swift
        editorqml/PolyphonyShellProbe.swift
        editorqml/WavFileProbe.swift
        editorqml/SampleBinProbe.swift
        editorqml/BridgeValueTypeProbe.swift
        editorqml/TabsDrawerProbe.swift
        keyboard/KeybindingRegistryChecks.swift
        editorqml/ImportWizardProbe.swift
        editorqml/SampleStudioVoiceProbe.swift
        "${CMAKE_CURRENT_BINARY_DIR}/editorqml/EditorQmlPaths.swift"
        SWIFT_COMPILE_OPTIONS
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_BINARY_DIR}/src/swift/app/module.modulemap>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
        SWIFT_LINK_LIBRARIES QtBridge PorydawApp PorydawCore
        SOURCES
        editorqml/EditorQmlPaths.swift.in
        editorqml/NativeWait.js
        editorqml/ShellLaneSupport.qml
        editorqml/ShellWindowSupport.qml
        editorqml/tst_ShellWindowCrossTab.qml
        editorqml/tst_ShellWindowDrawer.qml
        editorqml/tst_ShellWindowShortcuts.qml
        editorqml/tst_ShellWindowEditorKeys.qml
        editorqml/tst_ShellWindowPrompts.qml
        editorqml/tst_ShellWindowFocus.qml
        editorqml/tst_ShellWindowTimeEditing.qml
        editorqml/tst_ShellWindowVelocity.qml
        editorqml/tst_ShellDeferralProbe.qml
        editorqml/tst_ShellWindowParameterKeys.qml
        editorqml/tst_ShellWindowLabelCommands.qml
        editorqml/tst_ShellWindowHints.qml
        editorqml/ShellGridInputSupport.qml
        editorqml/tst_ShellGridInputDraw.qml
        editorqml/tst_ShellGridInputEditing.qml
        editorqml/tst_ShellGridInputCancel.qml
        editorqml/tst_ShellGridInputKeyboard.qml
        editorqml/tst_ShellGridInputAutomation.qml
        editorqml/ShellPitchBendSupport.qml
        editorqml/tst_ShellPitchBendCancellation.qml
        editorqml/tst_ShellPitchBendControls.qml
        editorqml/tst_ShellPitchBendPointer.qml
        editorqml/tst_ShellPitchBendKeys.qml
        editorqml/tst_ShellPitchBendRetarget.qml
        editorqml/ShellGridMenuSupport.qml
        editorqml/tst_ShellGridMenuInputZones.qml
        editorqml/tst_ShellGridMenuNoteActions.qml
        editorqml/tst_ShellGridMenuRulerLifecycle.qml
        editorqml/tst_ShellGridMenuRulerMarkers.qml
        editorqml/tst_ShellGridMenuRulerClipboard.qml
        editorqml/tst_ShellGridMenuAutomation.qml
        editorqml/ShellClipboardSupport.qml
        editorqml/tst_ShellClipboardRange.qml
        editorqml/tst_ShellClipboardRoundTrip.qml
        editorqml/ShellTransportSupport.qml
        editorqml/tst_ShellTransportVolume.qml
        editorqml/tst_ShellTransportSession.qml
        editorqml/ShellMenusSupport.qml
        editorqml/tst_ShellMenusCommands.qml
        editorqml/tst_ShellMenusLoop.qml
        editorqml/ShellNoteVisualsSupport.qml
        editorqml/tst_ShellNoteVisualsDetail.qml
        editorqml/tst_ShellNoteVisualsRuler.qml
        editorqml/ShellTabsSupport.qml
        editorqml/ShellTabsRenderingSupport.js
        editorqml/tst_ShellTabsMouseHints.qml
        editorqml/tst_ShellTabsOpenSelect.qml
        editorqml/tst_ShellTabsClose.qml
        editorqml/tst_ShellTabsDrawer.qml
        editorqml/tst_ShellTabsBankLifetime.qml
        editorqml/tst_ShellTabsReload.qml
        editorqml/ShellEventListSupport.qml
        editorqml/tst_ShellEventListMenus.qml
        editorqml/tst_ShellEventListPresentation.qml
        editorqml/tst_ShellEventListKeyboardSelection.qml
        editorqml/ShellDrawerParitySupport.qml
        editorqml/ShellDrawerParityRasterSupport.js
        editorqml/ShellDrawerParityVelocitySupport.js
        editorqml/ShellDrawerParityVelocityInputSupport.js
        editorqml/tst_ShellDrawerParityAutomation.qml
        editorqml/tst_ShellDrawerParityVoiceVelocity.qml
        editorqml/ShellVoicegroupSupport.qml
        editorqml/tst_ShellSettings.qml
        editorqml/tst_ShellVoicegroupEditing.qml
        editorqml/tst_ShellVoicegroupPicker.qml
        editorqml/tst_ShellVoicegroupSave.qml
    )
endif()
