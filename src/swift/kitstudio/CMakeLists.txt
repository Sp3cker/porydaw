add_library(PorydawKitStudio STATIC
    KitZone.swift
    KitDraft.swift
    KitDraftCodec.swift
)
porydaw_swift_module(PorydawKitStudio PorydawKitStudio)
set_target_properties(PorydawKitStudio PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
porydaw_swift_qt_interop(PorydawKitStudio)
target_link_libraries(PorydawKitStudio PUBLIC
    PorydawSample PorydawSampleUI PorydawVoicegroup PorydawAppAudio QtBridge
)
add_dependencies(PorydawKitStudio QtBridgeMacros)
