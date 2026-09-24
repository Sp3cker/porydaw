add_library(PorydawProject STATIC
    ProjectFileStore.swift
    ProjectIdentity.swift
)

configure_file(
    module.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/module.modulemap"
    @ONLY
)

set_target_properties(PorydawProject PROPERTIES
    Swift_MODULE_NAME PorydawProject
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

target_compile_options(PorydawProject PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src/project>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
)

target_include_directories(PorydawProject INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawProject,Swift_MODULE_DIRECTORY>>"
)
