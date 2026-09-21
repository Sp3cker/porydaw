set(SWIFT_GRID_DIR "${CMAKE_SOURCE_DIR}/src/ui/songview/quick/swiftroll")
set(SWIFT_GRID_NATIVE_DIR "${SWIFT_GRID_DIR}/native")

add_library(PorydawApp STATIC
    ProjectService.swift
    DocumentSession.swift
    EditorCamera.swift
    EditorDrawer.swift
    NativeAudio.swift
    ApplicationSession.swift
    Clipboard.swift
    "${SWIFT_GRID_DIR}/EditCommands.swift"
    "${SWIFT_GRID_DIR}/EditKeyArbiter.swift"
    "${SWIFT_GRID_DIR}/GridGeometry.swift"
    "${SWIFT_GRID_DIR}/GridGesture.swift"
    "${SWIFT_GRID_DIR}/GridPalette.swift"
    "${SWIFT_GRID_DIR}/GridScene.swift"
    "${SWIFT_GRID_DIR}/GridTypography.swift"
    NoteCommands.swift
    "${SWIFT_GRID_DIR}/PianoGrid.swift"
    "${SWIFT_GRID_DIR}/TimeAxis.swift"
)

# Generated like the playback module map: the service header lives at the
# repo's src/project, not beside this module map.
configure_file(
    module.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/module.modulemap"
    @ONLY
)
set_target_properties(PorydawApp PROPERTIES
    Swift_MODULE_NAME PorydawApp
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
)

target_include_directories(PorydawApp INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawApp,Swift_MODULE_DIRECTORY>>"
)

target_compile_options(PorydawApp PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${SWIFT_GRID_NATIVE_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${SWIFT_GRID_NATIVE_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src>"
)

target_link_libraries(PorydawApp PUBLIC PorydawCore PorydawPlayback QtBridge)
