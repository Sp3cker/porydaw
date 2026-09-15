# ---- In-tree m4a converter required by the harness sweep ----
get_filename_component(PORYAAAA_PACKAGES_DIR "${PORYAAAA_DIR}" DIRECTORY)
set(MID2AGB_SOURCE_DIR "${PORYAAAA_PACKAGES_DIR}/ccomidi/mid2agb")
if(NOT EXISTS "${MID2AGB_SOURCE_DIR}/main.cpp")
    message(FATAL_ERROR "PORYAAAA_DIR must belong to the poryaaaa monorepo")
endif()
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
set_target_properties(mid2agb PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")

# ---- porydaw check executable ----
# Qt Test is required only by the checks target; app-only builds must not need it.
find_package(Qt6 REQUIRED COMPONENTS Test)

qt_add_executable(porydaw_checks
    checks_main.cpp
    checkregistry.cpp
    checkregistry.hpp
    checkcatalog.cpp
    checkcatalog.h
    fixturecatalog.cpp
    fixturecatalog.hpp
    fwd.hpp
    support/editorrig.cpp
    support/editorrig.h
    support/eventsynth.cpp
    support/eventsynth.h
    support/quickframebuffer.cpp
    support/quickframebuffer.h
    support/songfixture.cpp
    support/songfixture.h
    support/support.cpp
    support/support.h
    support/voicegroupbrowserdriver.cpp
    support/voicegroupbrowserdriver.h
    clipboard/clipcheck_test.h
    clipboard/clipcheck_fixture.cpp
    clipboard/clipcheck_copy.cpp
    clipboard/clipcheck_merge.cpp
    clipboard/clipmime_test.cpp
    clipboard/selectioncheck_test.h
    clipboard/selectioncheck_core.cpp
    clipboard/selectioncheck_tracks.cpp
    clipboard/laneselection_test.cpp
    workspace/tst_workspacesessions.h
    workspace/tst_workspacesessions.cpp
    workspace/fixture.h
    workspace/fixture.cpp
    workspace/session.cpp
    workspace/tabs_lifecycle.cpp
    workspace/tabs_transport.cpp
    workspace/tabs_scale.cpp
    workspace/tabs_persistence.cpp
    workspace/selftest_timeline.cpp
    workspace/selftest_transport.cpp
    workspace/selftest_workspace.cpp
    pitchbend/tst_pitchbendediting.h
    pitchbend/fixture.cpp
    pitchbend/curve.cpp
    pitchbend/vertex.cpp
    pitchbend/controller.cpp
    pitchbend/lifecycle.cpp
    pitchbend/raster.cpp
    rollcheck.cpp
    rollcheck/rollcheck.h
    rollcheck/harness.cpp
    rollcheck/identity.cpp
    rollcheck/remap.cpp
    rollcheck/pencil.cpp
    rollcheck/pencil_velocity.cpp
    rollcheck/velocity_prompt.cpp
    rollcheck/time_signature_prompt.cpp
    rollcheck/interlock.cpp
    rollcheck/selection.cpp
    rollcheck/note_rendering.cpp
    rollcheck/resize.cpp
    rollcheck/keyboard.cpp
    rollcheck/note_commands.cpp
    rollcheck/timemenu.cpp
    rollcheck/ruler_loop_menu.cpp
    rollcheck/presentation.cpp
    rollcheck/scale_projection.cpp
    rollcheck/scale_fold.cpp
    rollcheck/scale_editing.cpp
    rollcheck/tst_pianoroll.h
    rollcheck/static/tst_pianorollstatic.h
    rollcheck/static/fixtures.h
    rollcheck/static/fixtures.cpp
    rollcheck/static/geometry.cpp
    rollcheck/static/gate.cpp
    rollcheck/static/camera.cpp
    rollcheck/static/tst_pianorollstatic.cpp
    timelinepan/timelinepanfixture.cpp
    timelinepan/tst_timelinepan.cpp
    timelinepan/tst_timelinepannative.cpp
    eventviews/eventview_fixture.h
    eventviews/eventview_fixture.cpp
    eventviews/tst_eventviews.h
    eventviews/chrome.cpp
    eventviews/edits.cpp
    eventviews/remap.cpp
    eventviews/playhead.cpp
    eventviews/viewbuckets_grid.cpp
    nativegraphics/nativegraphics_fixture.h
    nativegraphics/nativegraphics_fixture.cpp
    nativegraphics/tst_renderingplayhead.h
    nativegraphics/renderingplayhead_runner.cpp
    nativegraphics/tst_nativewindowing.cpp
    nativegraphics/tst_playhead_guides.cpp
    nativegraphics/tst_playhead_autohover.cpp
    nativegraphics/tst_playhead_quick.cpp
    nativegraphics/tst_playhead_plots.cpp
    midi/tst_midismf.h
    midi/tst_midismf.cpp
    midi/tst_midiroundtrip.h
    midi/tst_midiroundtrip.cpp
    midi/tst_midiexport.h
    midi/tst_midiexport.cpp
    editcheck/tst_songdocument.h
    editcheck/tst_songdocument_support.h
    editcheck/tst_songdocument_support.cpp
    editcheck/tst_songdocument_runner.cpp
    editcheck/tst_songdocument_document.cpp
    editcheck/tst_songdocument_timerange.cpp
    editcheck/tst_songdocument_metadata.cpp
    editcheck/tst_songdocument_songraw.cpp
    editcheck/tst_songdocument_songnotes.cpp
    editcheck/tst_songdocument_songranges.cpp
    editcheck/tst_songdocument_songmoves.cpp
    editcheck/tst_songdocument_songtime.cpp
    editcheck/tst_songdocument_songtracks.cpp
    editcheck/tst_songdocument_logic.cpp
    onboardcheck/onboardingtest.h
    onboardcheck/support.cpp
    onboardcheck/action.cpp
    onboardcheck/registration.cpp
    onboardcheck/debuglayout.cpp
    onboardcheck/regionedlayout.cpp
    onboardcheck/import.cpp
    onboardcheck/deletion.cpp
    voicegroup/voicegrouptestfixture.h
    voicegroup/voicegrouptestfixture.cpp
    voicegroup/voicegroupsourcecatalog.cpp
    voicegroup/voicegroupsourceediting.cpp
    voicegroup/tst_voicegroupsource.h
    voicegroup/tst_voicegroupbank.cpp
    voicegroup/voicegrouploadfixture.h
    voicegroup/voicegrouploadfixture.cpp
    voicegroup/tst_voicegrouploader.cpp
    voicegroup/tst_voicegroupviewcache.cpp
    voicegroupsave/tst_voicegroupsave.h
    voicegroupsave/fixture.cpp
    voicegroupsave/savecore.cpp
    voicegroupsave/switching.cpp
    voicegroupsave/editor.cpp
    voicegroupsave/synth.cpp
    voicegroupsave/picker.cpp
    voicegroupsave/presentation.cpp
    playback/tst_transport.h
    playback/tst_transport.cpp
    playback/transportfixture.h
    playback/transportfixture.cpp
    playback/publish.cpp
    playback/cgb.cpp
    playback/tails.cpp
    playback/settle.cpp
    playback/sustainvoicegroup.h
    playback/tst_loop.h
    playback/tst_loop.cpp
    playback/tst_prime.h
    playback/tst_prime.cpp
    playback/tst_xcmd.h
    playback/tst_xcmd.cpp
    playback/projection.cpp
    playback/rewrites.cpp
    playback/opaque.cpp
    playback/rawreconciliation.cpp
    playback/export.cpp
    audio/clickrig.h
    audio/clickrig.cpp
    audio/resonancefixture.h
    audio/resonancefixture.cpp
    audio/tst_audiotelemetry.h
    audio/tst_audiotelemetry.cpp
    audio/tst_audiobackend.h
    audio/tst_audiobackend.cpp
    audio/tst_clicktransport.h
    audio/tst_clicktransport.cpp
    audio/tst_resonancelaw.h
    audio/tst_resonancelaw.cpp
    audio/tst_resonancetiming.h
    audio/tst_resonancetiming.cpp
    audio/tst_trackactivity.h
    audio/tst_trackactivity.cpp
    trackheaders/tst_trackheaders.h
    trackheaders/tst_trackheaders.cpp
    trackheaders/tst_trackheadermodel.cpp
    trackheaders/trackheaderfixture.cpp
    trackheaders/trackheaderinput.cpp
    trackheaders/trackheaderraster.cpp
    trackheaders/trackheadermutations.cpp
    trackheaders/trackheadermenu.cpp
    trackheaders/trackheaderoracles.h
    trackheaders/tst_trackactivitymeter.h
    trackheaders/tst_trackactivitymeter.cpp
    scrollbar/tst_scrollbar.cpp
    scrollbar/tst_scrollbar.h
    scrollbar/control.cpp
    scrollbar/input.cpp
    scrollbar/geometry.cpp
    scrollbar/drag.cpp
    samplecheck.cpp
    samplecheck/samplecheck.h
    samplecheck/fixtures.h
    samplecheck/fixtures.cpp
    samplecheck/project.cpp
    samplecheck/decoder.cpp
    samplecheck/dsp.cpp
    samplecheck/editor.cpp
    samplecheck/analysis.cpp
    samplecheck/soundfont.cpp
    samplecheck/integration.cpp
    project/iofixture.h
    project/iofixture.cpp
    project/identity.cpp
    project/ioflow.cpp
    project/iomutations.cpp
    project/workspace.cpp
    project/save.cpp
    project/mk.cpp
    project/ignore.cpp
    host/tst_hostseams.cpp
    host/tst_rulergridmenu.cpp
    host/tst_hostadapter.cpp
    host/tst_hostintegration.cpp
    mainwindowrouting/mainwindowroutingfixture.h
    mainwindowrouting/tst_mainwindowrouting_input.cpp
    mainwindowrouting/tst_mainwindowrouting_state.cpp
    mainwindowrouting/tst_mainwindowrouting_lifecycle.cpp
    mainwindowrouting/tst_mainwindowrouting_native.cpp
    keyboard/tst_keymapcheck.h
    keyboard/keymapregistry.cpp
    keyboard/tst_velocitymodel.h
    keyboard/tst_velocitymodel.cpp
    keyboard/tst_settingsdialog.h
    keyboard/tst_settingsdialog.cpp
    polyphony/tst_polyphonycheck.h
    polyphony/polyphonyengine.cpp
    polyphony/polyphonypanel.cpp
    polyphony/polyphonygate.cpp
    selectionkey/primitives.h
    selectionkey/automationprobe.h
    selectionkey/automationprobe.cpp
    selectionkey/tst_selectionkeycore.h
    selectionkey/corefixture.h
    selectionkey/corefixture.cpp
    selectionkey/core.cpp
    selectionkey/corearrows.cpp
    selectionkey/coreediting.cpp
    selectionkey/gesturecheck.h
    selectionkey/gesture.cpp
    selectionkey/gesturevelocity.cpp
    selectionkey/gesturecommands.cpp
    selectionkey/gesturethumbs.cpp
    selectionkey/session.h
    selectionkey/tst_windowtier.h
    selectionkey/window.cpp
    selectionkey/windowtier_keyboard.cpp
    selectionkey/windowtier_gestures.cpp
    selectionkey/windowtier_lifetime.cpp
    selectionkey/tst_localinputtier.h
    selectionkey/localinput.cpp
    selectionkey/localinputtier_text.cpp
    selectionkey/localinputtier_pitchbend.cpp
    selectionkey/localinputtier_eventlist.cpp
    automation/raster/tst_automationraster.h
    automation/raster/painting.cpp
    automation/raster/interaction.cpp
    automation/raster/rasterfixture.cpp
    automation/raster/rasterfixture.h
    drawerpresentation/tst_drawerpresentation.h
    drawerpresentation/fixtures.h
    drawerpresentation/fixtures.cpp
    drawerpresentation/drawer.cpp
    drawerpresentation/valueprompt.cpp
    drawerpresentation/voice.cpp
    drawerpresentation/voicemenus.cpp
    drawerpresentation/velocity.cpp
    velocity/tst_velocityediting.cpp
    velocity/tst_velocityediting.h
    velocity/velocityselection.cpp
    velocity/velocityhitpriority.cpp
    velocity/velocitypainting.cpp
    velocity/velocityclicks.cpp
    velocity/velocityroll.cpp
    velocity/velocitydetentpainting.cpp
    velocity/velocitydetentdragging.cpp
    automation/tst_automationediting.cpp
    automation/tst_automationediting.h
    automation/automationfixture.cpp
    automation/automationpencil.cpp
    automation/automationstroke.cpp
    automation/automationparity.cpp
    automation/automationnodedrag.cpp
    automation/automationselection.cpp
    automation/automationactions.cpp
    automation/automationownership.cpp
    automation/automationrouting.cpp
    automation/automationvoice.cpp
    automation/automationpainting.cpp
    automation/automationpreviews.cpp
    automation/automationmenus.cpp
    automation/automationpointmenus.cpp
    automation/automationclipboard.cpp
    automation/automationcanvaslayout.cpp
    automation/automationcanvasediting.cpp
    automation/ccdeleteconfirmation.cpp
    automation/automationtaptempo.cpp
    automation/domain/tst_automationdomain.h
    automation/domain/tst_automationdomain.cpp
    automation/domain/gestures.cpp
    automation/domain/xcmd.cpp
    automation/presentation/tst_automationpresentation.h
    automation/presentation/tst_automationpresentation.cpp
    automation/presentation/painting.cpp
    automation/hover/tst_automationhover.h
    automation/hover/tst_automationhover.cpp
    automation/hover/hoverfixture.h
    automation/hover/hoverfixture.cpp
    themelayout/tst_themelayout.h
    themelayout/themelayoutcheck.cpp
    themelayout/tst_themelayout_color.cpp
    themelayout/tst_themelayout_settings.cpp
    themelayout/tst_themelayout_chrome.cpp
    themelayout/tst_themelayout_font.cpp
    themelayout/tst_themelayout_scale.cpp
    ${PROJECT_SOURCE_DIR}/resources/fonts.qrc
)
set_target_properties(porydaw_checks PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")

target_compile_options(porydaw_checks PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow>
)
if(APPLE)
    target_sources(porydaw_checks PRIVATE
        nativegraphics/tst_playhead_native_mac.mm
    )
    set_target_properties(porydaw_checks PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_GUI_IDENTIFIER com.sp3cker.porydaw.checks
    )
    # Keep the cross-platform runner entry path while the resolved executable
    # remains inside its Cocoa foreground-application bundle.
    add_custom_command(TARGET porydaw_checks POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E rm -f
                "${PROJECT_BINARY_DIR}/porydaw_checks"
        COMMAND ${CMAKE_COMMAND} -E create_symlink
                "$<TARGET_FILE:porydaw_checks>"
                "${PROJECT_BINARY_DIR}/porydaw_checks"
        VERBATIM
    )
endif()
target_link_libraries(porydaw_checks PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
    Qt6::Quick
    Qt6::Test
)
target_precompile_headers(porydaw_checks PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:${PROJECT_SOURCE_DIR}/src/porydaw_pch.hpp>")
add_dependencies(porydaw_checks mid2agb)

qt_add_resources(porydaw_checks "checks_app_icon"
    PREFIX "/icons"
    BASE "${PROJECT_SOURCE_DIR}/resources"
    FILES
        ${PROJECT_SOURCE_DIR}/resources/flat-music.svg
        ${PROJECT_SOURCE_DIR}/resources/porydaw-16.png
        ${PROJECT_SOURCE_DIR}/resources/porydaw-32.png
        ${PROJECT_SOURCE_DIR}/resources/porydaw-48.png
        ${PROJECT_SOURCE_DIR}/resources/porydaw-128.png
        ${PROJECT_SOURCE_DIR}/resources/porydaw-256.png
        ${PROJECT_SOURCE_DIR}/resources/velocity.svg
        ${PROJECT_SOURCE_DIR}/resources/velocity_labels.svg
        ${PROJECT_SOURCE_DIR}/resources/automation.svg
)
qt_add_resources(porydaw_checks "checks_cursor_images"
    PREFIX "/cursors"
    BASE "${PROJECT_SOURCE_DIR}/resources"
    FILES
        ${PROJECT_SOURCE_DIR}/resources/left-drag.png
        ${PROJECT_SOURCE_DIR}/resources/left-drag@2x.png
        ${PROJECT_SOURCE_DIR}/resources/pencil.png
        ${PROJECT_SOURCE_DIR}/resources/pencil@2x.png
        ${PROJECT_SOURCE_DIR}/resources/right-drag.png
        ${PROJECT_SOURCE_DIR}/resources/right-drag@2x.png
)
qt_add_resources(porydaw_checks "smf_check_fixtures"
    PREFIX "/checks"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/decompproject"
    FILES
        fixtures/decompproject/test_midis/smf/valid/opaque_sysex.mid
        fixtures/decompproject/test_midis/smf/valid/vlq_running_status.mid
        fixtures/decompproject/test_midis/smf/valid/note_lifecycle.mid
        fixtures/decompproject/test_midis/smf/malformed/duplicate_eot.mid
        fixtures/decompproject/test_midis/smf/stress/automation_burst.mid
)
