add_library(PorydawCore STATIC
    MusicTypes.swift
    MidiFile.swift
    MidiFile+Codec.swift
    NoteProjection.swift
    MidiSemantics.swift
    Meter.swift
    PlaybackTimeline.swift
    SongDocument.swift
    DocumentChangeSet.swift
    SongHistory.swift
    NoteEditing.swift
    NoteCollision.swift
    NoteMovement.swift
    EventEditing.swift
    EventEditing+Helpers.swift
    TimeEditing.swift
    TimeEditingSupport.swift
    TimeEditing+Plan.swift
    TimeEditing+Streams.swift
    TimeEditing+Collisions.swift
    TimeEditing+Tempo.swift
    Xcmd.swift
    MidiImport.swift
    MusicalScale.swift
)

set_target_properties(PorydawCore PROPERTIES
    Swift_MODULE_NAME PorydawCore
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
)
porydaw_enable_swift_batch_mode(PorydawCore)

target_include_directories(PorydawCore INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawCore,Swift_MODULE_DIRECTORY>>"
)

target_link_libraries(PorydawCore PUBLIC BinaryParsing)
