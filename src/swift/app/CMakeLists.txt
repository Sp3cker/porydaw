set(SWIFT_GRID_DIR "${CMAKE_SOURCE_DIR}/src/ui/songview/quick/swiftroll")
set(SWIFT_GRID_NATIVE_DIR "${SWIFT_GRID_DIR}/native")

add_library(PorydawApp STATIC
    ProjectService.swift
    ServiceBankHistory.swift
    DocumentSession.swift
    DocumentWorkspace.swift
    NativeAudio.swift
    audio/AudioDevice.swift
    audio/AudioRenderEngine.swift
    audio/AudioTransport.swift
    audio/AudioTimelineHandoff.swift
    audio/AudioTelemetry.swift
    audio/AudioAudition.swift
    audio/AudioSampleAudition.swift
    audio/ResonanceSuppression.swift
    ApplicationSession.swift
    SongTabsController.swift
    eventlist/EventListModel.swift
    eventlist/EventListPresenter.swift
    songlist/SongListPresenter.swift
    voicelist/VoiceListSemantics.swift
    voicelist/VoiceListController.swift
    MouseHints.swift
    QListModelSync.swift
    roll/PianoGrid.swift
    roll/GridGesture.swift
    roll/GridScene.swift
    roll/NoteCommands.swift
    timeline/EditorCamera.swift
    timeline/DocumentProjectionCache.swift
    timeline/PlayheadGuides.swift
    timeline/SharedPlayhead.swift
    timeline/TimeAxis.swift
    timeline/GridGeometry.swift
    timeline/GridPalette.swift
    timeline/GridTypography.swift
    timeline/TimelineSnapPolicy.swift
    commands/EditCommands.swift
    commands/EditKeyArbiter.swift
    commands/KeybindingRegistry.swift
    commands/Clipboard.swift
    drawer/EditorDrawer.swift
    drawer/PromptAppearance.swift
    drawer/EditorDrawerTypes.swift
    drawer/EditorDrawerLayout.swift
    drawer/velocity/VelocityContext.swift
    drawer/velocity/VelocityAxis.swift
    drawer/velocity/VelocityTransactions.swift
    drawer/velocity/VelocityProjection.swift
    drawer/velocity/VelocitySceneValues.swift
    drawer/velocity/VelocityScene.swift
    drawer/velocity/VelocityInteraction.swift
    drawer/velocity/VelocityPublication.swift
    drawer/velocity/VelocityPage.swift
    drawer/voicechanges/VoiceLanePolicy.swift
    drawer/voicechanges/VoiceChangesProjection.swift
    drawer/voicechanges/VoiceChangesTransactions.swift
    drawer/voicechanges/VoiceChangesScene.swift
    drawer/voicechanges/VoiceChangesInteraction.swift
    drawer/voicechanges/VoiceChangesPublication.swift
    drawer/voicechanges/VoiceChangesPage.swift
    drawer/automation/AutomationParameter.swift
    drawer/automation/AutomationLaneProjection.swift
    drawer/automation/AutomationProjection.swift
    drawer/automation/AutomationProjectionCache.swift
    drawer/automation/AutomationTransactions.swift
    drawer/automation/AutomationDrawingTransactions.swift
    drawer/automation/AutomationNodeTransactions.swift
    drawer/automation/AutomationEdits.swift
    drawer/automation/AutomationSelectionCommands.swift
    drawer/automation/AutomationScene.swift
    drawer/automation/AutomationHandles.swift
    drawer/automation/AutomationContentPublication.swift
    drawer/automation/AutomationOverlayPublication.swift
    drawer/automation/AutomationInteraction.swift
    drawer/automation/AutomationModal.swift
    drawer/automation/AutomationTapTempo.swift
    drawer/automation/AutomationLifecycle.swift
    drawer/automation/AutomationPage.swift
    headers/TrackHeaders.swift
    headers/TrackActivity.swift
    headers/TrackHeadersGeometry.swift
    headers/TrackHeadersInput.swift
    shell/ShellPresenter.swift
    shell/ShellAppearance.swift
)

# Generated like the playback module map: the bank-lease header lives at the
# repo's src/project, not beside this module map.
configure_file(
    module.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/module.modulemap"
    @ONLY
)
configure_file(
    audio/module.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/audio/module.modulemap"
    @ONLY
)

# Resolve the actual imported QtGui headers rather than assuming a framework
# layout; the generated Clang module must name an existing qkeysequence.h.
get_target_property(qt_gui_includes Qt6::Gui INTERFACE_INCLUDE_DIRECTORIES)
set(QT_GUI_HEADERS "")
foreach(qt_include IN LISTS qt_gui_includes)
    if(EXISTS "${qt_include}/qkeysequence.h")
        set(QT_GUI_HEADERS "${qt_include}")
        break()
    endif()
endforeach()
if(NOT QT_GUI_HEADERS)
    message(FATAL_ERROR "Qt6::Gui does not expose qkeysequence.h for Swift keybindings")
endif()
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/commands")
configure_file(
    commands/QtKeybindings.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/commands/QtKeybindings.modulemap"
    @ONLY
)
set_target_properties(PorydawApp PROPERTIES
    Swift_MODULE_NAME PorydawApp
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
)

if(PORYDAW_BUILD_CHECKS)
    target_compile_options(PorydawApp PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
endif()

target_include_directories(PorydawApp INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawApp,Swift_MODULE_DIRECTORY>>"
)

target_compile_options(PorydawApp PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:-cxx-interoperability-mode=default>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -std=c++20>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/third_party>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/m4a>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/hw_audio>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I$<JOIN:$<TARGET_PROPERTY:Qt6::Core,INTERFACE_INCLUDE_DIRECTORIES>, -Xcc -I>>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/audio/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_NATIVE_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/commands/QtKeybindings.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_NATIVE_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)

target_link_libraries(PorydawApp PUBLIC PorydawCore PorydawPlayback PorydawProject QtBridge Qt6::Gui)
