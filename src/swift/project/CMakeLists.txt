add_library(PorydawProject STATIC
    ProjectFileStore.swift
    ProjectIdentity.swift
    FileIo.swift
    MidiCfg.swift
    SongModel.swift
    ProjectContext.swift
    SongsMk.swift
    VoiceValues.swift
    SongCatalog.swift
    SongRegistration.swift
    SongRegistration+Debug.swift
    SongRegistration+Writes.swift
    SongRegistration+Removal.swift
    SongRegistration+Store.swift
    VoicegroupSource.swift
    VoicegroupSource+Create.swift
    VoiceEdits.swift
    VoicegroupSave.swift
    AsmLine.swift
    SynthCatalog.swift
    VoicegroupStore.swift
    ProjectStore.swift
    ProjectStore+Open.swift
    ProjectStore+Reads.swift
    MintedSynths.swift
    ProjectStore+Bank.swift
    ProjectStore+Edit.swift
    ProjectStore+Save.swift
    ProjectStore+Picker.swift
    ProjectStore+Synth.swift
    SampleRegistrar.swift
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
if(APPLE)
    # Native headers include <QtCore/...>; optimized (WMO) imports need Qt's framework root.
    get_filename_component(qt_framework_root "${Qt6Core_DIR}/../.." ABSOLUTE)
    target_compile_options(PorydawProject PUBLIC
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -F${qt_framework_root}>")
endif()

target_include_directories(PorydawProject INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawProject,Swift_MODULE_DIRECTORY>>"
)
porydaw_enable_swift_batch_mode(PorydawProject)

target_link_libraries(PorydawProject PUBLIC PorydawCore PorydawSample)
