add_library(PorydawPlayback STATIC
    Sequencer.swift
    PlaybackBridge.swift
)

# The native module map is generated: the poryaaaa package lives at the
# PORYAAAA_DIR the build already resolves (shared submodule in linked
# worktrees), so a repo-relative header path is wrong outside the main
# checkout.
configure_file(
    module.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/module.modulemap"
    @ONLY
)

set_target_properties(PorydawPlayback PROPERTIES
    Swift_MODULE_NAME PorydawPlayback
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

target_compile_options(PorydawPlayback PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src/audio>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
)

target_include_directories(PorydawPlayback INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawPlayback,Swift_MODULE_DIRECTORY>>"
)
porydaw_enable_swift_batch_mode(PorydawPlayback)

target_link_libraries(PorydawPlayback
    PUBLIC PorydawCore
    PRIVATE poryaaaa_engine
)
