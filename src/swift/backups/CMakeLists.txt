add_library(PorydawBackups STATIC
    MidiBackupStore.swift
)

set_target_properties(PorydawBackups PROPERTIES
    Swift_MODULE_NAME PorydawBackups
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

porydaw_enable_swift_batch_mode(PorydawBackups)

target_include_directories(PorydawBackups INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawBackups,Swift_MODULE_DIRECTORY>>"
)
