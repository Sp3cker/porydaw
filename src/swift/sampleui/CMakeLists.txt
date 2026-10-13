add_library(PorydawSampleUI STATIC
    SampleLibraryModel.swift
    SampleAuditionArbiter.swift
    PcmAuditionPlayer.swift
    MarkerWaveformModel.swift
    MarkerWaveformScene.swift
)
porydaw_swift_module(PorydawSampleUI PorydawSampleUI)
set_target_properties(PorydawSampleUI PROPERTIES
    AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
)
porydaw_swift_qt_interop(PorydawSampleUI)
target_link_libraries(PorydawSampleUI PUBLIC
    PorydawSample PorydawAppAudio PorydawAppPresentation QtBridge
)
add_dependencies(PorydawSampleUI QtBridgeMacros)
