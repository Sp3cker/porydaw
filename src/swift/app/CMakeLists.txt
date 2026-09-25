set(SWIFT_GRID_DIR "${CMAKE_SOURCE_DIR}/src/ui/songview/quick/swiftroll")
set(SWIFT_GRID_NATIVE_DIR "${SWIFT_GRID_DIR}/native")

add_library(PorydawApp STATIC
    ProjectService.swift
    SharedBankState.swift
    ServiceBankHistory.swift
    DocumentSession.swift
    DocumentWorkspace.swift
    NativeAudio.swift
    audio/PolyphonyPanelPresenter.swift
    ApplicationSession.swift
    transport/TransportBarPresenter.swift
    SongTabsController.swift
    eventlist/EventListSelection.swift
    eventlist/EventListEditing.swift
    eventlist/EventListMenus.swift
    eventlist/EventListPresenter.swift
    songlist/SongListPresenter.swift
    songlist/SongDockController.swift
    voicelist/VoiceListSemantics.swift
    voicelist/VoiceListController.swift
    voicelist/VoiceEditorController.swift
    voicelist/VoicegroupCatalog.swift
    MouseHints.swift
    QListModelSync.swift
    QmlEngineAccess.swift
    roll/PianoGrid.swift
    roll/GridGesture.swift
    roll/GridScene.swift
    roll/NoteCommands.swift
    roll/NoteNameLabels.swift
    pitchbend/PitchBendGeometry.swift
    pitchbend/PitchBendKernel.swift
    pitchbend/PitchBendScene.swift
    pitchbend/PitchBendPresenter.swift
    timeline/EditorCamera.swift
    timeline/ScaleProjection.swift
    timeline/EditorViewStateCodec.swift
    timeline/TimelineScrollbar.swift
    timeline/DocumentProjectionCache.swift
    timeline/PlayheadGuides.swift
    timeline/SharedPlayhead.swift
    timeline/TimeAxis.swift
    timeline/GridGeometry.swift
    timeline/GridPalette.swift
    timeline/GridTypography.swift
    timeline/RulerMenuPresenter.swift
    timeline/TimelineSnapPolicy.swift
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
    shell/EngineSettingsStore.swift
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


# The -load-plugin-library genex in compile options creates no Ninja edge, so
# the hub could schedule before the in-tree SHARED plugin dylib exists. Order
# the macro-consuming target behind it explicitly.
add_dependencies(PorydawApp QtBridgeMacros)

# autoresearch star-topology leaves: macro-plugin-free modules that compile in
# parallel with the QtBridgeMacros head instead of inside the PorydawApp edge.
# Each imports only upstream modules (PorydawCore/Playback/Project), never the
# hub. PorydawApp links them PUBLIC; the hub gains `import`s for their types.
add_library(PorydawAppCommands STATIC
    commands/EditCommands.swift
    commands/EditKeyArbiter.swift
    commands/KeybindingRegistry.swift
    commands/Clipboard.swift
)
set_target_properties(PorydawAppCommands PROPERTIES
    Swift_MODULE_NAME PorydawAppCommands
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
target_include_directories(PorydawAppCommands INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawAppCommands,Swift_MODULE_DIRECTORY>>"
)
target_compile_options(PorydawAppCommands PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:-cxx-interoperability-mode=default>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -std=c++20>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/commands/QtKeybindings.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I$<JOIN:$<TARGET_PROPERTY:Qt6::Core,INTERFACE_INCLUDE_DIRECTORIES>, -Xcc -I>>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)
target_link_libraries(PorydawAppCommands PUBLIC PorydawCore QtBridgeCpp Qt6::Gui)

add_library(PorydawAppAudio STATIC
    audio/AudioDevice.swift
    audio/AudioRenderEngine.swift
    audio/AudioTransport.swift
    audio/AudioTimelineHandoff.swift
    audio/AudioTelemetry.swift
    audio/AudioAudition.swift
    audio/AudioSampleAudition.swift
    audio/ResonanceSuppression.swift
)
set_target_properties(PorydawAppAudio PROPERTIES
    Swift_MODULE_NAME PorydawAppAudio
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
target_include_directories(PorydawAppAudio INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawAppAudio,Swift_MODULE_DIRECTORY>>"
)
target_compile_options(PorydawAppAudio PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:-cxx-interoperability-mode=default>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -std=c++20>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/audio/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/third_party>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/m4a>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/hw_audio>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)
target_link_libraries(PorydawAppAudio PUBLIC PorydawCore PorydawPlayback)

add_library(PorydawAppEventList STATIC
    eventlist/EventListModel.swift
    eventlist/EventListProjection.swift
)
set_target_properties(PorydawAppEventList PROPERTIES
    Swift_MODULE_NAME PorydawAppEventList
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
target_include_directories(PorydawAppEventList INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawAppEventList,Swift_MODULE_DIRECTORY>>"
)
target_compile_options(PorydawAppEventList PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:-cxx-interoperability-mode=default>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -std=c++20>"
)
target_link_libraries(PorydawAppEventList PUBLIC PorydawCore)

target_link_libraries(PorydawApp PUBLIC
    PorydawAppCommands PorydawAppAudio PorydawAppEventList
)
