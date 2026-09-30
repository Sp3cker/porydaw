foreach(module IN ITEMS PorydawCore PorydawPlayback PorydawProject PorydawApp
        PorydawAppCommands PorydawAppAudio PorydawAppEventList PorydawSample)
    target_compile_options(${module} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:-g>")
endforeach()

qt_add_library(automation_bench_swift STATIC
    BenchMain.swift
    Fixture.swift
    BenchWorkload.swift
    NodeScenarios.swift
    NodeScenarioSupport.swift
    PromptScenarios.swift
    DrawingScenarios.swift
    DrawingScenarioSupport.swift
    RangeScenarios.swift
    HistoryScenarios.swift
    NodeScalingScenarios.swift
    BulkScalingScenarios.swift
    SustainedHistoryScenarios.swift
)
set_target_properties(automation_bench_swift PROPERTIES
    Swift_MODULE_NAME AutomationBench
    Swift_LANGUAGE_VERSION 6
    AUTOMOC OFF
    AUTOUIC OFF
    AUTORCC OFF
)
target_compile_options(automation_bench_swift PRIVATE
    "$<$<COMPILE_LANGUAGE:Swift>:-g>"
)
target_link_libraries(automation_bench_swift PRIVATE PorydawApp)

qt_add_executable(automation_bench
    "${CMAKE_SOURCE_DIR}/src/app/automation_bench_host.cpp"
    "${CMAKE_SOURCE_DIR}/resources/fonts.qrc"
)
set_target_properties(automation_bench PROPERTIES
    OUTPUT_NAME automation-bench
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    AUTOMOC OFF
    AUTOUIC OFF
    LINKER_LANGUAGE CXX
)
target_compile_options(automation_bench PRIVATE -g)
target_link_libraries(automation_bench PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,automation_bench_swift>"
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,porydaw_app>"
    PorydawApp
)
