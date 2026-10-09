set(SWIFT_GRID_DIR "${CMAKE_SOURCE_DIR}/src/ui/songview/quick/swiftroll")
set(SWIFT_GRID_NATIVE_DIR "${SWIFT_GRID_DIR}/native")
# New modules: add_library + porydaw_swift_module + porydaw_swift_qt_interop + extras.
function(porydaw_swift_module target module_name)
    set_target_properties(${target} PROPERTIES
        Swift_MODULE_NAME ${module_name}
        Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
        Swift_LANGUAGE_VERSION 6
    )
    target_include_directories(${target} INTERFACE
        "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:${target},Swift_MODULE_DIRECTORY>>"
    )
    porydaw_enable_swift_batch_mode(${target})
endfunction()
function(porydaw_swift_qt_interop target)
    target_compile_options(${target} PUBLIC
        "$<$<COMPILE_LANGUAGE:Swift>:-cxx-interoperability-mode=default>"
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -std=c++20>"
    )
endfunction()


add_library(PorydawApp STATIC
    DocumentWorkspace.swift
    NativeAudio.swift
    export/WavExportJob.swift
    export/WavExportPresenter.swift
    samplestudio/Sf2ZonePickerModel.swift
    samplestudio/Sf2ZonePickerPresenter.swift
    samplestudio/SampleStudioHistory.swift
    samplestudio/SampleStudioReadouts.swift
    samplestudio/SampleStudioPresenter.swift
    samplestudio/SampleLoopTools.swift
    samplestudio/SampleStudioAudition.swift
    samplestudio/SampleWaveformModel.swift
    samplestudio/SampleWaveformScene.swift
    samplestudio/SampleProvenanceStore.swift
    samplestudio/SampleStudioWorkflow.swift
    audio/PolyphonyPanelPresenter.swift
    ApplicationSession.swift
    ApplicationSession+Tabs.swift
    ApplicationSession+Close.swift
    ApplicationSession+ProjectOpening.swift
    ApplicationSession+Ruler.swift
    ApplicationSession+Audio.swift
    ApplicationSession+Commands.swift
    ApplicationSession+Catalog.swift
    ApplicationSession+Samples.swift
    midiimport/ImportAnalysisSummary.swift
    midiimport/MidiImportWizardState.swift
    midiimport/MidiImportController.swift
    newsong/NewSongWizardState.swift
    newsong/NewSongController.swift
    EditorCommandRouter.swift
    transport/TransportBarPresenter.swift
    SongTabsController.swift
    SongTabsController+Close.swift
    eventlist/EventListSelection.swift
    eventlist/EventListEditing.swift
    eventlist/EventListMenus.swift
    eventlist/EventListPresenter.swift
    songlist/SongListPresenter.swift
    songlist/SongDockController.swift
    songlist/SongIntake.swift
    voicelist/VoiceListController.swift
    voicelist/VoiceListController+Bank.swift
    voicelist/SamplePickerRows.swift
    voicelist/VoiceEditorController.swift
    MouseHints.swift
    QmlEngineAccess.swift
    roll/PianoGrid.swift
    roll/PianoGrid+Support.swift
    roll/PianoGrid+Gestures.swift
    roll/PianoGrid+Camera.swift
    roll/PianoGrid+Commands.swift
    roll/PianoGrid+SceneSync.swift
    roll/GridScene.swift
    roll/GridScene+Rebuild.swift
    roll/GridScene+Notes.swift
    roll/GridScene+Primitives.swift
    roll/RollDisplayLists.swift
    roll/RollPlotBuilder.swift
    roll/RollKeyboardBuilder.swift
    roll/RollRulerBuilder.swift
    pitchbend/PitchBendScene.swift
    pitchbend/PitchBendPresenter.swift
    timeline/SharedPlayhead.swift
    timeline/RulerMenuPresenter.swift
    drawer/EditorDrawer.swift
    drawer/EditorDrawerLayout.swift
    drawer/otherEvents/OtherEventsStrip.swift
    drawer/otherEvents/OtherEventsBandPresenter.swift
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
    drawer/automation/AutomationDrawingContent.swift
    drawer/automation/AutomationOverlayPublication.swift
    drawer/automation/AutomationInteraction.swift
    drawer/automation/AutomationModal.swift
    drawer/automation/AutomationTapTempo.swift
    drawer/automation/AutomationLifecycle.swift
    drawer/automation/AutomationPage.swift
    drawer/automation/AutomationPage+Session.swift
    drawer/automation/AutomationGestureEditing.swift
    drawer/automation/AutomationPointerDispatch.swift
    headers/TrackHeaders.swift
    headers/HeaderVoicePicker.swift
    headers/TrackActivity.swift
    headers/TrackHeadersGeometry.swift
    headers/TrackHeadersInput.swift
    shell/ShellPresenter.swift
    shell/ShellActionCatalog.swift
    shell/ShellPresenter+ActionPolicy.swift
    shell/ShellActionState.swift
    shell/ShellAppearance.swift
    shell/EngineSettingsStore.swift
)

