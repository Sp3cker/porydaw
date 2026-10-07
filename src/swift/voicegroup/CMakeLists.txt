add_library(PorydawVoicegroup STATIC
    AsmLine.swift
    VoiceValues.swift
    VoicegroupSource.swift
    VoicegroupSource+Create.swift
    VoiceEdits.swift
    VoicegroupSave.swift
    SynthCatalog.swift
    MintedSynths.swift
    VoicegroupStore.swift
    ProjectContext.swift
    FileIo.swift
    ProjectFileStore.swift
    VoicegroupId.swift
    ProjectBankLease.swift
)

configure_file(
    module.modulemap.in
    "${CMAKE_CURRENT_BINARY_DIR}/module.modulemap"
    @ONLY
)

set_target_properties(PorydawVoicegroup PROPERTIES
    Swift_MODULE_NAME PorydawVoicegroup
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

target_compile_options(PorydawVoicegroup PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_CURRENT_BINARY_DIR}/module.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${PORYAAAA_DIR}/plugin>"
)

target_include_directories(PorydawVoicegroup INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawVoicegroup,Swift_MODULE_DIRECTORY>>"
)
porydaw_enable_swift_batch_mode(PorydawVoicegroup)
