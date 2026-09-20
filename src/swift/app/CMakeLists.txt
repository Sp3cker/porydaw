add_library(PorydawApp STATIC
    ProjectService.swift
    DocumentSession.swift
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
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_CURRENT_SOURCE_DIR}/../../project>"
)

target_link_libraries(PorydawApp PUBLIC PorydawCore)
