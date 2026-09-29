add_library(PorydawSample STATIC
    ImportedSample.swift
    SampleNames.swift
    SampleImport.swift
    SampleWavReader.swift
    SampleAiffReader.swift
    SampleCompressedDecode.swift
    Sf2Reader.swift
    SampleDsp.swift
    SampleResampler.swift
    SampleSeam.swift
    SampleEditParams.swift
    SampleDocument.swift
    SampleRender.swift
    SampleWavWriter.swift
    SampleAnalysis.swift
    SampleSourceHash.swift
    SampleSidecar.swift
    SampleReopen.swift
)
set_target_properties(PorydawSample PROPERTIES
    Swift_MODULE_NAME PorydawSample
    Swift_MODULE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/module"
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
target_include_directories(PorydawSample INTERFACE
    "$<$<COMPILE_LANGUAGE:Swift>:$<TARGET_PROPERTY:PorydawSample,Swift_MODULE_DIRECTORY>>"
)
porydaw_enable_swift_batch_mode(PorydawSample)
target_link_libraries(PorydawSample PRIVATE BinaryParsing)
target_compile_options(PorydawSample PUBLIC
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -fmodule-map-file=${CMAKE_SOURCE_DIR}/src/audio/sample_codec.modulemap>"
    "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-Xcc -I${CMAKE_SOURCE_DIR}/src/audio>"
)