# Generated like the playback module map: the native host headers
# (native_host.h, qml_engine_host.h) are referenced with CMAKE_SOURCE_DIR paths.
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
porydaw_swift_module(PorydawApp PorydawApp)
target_compile_options(PorydawApp PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
)

if(PORYDAW_BUILD_CHECKS)
    target_compile_options(PorydawApp PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
endif()

porydaw_swift_qt_interop(PorydawApp)
target_compile_options(PorydawApp PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/third_party>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/m4a>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/hw_audio>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I$<JOIN:$<TARGET_PROPERTY:Qt6::Core,INTERFACE_INCLUDE_DIRECTORIES>, -Xcc -I>>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/audio/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_NATIVE_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_SOURCE_DIR}/src/render/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/commands/QtKeybindings.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_NATIVE_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src/render>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)
target_link_libraries(PorydawApp PUBLIC PorydawBackups PorydawCore PorydawDocument PorydawPlayback PorydawProject PorydawSample QtBridge Qt6::Gui)

add_dependencies(PorydawApp QtBridgeMacros)

add_library(PorydawAppCommands STATIC
    commands/EditCommands.swift
    commands/EditKeyArbiter.swift
    commands/KeybindingRegistry.swift
    commands/Clipboard.swift
    commands/ClipboardSemantics+Paste.swift
)
porydaw_swift_module(PorydawAppCommands PorydawAppCommands)
set_target_properties(PorydawAppCommands PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
porydaw_swift_qt_interop(PorydawAppCommands)
target_compile_options(PorydawAppCommands PUBLIC
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
    export/WavExport.swift
)
porydaw_swift_module(PorydawAppAudio PorydawAppAudio)
target_compile_options(PorydawAppAudio PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
)
set_target_properties(PorydawAppAudio PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
target_compile_options(PorydawAppAudio PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/audio/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/third_party>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/m4a>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin/hw_audio>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)
target_link_libraries(PorydawAppAudio PUBLIC PorydawCore PorydawPlayback)

add_library(PorydawAppEventList STATIC
    eventlist/EventListCellPolicy.swift
    eventlist/EventListModel.swift
    eventlist/EventListProjection.swift
)
porydaw_swift_module(PorydawAppEventList PorydawAppEventList)
set_target_properties(PorydawAppEventList PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
target_link_libraries(PorydawAppEventList PUBLIC PorydawCore)

add_library(PorydawAppPresentation STATIC
    presentation/QListModelSync.swift
    presentation/drawer/DrawerPan.swift
    presentation/drawer/DrawerStaticsContent.swift
    presentation/drawer/LaneCaptionMetrics.swift
    presentation/drawer/PromptAppearance.swift
    presentation/pitchbend/PitchBendGeometry.swift
    presentation/pitchbend/PitchBendKernel.swift
    presentation/roll/GridTypography.swift
    presentation/roll/NoteCommands.swift
    presentation/shell/BundledFont.swift
    presentation/shell/EditorViewStatePreferences.swift
    presentation/shell/PreferencesStore.swift
    presentation/theme/GridPalette.swift
    presentation/theme/ThemeColorTables.swift
    presentation/timeline/DisplayListWriter.swift
    presentation/timeline/PlayheadGuides.swift
    presentation/timeline/TimelineScrollbar.swift
    presentation/typography/LayoutSpaces.swift
    presentation/typography/Typography.swift
    presentation/typography/TypographyFonts.swift
)
porydaw_swift_module(PorydawAppPresentation PorydawAppPresentation)
set_target_properties(PorydawAppPresentation PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
porydaw_swift_qt_interop(PorydawAppPresentation)
target_compile_options(PorydawAppPresentation PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I$<JOIN:$<TARGET_PROPERTY:Qt6::Core,INTERFACE_INCLUDE_DIRECTORIES>, -Xcc -I>>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_SOURCE_DIR}/src/render/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_NATIVE_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_NATIVE_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src/render>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)
target_link_libraries(PorydawAppPresentation PUBLIC PorydawCore PorydawDocument PorydawProject PorydawAppCommands QtBridge Qt6::Gui)

add_dependencies(PorydawAppPresentation QtBridgeMacros)

add_library(PorydawAppHistory STATIC
    history/UndoHistoryPanel.swift
    history/UndoHistoryRow.swift
)
porydaw_swift_module(PorydawAppHistory PorydawAppHistory)
set_target_properties(PorydawAppHistory PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
porydaw_swift_qt_interop(PorydawAppHistory)
target_link_libraries(PorydawAppHistory PUBLIC PorydawCore PorydawDocument PorydawAppPresentation QtBridge)

add_dependencies(PorydawAppHistory QtBridgeMacros)

target_link_libraries(PorydawApp PUBLIC
    PorydawAppCommands PorydawAppAudio PorydawAppEventList PorydawAppHistory PorydawAppPresentation
)

if(PORYDAW_BUILD_CHECKS)
    foreach(leaf PorydawAppCommands PorydawAppAudio PorydawAppEventList PorydawAppHistory PorydawAppPresentation)
        target_compile_options(${leaf} PRIVATE
            "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
    endforeach()
endif()
