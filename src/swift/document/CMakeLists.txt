# PorydawDocument: Qt-free, C++-interop-free document model (DocumentSession)
# and its viewport presentation (DocumentViewport, view/). The viewport types
# live here rather than in PorydawApp for build time: a body edit rebuilds this
# small module in under a second, while any PorydawApp edit re-emits that
# whole module (~8s).
# Invariant: no file in this target may import (transitively or directly)
# QtBridge, QtBridgeCpp, Qt, or any PorydawApp* module, and this target
# must never pass -cxx-interoperability-mode. Allowed: Foundation,
# Synchronization, PorydawBackups, PorydawCore, PorydawProject, PorydawProjectNative (C loader).
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
    view/DocumentViewport.swift
    view/EditorDrawerTypes.swift
    view/EditorViewState.swift
    view/DocumentProjectionCache.swift
    view/EditorCamera.swift
    view/GridGeometry.swift
    view/ScaleProjection.swift
    view/TimelineSnapPolicy.swift
    view/TimeAxis.swift
    view/AutomationParameter.swift
    view/AutomationTimeSelection.swift
    view/VoicegroupCatalog.swift
    view/VoiceListSemantics.swift
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
target_compile_options(PorydawDocument PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Lifetimes>"
)

if(PORYDAW_BUILD_CHECKS)
    target_compile_options(PorydawDocument PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:-enable-testing>")
endif()

target_link_libraries(PorydawDocument PUBLIC PorydawBackups PorydawCore PorydawProject)
