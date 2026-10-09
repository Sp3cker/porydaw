add_library(PorydawVoicegroup STATIC
    AsmLine.swift
    Bank.swift
    BankBuilder.swift
    KeysplitTables.swift
    NativeFileSystem.swift
    ProjectLayout.swift
    SoundDataMap.swift
    VoiceDescriptor.swift
    VoiceValues.swift
    VoicegroupLocator.swift
    VoicegroupSource.swift
    VoicegroupSource+Create.swift
    VoiceEdits.swift
    VoicegroupSave.swift
    SynthCatalog.swift
    MintedSynths.swift
    VoicegroupStore.swift
    ProjectFileStore.swift
    VoicegroupId.swift
    ProjectBankLease.swift
    WaveCache.swift
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
target_compile_options(PorydawVoicegroup PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
)
target_link_libraries(PorydawVoicegroup PRIVATE BinaryParsing)

if(PORYDAW_BUILD_CHECKS)
    target_compile_options(PorydawVoicegroup PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
endif()
