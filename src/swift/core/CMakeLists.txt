add_library(PorydawCore STATIC
    MusicTypes.swift
    MidiFile.swift
    MidiSemantics.swift
    PlaybackTimeline.swift
    SongDocument.swift
    SongHistory.swift
    NoteEditing.swift
    EventEditing.swift
    TimeEditing.swift
    Xcmd.swift
    MidiImport.swift
)

set_target_properties(PorydawCore PROPERTIES
    Swift_MODULE_NAME PorydawCore
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
)

target_include_directories(PorydawCore INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawCore,Swift_MODULE_DIRECTORY>>"
)
