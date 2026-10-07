add_library(PorydawProject STATIC
    ProjectIdentity.swift
    MidiCfg.swift
    SongModel.swift
    SongsMk.swift
    SongCatalog.swift
    SongRegistration.swift
    SongRegistration+Debug.swift
    SongRegistration+Writes.swift
    SongRegistration+Removal.swift
    SongRegistration+Store.swift
    ProjectStore.swift
    ProjectStore+Open.swift
    ProjectStore+Reads.swift
    ProjectStore+Bank.swift
    ProjectStore+Edit.swift
    ProjectStore+Save.swift
    ProjectStore+Picker.swift
    ProjectStore+Samples.swift
    ProjectStore+Synth.swift
    SampleRegistrar.swift
    SampleRegistrar+Committed.swift
)

set_target_properties(PorydawProject PROPERTIES
    Swift_MODULE_NAME PorydawProject
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

target_include_directories(PorydawProject INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawProject,Swift_MODULE_DIRECTORY>>"
)
porydaw_enable_swift_batch_mode(PorydawProject)

target_link_libraries(PorydawProject PUBLIC PorydawCore PorydawVoicegroup)
