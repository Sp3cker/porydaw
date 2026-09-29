add_library(PorydawSample STATIC
    ImportedSample.swift
    SampleNames.swift
    SampleImport.swift
    SampleWavReader.swift
    SampleAiffReader.swift
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
