# PorydawDocument: Qt-free, C++-interop-free document model.
# Invariant: no file in this target may import (transitively or directly)
# QtBridge, QtBridgeCpp, Qt, or any PorydawApp* module, and this target
# must never pass -cxx-interoperability-mode. Allowed: Foundation,
# Synchronization, PorydawCore, PorydawProject, PorydawProjectNative (C loader).
add_library(PorydawDocument STATIC
    DocumentSession.swift
    DocumentSession+Internals.swift
    DocumentSession+Selection.swift
    SharedBankState.swift
    ServiceBankHistory.swift
    service/ProjectService.swift
    service/ProjectService+Bank.swift
    service/ProjectService+Import.swift
    service/ProjectService+Picker.swift
    service/ProjectService+Samples.swift
    service/ProjectService+Songs.swift
    service/SongLabelPolicy.swift
    view/timeline/DocumentProjectionCache.swift
    view/timeline/TimelineSnapPolicy.swift
    view/timeline/TimeAxis.swift
    view/automation/AutomationParameter.swift
    view/automation/AutomationTimeSelection.swift
    view/voicelist/VoicegroupCatalog.swift
    view/voicelist/VoiceListSemantics.swift
)

set_target_properties(PorydawDocument PROPERTIES
    Swift_MODULE_NAME PorydawDocument
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)

target_include_directories(PorydawDocument INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawDocument,Swift_MODULE_DIRECTORY>>"
)
porydaw_enable_swift_batch_mode(PorydawDocument)

if(PORYDAW_BUILD_CHECKS)
    target_compile_options(PorydawDocument PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
endif()

target_link_libraries(PorydawDocument PUBLIC PorydawCore PorydawProject)
